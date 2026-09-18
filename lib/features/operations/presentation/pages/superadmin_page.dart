// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/core/permissions/permission_guard.dart";
import "package:unichat_mobile_app/core/storage/local_storage.dart";
import "package:unichat_mobile_app/core/widgets/app_empty_state.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ SuperAdmin ══════════════════════════

class SuperAdminPage extends StatelessWidget {
  const SuperAdminPage({super.key});
  @override
  Widget build(BuildContext context) {
    if (!PermissionGuard.isOwner && !PermissionGuard.can('platform.manage')) {
      return Scaffold(
        appBar: AppBar(title: const Text('SuperAdmin')),
        body: Center(
          child: Text('Platform access only',
              style: TextStyle(color: context.mutedColor)),
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SuperAdmin'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Dashboard'),
            Tab(text: 'Companies'),
          ]),
        ),
        body: TabBarView(children: [
          ProviderObject(
            provider: superAdminDashboardProvider,
            builder: (context, d) {
              final stats = _flatten(d)
                  .where((e) => num.tryParse(e.$2) != null)
                  .take(6)
                  .map((e) => (e.$1, compact(e.$2), Icons.analytics_rounded))
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stats.isNotEmpty) StatGrid(stats),
                  const SectionHeader('All metrics'),
                  ..._flatten(d).map((e) => KvRow(e.$1, e.$2)),
                ],
              );
            },
          ),
          Consumer(
            builder: (context, ref, _) => ProviderList(
              provider: superAdminCompaniesProvider,
              emptyLabel: 'No companies',
              tile: (context, c) {
                final status =
                    str(c['status'] ?? (c['is_active'] == true ? 'active' : 'suspended'));
                return RecordCard(
                  title: str(c['name'] ?? c['company_name'], 'Company'),
                  subtitle:
                      '${str(c['plan'] ?? c['plan_name'], 'no plan')} · ${str(c['email'])}',
                  leadingIcon: Icons.business_rounded,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusPill(status),
                      RowMenu(items: [
                        (
                          status == 'active' ? 'Suspend' : 'Activate',
                          Icons.toggle_on_rounded,
                          () async {
                            final ok = await runAction(
                              context,
                              () => Api.patch(
                                  '/superadmin/companies/${c['id']}/status',
                                  data: {
                                    'status': status == 'active'
                                        ? 'suspended'
                                        : 'active'
                                  }),
                              success: 'Updated',
                            );
                            if (ok) {
                              ref.invalidate(superAdminCompaniesProvider);
                            }
                          }
                        ),
                        (
                          'Top up wallet',
                          Icons.account_balance_wallet_rounded,
                          () => _topUp(context, ref, c),
                        ),
                      ]),
                    ],
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _topUp(BuildContext context, WidgetRef ref, Rec c) async {
    final data = <String, dynamic>{};
    await showFormSheet(
      context,
      title: 'Top up ${str(c['name'] ?? c['company_name'])}',
      submitLabel: 'Add credit',
      fields: (ctx) => [
        FNumber(
          label: 'Amount (₹)',
          required: true,
          onSaved: (v) => data['amount'] = v,
        ),
        FText(
          label: 'Note',
          onSaved: (v) => v.isEmpty ? null : data['note'] = v,
        ),
      ],
      onSubmit: () =>
          Api.post('/superadmin/companies/${c['id']}/top-up', data: data),
    );
  }
}

List<(String, String)> _flatten(Map<String, dynamic> d, [String prefix = '']) {
  final out = <(String, String)>[];
  d.forEach((k, v) {
    final label = prefix.isEmpty ? k : '$prefix · $k';
    if (v is Map) {
      out.addAll(_flatten(v.cast<String, dynamic>(), label));
    } else if (v is List) {
      out.add((label, '${v.length} items'));
    } else {
      out.add((label.replaceAll('_', ' '), '${v ?? '—'}'));
    }
  });
  return out;
}
