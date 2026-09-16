import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:unichat_mobile_app/core/network/api.dart' show apiErrorMessage;
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_actions.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_gate.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

/// Today's clock-in/out + break status card — status dot, break-in/break-out/worked-today
/// stats, and the clock-in / take-break / clock-out actions. Shared by Home (as a
/// preview) and the full Attendance screen, so the clock-in/out logic lives in one place.
class AttendanceStatusCard extends ConsumerWidget {
  const AttendanceStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hrAttendanceMeProvider);
    final dash = ref.watch(dashboardMeProvider).maybeWhen(orElse: () => null, data: (d) => d);
    final dashAttendance = (dash?['attendance'] is Map) ? (dash!['attendance'] as Map).cast<String, dynamic>() : null;

    // Self-service attendance has no HR permission requirement server-side —
    // but if the company doesn't use the HR module at all the call 404s; that's an
    // expected "not applicable here" outcome, so it collapses quietly. Any other
    // failure (network, 500, etc.) is a real problem and is shown, not hidden —
    // a silently blank Home page gives no clue which section actually broke.
    return async.when(
      loading: () => const _AttendanceMessage(text: 'Loading attendance…', showSpinner: true),
      error: (e, _) {
        if (e is DioException && e.response?.statusCode == 404) return const SizedBox(height: 0);
        return _AttendanceMessage(text: "Couldn't load attendance — ${apiErrorMessage(e)}");
      },
      data: (d) {
        final today = (d['today'] is Map) ? (d['today'] as Map).cast<String, dynamic>() : null;
        final settings =
            (d['settings'] is Map) ? (d['settings'] as Map).cast<String, dynamic>() : <String, dynamic>{};
        final openBreak = d['open_break'];
        final clockedIn =
            today != null && today['clock_in_at'] != null && today['clock_out_at'] == null;
        final dayDone = today != null && today['clock_out_at'] != null;
        final onBreak = openBreak != null;
        final workedMinutes = dashAttendance?['worked_minutes'] ?? today?['worked_minutes'];
        final lastBreakIn = dashAttendance?['last_break_in'];
        final lastBreakOut = dashAttendance?['last_break_out'];

        final Color cardBg;
        final Color dotColor;
        final String title;
        if (onBreak) {
          cardBg = M.amberBg;
          dotColor = M.amberMuted;
          title = 'On break';
        } else if (dayDone) {
          cardBg = M.attBg;
          dotColor = context.mutedColor;
          title = 'Day complete';
        } else if (clockedIn) {
          cardBg = M.attBg;
          dotColor = M.attDot;
          title = 'Clocked in at ${time12(today['clock_in_at'])}';
        } else {
          cardBg = context.altSurface;
          dotColor = context.mutedColor;
          title = 'Not clocked in';
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_dateLabel(today), style: TextStyle(fontSize: 10.5, color: context.mutedColor, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: M.attTitle)),
                  ),
                ],
              ),
              if (today?['clock_in_at'] != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    AttendanceStat(label: 'Break in', value: lastBreakIn != null ? time12(lastBreakIn) : '—'),
                    const SizedBox(width: 18),
                    AttendanceStat(label: 'Break out', value: lastBreakOut != null ? time12(lastBreakOut) : '—'),
                    const SizedBox(width: 18),
                    AttendanceStat(label: 'Worked today', value: _hm(workedMinutes)),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (!clockedIn && !dayDone)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: M.attMuted),
                    onPressed: () => _run(context, ref, 'clock_in', settings),
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Clock in'),
                  ),
                )
              else if (clockedIn)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: M.attMuted,
                            side: const BorderSide(color: M.attBtnBorder),
                            padding: EdgeInsets.zero,
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          onPressed: () =>
                              _run(context, ref, onBreak ? 'break_end' : 'break_start', settings),
                          child: Text(onBreak ? 'End break' : 'Take break'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: M.attMuted,
                            padding: EdgeInsets.zero,
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          onPressed: onBreak ? null : () => _run(context, ref, 'clock_out', settings),
                          child: const Text('Clock out'),
                        ),
                      ),
                    ),
                  ],
                )
              else if (dayDone)
                _ReopenRequestSection(reopenStatus: today['reopen_status'] as String?, onSubmit: () => _reopen(context, ref)),
            ],
          ),
        );
      },
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, String action,
      Map<String, dynamic> settings) async {
    final ok = await attendanceAction(context, action: action, settings: settings);
    if (!ok) return;
    ref.invalidate(hrAttendanceMeProvider);
    ref.invalidate(dashboardMeProvider);
    ref.invalidate(attendanceCalendarProvider);
    ref.read(attendanceGateProvider.notifier).refresh();
  }

  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    final ok = await requestAttendanceReopen(context);
    if (ok) ref.invalidate(hrAttendanceMeProvider);
  }

  static String _hm(Object? minutes) {
    final m = int.tryParse('${minutes ?? 0}') ?? 0;
    return '${m ~/ 60}h ${m % 60}m';
  }

  /// Prefers the server's own `work_date` for the row this card is showing (so a clock near
  /// midnight, or a server/device timezone mismatch, is never ambiguous about which day is
  /// on screen) — only falls back to the device's local date once there's no row yet at all
  /// (nothing clocked in today).
  static String _dateLabel(Map<String, dynamic>? today) {
    final raw = today?['work_date'];
    final parsed = raw != null ? DateTime.tryParse('$raw') : null;
    return DateFormat('EEE, d MMM').format(parsed ?? DateTime.now());
  }
}

/// Shown in place of the clock-in/out buttons once the day is done — the only way back in
/// after a clock-out is a manager-approved reopen request (see `requestAttendanceReopen`),
/// never a direct re-clock-in.
class _ReopenRequestSection extends StatelessWidget {
  const _ReopenRequestSection({required this.reopenStatus, required this.onSubmit});
  final String? reopenStatus;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    if (reopenStatus == 'pending') {
      return Row(
        children: [
          Icon(Icons.hourglass_top_rounded, size: 15, color: context.mutedColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Reopen request sent — waiting for a manager to review it.',
                style: TextStyle(fontSize: 11.5, color: context.mutedColor)),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reopenStatus == 'rejected')
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Your last reopen request was rejected.',
                style: TextStyle(fontSize: 11.5, color: AppPalette.danger)),
          ),
        TextButton.icon(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
          onPressed: onSubmit,
          icon: const Icon(Icons.lock_reset_rounded, size: 16),
          label: const Text('Accidentally clocked out? Request reopen', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

/// Loading/error placeholder in the same card shape as the real content, so it's
/// obvious this is the Attendance card specifically, not a random blank gap.
class _AttendanceMessage extends StatelessWidget {
  const _AttendanceMessage({required this.text, this.showSpinner = false});
  final String text;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          if (showSpinner) ...[
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: context.mutedColor)),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(text, style: TextStyle(color: context.mutedColor, fontSize: 12.5))),
        ],
      ),
    );
  }
}

class AttendanceStat extends StatelessWidget {
  const AttendanceStat({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: M.attMuted, fontSize: 10)),
        const SizedBox(height: 1),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: M.attTitle)),
      ],
    );
  }
}
