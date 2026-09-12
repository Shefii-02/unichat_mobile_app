import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/auth/data/device_auth_repository.dart';
import 'auth_provider.dart';

enum DeviceLoginPhase { idle, checking, confirm, claiming, deviceLimit, done }

class DeviceLoginState {
  const DeviceLoginState({
    this.phase = DeviceLoginPhase.idle,
    this.token,
    this.pin,
    this.check,
    this.limit,
    this.error,
  });

  final DeviceLoginPhase phase;
  final String? token;
  final String? pin;
  final DeviceCheckResult? check;
  final DeviceLimitException? limit;
  final String? error;

  bool get busy =>
      phase == DeviceLoginPhase.checking || phase == DeviceLoginPhase.claiming;

  DeviceLoginState copyWith({
    DeviceLoginPhase? phase,
    String? token,
    String? pin,
    DeviceCheckResult? check,
    DeviceLimitException? limit,
    String? error,
    bool clearError = false,
  }) {
    return DeviceLoginState(
      phase: phase ?? this.phase,
      token: token ?? this.token,
      pin: pin ?? this.pin,
      check: check ?? this.check,
      limit: limit ?? this.limit,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DeviceLoginController extends Notifier<DeviceLoginState> {
  @override
  DeviceLoginState build() => const DeviceLoginState();

  DeviceAuthRepository get _repo => ref.read(deviceAuthRepositoryProvider);

  void reset() => state = const DeviceLoginState();

  /// Step 1 — verify the QR token / PIN and move to the confirm screen.
  Future<void> submit({String? token, String? pin}) async {
    if (state.busy) return;
    state = state.copyWith(
      phase: DeviceLoginPhase.checking,
      token: token,
      pin: pin,
      clearError: true,
    );
    try {
      final result = await _repo.check(token: token, pin: pin);
      state = state.copyWith(phase: DeviceLoginPhase.confirm, check: result);
    } on DeviceChallengeException catch (e) {
      state = state.copyWith(phase: DeviceLoginPhase.idle, error: e.message);
    } catch (e) {
      state = state.copyWith(
          phase: DeviceLoginPhase.idle, error: 'Something went wrong. Try again.');
    }
  }

  /// Step 2 — link this device and sign in.
  Future<void> confirm() async {
    if (state.busy) return;
    state = state.copyWith(phase: DeviceLoginPhase.claiming, clearError: true);
    await _claim(token: state.token, pin: state.pin);
  }

  /// Device-limit recovery — remove one device, then retry the claim.
  Future<void> removeAndRetry(int deviceId) async {
    final limit = state.limit;
    if (limit == null || state.busy) return;
    state = state.copyWith(phase: DeviceLoginPhase.claiming, clearError: true);
    try {
      await _repo.removeDevice(
        deviceId: deviceId,
        token: limit.retryToken ?? state.token,
        pin: limit.retryPin ?? state.pin,
      );
    } on DeviceChallengeException catch (e) {
      state = state.copyWith(
          phase: DeviceLoginPhase.deviceLimit, error: e.message);
      return;
    }
    await _claim(
      token: limit.retryToken ?? state.token,
      pin: limit.retryPin ?? state.pin,
    );
  }

  Future<void> _claim({String? token, String? pin}) async {
    try {
      final user = await _repo.claim(token: token, pin: pin);
      ref.read(authProvider.notifier).adopt(user);
      state = state.copyWith(phase: DeviceLoginPhase.done);
    } on DeviceLimitException catch (e) {
      state = state.copyWith(phase: DeviceLoginPhase.deviceLimit, limit: e);
    } on DeviceChallengeException catch (e) {
      state = state.copyWith(phase: DeviceLoginPhase.idle, error: e.message);
    } catch (e) {
      state = state.copyWith(
          phase: DeviceLoginPhase.idle, error: 'Sign-in failed. Try again.');
    }
  }
}

final deviceLoginControllerProvider =
    NotifierProvider<DeviceLoginController, DeviceLoginState>(
        DeviceLoginController.new);
