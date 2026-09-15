// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/core/widgets/app_empty_state.dart';
import 'module_providers.dart';
import '_shared.dart';

// ══════════════════════════ Analytics ══════════════════════════

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Analytics'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'Leads'),
            Tab(text: 'Wallet'),
          ]),
        ),
        body: TabBarView(children: [
          ProviderObject(
            provider: analyticsOverviewProvider,
            builder: (context, d) => _overview(context, d),
          ),
          ProviderObject(
            provider: analyticsLeadsProvider,
            builder: (context, d) => _kvBlock(context, d),
          ),
          ProviderObject(
            provider: analyticsWalletProvider,
            builder: (context, d) => _kvBlock(context, d),
          ),
        ]),
      ),
    );
  }

  Widget _overview(BuildContext context, Rec d) {
    num n(String k) => num.tryParse('${d[k] ?? (d[k] is Map ? '' : d[k])}') ?? 0;
    final items = <(String, String, IconData)>[
      ('Messages sent', compact(d['messages_sent'] ?? d['total_messages'] ?? n('sent')), Icons.send_rounded),
      ('Delivered', compact(d['delivered'] ?? d['messages_delivered']), Icons.done_all_rounded),
      ('Contacts', compact(d['contacts'] ?? d['total_contacts']), Icons.contacts_rounded),
      ('Leads', compact(d['leads'] ?? d['total_leads']), Icons.trending_up_rounded),
      ('Campaigns', compact(d['campaigns'] ?? d['total_campaigns']), Icons.campaign_rounded),
      ('Conversion', '${d['conversion_rate'] ?? d['conversion'] ?? 0}%', Icons.percent_rounded),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatGrid(items),
        const SectionHeader('Raw metrics'),
        ..._flatten(d).map((e) => KvRow(e.$1, e.$2)),
      ],
    );
  }

  Widget _kvBlock(BuildContext context, Rec d) {
    final rows = _flatten(d);
    if (rows.isEmpty) {
      return Center(
          child: Text('No data', style: TextStyle(color: context.mutedColor)));
    }
    return Column(children: rows.map((e) => KvRow(e.$1, e.$2)).toList());
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

// ══════════════════════════ Wallet & Plans ══════════════════════════

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wallet & Plans'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Balance'),
            Tab(text: 'Transactions'),
            Tab(text: 'Plan'),
          ]),
        ),
        body: TabBarView(children: [
          ProviderObject(
            provider: walletProvider,
            builder: (context, d) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                      ]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Available balance',
                            style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 6),
                        Text(
                          money(d['balance'] ?? d['wallet_balance'] ?? d['amount']),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SectionHeader('Details'),
                  ..._flatten(d).map((e) => KvRow(e.$1, e.$2)),
                ],
              );
            },
          ),
          ProviderList(
            provider: walletTxProvider,
            emptyLabel: 'No transactions yet',
            tile: (context, t) => RecordCard(
              title: str(t['description'] ?? t['type'] ?? t['note'], 'Transaction'),
              subtitle: when(t['created_at'] ?? t['date']),
              leadingIcon: ('${t['type'] ?? ''}'.contains('credit') ||
                      num.tryParse('${t['amount'] ?? 0}') != null &&
                          (num.tryParse('${t['amount']}') ?? 0) > 0)
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              trailing: Text(money(t['amount'] ?? t['value']),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          ProviderObject(
            provider: currentPlanProvider,
            builder: (context, d) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(str(d['name'] ?? d['plan_name'] ?? d['plan'], 'Current plan'),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ..._flatten(d).map((e) => KvRow(e.$1, e.$2)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════ Devices ══════════════════════════

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Linked devices')),
      body: ProviderObject(
        provider: devicesProvider,
        builder: (context, res) {
          final rows = ((res['devices'] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
          final max = (res['max'] as num?)?.toInt() ?? 2;
          final active = (res['active'] as num?)?.toInt() ?? 0;
          final myUid = LocalStorage.getString(LocalStorage.kDeviceUid);

          if (rows.isEmpty) {
            return const AppEmptyState(
              icon: Icons.devices_rounded,
              title: 'No linked devices',
            );
          }

          bool isActiveRow(Rec d) =>
              d['revoked_at'] == null && (d['active'] == null || d['active'] == true);
          bool isThisDevice(Rec d) =>
              myUid != null && myUid.isNotEmpty && d['device_uid'] == myUid;

          final activeRows = rows.where(isActiveRow).toList();
          final historyRows = rows.where((d) => !isActiveRow(d)).toList();
          final hasOtherActive = activeRows.any((d) => !isThisDevice(d));

          Widget deviceCard(Rec d, {required bool isHistory}) {
            final platform = '${d['platform'] ?? ''}'.toLowerCase();
            final mine = isThisDevice(d);
            return RecordCard(
              title: str(d['device_name'] ?? d['name'], 'Device') +
                  (mine ? ' (this device)' : ''),
              subtitle:
                  '${str(d['platform'], 'unknown')} · last active ${when(d['last_active_at'])}',
              leadingIcon: platform.contains('ios')
                  ? Icons.phone_iphone_rounded
                  : platform.contains('android')
                      ? Icons.phone_android_rounded
                      : Icons.devices_rounded,
              trailing: StatusPill(isHistory ? 'revoked' : 'active'),
              footer: !isHistory && !mine
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          final ok = await runAction(
                            context,
                            () => Api.delete('/devices/${d['id']}'),
                            success: 'Device removed',
                          );
                          if (ok) ref.invalidate(devicesProvider);
                        },
                        icon: const Icon(Icons.link_off_rounded, size: 18),
                        label: const Text('Unlink'),
                      ),
                    )
                  : !isHistory && mine
                      ? Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Use Logout in Settings to sign this device out.',
                            style: TextStyle(color: context.mutedColor, fontSize: 12),
                          ),
                        )
                      : isHistory
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () async {
                                  final ok = await runAction(
                                    context,
                                    () => Api.delete('/devices/history/${d['id']}'),
                                    success: 'Removed from history',
                                  );
                                  if (ok) ref.invalidate(devicesProvider);
                                },
                                style: TextButton.styleFrom(
                                    foregroundColor: Theme.of(context).colorScheme.error),
                                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                label: const Text('Delete'),
                              ),
                            )
                          : null,
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: (active >= max
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      active >= max
                          ? Icons.warning_amber_rounded
                          : Icons.devices_other_rounded,
                      color: active >= max
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        active >= max
                            ? '$active of $max device slots used — remove one below to link a new device.'
                            : '$active of $max device slots used.',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Active devices ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Active', style: Theme.of(context).textTheme.titleSmall),
                  if (hasOtherActive)
                    TextButton(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Unlink all other devices?'),
                            content: const Text(
                                'Every device except this one will be signed out immediately.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Unlink all')),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        final ok = await runAction(
                          context,
                          () => Api.post('/devices/unlink-all'),
                          success: 'Other devices unlinked',
                        );
                        if (ok) ref.invalidate(devicesProvider);
                      },
                      child: const Text('Unlink all'),
                    ),
                ],
              ),
              if (activeRows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No active devices.',
                      style: TextStyle(color: context.mutedColor, fontSize: 13)),
                )
              else
                ...activeRows.map((d) => deviceCard(d, isHistory: false)),

              // ── History (already-removed devices) ──
              if (historyRows.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('History', style: Theme.of(context).textTheme.titleSmall),
                    TextButton(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Clear all history?'),
                            content: const Text(
                                'Permanently deletes the record of every previously removed device.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Clear all')),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        final ok = await runAction(
                          context,
                          () => Api.delete('/devices/history'),
                          success: 'History cleared',
                        );
                        if (ok) ref.invalidate(devicesProvider);
                      },
                      child: const Text('Clear all'),
                    ),
                  ],
                ),
                ...historyRows.map((d) => deviceCard(d, isHistory: true)),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ══════════════════════════ Setup Guide ══════════════════════════

