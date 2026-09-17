// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'module_providers.dart';
import '_shared.dart';

class TemplatesPage extends ConsumerWidget {
  const TemplatesPage({super.key, this.initialTabIndex = 0});

  /// Lets Quick Links open straight on "WA Templates" (tab 0) or "Templates" (tab 1).
  final int initialTabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      initialIndex: initialTabIndex.clamp(0, 1),
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Message Templates'),
          bottom: const TabBar(tabs: [
            Tab(text: 'WA Cloud'),
            Tab(text: 'WA Chat'),
          ]),
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
        body: TabBarView(children: [
          ProviderList(
            provider: waCloudTemplatesProvider,
            emptyLabel: 'No cloud templates',
            tile: (context, t) => _templateTile(context, ref, t, cloud: true),
          ),
          ProviderList(
            provider: waChatTemplatesProvider,
            emptyLabel: 'No chat templates',
            tile: (context, t) => _templateTile(context, ref, t, cloud: false),
          ),
        ]),
      ),
    );
  }

  Widget _templateTile(BuildContext context, WidgetRef ref, Rec t,
      {required bool cloud}) {
    final body = t['body'] ??
        t['content'] ??
        (t['components'] is List
            ? (t['components'] as List).firstWhere(
                (c) => c is Map && c['type'] == 'BODY',
                orElse: () => const {})['text']
            : null);
    final base = cloud ? '/templates' : '/wa-chat-templates';
    return RecordCard(
      title: str(t['name']),
      subtitle: str(body),
      leadingIcon: Icons.dashboard_customize_rounded,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(str(t['status'] ?? t['approval_status'], 'draft')),
          RowMenu(items: [
            if (cloud)
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
            if (cloud)
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
                    context, () => Api.delete('$base/${t['id']}'),
                    success: 'Deleted');
                if (ok) {
                  ref.invalidate(cloud
                      ? waCloudTemplatesProvider
                      : waChatTemplatesProvider);
                }
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
