import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Split out of the former shared `MetaAdsPage` (tab 3, "Accounts").
class MetaAccountsPage extends ConsumerWidget {
  const MetaAccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: ProviderList(
        provider: metaAccountsProvider,
        emptyLabel: 'No ad accounts linked',
        tile: (context, a) => RecordCard(
          title: str(a['ad_account_name'] ?? a['page_name'], 'Ad account'),
          subtitle: '${str(a['ad_account_id'])} · ${str(a['currency'], 'INR')}',
          leadingIcon: Icons.account_box_rounded,
          trailing: (a['is_default'] == true)
              ? const StatusPill('default')
              : StatusPill(str(a['account_status'], 'active')),
          onTap: a['is_default'] == true
              ? null
              : () async {
                  final ok = await runAction(context,
                      () => Api.post('/meta-ads/accounts/${a['id']}/set-default'),
                      success: 'Set as default');
                  if (ok) ref.invalidate(metaAccountsProvider);
                },
        ),
      ),
    );
  }
}
