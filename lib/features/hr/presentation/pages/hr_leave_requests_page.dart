// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Leave (approve/reject) ══════════════════════════

/// Split out of the former shared `HrAdminPage` (tab 1, "Leave").
class HrLeaveRequestsPage extends ConsumerWidget {
  const HrLeaveRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave Requests')),
      body: ProviderList(
      provider: hrLeaveTeamProvider,
      emptyLabel: 'No leave requests',
      emptyIcon: Icons.beach_access_rounded,
      tile: (context, l) {
        final user = (l['user'] is Map) ? (l['user'] as Map) : const {};
        final leaveType = (l['leave_type'] is Map) ? (l['leave_type'] as Map) : const {};
        final pending = str(l['status'], 'pending') == 'pending';
        return RecordCard(
          title: '${str(user['name'], 'Staff')} · ${str(leaveType['name'], 'Leave')}',
          subtitle: '${str(l['start_date'])} → ${str(l['end_date'])}${l['reason'] != null ? ' · ${l['reason']}' : ''}',
          leadingIcon: Icons.beach_access_rounded,
          trailing: pending
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline_rounded, color: AppPalette.success),
                    onPressed: () => _review(context, ref, l['id'], 'approved'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined, color: AppPalette.danger),
                    onPressed: () => _review(context, ref, l['id'], 'rejected'),
                  ),
                ])
              : StatusPill(str(l['status'])),
        );
      },
      ),
    );
  }

  Future<void> _review(BuildContext context, WidgetRef ref, int id, String decision) async {
    final ok = await runAction(context, () => Api.post('/hr/leave/$id/review', data: {'decision': decision}),
        success: decision == 'approved' ? 'Approved' : 'Rejected');
    if (ok) ref.invalidate(hrLeaveTeamProvider);
  }
}

