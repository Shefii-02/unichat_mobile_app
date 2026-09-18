import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Split out of the former shared `MetaAdsPage` (tab 2, "Audience Sets").
class MetaAudienceSetsPage extends ConsumerWidget {
  const MetaAudienceSetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audience Set')),
      body: ProviderList(
        provider: metaAudienceSetsProvider,
        emptyLabel: 'No saved audience sets',
        emptyIcon: Icons.groups_rounded,
        tile: (context, a) => RecordCard(
          title: str(a['name']),
          subtitle: str(a['description'] ?? a['summary'],
              'Reusable targeting preset'),
          leadingIcon: Icons.groups_rounded,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (a['estimated_reach'] != null)
                Text(compact(a['estimated_reach']),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              RowMenu(items: [
                (
                  'Duplicate',
                  Icons.copy_rounded,
                  () async {
                    final ok = await runAction(context,
                        () => Api.post('/meta-ads/audience-sets/${a['id']}/duplicate'),
                        success: 'Duplicated');
                    if (ok) ref.invalidate(metaAudienceSetsProvider);
                  }
                ),
                (
                  'Delete',
                  Icons.delete_rounded,
                  () async {
                    if (!await confirm(context,
                        title: 'Delete audience set?',
                        destructive: true,
                        confirmLabel: 'Delete')) { return; }
                    final ok = await runAction(context,
                        () => Api.delete('/meta-ads/audience-sets/${a['id']}'),
                        success: 'Deleted');
                    if (ok) ref.invalidate(metaAudienceSetsProvider);
                  }
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
