import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';

/// Whether the signed-in user is allowed past [ClockInRequiredPage] into the
/// rest of the app. Every user must clock in once per day before using any
/// screen, and must end an open break before continuing — this is the single
/// source of truth the router's `redirect` consults for that gate.
class AttendanceGateState {
  const AttendanceGateState({
    this.loaded = false,
    this.needsClockIn = false,
    this.onBreak = false,
  });

  /// `false` until the first `/hr/attendance/me` fetch resolves (or fails).
  final bool loaded;
  final bool needsClockIn;
  final bool onBreak;

  bool get blocks => needsClockIn || onBreak;
}

class AttendanceGateNotifier extends Notifier<AttendanceGateState> {
  bool _inFlight = false;

  @override
  AttendanceGateState build() => const AttendanceGateState();

  Future<void> refresh() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final d = await Api.one('/hr/attendance/me');
      final today = d['today'] is Map ? (d['today'] as Map) : null;
      final needsClockIn = today == null || today['clock_in_at'] == null;
      final onBreak = d['open_break'] != null;
      state = AttendanceGateState(
          loaded: true, needsClockIn: needsClockIn, onBreak: onBreak);
    } catch (_) {
      // A company that doesn't use the HR module, or a transient network
      // error, must never lock users out of the rest of the app — fail open.
      state = const AttendanceGateState(loaded: true);
    } finally {
      _inFlight = false;
    }
  }

  /// Re-arm for the next login (called on logout).
  void clear() {
    _inFlight = false;
    state = const AttendanceGateState();
  }
}

final attendanceGateProvider =
    NotifierProvider<AttendanceGateNotifier, AttendanceGateState>(
        AttendanceGateNotifier.new);
