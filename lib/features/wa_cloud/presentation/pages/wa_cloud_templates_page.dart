// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// WA Cloud's own Message Templates — split out of the former shared `TemplatesPage`
/// (`?tab=0`), which also served WA Chat's templates from the same tabbed class. Each
/// domain now owns an independent page instead of sharing one class via a tab index.
class WaCloudTemplatesPage extends ConsumerWidget {
  const WaCloudTemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WA Cloud Templates'),
        actions: [
          IconButton(
            tooltip: 'Sync from Meta',
            icon: const Icon(Icons.sync_rounded),
            onPressed: () async {
              final ok = await runAction(context,
                  () => Api.post('/templates/sync-from-meta'),
                  success: 'Synced from Meta');
              if (ok) ref.invalidate(waCloudTemplatesProvider);
            },
          ),
        ],
      ),
      body: ProviderList(
        provider: waCloudTemplatesProvider,
        emptyLabel: 'No cloud templates',
        tile: (context, t) => _templateTile(context, ref, t),
      ),
    );
  }

  Widget _templateTile(BuildContext context, WidgetRef ref, Rec t) {
    final body = t['body'] ??
        t['content'] ??
        (t['components'] is List
            ? (t['components'] as List).firstWhere(
                (c) => c is Map && c['type'] == 'BODY',
                orElse: () => const {})['text']
            : null);
    return RecordCard(
      title: str(t['name']),
      subtitle: str(body),
      leadingIcon: Icons.dashboard_customize_rounded,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(str(t['status'] ?? t['approval_status'], 'draft')),
          RowMenu(items: [
            (
              'Sync status',
              Icons.sync_rounded,
              () async {
                final ok = await runAction(
                    context, () => Api.post('/templates/${t['id']}/sync'),
                    success: 'Synced');
                if (ok) ref.invalidate(waCloudTemplatesProvider);
              }
            ),
            (
              'Duplicate',
              Icons.copy_rounded,
              () async {
                final ok = await runAction(context,
                    () => Api.post('/templates/${t['id']}/duplicate'),
                    success: 'Duplicated');
                if (ok) ref.invalidate(waCloudTemplatesProvider);
              }
            ),
            (
              'Delete',
              Icons.delete_rounded,
              () async {
                if (!await confirm(context,
                    title: 'Delete template?',
                    destructive: true,
                    confirmLabel: 'Delete')) { return; }
                final ok = await runAction(
                    context, () => Api.delete('/templates/${t['id']}'),
                    success: 'Deleted');
                if (ok) ref.invalidate(waCloudTemplatesProvider);
              }
            ),
          ]),
        ],
      ),
      footer: Wrap(
        spacing: 6,
        children: [
          if (t['category'] != null)
            StatusPill(str(t['category']), color: AppPalette.info),
          if (t['language'] != null)
            StatusPill(str(t['language']), color: AppPalette.cold),
        ],
      ),
    );
  }
}
