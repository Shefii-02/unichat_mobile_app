import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/storage/secure_storage.dart';
import 'package:unichat_mobile_app/features/app_lock/app_lock_provider.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_gate.dart';
import 'package:unichat_mobile_app/features/auth/data/auth_repository.dart';
import 'package:unichat_mobile_app/features/auth/data/device_auth_repository.dart';
import 'package:unichat_mobile_app/features/auth/data/models/user_model.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

final deviceAuthRepositoryProvider =
    Provider<DeviceAuthRepository>((ref) => DeviceAuthRepository());

class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  FutureOr<UserModel?> build() async {
    // Load from local cache — avoids a network call on every cold start.
    // Any 401 from DioClient clears storage; the splash screen re-checks
    // device-auth status before routing into the app.
    return ref.read(authRepositoryProvider).getStoredUser();
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).login(email: email, password: password),
    );
    if (state.hasValue && state.value != null) {
      ref.read(appLockProvider.notifier).requireUnlockAfterLogin();
    }
  }

  /// Called by the device-login flow once `claim` has persisted the session.
  void adopt(UserModel user) {
    state = AsyncData(user);
    ref.read(appLockProvider.notifier).requireUnlockAfterLogin();
  }

  /// Called on cold start, before the splash screen lets the user into the app. Three cases:
  /// no token stored at all → straight to relogin (no point making a network call that can
  /// only ever come back "no token"); a token that's stored but rejected outright (invalid,
  /// blacklisted, past even the refresh-TTL window) → also relogin; a token that's stored and
  /// still refreshable → slide it forward via `/auth/refresh` and let the user in. Either way
  /// this also re-validates the device itself hasn't been unlinked/revoked from the account
  /// (`/device-auth/status`), which a token refresh alone wouldn't catch.
  Future<bool> verifyDevice() async {
    if (state.value == null) return false;

    final hasToken = await SecureStorageService.getToken() != null;
    if (!hasToken) {
      // A stale cached user record with no session behind it — e.g. survives a
      // token-clearing 401 from an earlier run, since that only wipes SecureStorage, never
      // the cached UserModel JSON in LocalStorage (see AuthRepository.getStoredUser).
      // Without this check that combination used to sail straight through to '/home': the
      // resulting "no token" response from the server was indistinguishable, from here, from
      // a genuine network hiccup, so it was treated as one and waved through.
      await logout();
      return false;
    }

    final refreshResult = await ref.read(authRepositoryProvider).refreshToken();
    if (refreshResult == TokenRefreshResult.invalid) {
      await logout();
      return false;
    }

    final ok = await ref.read(deviceAuthRepositoryProvider).statusOk();
    if (!ok) {
      await logout();
      return false;
    }
    return true;
  }

  Future<void> logout() async {
    await ref.read(deviceAuthRepositoryProvider).logout();
    await ref.read(authRepositoryProvider).logout();
    ref.read(attendanceGateProvider.notifier).clear();
    state = const AsyncData(null);
  }

  /// Called by `DioClient.onAuthFailure` (wired up in `app.dart`) the moment any request
  /// comes back proving the session token itself is invalid — a 401/419, or the backend's
  /// jwt-auth 500 for an expired/blacklisted token (see `isAuthFailure`). SecureStorage is
  /// already cleared by that point; this just mirrors that into in-memory state so
  /// `authProvider.value` flips to null and the router immediately redirects to `/auth`
  /// (device QR/PIN re-login), instead of leaving the user stuck on a screen where every
  /// API call keeps failing until they manually restart the app.
  void forceSignOut() {
    if (state.value == null) return;
    ref.read(attendanceGateProvider.notifier).clear();
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(AuthNotifier.new);
