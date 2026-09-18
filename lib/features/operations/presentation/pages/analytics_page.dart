import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Analytics'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'Leads'),
            Tab(text: 'Wallet'),
          ]),
        ),
        body: TabBarView(children: [
          ProviderObject(
            provider: analyticsOverviewProvider,
            builder: (context, d) => _overview(context, d),
          ),
          ProviderObject(
            provider: analyticsLeadsProvider,
            builder: (context, d) => _kvBlock(context, d),
          ),
          ProviderObject(
            provider: analyticsWalletProvider,
            builder: (context, d) => _kvBlock(context, d),
          ),
        ]),
      ),
    );
  }

  Widget _overview(BuildContext context, Rec d) {
    num n(String k) => num.tryParse('${d[k] ?? (d[k] is Map ? '' : d[k])}') ?? 0;
    final items = <(String, String, IconData)>[
      ('Messages sent', compact(d['messages_sent'] ?? d['total_messages'] ?? n('sent')), Icons.send_rounded),
      ('Delivered', compact(d['delivered'] ?? d['messages_delivered']), Icons.done_all_rounded),
      ('Contacts', compact(d['contacts'] ?? d['total_contacts']), Icons.contacts_rounded),
      ('Leads', compact(d['leads'] ?? d['total_leads']), Icons.trending_up_rounded),
      ('Campaigns', compact(d['campaigns'] ?? d['total_campaigns']), Icons.campaign_rounded),
      ('Conversion', '${d['conversion_rate'] ?? d['conversion'] ?? 0}%', Icons.percent_rounded),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatGrid(items),
        const SectionHeader('Raw metrics'),
        ..._flatten(d).map((e) => KvRow(e.$1, e.$2)),
      ],
    );
  }

  Widget _kvBlock(BuildContext context, Rec d) {
    final rows = _flatten(d);
    if (rows.isEmpty) {
      return Center(
          child: Text('No data', style: TextStyle(color: context.mutedColor)));
    }
    return Column(children: rows.map((e) => KvRow(e.$1, e.$2)).toList());
  }
}

List<(String, String)> _flatten(Map<String, dynamic> d, [String prefix = '']) {
  final out = <(String, String)>[];
  d.forEach((k, v) {
    final label = prefix.isEmpty ? k : '$prefix · $k';
    if (v is Map) {
      out.addAll(_flatten(v.cast<String, dynamic>(), label));
    } else if (v is List) {
      out.add((label, '${v.length} items'));
    } else {
      out.add((label.replaceAll('_', ' '), '${v ?? '—'}'));
    }
  });
  return out;
}
