import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Split out of the former shared `MetaAdsPage` (tab 1, "Campaigns").
class MetaCampaignsPage extends ConsumerWidget {
  const MetaCampaignsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Campaigns')),
      body: ProviderList(
        provider: metaCampaignsProvider,
        emptyLabel: 'No campaigns',
        tile: (context, c) {
          final status = str(c['status'] ?? c['effective_status'], 'PAUSED');
          return RecordCard(
            title: str(c['name']),
            subtitle:
                '${str(c['objective'])} · budget ${money(c['daily_budget'] ?? c['budget'] ?? c['lifetime_budget'])}',
            leadingIcon: Icons.campaign_rounded,
            leadingColor: const Color(0xFF1877F2),
            trailing: StatusPill(status),
            onTap: () => _campaignDetail(context, ref, c),
          );
        },
      ),
    );
  }

  void _campaignDetail(BuildContext context, WidgetRef ref, Rec c) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(str(c['name']),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              KvRow('Objective', str(c['objective'])),
              KvRow('Status', str(c['status'] ?? c['effective_status'])),
              KvRow('Daily budget', money(c['daily_budget'])),
              KvRow('Lifetime budget', money(c['lifetime_budget'])),
              KvRow('Special category', str(c['special_ad_categories'] ?? c['special_ad_category'], 'none')),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in ['ACTIVE', 'PAUSED', 'ARCHIVED'])
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        final ok = await runAction(
                          context,
                          () => Api.patch('/meta-ads/campaigns/${c['id']}/status',
                              data: {'status': s}),
                          success: 'Campaign $s',
                        );
                        if (ok) ref.invalidate(metaCampaignsProvider);
                      },
                      child: Text(s),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      final ok = await runAction(context,
                          () => Api.post('/meta-ads/campaigns/${c['id']}/duplicate'),
                          success: 'Duplicated');
                      if (ok) ref.invalidate(metaCampaignsProvider);
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Duplicate'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      if (!await confirm(context,
                          title: 'Delete campaign?',
                          destructive: true,
                          confirmLabel: 'Delete')) { return; }
                      final ok = await runAction(context,
                          () => Api.delete('/meta-ads/campaigns/${c['id']}'),
                          success: 'Deleted');
                      if (ok) ref.invalidate(metaCampaignsProvider);
                    },
                    icon: const Icon(Icons.delete_rounded,
                        size: 16, color: AppPalette.danger),
                    label: const Text('Delete',
                        style: TextStyle(color: AppPalette.danger)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
