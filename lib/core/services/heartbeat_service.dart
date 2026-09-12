import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';

/// Keeps the linked device's `last_active_at` fresh and re-checks that the
/// device is still authorised. Runs while the app is in the foreground and
/// fires once immediately on resume.
class HeartbeatService with WidgetsBindingObserver {
  HeartbeatService(this._ref);
  final Ref _ref;
  Timer? _timer;

  static const _interval = Duration(minutes: 5);

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _tick();
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  Future<void> _tick() async {
    final auth = _ref.read(authProvider);
    if (auth.value == null) return;
    final repo = _ref.read(deviceAuthRepositoryProvider);
    await repo.heartbeat();
    final ok = await repo.statusOk();
    if (!ok) {
      // Device was revoked elsewhere — drop the local session.
      await _ref.read(authProvider.notifier).logout();
    }
  }
}

final heartbeatServiceProvider = Provider<HeartbeatService>((ref) {
  final service = HeartbeatService(ref);
  ref.onDispose(service.dispose);
  return service;
});
