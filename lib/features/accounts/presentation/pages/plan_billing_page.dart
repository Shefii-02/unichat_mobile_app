import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Split out of the former shared `WalletPage` (tab 2, "Plan") — its own catalogue tile
/// ("Plan Billing"), now its own independent page.
class PlanBillingPage extends StatelessWidget {
  const PlanBillingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan Billing')),
      body: ProviderObject(
        provider: currentPlanProvider,
        builder: (context, d) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(str(d['name'] ?? d['plan_name'] ?? d['plan'], 'Current plan'),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              ..._flatten(d).map((e) => KvRow(e.$1, e.$2)),
            ],
          ),
        ),
      ),
    );
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
