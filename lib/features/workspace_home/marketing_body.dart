import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/router/shell_routes.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/workspace_home/ws_style.dart';

/// Marketing workspace Home: leads from marketing (30 days) with a 7-day chart, campaigns / templates / flows / social tiles, live campaigns, flows.
class MarketingBody extends ConsumerWidget {
  const MarketingBody({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wsHomeProvider('marketing'));
    final d = dataOf(async);
    final tiles = asMap(d?['tiles']);
    final days = asRows(d?['daily_leads']);
    final live = asRows(d?['live_campaigns']);
    final flows = asRows(d?['flows']);
    final peak = days.fold<num>(1, (m, x) => (n(x['leads']) ?? 0) > m ? n(x['leads'])! : m);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (async.hasError && d == null) WsLoadError(async.error, () => ref.invalidate(wsHomeProvider('marketing'))),
      WsSummary(
        title: 'Leads from marketing · last 30 days',
        value: fmtNum(d?['leads_30d']),
        footer: 'Cost / lead ${fmtMoney(d?['cost_per_lead'])} · Ad spend ${fmtMoney(d?['spend_30d'])} · CTR ${d?['ctr'] == null ? '—' : '${fmtNum(d?['ctr'])}%'}',
        actions: const [],
      ),
      if (days.isNotEmpty)
        Container(
          width: double.infinity,
          color: M.heroBg,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: SizedBox(
            height: 64,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final x in days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Container(height: 6 + 36 * ((n(x['leads']) ?? 0) / peak).toDouble(), decoration: BoxDecoration(color: (n(x['leads']) ?? 0) == peak && peak > 1 ? M.heroRing : Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(5))),
                      const SizedBox(height: 4),
                      Text('${x['day'] ?? ''}', style: const TextStyle(fontSize: 10, color: M.heroMuted)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      const WsAttendance(),
      WsTiles([
        ('Campaigns', fmtNum(asMap(tiles?['campaigns'])?['live']), 'live now', tintPeach, () => context.goToRoute('/meta-ads/campaigns')),
        ('Templates', fmtNum(asMap(tiles?['templates'])?['total']), '${fmtNum(asMap(tiles?['templates'])?['approved'])} approved', tintLavender, () => context.goToRoute('/wa-cloud/templates')),
        ('Flows', fmtNum(asMap(tiles?['flows'])?['total']), '${fmtNum(asMap(tiles?['flows'])?['running'])} running', tintGreen, () => context.goToRoute('/instagram/automations')),
        ('Social & ads', fmtNum(asMap(tiles?['social'])?['accounts']), 'accounts connected', tintAmber, () => context.goToRoute('/instagram')),
      ]),
      WsSection(
        title: 'Live campaigns',
        perms: const ['campaigns.view', 'meta_ads.view'],
        action: 'All campaigns',
        onAction: () => context.goToRoute('/meta-ads/campaigns'),
        child: WsRows([
          for (final c in live)
            WsRow(
              title: '${c['name'] ?? 'Campaign'}',
              subtitle: '${c['type'] ?? ''} · ${asMap(c['a'])?['label']} ${asMap(c['a'])?['money'] == true ? fmtMoney(asMap(c['a'])?['value']) : fmtNum(asMap(c['a'])?['value'])} · ${asMap(c['b'])?['label']} ${fmtNum(asMap(c['b'])?['value'])}',
              trailing: c['leads'] != null ? WsBadge('${fmtNum(c['leads'])} leads', tintGreen) : (c['progress'] != null ? Text('${((n(c['progress']) ?? 0) * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w600)) : null),
            ),
        ], empty: 'No live campaigns — start one from Campaigns.'),
      ),
      WsSection(
        title: 'Automation flows',
        perms: const ['flow_builder.view', 'instagram.view'],
        action: '+ New flow',
        onAction: () => context.goToRoute('/instagram/automations'),
        child: WsRows([
          for (final f in flows) WsRow(title: '${f['name'] ?? 'Flow'}', subtitle: '${fmtNum(f['runs'])} runs', trailing: Switch(value: f['active'] == true, onChanged: null)),
        ], empty: 'No automation flows yet.'),
      ),
      const SizedBox(height: 12),
    ]);
  }
}
