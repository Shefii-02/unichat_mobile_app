import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/router/shell_routes.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/workspace_home/ws_style.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sales workspace Home. A team head / manager sees the team view; a plain sales member sees their own day.
class SalesBody extends ConsumerWidget {
  const SalesBody({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final head = PermissionGuard.isManager || PermissionGuard.can('staff.view') || PermissionGuard.can('hr.manage');
    return head ? const _SalesTeam() : const _SalesStaff();
  }
}

class _SalesTeam extends ConsumerWidget {
  const _SalesTeam();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wsHomeProvider('sales'));
    final d = dataOf(async);
    final f = asMap(d?['followups']);
    final k = asMap(d?['kpis']);
    final done = n(f?['done']) ?? 0, total = n(f?['total_today']) ?? 0, overdue = n(f?['overdue']) ?? 0, due = n(f?['due_today']) ?? 0;
    final chats = asRows(d?['recent_chats']);
    final dueList = asRows(d?['followups_due']);
    final stages = asRows(d?['leads_by_stage']);
    const stageTints = [tintPeach, tintAmber, tintBlue, tintGreen, tintRed];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (async.hasError && d == null) WsLoadError(async.error, () => ref.invalidate(wsHomeProvider('sales'))),
      WsSummary(
        title: "Today's follow-ups",
        value: '${fmtNum(done)} / ${fmtNum(total)}',
        suffix: 'done',
        badge: overdue > 0 ? '${fmtNum(overdue)} overdue' : null,
        progress: total > 0 ? (done / total).toDouble() : 0,
        actions: [WsHeroButton('Start follow-ups', () => context.goToRoute('/crm-followups')), WsHeroButton('Plan day', () => context.goToRoute('/crm-tasks'), filled: false)],
      ),
      const WsAttendance(),
      WsTiles([
        ('Leads', fmtNum(asMap(k?['leads'])?['total']), '${fmtNum(asMap(k?['leads'])?['new_today'])} new today', tintPeach, () => context.goToRoute('/leads')),
        ('Contacts', fmtNum(asMap(k?['contacts'])?['total']), '+${fmtNum(asMap(k?['contacts'])?['new_week'])} this week', tintBlue, () => context.goToRoute('/contacts')),
        ('Chats', fmtNum(asMap(k?['chats'])?['unread']), 'people waiting (24 h)', tintGreen, () => context.goToRoute('/wa-chat/chats')),
        ('Follow-ups', fmtNum(due), 'due today · ${fmtNum(overdue)} overdue', tintAmber, () => context.goToRoute('/crm-followups')),
      ]),
      WsSection(
        title: 'Recent chats',
        action: 'Open inbox',
        onAction: () => context.goToRoute('/wa-chat/chats'),
        child: WsRows([
          for (final c in chats)
            WsRow(leading: WsAvatar('${c['name'] ?? ''}'), title: '${c['name'] ?? ''}', subtitle: '${c['channel'] ?? ''} · ${c['preview'] ?? ''}', trailing: Text(wsAgo('${c['at'] ?? ''}'), style: TextStyle(fontSize: 11, color: context.mutedColor))),
        ], empty: 'No recent chats.'),
      ),
      WsSection(
        title: 'Follow-ups due',
        action: 'See all ${fmtNum(due + overdue)}',
        onAction: () => context.goToRoute('/crm-followups'),
        child: WsRows([
          for (final t in dueList)
            WsRow(
              title: '${t['title'] ?? 'Follow-up'}',
              subtitle: '${t['contact'] ?? t['type'] ?? ''}',
              trailing: t['overdue'] == true ? const WsBadge('Overdue', tintRed) : WsBadge(wsClock('${t['due_at'] ?? ''}'), tintLavender),
            ),
        ], empty: 'Nothing due — nice.'),
      ),
      WsSection(
        title: 'Leads by stage',
        action: 'View all',
        onAction: () => context.goToRoute('/leads'),
        child: WsChips([for (var i = 0; i < stages.length; i++) ('${stages[i]['label']}', fmtNum(stages[i]['count']), stageTints[i % stageTints.length])]),
      ),
      const SizedBox(height: 12),
    ]);
  }
}

class _SalesStaff extends ConsumerWidget {
  const _SalesStaff();

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wsHomeProvider('sales'));
    final d = dataOf(async);
    final me = dataOf(ref.watch(dashboardMeProvider));
    final target = asMap(me?['sales_target']);
    final rank = asMap(me?['rank']);
    final f = asMap(d?['followups']);
    final k = asMap(d?['kpis']);
    final hot = asRows(d?['hot_leads']);
    final pct = (n(target?['progress']) ?? 0).toDouble();
    final done = n(f?['done']) ?? 0, total = n(f?['total_today']) ?? 0;

    Widget action(IconData icon, String label, Tint t, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: t.$1, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [Icon(icon, size: 20, color: t.$2), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.$3))]),
            ),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (async.hasError && d == null) WsLoadError(async.error, () => ref.invalidate(wsHomeProvider('sales'))),
      WsSummary(
        title: 'My target · this month',
        value: fmtMoney(target?['achieved']),
        suffix: 'of ${fmtMoney(target?['target'])} · ${pct.round()}%',
        badge: rank?['position'] != null ? 'Rank #${rank!['position']} in team' : null,
        progress: pct / 100,
        footer: target?['remaining'] != null ? '${fmtMoney(target?['remaining'])} to go' : null,
      ),
      const WsAttendance(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          action(Icons.person_add_alt_1_rounded, 'Add lead', tintLavender, () => context.goToRoute('/leads')),
          const SizedBox(width: 8),
          action(Icons.phone_outlined, 'Log call', tintBlue, () => context.goToRoute('/leads')),
          const SizedBox(width: 8),
          action(Icons.chat_outlined, 'WhatsApp', tintGreen, () => context.goToRoute('/wa-chat/chats')),
          const SizedBox(width: 8),
          action(Icons.event_outlined, 'Meeting', tintPeach, () => context.goToRoute('/calendar')),
        ]),
      ),
      WsTiles([
        ('Follow-ups', '${fmtNum(done)}/${fmtNum(total)}', 'done today', tintBlue, () => context.goToRoute('/crm-followups')),
        ('New leads', fmtNum(asMap(k?['leads'])?['new_today']), 'today', tintPeach, () => context.goToRoute('/leads')),
        ('My leads', fmtNum(asMap(k?['leads'])?['total']), 'in my pipeline', tintLavender, () => context.goToRoute('/leads')),
        ('Chats', fmtNum(asMap(k?['chats'])?['unread']), 'waiting', tintGreen, () => context.goToRoute('/wa-chat/chats')),
      ]),
      WsSection(
        title: 'Hot leads',
        action: 'My leads',
        onAction: () => context.goToRoute('/leads'),
        child: WsRows([
          for (final l in hot)
            WsRow(
              leading: WsAvatar('${l['name'] ?? ''}'),
              title: '${l['name'] ?? ''}',
              subtitle: '${'${l['stage'] ?? ''}'.replaceAll('_', ' ')} · ${wsAgo('${l['updated_at'] ?? ''}')} ago',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                WsIconBtn(Icons.phone_outlined, () => _open('tel:${l['phone']}')),
                const SizedBox(width: 8),
                WsIconBtn(Icons.chat_rounded, () => _open('https://wa.me/${'${l['phone']}'.replaceAll(RegExp(r'[^0-9]'), '')}'), fg: Colors.white, bg: M.taskDoneBg),
              ]),
            ),
        ], empty: 'New leads assigned to you will appear here.'),
      ),
      const SizedBox(height: 12),
    ]);
  }
}
