// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/core/permissions/permission_guard.dart";
import "package:unichat_mobile_app/core/storage/local_storage.dart";
import "package:unichat_mobile_app/core/widgets/app_empty_state.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

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

