// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'module_providers.dart';
import '_shared.dart';

class FlowBuilderPage extends ConsumerWidget {
  const FlowBuilderPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flow Builder')),
      body: ProviderList(
        provider: flowBuildersProvider,
        emptyLabel: 'No flows built yet',
        emptyIcon: Icons.account_tree_rounded,
        tile: (context, f) {
          final active = f['is_active'] == true ||
              f['active'] == true ||
              f['status'] == 'active';
          return RecordCard(
            title: str(f['name'] ?? f['title']),
            subtitle:
                '${str(f['description'] ?? f['trigger_type'] ?? f['trigger'])} · ${str(f['nodes_count'] ?? (f['nodes'] is List ? (f['nodes'] as List).length : ''), '0')} steps',
            leadingIcon: Icons.account_tree_rounded,
            leadingColor: const Color(0xFF8B5CF6),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(active ? 'active' : 'inactive'),
                RowMenu(items: [
                  (
                    active ? 'Deactivate' : 'Activate',
                    Icons.toggle_on_rounded,
                    () async {
                      final ok = await runAction(
                          context,
                          () => Api.post(
                              '/flow-builders/${f['id']}/${active ? 'deactivate' : 'activate'}'),
                          success: 'Updated');
                      if (ok) ref.invalidate(flowBuildersProvider);
                    }
                  ),
                  (
                    'Delete',
                    Icons.delete_rounded,
                    () async {
                      if (!await confirm(context,
                          title: 'Delete flow?',
                          destructive: true,
                          confirmLabel: 'Delete')) { return; }
                      final ok = await runAction(context,
                          () => Api.delete('/flow-builders/${f['id']}'),
                          success: 'Deleted');
                      if (ok) ref.invalidate(flowBuildersProvider);
                    }
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }
}
