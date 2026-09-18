import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Split out of the former shared `WaCloudPage` (tab 0) — an independent page instead of
/// one class shared with `WaCloudAutomationsPage` via a tab index.
class WaCloudInboxAnalyticsPage extends ConsumerWidget {
  const WaCloudInboxAnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('WA Cloud — Inbox Analytics')),
      body: ProviderObject(
        provider: waCloudInboxAnalyticsProvider,
        builder: (context, d) {
          final items = <(String, String, IconData)>[
            ('Messages in', compact(d['messages_in'] ?? d['inbound']), Icons.call_received_rounded),
            ('Messages out', compact(d['messages_out'] ?? d['outbound']), Icons.call_made_rounded),
            ('Conversations', compact(d['conversations']), Icons.forum_rounded),
            ('Calls', compact(d['calls']), Icons.call_rounded),
            ('Avg first reply', str(d['avg_first_response'] ?? d['first_reply'], '—'), Icons.timer_outlined),
            ('Resolved', compact(d['resolved']), Icons.check_circle_rounded),
          ];
          return ListView(children: [StatGrid(items)]);
        },
      ),
    );
  }
}
