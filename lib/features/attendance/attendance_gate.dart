import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';

String _todayKey() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

/// Whether the signed-in user is allowed past [ClockInRequiredPage] into the
/// rest of the app. Every user must clock in once per day before using any
/// screen, and must end an open break before continuing — this is the single
/// source of truth the router's `redirect` consults for that gate.
class AttendanceGateState {
  const AttendanceGateState({
    this.loaded = false,
    this.needsClockIn = false,
    this.onBreak = false,
    this.fetchedForDate,
  });

  /// `false` until the first `/hr/attendance/me` fetch resolves (or fails).
  final bool loaded;
  final bool needsClockIn;
  final bool onBreak;

  /// The device's local "YYYY-MM-DD" at the moment this state was fetched — never the
  /// source of truth itself (the server's response is), just a cheap trigger the router
  /// checks on every navigation to notice "this was fetched for a day that has since
  /// passed" and ask the server again, rather than trusting a client-side timer to catch
  /// midnight. See `_AuthRouterNotifier`'s gate check in app_router.dart.
  final String? fetchedForDate;

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
          loaded: true, needsClockIn: needsClockIn, onBreak: onBreak, fetchedForDate: _todayKey());
    } catch (_) {
      // A company that doesn't use the HR module, or a transient network
      // error, must never lock users out of the rest of the app — fail open.
      state = AttendanceGateState(loaded: true, fetchedForDate: _todayKey());
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
