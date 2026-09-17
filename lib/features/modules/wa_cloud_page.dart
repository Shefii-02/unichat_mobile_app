// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'module_providers.dart';
import '_shared.dart';

class WaCloudPage extends ConsumerWidget {
  const WaCloudPage({super.key, this.initialTabIndex = 0});

  /// Lets Quick Links open straight on "Inbox Analytics" (tab 0) or "Agent Automations"
  /// (tab 1).
  final int initialTabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      initialIndex: initialTabIndex.clamp(0, 1),
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('WA Cloud'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Inbox Analytics'),
            Tab(text: 'Automations'),
          ]),
        ),
        floatingActionButton: Builder(
          builder: (tabCtx) {
            final idx = DefaultTabController.of(tabCtx).index;
            if (idx != 1) return const SizedBox.shrink();
            return FloatingActionButton.extended(
              onPressed: () => _editRule(tabCtx, ref, null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New rule'),
            );
          },
        ),
        body: TabBarView(children: [
          ProviderObject(
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
          ProviderList(
            provider: waCloudAutomationsProvider,
            emptyLabel: 'No automation rules',
            emptyIcon: Icons.bolt_rounded,
            tile: (context, a) {
              final active = a['is_active'] == true || a['active'] == true;
              return RecordCard(
                title: str(a['name'] ?? a['title']),
                subtitle: str(
                    a['rule_type'] ?? a['trigger'] ?? a['description']),
                leadingIcon: Icons.bolt_rounded,
                leadingColor: const Color(0xFF0EA5E9),
                trailing: RowMenu(items: [
                  (
                    active ? 'Disable' : 'Enable',
                    Icons.toggle_on_rounded,
                    () async {
                      final ok = await runAction(context,
                          () => Api.post('/wa-cloud/automations/${a['id']}/toggle'),
                          success: 'Updated');
                      if (ok) ref.invalidate(waCloudAutomationsProvider);
                    }
                  ),
                  ('Edit', Icons.edit_rounded,
                      () => _editRule(context, ref, a)),
                  (
                    'Delete',
                    Icons.delete_rounded,
                    () async {
                      if (!await confirm(context,
                          title: 'Delete rule?',
                          destructive: true,
                          confirmLabel: 'Delete')) { return; }
                      final ok = await runAction(context,
                          () => Api.delete('/wa-cloud/automations/${a['id']}'),
                          success: 'Deleted');
                      if (ok) ref.invalidate(waCloudAutomationsProvider);
                    }
                  ),
                ]),
              );
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _editRule(BuildContext context, WidgetRef ref, Rec? a) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: a == null ? 'New automation rule' : 'Edit rule',
      fields: (ctx) => [
        FText(
          label: 'Name',
          required: a == null,
          initial: a?['name'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['name'] = v,
        ),
        FSelect<String>(
          label: 'Rule type',
          options: const [
            'keyword_reply',
            'welcome',
            'away',
            'follow_up',
            'inactivity',
          ],
          initial: (a?['rule_type'] as String?) ?? 'keyword_reply',
          onSaved: (v) => data['rule_type'] = v ?? 'keyword_reply',
        ),
        FChips(
          label: 'Keywords',
          initial: ((a?['keywords'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
          onSaved: (v) => data['keywords'] = v,
        ),
        FText(
          label: 'Reply message',
          maxLines: 4,
          initial: a?['actions'] is List &&
                  (a!['actions'] as List).isNotEmpty &&
                  (a['actions'] as List).first is Map
              ? '${((a['actions'] as List).first as Map)['message'] ?? ''}'
              : null,
          onSaved: (v) => data['actions'] = [
            {'type': 'send_message', 'message': v}
          ],
        ),
        FBoolField(
          label: 'Active',
          initial: a?['is_active'] != false,
          onSaved: (v) => data['is_active'] = v,
        ),
      ],
      onSubmit: () => a == null
          ? Api.post('/wa-cloud/automations', data: data)
          : Api.patch('/wa-cloud/automations/${a['id']}', data: data),
    );
    if (ok) ref.invalidate(waCloudAutomationsProvider);
  }
}
