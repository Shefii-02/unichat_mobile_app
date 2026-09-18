// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:image_picker/image_picker.dart";
import "package:url_launcher/url_launcher.dart";
import "package:dio/dio.dart";
import "package:unichat_mobile_app/core/permissions/permission_guard.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Integrations ══════════════════════════

class IntegrationsPage extends ConsumerWidget {
  const IntegrationsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Integrations'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Google'),
            Tab(text: 'API Keys'),
          ]),
        ),
        body: TabBarView(children: [
          ProviderObject(
            provider: googleStatusProvider,
            builder: (context, d) {
              final connected = d['connected'] == true;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.add_to_drive_rounded,
                          color: Color(0xFF16A34A)),
                      title: const Text('Google Workspace'),
                      subtitle: Text(connected
                          ? 'Connected as ${str(d['email'] ?? d['account'])}'
                          : 'Not connected'),
                      trailing: StatusPill(
                          connected ? 'connected' : 'disconnected'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!connected)
                    FilledButton.icon(
                      onPressed: () async {
                        try {
                          final r = await Api.one('/google/connect');
                          final url = r['url'] ?? r['connect_url'] ?? r['auth_url'];
                          if (url != null) {
                            await launchUrl(Uri.parse('$url'),
                                mode: LaunchMode.externalApplication);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(apiErrorMessage(e))));
                          }
                        }
                      },
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Connect Google'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () async {
                        if (!await confirm(context,
                            title: 'Disconnect Google?',
                            destructive: true,
                            confirmLabel: 'Disconnect')) { return; }
                        final ok = await runAction(context,
                            () => Api.delete('/google/disconnect'),
                            success: 'Disconnected');
                        if (ok) ref.invalidate(googleStatusProvider);
                      },
                      icon: const Icon(Icons.link_off_rounded),
                      label: const Text('Disconnect'),
                    ),
                  const SectionHeader('Sheets syncs'),
                  ...((d['syncs'] as List?) ?? const [])
                      .whereType<Map>()
                      .map((s) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.table_chart_rounded),
                              title: Text(str(s['name'] ??
                                  s['sheet_name'] ??
                                  s['spreadsheet_id'])),
                              subtitle: Text(
                                  '${str(s['source'] ?? s['type'])} · last run ${when(s['last_run_at'] ?? s['last_synced_at'])}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.play_arrow_rounded),
                                onPressed: () async {
                                  final ok = await runAction(
                                      context,
                                      () => Api.post(
                                          '/google/syncs/${s['id']}/run'),
                                      success: 'Sync started');
                                  if (ok) ref.invalidate(googleStatusProvider);
                                },
                              ),
                            ),
                          )),
                  if (connected)
                    Text(
                      'WhatsApp messages (inbound + outbound), leads and Drive '
                      'file storage sync through this connection.',
                      style: TextStyle(
                          color: context.mutedColor,
                          fontSize: 12.5,
                          height: 1.4),
                    ),
                ],
              );
            },
          ),
          ProviderList(
            provider: companyApiKeysProvider,
            emptyLabel: 'No API keys',
            emptyIcon: Icons.key_rounded,
            tile: (context, k) => RecordCard(
              title: str(k['name'] ?? k['provider'] ?? k['label']),
              subtitle:
                  '${str(k['provider'] ?? k['type'])} · ${str(k['masked_key'] ?? k['key_preview'] ?? '••••')}',
              leadingIcon: Icons.key_rounded,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusPill(
                      (k['is_active'] == true || k['active'] == true)
                          ? 'active'
                          : (k['verified'] == true ? 'verified' : 'inactive')),
                  // These act on company AI-provider API keys — restrict to wa_chat.api_keys.manage
                  // (matching the backend route gate) rather than whatever got this page open at all.
                  RowMenu(items: PermissionGuard.can('wa_chat.api_keys.manage') ? [
                    (
                      'Verify',
                      Icons.verified_rounded,
                      () async {
                        final ok = await runAction(context,
                            () => Api.post('/settings/api-keys/${k['id']}/verify'),
                            success: 'Verified');
                        if (ok) ref.invalidate(companyApiKeysProvider);
                      }
                    ),
                    (
                      'Set active',
                      Icons.check_circle_rounded,
                      () async {
                        final ok = await runAction(
                            context,
                            () => Api.post(
                                '/settings/api-keys/${k['id']}/set-active'),
                            success: 'Activated');
                        if (ok) ref.invalidate(companyApiKeysProvider);
                      }
                    ),
                    (
                      'Delete',
                      Icons.delete_rounded,
                      () async {
                        if (!await confirm(context,
                            title: 'Delete API key?',
                            destructive: true,
                            confirmLabel: 'Delete')) { return; }
                        final ok = await runAction(context,
                            () => Api.delete('/settings/api-keys/${k['id']}'),
                            success: 'Deleted');
                        if (ok) ref.invalidate(companyApiKeysProvider);
                      }
                    ),
                  ] : const []),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

