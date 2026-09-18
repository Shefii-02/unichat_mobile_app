// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Attendance (team, today) ══════════════════════════

/// Split out of the former shared `HrAdminPage` (tab 0, "Attendance (All)").
class HrAttendanceAllPage extends ConsumerWidget {
  const HrAttendanceAllPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendances (All)')),
      body: ProviderList(
      provider: hrTeamAttendanceTodayProvider,
      emptyLabel: 'No attendance records for today',
      emptyIcon: Icons.groups_rounded,
      header: const _ReopenRequestsHeader(),
      tile: (context, r) {
        final u = (r['user'] is Map) ? (r['user'] as Map) : const {};
        return RecordCard(
          title: str(u['name'], 'Staff'),
          subtitle: str(u['department'], ''),
          leadingIcon: Icons.badge_rounded,
          onTap: () => _editAttendance(context, ref, r, u),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusPill(str(r['status'], 'absent')),
                if (r['clock_in_at'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(when(r['clock_in_at']), style: TextStyle(fontSize: 11, color: context.mutedColor)),
                  ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 18),
              tooltip: 'Edit attendance',
              onPressed: () => _editAttendance(context, ref, r, u),
            ),
          ]),
        );
      },
      ),
    );
  }

  static String _timeOnly(Object? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse('$iso');
    if (d == null) return '';
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  /// Converts a `work_date` ("YYYY-MM-DD") + a locally-edited "HH:mm" into a UTC ISO
  /// instant, so the edit is correct regardless of the device's timezone vs the
  /// server's — sending a naive "date time" string for the server to parse would
  /// silently shift by the device's UTC offset instead.
  static String? _localTimeToUtcIso(String workDate, String hhmm) {
    if (hhmm.trim().isEmpty) return null;
    final t = hhmm.split(':');
    final d = workDate.split('-');
    if (t.length != 2 || d.length != 3) return null;
    final h = int.tryParse(t[0]);
    final m = int.tryParse(t[1]);
    final y = int.tryParse(d[0]);
    final mo = int.tryParse(d[1]);
    final da = int.tryParse(d[2]);
    if ([h, m, y, mo, da].any((v) => v == null)) return null;
    return DateTime(y!, mo!, da!, h!, m!).toUtc().toIso8601String();
  }

  Future<void> _editAttendance(BuildContext context, WidgetRef ref, Rec r, Map u) async {
    final workDate = str(r['work_date'], DateTime.now().toIso8601String().substring(0, 10));
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Edit attendance — ${str(u['name'], 'Staff')}',
      fields: (ctx) => [
        FText(
          label: 'Clock in (HH:mm, blank = not clocked in)',
          initial: _timeOnly(r['clock_in_at']),
          onSaved: (v) => data['clock_in_at'] = _localTimeToUtcIso(workDate, v),
        ),
        FText(
          label: 'Clock out (HH:mm, blank = allow clocking in again today)',
          initial: _timeOnly(r['clock_out_at']),
          onSaved: (v) => data['clock_out_at'] = _localTimeToUtcIso(workDate, v),
        ),
        FSelect<String>(
          label: 'Status',
          options: const ['present', 'absent', 'on_leave', 'half_day', 'weekly_off'],
          initial: str(r['status'], 'present'),
          onSaved: (v) => data['status'] = v ?? 'present',
        ),
        FText(
          label: 'Note (shown to the staff member)',
          initial: r['note_message'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['note_message'] = v,
        ),
      ],
      onSubmit: () => Api.patch('/hr/attendance/${r['id']}', data: data),
    );
    if (ok) ref.invalidate(hrTeamAttendanceTodayProvider);
  }
}

/// Pending "I accidentally clocked out" requests, shown above today's attendance list —
/// approving clears clock_out_at server-side (see AttendanceController::reviewReopen) so the
/// staff member can clock back in; rejecting just closes the request out.
class _ReopenRequestsHeader extends ConsumerWidget {
  const _ReopenRequestsHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hrReopenRequestsProvider);
    final rows = async.maybeWhen(data: (d) => d, orElse: () => const <Rec>[]);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reopen requests',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          ...rows.map((r) {
            final u = (r['user'] is Map) ? (r['user'] as Map) : const {};
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecordCard(
                title: str(u['name'], 'Staff'),
                subtitle: str(r['reopen_reason'], ''),
                leadingIcon: Icons.lock_reset_rounded,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline_rounded, color: AppPalette.success),
                    tooltip: 'Approve — clear the clock-out so they can clock back in',
                    onPressed: () => _review(context, ref, r['id'], 'approved'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined, color: AppPalette.danger),
                    tooltip: 'Reject',
                    onPressed: () => _review(context, ref, r['id'], 'rejected'),
                  ),
                ]),
              ),
            );
          }),
          const Divider(height: 20),
        ],
      ),
    );
  }

  Future<void> _review(BuildContext context, WidgetRef ref, int id, String decision) async {
    final ok = await runAction(
      context,
      () => Api.post('/hr/attendance/$id/reopen', data: {'decision': decision}),
      success: decision == 'approved' ? 'Reopened — they can clock in again.' : 'Rejected',
    );
    if (ok) {
      ref.invalidate(hrReopenRequestsProvider);
      ref.invalidate(hrTeamAttendanceTodayProvider);
    }
  }
}

