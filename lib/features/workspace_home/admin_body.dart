import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/router/shell_routes.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/workspace_home/ws_style.dart';

/// Administrators workspace Home: plan + seats, staff / roles / devices / integrations, linked devices, integrations, roles & access, activity.
class AdminBody extends ConsumerWidget {
  const AdminBody({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wsHomeProvider('administrators'));
    final d = dataOf(async);
    final plan = asMap(d?['plan']);
    final staff = asMap(d?['staff']);
    final dev = asMap(d?['devices']);
    final roles = asRows(d?['roles']);
    final devices = asRows(dev?['list']);
    final integrations = asRows(d?['integrations']);
    final activity = asRows(d?['recent_activity']);
    final used = n(plan?['seats_used']) ?? 0, limit = n(plan?['seats_limit']);
    final broken = integrations.where((i) => i['ok'] != true).length;
    final planName = '${plan?['name'] ?? ''}'.trim();
    final maxRole = roles.fold<num>(1, (m, r) => (n(r['users']) ?? 0) > m ? n(r['users'])! : m);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (async.hasError && d == null) WsLoadError(async.error, () => ref.invalidate(wsHomeProvider('administrators'))),
      WsSummary(
        title: planName.isEmpty ? 'Your plan' : 'Teamzo $planName plan',
        value: fmtNum(used),
        suffix: limit != null ? '/ ${fmtNum(limit)} seats used' : 'staff',
        badge: broken == 0 ? 'All systems running' : '$broken need attention',
        progress: limit != null && limit > 0 ? used / limit : 0,
        footer: plan?['renews_at'] != null ? 'Renews ${plan?['renews_at']}' : null,
        actions: [WsHeroButton('Invite staff', () => context.goToRoute('/staff')), WsHeroButton('Manage plan', () => context.goToRoute('/account/plan-billing'), filled: false)],
      ),
      const WsAttendance(),
      WsTiles([
        ('Staff', fmtNum(staff?['total']), (n(staff?['inactive']) ?? 0) > 0 ? '${fmtNum(staff?['inactive'])} inactive' : 'all active', tintBlue, () => context.goToRoute('/staff')),
        ('Roles', fmtNum(roles.length), 'with permissions', tintLavender, () => context.goToRoute('/account/roles')),
        ('Devices', fmtNum(dev?['active']), 'signed in', tintPeach, () => context.goToRoute('/devices')),
        ('Integrations', fmtNum(integrations.length), broken > 0 ? '$broken need attention' : 'all healthy', broken > 0 ? tintRed : tintGreen, () => context.goToRoute('/integrations')),
      ]),
      WsSection(
        title: 'Linked devices',
        perms: const ['devices.view'],
        action: 'Manage',
        onAction: () => context.goToRoute('/devices'),
        child: WsRows([
          for (final x in devices.take(4)) WsRow(leading: const Icon(Icons.smartphone_rounded, size: 22), title: '${x['name'] ?? 'Device'}', subtitle: '${x['user'] ?? ''}${x['last_active_at'] != null ? ' · ${wsAgo('${x['last_active_at']}')} ago' : ''}'),
        ], empty: 'No linked devices.'),
      ),
      WsSection(
        title: 'Integrations',
        perms: const ['integrations.view'],
        action: 'Manage',
        onAction: () => context.goToRoute('/integrations'),
        child: WsRows([
          for (final i in integrations) WsRow(leading: WsAvatar('${i['name'] ?? ''}'), title: '${i['name']}', subtitle: '${i['detail'] ?? ''}', trailing: i['ok'] == true ? const WsBadge('Connected', tintGreen) : const WsBadge('Check', tintRed)),
        ], empty: 'Nothing connected yet.'),
      ),
      WsSection(
        title: 'Roles & access',
        perms: const ['roles.view'],
        action: '+ New role',
        onAction: () => context.goToRoute('/account/roles'),
        child: WsRows([
          for (final r in roles.take(7))
            Row(children: [
              Expanded(flex: 4, child: Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              Expanded(flex: 5, child: ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: ((n(r['users']) ?? 0) / maxRole).toDouble(), minHeight: 6, backgroundColor: M.lavenderBg, valueColor: const AlwaysStoppedAnimation(M.lavenderMuted)))),
              SizedBox(width: 30, child: Text(fmtNum(r['users']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
        ], empty: 'No roles yet.'),
      ),
      WsSection(
        title: 'Recent activity',
        child: WsRows([for (final a in activity) WsRow(title: '${a['text']}', subtitle: '${wsAgo('${a['at']}')} ago')], empty: 'No recent activity.'),
      ),
      const SizedBox(height: 12),
    ]);
  }
}
