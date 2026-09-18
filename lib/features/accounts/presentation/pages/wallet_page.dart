import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Balance + Transactions — split out of the former shared `WalletPage` (tabs 0-1); "Plan"
/// (tab 2) is its own catalogue tile and now its own page, `PlanBillingPage`.
class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wallet'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Balance'),
            Tab(text: 'Transactions'),
          ]),
        ),
        body: TabBarView(children: [
          ProviderObject(
            provider: walletProvider,
            builder: (context, d) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                      ]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Available balance',
                            style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 6),
                        Text(
                          money(d['balance'] ?? d['wallet_balance'] ?? d['amount']),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SectionHeader('Details'),
                  ..._flatten(d).map((e) => KvRow(e.$1, e.$2)),
                ],
              );
            },
          ),
          ProviderList(
            provider: walletTxProvider,
            emptyLabel: 'No transactions yet',
            tile: (context, t) => RecordCard(
              title: str(t['description'] ?? t['type'] ?? t['note'], 'Transaction'),
              subtitle: when(t['created_at'] ?? t['date']),
              leadingIcon: ('${t['type'] ?? ''}'.contains('credit') ||
                      num.tryParse('${t['amount'] ?? 0}') != null &&
                          (num.tryParse('${t['amount']}') ?? 0) > 0)
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              trailing: Text(money(t['amount'] ?? t['value']),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
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
