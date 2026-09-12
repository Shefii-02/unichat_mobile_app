import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  }

  /// Called by the device-login flow once `claim` has persisted the session.
  void adopt(UserModel user) {
    state = AsyncData(user);
  }

  /// Re-validate the cached session against `/device-auth/status`. Returns
  /// `true` if still authorised; signs the user out and returns `false` if not.
  Future<bool> verifyDevice() async {
    if (state.value == null) return false;
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
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(AuthNotifier.new);
