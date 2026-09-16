// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'module_providers.dart';
import '_shared.dart';

// ══════════════════════════ Staff & Roles ══════════════════════════

class StaffPage extends ConsumerWidget {
  const StaffPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Staff & Roles'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Team'),
            Tab(text: 'Roles'),
          ]),
        ),
        // "Add staff" and every per-row action below previously rendered unconditionally —
        // reachable by anyone who could open this page at all (staff.view), not just staff.manage.
        floatingActionButton: PermissionGuard.can('staff.manage')
            ? FloatingActionButton.extended(
                onPressed: () => _edit(context, ref, null),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add staff'),
              )
            : null,
        body: TabBarView(children: [
          ProviderList(
            provider: staffListProvider,
            emptyLabel: 'No staff members',
            emptyIcon: Icons.groups_rounded,
            tile: (context, s) {
              final role = s['role'] is Map
                  ? str((s['role'] as Map)['label'] ?? (s['role'] as Map)['name'])
                  : str(s['role'] ?? s['role_name']);
              final active = s['is_active'] == true || s['active'] == true;
              return RecordCard(
                title: str(s['name']),
                subtitle: '${str(s['email'])} · $role',
                leadingIcon: Icons.person_rounded,
                onTap: () => _edit(context, ref, s),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusPill(active ? 'active' : 'inactive'),
                    RowMenu(items: PermissionGuard.can('staff.manage') ? [
                      ('Edit', Icons.edit_rounded, () => _edit(context, ref, s)),
                      (
                        active ? 'Deactivate' : 'Activate',
                        Icons.toggle_on_rounded,
                        () async {
                          final ok = await runAction(
                              context,
                              () => Api.patch('/staff/${s['id']}/toggle-active'),
                              success: 'Updated');
                          if (ok) ref.invalidate(staffListProvider);
                        }
                      ),
                      (
                        'Reset password',
                        Icons.lock_reset_rounded,
                        () => _resetPassword(context, s),
                      ),
                      (
                        'Delete',
                        Icons.delete_rounded,
                        () async {
                          if (!await confirm(context,
                              title: 'Remove staff member?',
                              message:
                                  'Their leads will be unassigned. This cannot be undone.',
                              destructive: true,
                              confirmLabel: 'Remove')) { return; }
                          final ok = await runAction(context,
                              () => Api.delete('/staff/${s['id']}'),
                              success: 'Removed');
                          if (ok) ref.invalidate(staffListProvider);
                        }
                      ),
                    ] : const []),
                  ],
                ),
                footer: s['department'] != null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: StatusPill(str(s['department']),
                            color: AppPalette.info))
                    : null,
              );
            },
          ),
          ProviderList(
            provider: rolesListProvider,
            emptyLabel: 'No roles',
            emptyIcon: Icons.badge_rounded,
            tile: (context, r) => RecordCard(
              title: str(r['label'] ?? r['name']),
              subtitle: str(r['description'] ??
                  '${(r['permissions'] is List ? (r['permissions'] as List).length : 0)} permissions'),
              leadingIcon: Icons.shield_rounded,
              trailing: (r['is_system'] == true)
                  ? const StatusPill('system', color: AppPalette.cold)
                  : null,
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec? s) async {
    final roles = await _safeList('/roles');
    if (!context.mounted) return;
    final data = <String, dynamic>{};
    final creating = s == null;
    Rec? initialRole;
    if (s != null && s['role'] is Map) {
      initialRole = roles.firstWhere(
        (r) => r['id'] == (s['role'] as Map)['id'],
        orElse: () => <String, dynamic>{},
      );
      if (initialRole.isEmpty) initialRole = null;
    }
    final ok = await showFormSheet(
      context,
      title: creating ? 'Add staff member' : 'Edit ${str(s['name'])}',
      fields: (ctx) => [
        FText(
          label: 'Name',
          required: creating,
          initial: s?['name'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['name'] = v,
        ),
        if (creating) ...[
          FText(
            label: 'Email',
            required: true,
            keyboardType: TextInputType.emailAddress,
            onSaved: (v) => data['email'] = v,
          ),
          FText(
            label: 'Password',
            required: true,
            obscure: true,
            hint: 'Min 8 characters',
            onSaved: (v) {
              data['password'] = v;
              data['password_confirmation'] = v;
            },
          ),
        ],
        if (roles.isNotEmpty)
          FSelect<Rec>(
            label: 'Role',
            options: roles,
            initial: initialRole,
            labelOf: (r) => str(r['label'] ?? r['name']),
            onSaved: (r) => r?['id'] != null ? data['role_id'] = r!['id'] : null,
          ),
        FText(
          label: 'Phone',
          keyboardType: TextInputType.phone,
          initial: s?['phone'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['phone'] = v,
        ),
        FText(
          label: 'Department',
          initial: s?['department'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['department'] = v,
        ),
        FNumber(
          label: 'Max leads',
          initial: num.tryParse('${s?['max_leads'] ?? ''}'),
          onSaved: (v) => v == null ? null : data['max_leads'] = v.toInt(),
        ),
      ],
      onSubmit: () => creating
          ? Api.post('/staff', data: data)
          : Api.put('/staff/${s['id']}', data: data),
    );
    if (ok) ref.invalidate(staffListProvider);
  }

  Future<void> _resetPassword(BuildContext context, Rec s) async {
    final data = <String, dynamic>{};
    await showFormSheet(
      context,
      title: 'Reset password — ${str(s['name'])}',
      submitLabel: 'Reset',
      fields: (ctx) => [
        FText(
          label: 'New password',
          required: true,
          obscure: true,
          hint: 'Min 8 characters',
          onSaved: (v) {
            data['password'] = v;
            data['password_confirmation'] = v;
          },
        ),
      ],
      onSubmit: () => Api.patch('/staff/${s['id']}/reset-password', data: data),
    );
  }
}

// ══════════════════════════ OTP / API Service ══════════════════════════

class OtpServicePage extends ConsumerWidget {
  const OtpServicePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('OTP / API Service'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Service'),
            Tab(text: 'Logs'),
          ]),
        ),
        body: TabBarView(children: [
          ProviderObject(
            provider: otpServiceProvider,
            builder: (context, d) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.altSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.lineColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('API token',
                          style: TextStyle(
                              color: context.mutedColor, fontSize: 12)),
                      const SizedBox(height: 4),
                      // The raw token used to render for anyone who could open this page at
                      // all (otp.view) — restrict the cleartext value to otp.manage.
                      PermissionGuard.can('otp.manage')
                          ? SelectableText(
                              str(d['api_token'] ?? d['token'], 'not generated'),
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600),
                            )
                          : Text('•••••••••••••••• (hidden)',
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  color: context.mutedColor)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    if (PermissionGuard.can('otp.manage'))
                      OutlinedButton.icon(
                        onPressed: () async {
                          if (!await confirm(context,
                              title: 'Reset API token?',
                              message: 'Existing integrations will stop working.',
                              confirmLabel: 'Reset')) { return; }
                          final ok = await runAction(context,
                              () => Api.post('/otp-service/reset-token'),
                              success: 'Token reset');
                          if (ok) ref.invalidate(otpServiceProvider);
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Reset token'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _testSend(context),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Test send'),
                    ),
                  ],
                ),
                const SectionHeader('Configuration'),
                ..._entries(d).map((e) => KvRow(e.$1, e.$2)),
              ],
            ),
          ),
          ProviderList(
            provider: otpServiceLogsProvider,
            emptyLabel: 'No requests logged',
            emptyIcon: Icons.receipt_long_rounded,
            tile: (context, l) => RecordCard(
              title: str(l['phone'] ?? l['to'] ?? l['recipient'], 'Request'),
              subtitle:
                  '${str(l['type'] ?? l['action'] ?? l['event'])} · ${when(l['created_at'])}',
              leadingIcon: Icons.vpn_key_rounded,
              trailing: StatusPill(str(l['status'] ?? l['result'], 'sent')),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _testSend(BuildContext context) async {
    final data = <String, dynamic>{};
    await showFormSheet(
      context,
      title: 'Test send',
      submitLabel: 'Send',
      fields: (ctx) => [
        FText(
          label: 'Phone number',
          required: true,
          keyboardType: TextInputType.phone,
          hint: 'With country code',
          onSaved: (v) => data['phone'] = v,
        ),
      ],
      onSubmit: () => Api.post('/otp-service/test-send', data: data),
    );
  }

  List<(String, String)> _entries(Map<String, dynamic> d) => d.entries
      .where((e) =>
          e.value != null &&
          e.value is! Map &&
          e.value is! List &&
          !e.key.contains('token'))
      .map((e) => (e.key.replaceAll('_', ' '), '${e.value}'))
      .toList();
}

// ══════════════════════════ Survey Forms ══════════════════════════

class SurveyFormsPage extends ConsumerWidget {
  const SurveyFormsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Survey Forms')),
      body: ProviderList(
        provider: surveyFormsProvider,
        emptyLabel: 'No forms yet',
        emptyIcon: Icons.assignment_rounded,
        tile: (context, f) {
          final active = f['is_active'] == true ||
              f['active'] == true ||
              f['status'] == 'published';
          return RecordCard(
            title: str(f['name'] ?? f['title']),
            subtitle:
                '${str(f['fields_count'] ?? (f['fields'] is List ? (f['fields'] as List).length : ''), '0')} fields · ${str(f['responses_count'] ?? f['submissions_count'] ?? '0')} responses',
            leadingIcon: Icons.assignment_rounded,
            onTap: () => _responses(context, f),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(active ? 'active' : 'draft'),
                RowMenu(items: [
                  ('View responses', Icons.list_alt_rounded,
                      () => _responses(context, f)),
                  (
                    active ? 'Deactivate' : 'Activate',
                    Icons.toggle_on_rounded,
                    () async {
                      final ok = await runAction(
                        context,
                        () => Api.put('/survey-forms/${f['id']}', data: {
                          'name': str(f['name'] ?? f['title']),
                          'fields': f['fields'] ?? [],
                          'is_active': !active,
                        }),
                        success: 'Updated',
                      );
                      if (ok) ref.invalidate(surveyFormsProvider);
                    }
                  ),
                  (
                    'Delete',
                    Icons.delete_rounded,
                    () async {
                      if (!await confirm(context,
                          title: 'Delete form?',
                          destructive: true,
                          confirmLabel: 'Delete')) { return; }
                      final ok = await runAction(context,
                          () => Api.delete('/survey-forms/${f['id']}'),
                          success: 'Deleted');
                      if (ok) ref.invalidate(surveyFormsProvider);
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

  Future<void> _responses(BuildContext context, Rec f) async {
    List<Rec> rows;
    try {
      rows = await Api.list('/survey-forms/${f['id']}/responses');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return;
    }
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(20),
          children: [
            Text('${str(f['name'] ?? f['title'])} — ${rows.length} responses',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Text('No responses yet',
                  style: TextStyle(color: ctx.mutedColor))
            else
              ...rows.map((r) {
                final answers = r['answers'] ?? r['data'] ?? r;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(when(r['created_at']),
                            style: TextStyle(
                                color: ctx.mutedColor, fontSize: 11)),
                        const SizedBox(height: 4),
                        if (answers is Map)
                          ...answers.entries.map((e) => Text(
                              '${e.key}: ${e.value}',
                              style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════ Data Export ══════════════════════════

class ExportPage extends ConsumerWidget {
  const ExportPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> start(String kind, String path) async {
      final ok = await runAction(context, () => Api.post(path),
          success: '$kind export queued');
      if (ok) ref.invalidate(exportJobsProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Data Export')),
      body: ProviderList(
        provider: exportJobsProvider,
        emptyLabel: 'No export jobs yet',
        emptyIcon: Icons.ios_share_rounded,
        header: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => start('Chats', '/wa-export/chats'),
                icon: const Icon(Icons.forum_rounded, size: 18),
                label: const Text('Chats'),
              ),
              OutlinedButton.icon(
                onPressed: () => start('Contacts', '/wa-export/contacts'),
                icon: const Icon(Icons.contacts_rounded, size: 18),
                label: const Text('Contacts'),
              ),
              OutlinedButton.icon(
                onPressed: () => start('Groups', '/wa-export/groups'),
                icon: const Icon(Icons.groups_rounded, size: 18),
                label: const Text('Groups'),
              ),
            ],
          ),
        ),
        tile: (context, j) {
          final done = '${j['status'] ?? ''}'.toLowerCase() == 'completed';
          return RecordCard(
            title: str(j['type'] ?? j['kind'] ?? j['export_type'], 'Export'),
            subtitle:
                '${str(j['records_count'] ?? j['rows'] ?? '')} rows · ${when(j['created_at'])}',
            leadingIcon: Icons.description_rounded,
            trailing: done
                ? IconButton(
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () => launchUrl(
                      Uri.parse(
                          '${Api.raw.options.baseUrl}/wa-export/${j['id']}/download'),
                      mode: LaunchMode.externalApplication,
                    ),
                  )
                : StatusPill(str(j['status'], 'processing')),
          );
        },
      ),
    );
  }
}

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

// ══════════════════════════ shared bits ══════════════════════════

Future<List<Rec>> _safeList(String path) async {
  try {
    return await Api.list(path);
  } catch (_) {
    return const [];
  }
}

// media library upload helper used by messaging_pages
Future<bool> pickAndUploadMedia(BuildContext context, {int? folderId}) async {
  final picker = ImagePicker();
  final file = await picker.pickMedia();
  if (file == null) return false;
  try {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: file.name),
      if (folderId != null) 'folder_id': folderId,
    });
    await Api.raw.post('/media-library/upload', data: form);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Uploaded')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
    return false;
  }
}
