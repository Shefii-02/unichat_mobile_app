import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Split out of the former shared `MetaAdsPage` (tab 0, "Insights").
class MetaAdsInsightsPage extends ConsumerWidget {
  const MetaAdsInsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ads Insight')),
      body: ProviderObject(
        provider: metaInsightsOverviewProvider,
        builder: (context, d) {
          final items = <(String, String, IconData)>[
            ('Spend', money(d['spend'] ?? d['total_spend']), Icons.payments_rounded),
            ('Impressions', compact(d['impressions']), Icons.visibility_rounded),
            ('Clicks', compact(d['clicks']), Icons.ads_click_rounded),
            ('CTR', '${d['ctr'] ?? 0}%', Icons.percent_rounded),
            ('Leads', compact(d['leads'] ?? d['results']), Icons.person_add_alt_rounded),
            ('CPL', money(d['cpl'] ?? d['cost_per_lead']), Icons.request_quote_rounded),
          ];
          return ListView(children: [StatGrid(items)]);
        },
      ),
    );
  }
}
