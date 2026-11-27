import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/router/shell_routes.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/chat_channels/my_chats.dart';
import 'package:unichat_mobile_app/features/contacts/presentation/pages/contacts_page.dart';
import 'package:unichat_mobile_app/features/leads/presentation/pages/leads_page.dart';
import 'package:unichat_mobile_app/features/workspace_home/sales_feed.dart';
import 'package:unichat_mobile_app/features/workspace_home/ws_style.dart';

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
      const WsAttendance(afterPunchOnly: true),
      SalesFeed(onChanged: () => ref.invalidate(wsHomeProvider('sales'))),
      WsTiles([
        ('Leads', fmtNum(asMap(k?['leads'])?['total']), '${fmtNum(asMap(k?['leads'])?['new_today'])} new today', tintPeach, () => context.goToRoute('/leads')),
        ('Contacts', fmtNum(asMap(k?['contacts'])?['total']), '+${fmtNum(asMap(k?['contacts'])?['new_week'])} this week', tintBlue, () => context.goToRoute('/contacts')),
        ('Chats', fmtNum(asMap(k?['chats'])?['unread']), 'people waiting (24 h)', tintGreen, () => context.goToRoute('/wa-chat/chats')),
        ('Follow-ups', fmtNum(due), 'due today · ${fmtNum(overdue)} overdue', tintAmber, () => context.goToRoute('/crm-followups')),
      ]),
      WsSection(
        title: 'Recent chats',
        perms: const ['wa_chat.chats.view', 'inbox.view'],
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wsHomeProvider('sales'));
    final d = dataOf(async);
    final me = dataOf(ref.watch(dashboardMeProvider));
    final target = asMap(me?['sales_target']);
    final rank = asMap(me?['rank']);
    final f = asMap(d?['followups']);
    final pct = (n(target?['progress']) ?? 0).toDouble();
    final done = n(f?['done']) ?? 0;

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
      const WsAttendance(afterPunchOnly: true),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          action(Icons.person_add_alt_1_rounded, 'Add lead', tintLavender, () async {
            final saved = await showNewLeadSheet(context);
            if (!saved || !context.mounted) return;
            // refresh once the sheet has fully left the screen — rebuilding the Home underneath a closing route trips Flutter's tree asserts
            WidgetsBinding.instance.addPostFrameCallback((_) { if (context.mounted) ref.invalidate(wsHomeProvider('sales')); });
          }),
          const SizedBox(width: 8),
          action(Icons.contact_phone_outlined, 'New contact', tintBlue, () { showNewContactSheet(context); }),
          const SizedBox(width: 8),
          action(Icons.people_alt_outlined, 'Contacts', tintGreen, () => context.push('/contacts')),
          const SizedBox(width: 8),
          action(Icons.call_outlined, 'Call logs', tintPeach, () => context.push('/call-logs')),
        ]),
      ),
      // My chats by channel — round icons with how many are assigned to me; tap for the list (a number / account picker first when there are several).
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final (icon, label, key, tint) in [
            (Icons.cloud_done_rounded, 'WA Cloud', 'wa_cloud', tintGreen),
            (Icons.chat_rounded, 'WA Chat', 'wa_chat', tintGreen),
            (Icons.camera_alt_rounded, 'Instagram', 'instagram', tintPeach),
            (Icons.messenger_rounded, 'Messenger', 'messenger', tintBlue),
            (Icons.web_rounded, 'Web widget', 'widget', tintLavender),
          ])
            _RoundCount(
              icon: icon,
              label: label,
              count: ref.watch(myChatChannelsProvider).maybeWhen(data: (m) => m[key]?.total ?? 0, orElse: () => 0),
              tint: tint,
              onTap: () => openChannel(context, ref, key),
            ),
        ]),
      ),
      // Today at a glance — three cards per row
      WsTiles3([
        ('My leads', '${fmtNum(asMap(d?['cards'])?['my_leads']?['active'])}/${fmtNum(asMap(d?['cards'])?['my_leads']?['total'])}', 'active / total', tintLavender, () => context.goToRoute('/leads'), wide: false),
        ('New leads', '${fmtNum(asMap(d?['cards'])?['new_leads']?['today'])}/${fmtNum(asMap(d?['cards'])?['new_leads']?['prev'])}', 'today / yesterday', tintPeach, () => context.goToRoute('/leads'), wide: false),
        ('Follow-ups', fmtNum(asMap(d?['today'])?['followups']), '${fmtNum(f?['overdue'])} overdue · ${fmtNum(done)} done', tintBlue, () => context.goToRoute('/crm-followups'), wide: false),
        ('Missed', fmtNum(asMap(d?['today'])?['missed']), 'calls today', tintPeach, () => context.push('/call-logs?dir=missed&today=1'), wide: false),
        ('Called', fmtNum(asMap(d?['today'])?['called']), 'calls today', tintBlue, () => context.push('/call-logs?today=1'), wide: false),
        ('Closed', fmtNum(asMap(d?['today'])?['closed']), 'won today', tintGreen, () => context.goToRoute('/leads'), wide: false),
        ('Lost leads', '${fmtNum(asMap(d?['cards'])?['lost']?['today'])}/${fmtNum(asMap(d?['cards'])?['lost']?['total'])}', 'today / total', tintAmber, () => context.goToRoute('/leads'), wide: false),
        ('Transferred', '${fmtNum(asMap(d?['cards'])?['transferred']?['from_me'])} out · ${fmtNum(asMap(d?['cards'])?['transferred']?['to_me'])} in', 'from me · to me (this month)', tintLavender, () => context.goToRoute('/leads'), wide: true),
      ]),
      SalesFeed(onChanged: () => ref.invalidate(wsHomeProvider('sales'))),
      const SizedBox(height: 12),
    ]);
  }
}

/// A round icon with its label underneath and the count floating at the top right (hidden when 0).
class _RoundCount extends StatelessWidget {
  const _RoundCount({required this.icon, required this.label, required this.count, required this.tint, required this.onTap});
  final IconData icon;
  final String label;
  final int count;
  final Tint tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 40,
      child: SizedBox(
        width: 62,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(color: tint.$1, shape: BoxShape.circle), child: Icon(icon, color: tint.$2, size: 24)),
            if (count > 0)
              Positioned(
                top: -4,
                right: -6,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(10), border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2)),
                  child: Text(count > 99 ? '99+' : '$count', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
          const SizedBox(height: 5),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tint.$3)),
        ]),
      ),
    );
  }
}
