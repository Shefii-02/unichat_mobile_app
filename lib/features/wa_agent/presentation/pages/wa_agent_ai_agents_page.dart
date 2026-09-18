import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Split out of the former shared `WaAgentPage` (tab 0 "Stats" + tab 1 "Sessions", which had
/// no catalogue tile of its own — kept alongside Stats here rather than left unreachable).
/// Playbook (tab 2) is its own catalogue tile and is now `WaAgentPlaybooksPage`.
class WaAgentAiAgentsPage extends ConsumerWidget {
  const WaAgentAiAgentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AI Agents'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Stats'),
            Tab(text: 'Sessions'),
          ]),
        ),
        body: TabBarView(children: [
          ProviderObject(
            provider: waAgentStatsProvider,
            builder: (context, d) {
              final items = <(String, String, IconData)>[
                ('Conversations', compact(d['conversations'] ?? d['total_sessions']), Icons.forum_rounded),
                ('Handled by AI', compact(d['ai_handled'] ?? d['auto_resolved']), Icons.smart_toy_rounded),
                ('Handed off', compact(d['handed_off'] ?? d['transferred']), Icons.swap_horiz_rounded),
                ('Leads created', compact(d['leads'] ?? d['leads_created']), Icons.trending_up_rounded),
                ('Avg reply', str(d['avg_response_time'] ?? d['avg_reply'], '—'), Icons.timer_outlined),
                ('Satisfaction', '${d['satisfaction'] ?? d['csat'] ?? 0}%', Icons.sentiment_satisfied_rounded),
              ];
              return ListView(children: [StatGrid(items)]);
            },
          ),
          ProviderList(
            provider: waAgentSessionsProvider,
            emptyLabel: 'No agent sessions',
            tile: (context, s) => RecordCard(
              title: str(s['contact_name'] ?? s['contact'] ?? s['phone'], 'Session'),
              subtitle:
                  '${str(s['last_message'] ?? s['summary'])} · ${when(s['updated_at'] ?? s['last_activity_at'])}',
              leadingIcon: Icons.smart_toy_rounded,
              leadingColor: const Color(0xFF14B8A6),
              trailing: RowMenu(items: [
                (
                  'Close',
                  Icons.check_rounded,
                  () async {
                    final ok = await runAction(context,
                        () => Api.post('/wa-agent/sessions/${s['id']}/close'),
                        success: 'Closed');
                    if (ok) ref.invalidate(waAgentSessionsProvider);
                  }
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