class SetupGuidePage extends ConsumerWidget {
  const SetupGuidePage({super.key});

  static const _steps = <(String, String, String, IconData)>[
    ('session_connected', 'Connect WhatsApp', 'Scan the QR to link your number', Icons.qr_code_rounded),
    ('phone_added', 'Add a phone number', 'Register the number campaigns send from', Icons.smartphone_rounded),
    ('templates_created', 'Create a message template', 'Approved templates unlock broadcasts', Icons.dashboard_customize_rounded),
    ('kb_added', 'Add knowledge base content', 'Teach the AI agent about your business', Icons.menu_book_rounded),
    ('agent_configured', 'Configure the AI agent', 'Set tone, playbook and routing', Icons.smart_toy_rounded),
    ('listings_added', 'Add listings / products', 'The agent matches leads to these', Icons.inventory_2_rounded),
    ('google_connected', 'Connect Google', 'Sync leads to Sheets, store files in Drive', Icons.add_to_drive_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup Guide')),
      body: ProviderObject(
        provider: setupStatusProvider,
        builder: (context, status) {
          final done = _steps.where((s) => status[s.$1] == true).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$done of ${_steps.length} complete',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _steps.isEmpty ? 0 : done / _steps.length,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              ..._steps.map((s) {
                final complete = status[s.$1] == true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      complete
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: complete
                          ? AppPalette.success
                          : context.mutedColor,
                    ),
                    title: Text(s.$2,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: complete
                                ? TextDecoration.lineThrough
                                : null)),
                    subtitle: Text(s.$3),
                    trailing: Icon(s.$4, color: context.mutedColor, size: 20),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

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
