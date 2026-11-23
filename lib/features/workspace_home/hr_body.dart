import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/router/shell_routes.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/workspace_home/ws_style.dart';

/// HR workspace Home: attendance today, leave / payroll / directory tiles, leave requests, payroll, who is out.
class HrBody extends ConsumerWidget {
  const HrBody({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wsHomeProvider('hr'));
    final d = dataOf(async);
    final a = asMap(d?['attendance']);
    final leave = asMap(d?['leave']);
    final payroll = asMap(d?['payroll']);
    final dir = asMap(d?['directory']);
    final requests = asRows(leave?['requests']);
    final out = asRows(d?['out_today']);
    final staff = n(a?['staff']) ?? 0, present = n(a?['present']) ?? 0;
    final pending = n(leave?['pending']) ?? 0;

    Widget decide(Map<String, dynamic> l, String decision, IconData icon, Color? fg, Color? bg) => WsIconBtn(icon, () async {
          final ok = await runAction(context, () => Api.post('/hr/leave/${l['id']}/review', data: {'decision': decision}), success: decision == 'approved' ? 'Approved' : 'Rejected');
          if (ok) ref.invalidate(wsHomeProvider('hr'));
        }, fg: fg, bg: bg);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (async.hasError && d == null) WsLoadError(async.error, () => ref.invalidate(wsHomeProvider('hr'))),
      WsSummary(
        title: "Today's attendance",
        value: '${fmtNum(present)} / ${fmtNum(staff)}',
        suffix: 'present',
        progress: staff > 0 ? (present / staff).toDouble() : 0,
        footer: 'On time ${fmtNum(a?['on_time'])} · Late ${fmtNum(a?['late'])} · On leave ${fmtNum(a?['on_leave'])} · Absent ${fmtNum(a?['absent'])}',
        actions: [WsHeroButton('View live attendance', () => context.goToRoute('/hr/attendance-all'))],
      ),
      const WsAttendance(),
      WsTiles([
        ('Attendance', a?['month_pct'] != null ? '${fmtNum(a?['month_pct'])}%' : '—', 'avg. this month', tintGreen, () => context.goToRoute('/hr/attendance-all')),
        ('Leave', fmtNum(pending), 'requests pending', tintPeach, () => context.goToRoute('/hr/leave-requests')),
        ('Payroll', payroll == null ? '—' : fmtMoney(payroll['net']), payroll == null ? 'no run yet' : '${payroll['period']} · ${payroll['status']}', tintLavender, () => context.goToRoute('/hr/payrolls')),
        ('Directory', fmtNum(dir?['staff']), '${fmtNum(dir?['joining_soon'])} joined this month', tintBlue, () => context.goToRoute('/hr/staff-setup')),
      ]),
      WsSection(
        title: 'Leave requests',
        action: 'See all ${fmtNum(pending)}',
        onAction: () => context.goToRoute('/hr/leave-requests'),
        child: WsRows([
          for (final l in requests)
            WsRow(
              leading: WsAvatar('${l['name'] ?? ''}'),
              title: '${l['name'] ?? 'Staff'}',
              subtitle: '${l['type'] ?? 'Leave'} · ${'${l['from']}'.split('T').first} · ${fmtNum(l['days'])} day(s)',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [decide(l, 'rejected', Icons.close_rounded, M.redMuted, M.redBg), const SizedBox(width: 8), decide(l, 'approved', Icons.check_rounded, Colors.white, M.taskDoneBg)]),
            ),
        ], empty: 'No pending leave requests.'),
      ),
      if (payroll != null)
        WsSection(
          title: '${payroll['period']} payroll',
          action: 'Review',
          onAction: () => context.goToRoute('/hr/payrolls'),
          child: WsRows([
            WsRow(title: 'Gross', trailing: Text(fmtMoney(payroll['gross']), style: const TextStyle(fontWeight: FontWeight.w600))),
            WsRow(title: 'Deductions', trailing: Text(fmtMoney(payroll['deductions']), style: const TextStyle(fontWeight: FontWeight.w600))),
            WsRow(title: 'Net payout · ${fmtNum(payroll['staff'])} staff', subtitle: '${payroll['status']}', trailing: Text(fmtMoney(payroll['net']), style: const TextStyle(fontWeight: FontWeight.w700, color: M.attMuted))),
          ]),
        ),
      WsSection(
        title: 'Out today',
        child: WsRows([
          for (final o in out)
            WsRow(
              leading: WsAvatar('${o['name'] ?? ''}'),
              title: '${o['name'] ?? 'Staff'}',
              trailing: '${o['status']}' == 'on_leave' ? const WsBadge('On leave', tintLavender) : WsBadge('Late · ${fmtNum(o['late_minutes'])} min', tintAmber),
            ),
        ], empty: 'Everyone is in.'),
      ),
      const SizedBox(height: 12),
    ]);
  }
}
