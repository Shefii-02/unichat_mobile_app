import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:unichat_mobile_app/core/network/api.dart' show Api, apiErrorMessage;
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_actions.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_gate.dart';
import 'package:unichat_mobile_app/features/attendance/widgets/swipe_action_button.dart';
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
          title = 'Clocked out';
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
              if (_lateReasonOpen(today, settings)) _LateReasonRow(minutes: (today!['late_minutes'] as num).toInt(), onSaved: () => ref.invalidate(hrAttendanceMeProvider))
              else if (_lateReasonSaved(today)) Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Late reason: ${today!['late_note']}', style: TextStyle(fontSize: 11.5, color: context.mutedColor, fontStyle: FontStyle.italic)),
              ),
              const SizedBox(height: 12),
              if (!clockedIn)
                SwipeActionButton(
                  label: dayDone ? 'Clock in again' : 'Clock in',
                  icon: Icons.login_rounded,
                  color: M.attMuted,
                  onSwipe: () => _run(context, ref, 'clock_in', settings),
                )
              else ...[
                SwipeActionButton(
                  label: onBreak ? 'End break' : 'Take break',
                  icon: onBreak ? Icons.play_arrow_rounded : Icons.free_breakfast_rounded,
                  color: M.amberMuted,
                  onSwipe: () => _run(context, ref, onBreak ? 'break_end' : 'break_start', settings),
                ),
                const SizedBox(height: 8),
                SwipeActionButton(
                  label: 'Clock out',
                  icon: Icons.logout_rounded,
                  color: M.attMuted,
                  enabled: !onBreak,
                  onSwipe: () => _run(context, ref, 'clock_out', settings),
                ),
              ],
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


/// Late today, the company's late-reason setting is "optional" and nothing has been written yet → the reason is asked here, after clock-in.
bool _lateReasonOpen(Map<String, dynamic>? today, Map<String, dynamic> settings) =>
    settings['late_note_mode'] == 'optional' &&
    today != null &&
    today['clock_in_at'] != null &&
    ((today['late_minutes'] as num?) ?? 0) > 0 &&
    today['clock_in_status'] == 'danger' &&
    '${today['late_note'] ?? ''}'.trim().isEmpty;

bool _lateReasonSaved(Map<String, dynamic>? today) => today != null && '${today['late_note'] ?? ''}'.trim().isNotEmpty && ((today['late_minutes'] as num?) ?? 0) > 0;

class _LateReasonRow extends StatefulWidget {
  const _LateReasonRow({required this.minutes, required this.onSaved});
  final int minutes;
  final VoidCallback onSaved;

  @override
  State<_LateReasonRow> createState() => _LateReasonRowState();
}

class _LateReasonRowState extends State<_LateReasonRow> {
  final _c = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _c.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await Api.raw.post('/hr/attendance/late-note', data: {'note': text});
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('late-reason-row'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You clocked in ${formatDelay(widget.minutes)} min late — add a reason (optional).',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade800)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _c,
                maxLength: 500,
                decoration: const InputDecoration(hintText: 'e.g. Traffic delay', isDense: true, counterText: '', border: OutlineInputBorder()),
                onSubmitted: (_) => _save(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? '…' : 'Save')),
          ]),
        ],
      ),
    );
  }
}
