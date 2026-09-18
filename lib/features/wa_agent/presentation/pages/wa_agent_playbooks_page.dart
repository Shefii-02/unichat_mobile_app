import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Split out of the former shared `WaAgentPage` (tab 2, "Playbook").
class WaAgentPlaybooksPage extends ConsumerWidget {
  const WaAgentPlaybooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Playbooks')),
      body: ProviderList(
        provider: waAgentPlaybookProvider,
        emptyLabel: 'No playbook entries',
        emptyIcon: Icons.menu_book_rounded,
        tile: (context, p) => RecordCard(
          title: str(p['name'] ?? p['title'] ?? p['category'], 'Playbook'),
          subtitle: str(p['description'] ?? p['instructions'] ?? p['goal']),
          leadingIcon: Icons.auto_stories_rounded,
          leadingColor: const Color(0xFF14B8A6),
          trailing: RowMenu(items: [
            (
              (p['is_active'] == true) ? 'Disable' : 'Enable',
              Icons.toggle_on_rounded,
              () async {
                final ok = await runAction(context,
                    () => Api.post('/wa-agent/playbook/${p['id']}/toggle'),
                    success: 'Updated');
                if (ok) ref.invalidate(waAgentPlaybookProvider);
              }
            ),
            (
              'Delete',
              Icons.delete_rounded,
              () async {
                if (!await confirm(context,
                    title: 'Delete entry?',
                    destructive: true,
                    confirmLabel: 'Delete')) { return; }
                final ok = await runAction(context,
                    () => Api.delete('/wa-agent/playbook/${p['id']}'),
                    success: 'Deleted');
                if (ok) ref.invalidate(waAgentPlaybookProvider);
              }
            ),
          ]),
        ),
      ),
    );
  }
}
