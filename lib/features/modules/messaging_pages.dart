// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'module_providers.dart';
import 'ops_pages.dart' show pickAndUploadMedia;
import 'wa_chat_extra_pages.dart' show WaContactsPage;
import '_shared.dart';

// ══════════════════════════ Templates ══════════════════════════

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

// ══════════════════════════ Phone Numbers / Sessions ══════════════════════════

class SessionsPage extends ConsumerWidget {
  const SessionsPage({super.key, this.initialTabIndex = 0});

  /// Which single view to show — 0 is "Sessions" (WA Chat's open-wa devices), 1 is "Phone
  /// Numbers" (WA Cloud's official-API numbers). These are two distinct, unrelated concepts
  /// that happen to live on one page; each Quick Links entry only ever shows its own one, not
  /// a tab bar switching between both — Sessions never shows Cloud Numbers and vice versa.
  final int initialTabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showCloudNumbers = initialTabIndex == 1;
    return Scaffold(
      appBar: AppBar(title: Text(showCloudNumbers ? 'Phone Numbers' : 'Sessions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCloudNumbers ? _newPhone(context, ref) : _newSession(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(showCloudNumbers ? 'Add number' : 'New session'),
      ),
      body: showCloudNumbers ? _cloudNumbersList(ref) : _sessionsList(ref),
    );
  }

  Widget _sessionsList(WidgetRef ref) {
    return ProviderList(
      provider: wahaSessionsProvider,
            emptyLabel: 'No WhatsApp sessions',
            emptyIcon: Icons.smartphone_rounded,
            tile: (context, s) {
              final status = '${s['status'] ?? ''}'.toLowerCase();
              final connected =
                  status.contains('work') || status == 'connected';
              return RecordCard(
                title: str(s['name'] ?? s['session'] ?? s['phone'], 'Session'),
                subtitle:
                    '${str(s['phone'] ?? s['me']?['id'] ?? s['pushname'])} · ${str(s['status'], 'unknown')}',
                leadingIcon: connected
                    ? Icons.check_circle_rounded
                    : Icons.qr_code_rounded,
                leadingColor:
                    connected ? AppPalette.success : AppPalette.warning,
                onTap: connected ? null : () => _showQr(context, s),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusPill(str(s['status'], 'stopped')),
                    RowMenu(items: [
                      if (connected)
                        (
                          'WA Contacts',
                          Icons.contacts_rounded,
                          () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => WaContactsPage(
                                  sessionId: s['id'] as int,
                                  sessionLabel: str(s['name'] ?? s['session'] ?? s['phone'], 'Session'),
                                ),
                              )),
                        ),
                      if (connected)
                        (
                          'Sync WA labels to CRM',
                          Icons.label_rounded,
                          () => runAction(context,
                              () => Api.post('/waha/sessions/${s['id']}/labels/sync'),
                              success: 'Labels synced — see them under Labels.'),
                        ),
                      if (!connected)
                        (
                          'Start',
                          Icons.play_arrow_rounded,
                          () async {
                            final ok = await runAction(context,
                                () => Api.post('/waha/sessions/${s['id']}/start'),
                                success: 'Starting…');
                            if (ok) ref.invalidate(wahaSessionsProvider);
                          }
                        )
                      else
                        (
                          'Stop',
                          Icons.stop_rounded,
                          () async {
                            final ok = await runAction(context,
                                () => Api.post('/waha/sessions/${s['id']}/stop'),
                                success: 'Stopping…');
                            if (ok) ref.invalidate(wahaSessionsProvider);
                          }
                        ),
                      if (!connected)
                        (
                          'Show QR',
                          Icons.qr_code_rounded,
                          () => _showQr(context, s),
                        ),
                      if (!connected)
                        (
                          'Pairing code',
                          Icons.dialpad_rounded,
                          () => _requestPairingCode(context, s),
                        ),
                      (
                        'Log out',
                        Icons.logout_rounded,
                        () async {
                          final ok = await runAction(context,
                              () => Api.post('/waha/sessions/${s['id']}/logout'),
                              success: 'Logged out');
                          if (ok) ref.invalidate(wahaSessionsProvider);
                        }
                      ),
                      (
                        'Force kill',
                        Icons.power_off_rounded,
                        () async {
                          if (!await confirm(context,
                              title: 'Force-kill this session?',
                              message: 'Only use this if the session is stuck and Stop/Log out '
                                  "aren't responding — it hard-kills the engine.",
                              destructive: true,
                              confirmLabel: 'Force kill')) { return; }
                          final ok = await runAction(context,
                              () => Api.post('/waha/sessions/${s['id']}/force-kill'),
                              success: 'Session force-killed.');
                          if (ok) ref.invalidate(wahaSessionsProvider);
                        }
                      ),
                      (
                        'Delete',
                        Icons.delete_rounded,
                        () async {
                          if (!await confirm(context,
                              title: 'Delete session?',
                              destructive: true,
                              confirmLabel: 'Delete')) { return; }
                          final ok = await runAction(context,
                              () => Api.delete('/waha/sessions/${s['id']}'),
                              success: 'Deleted');
                          if (ok) ref.invalidate(wahaSessionsProvider);
                        }
                      ),
                    ]),
                  ],
                ),
              );
            },
    );
  }

  Widget _cloudNumbersList(WidgetRef ref) {
    return ProviderList(
            provider: phoneNumbersProvider,
            emptyLabel: 'No cloud numbers',
            emptyIcon: Icons.smartphone_rounded,
            tile: (context, p) => RecordCard(
              title: str(p['display_number'] ?? p['label'] ?? p['phone']),
              subtitle:
                  '${str(p['verified_name'] ?? p['label'])} · quality ${str(p['quality_rating'] ?? p['quality'])}',
              leadingIcon: Icons.smartphone_rounded,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p['is_default'] == true)
                    const StatusPill('default')
                  else
                    StatusPill(str(p['status'], 'active')),
                  RowMenu(items: [
                    (
                      'Verify',
                      Icons.verified_rounded,
                      () async {
                        final ok = await runAction(context,
                            () => Api.post('/phone-numbers/${p['id']}/verify'),
                            success: 'Verification requested');
                        if (ok) ref.invalidate(phoneNumbersProvider);
                      }
                    ),
                    if (p['is_default'] != true)
                      (
                        'Set default',
                        Icons.star_rounded,
                        () async {
                          final ok = await runAction(
                              context,
                              () => Api.post(
                                  '/phone-numbers/${p['id']}/set-default'),
                              success: 'Set as default');
                          if (ok) ref.invalidate(phoneNumbersProvider);
                        }
                      ),
                    (
                      'Delete',
                      Icons.delete_rounded,
                      () async {
                        if (!await confirm(context,
                            title: 'Remove number?',
                            destructive: true,
                            confirmLabel: 'Remove')) { return; }
                        final ok = await runAction(context,
                            () => Api.delete('/phone-numbers/${p['id']}'),
                            success: 'Removed');
                        if (ok) ref.invalidate(phoneNumbersProvider);
                      }
                    ),
                  ]),
                ],
              ),
            ),
    );
  }

  /// Alternative to scanning a QR (see [_showQr]) — the gateway issues an 8-char code the
  /// user types into WhatsApp's own "Link with phone number" flow instead.
  Future<void> _requestPairingCode(BuildContext context, Rec s) async {
    final phoneCtrl = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request pairing code'),
        content: TextField(
          controller: phoneCtrl,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone number (with country code)',
            hintText: 'e.g. 628123456789',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, phoneCtrl.text.trim()),
            child: const Text('Request'),
          ),
        ],
      ),
    );
    if (phone == null || phone.isEmpty || !context.mounted) return;

    Rec res;
    try {
      res = await Api.post('/waha/sessions/${s['id']}/pairing-code', data: {'phoneNumber': phone});
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return;
    }
    if (!context.mounted) return;
    final code = res['code'] ?? res['pairingCode'] ?? res['value'];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pairing code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter this code in WhatsApp → Linked devices → Link with phone number:',
                style: TextStyle(color: ctx.mutedColor, fontSize: 13)),
            const SizedBox(height: 12),
            SelectableText('$code',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 4)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _showQr(BuildContext context, Rec s) async {
    Rec qr;
    try {
      qr = await Api.one('/waha/sessions/${s['id']}/qr');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return;
    }
    if (!context.mounted) return;
    final value = qr['qr'] ?? qr['value'] ?? qr['data'] ?? qr['code'];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Scan with WhatsApp',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            if (value is String && value.startsWith('data:image'))
              Image.memory(
                Uri.parse(value).data!.contentAsBytes(),
                width: 240,
                height: 240,
              )
            else if (value != null)
              SelectableText('$value',
                  style: const TextStyle(fontFamily: 'monospace'))
            else
              Text('QR not available — try Start first',
                  style: TextStyle(color: ctx.mutedColor)),
          ],
        ),
      ),
    );
  }

  Future<void> _newSession(BuildContext context, WidgetRef ref) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'New WhatsApp session',
      submitLabel: 'Create',
      fields: (ctx) => [
        FText(
          label: 'Session name',
          required: true,
          hint: 'e.g. Sales line',
          onSaved: (v) => data['name'] = v,
        ),
      ],
      onSubmit: () => Api.post('/waha/sessions', data: data),
    );
    if (ok) ref.invalidate(wahaSessionsProvider);
  }

  Future<void> _newPhone(BuildContext context, WidgetRef ref) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Add cloud number',
      submitLabel: 'Add',
      fields: (ctx) => [
        FText(label: 'Label', required: true, onSaved: (v) => data['label'] = v),
        FText(
          label: 'Phone number ID',
          required: true,
          hint: 'From Meta WhatsApp Manager',
          onSaved: (v) => data['phone_number_id'] = v,
        ),
        FText(
          label: 'Access token',
          required: true,
          obscure: true,
          onSaved: (v) => data['access_token'] = v,
        ),
        FText(
          label: 'Business account ID',
          onSaved: (v) => v.isEmpty ? null : data['business_account_id'] = v,
        ),
        FText(
          label: 'Display number',
          keyboardType: TextInputType.phone,
          onSaved: (v) => v.isEmpty ? null : data['display_number'] = v,
        ),
      ],
      onSubmit: () => Api.post('/phone-numbers', data: data),
    );
    if (ok) ref.invalidate(phoneNumbersProvider);
  }
}

// ══════════════════════════ Flow Builder ══════════════════════════

class FlowBuilderPage extends ConsumerWidget {
  const FlowBuilderPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flow Builder')),
      body: ProviderList(
        provider: flowBuildersProvider,
        emptyLabel: 'No flows built yet',
        emptyIcon: Icons.account_tree_rounded,
        tile: (context, f) {
          final active = f['is_active'] == true ||
              f['active'] == true ||
              f['status'] == 'active';
          return RecordCard(
            title: str(f['name'] ?? f['title']),
            subtitle:
                '${str(f['description'] ?? f['trigger_type'] ?? f['trigger'])} · ${str(f['nodes_count'] ?? (f['nodes'] is List ? (f['nodes'] as List).length : ''), '0')} steps',
            leadingIcon: Icons.account_tree_rounded,
            leadingColor: const Color(0xFF8B5CF6),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(active ? 'active' : 'inactive'),
                RowMenu(items: [
                  (
                    active ? 'Deactivate' : 'Activate',
                    Icons.toggle_on_rounded,
                    () async {
                      final ok = await runAction(
                          context,
                          () => Api.post(
                              '/flow-builders/${f['id']}/${active ? 'deactivate' : 'activate'}'),
                          success: 'Updated');
                      if (ok) ref.invalidate(flowBuildersProvider);
                    }
                  ),
                  (
                    'Delete',
                    Icons.delete_rounded,
                    () async {
                      if (!await confirm(context,
                          title: 'Delete flow?',
                          destructive: true,
                          confirmLabel: 'Delete')) { return; }
                      final ok = await runAction(context,
                          () => Api.delete('/flow-builders/${f['id']}'),
                          success: 'Deleted');
                      if (ok) ref.invalidate(flowBuildersProvider);
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
}

// ══════════════════════════ WA Cloud ══════════════════════════

class WaCloudPage extends ConsumerWidget {
  const WaCloudPage({super.key, this.initialTabIndex = 0});

  /// Lets Quick Links open straight on "Inbox Analytics" (tab 0) or "Agent Automations"
  /// (tab 1).
  final int initialTabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      initialIndex: initialTabIndex.clamp(0, 1),
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('WA Cloud'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Inbox Analytics'),
            Tab(text: 'Automations'),
          ]),
        ),
        floatingActionButton: Builder(
          builder: (tabCtx) {
            final idx = DefaultTabController.of(tabCtx).index;
            if (idx != 1) return const SizedBox.shrink();
            return FloatingActionButton.extended(
              onPressed: () => _editRule(tabCtx, ref, null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New rule'),
            );
          },
        ),
        body: TabBarView(children: [
          ProviderObject(
            provider: waCloudInboxAnalyticsProvider,
            builder: (context, d) {
              final items = <(String, String, IconData)>[
                ('Messages in', compact(d['messages_in'] ?? d['inbound']), Icons.call_received_rounded),
                ('Messages out', compact(d['messages_out'] ?? d['outbound']), Icons.call_made_rounded),
                ('Conversations', compact(d['conversations']), Icons.forum_rounded),
                ('Calls', compact(d['calls']), Icons.call_rounded),
                ('Avg first reply', str(d['avg_first_response'] ?? d['first_reply'], '—'), Icons.timer_outlined),
                ('Resolved', compact(d['resolved']), Icons.check_circle_rounded),
              ];
              return ListView(children: [StatGrid(items)]);
            },
          ),
          ProviderList(
            provider: waCloudAutomationsProvider,
            emptyLabel: 'No automation rules',
            emptyIcon: Icons.bolt_rounded,
            tile: (context, a) {
              final active = a['is_active'] == true || a['active'] == true;
              return RecordCard(
                title: str(a['name'] ?? a['title']),
                subtitle: str(
                    a['rule_type'] ?? a['trigger'] ?? a['description']),
                leadingIcon: Icons.bolt_rounded,
                leadingColor: const Color(0xFF0EA5E9),
                trailing: RowMenu(items: [
                  (
                    active ? 'Disable' : 'Enable',
                    Icons.toggle_on_rounded,
                    () async {
                      final ok = await runAction(context,
                          () => Api.post('/wa-cloud/automations/${a['id']}/toggle'),
                          success: 'Updated');
                      if (ok) ref.invalidate(waCloudAutomationsProvider);
                    }
                  ),
                  ('Edit', Icons.edit_rounded,
                      () => _editRule(context, ref, a)),
                  (
                    'Delete',
                    Icons.delete_rounded,
                    () async {
                      if (!await confirm(context,
                          title: 'Delete rule?',
                          destructive: true,
                          confirmLabel: 'Delete')) { return; }
                      final ok = await runAction(context,
                          () => Api.delete('/wa-cloud/automations/${a['id']}'),
                          success: 'Deleted');
                      if (ok) ref.invalidate(waCloudAutomationsProvider);
                    }
                  ),
                ]),
              );
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _editRule(BuildContext context, WidgetRef ref, Rec? a) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: a == null ? 'New automation rule' : 'Edit rule',
      fields: (ctx) => [
        FText(
          label: 'Name',
          required: a == null,
          initial: a?['name'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['name'] = v,
        ),
        FSelect<String>(
          label: 'Rule type',
          options: const [
            'keyword_reply',
            'welcome',
            'away',
            'follow_up',
            'inactivity',
          ],
          initial: (a?['rule_type'] as String?) ?? 'keyword_reply',
          onSaved: (v) => data['rule_type'] = v ?? 'keyword_reply',
        ),
        FChips(
          label: 'Keywords',
          initial: ((a?['keywords'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
          onSaved: (v) => data['keywords'] = v,
        ),
        FText(
          label: 'Reply message',
          maxLines: 4,
          initial: a?['actions'] is List &&
                  (a!['actions'] as List).isNotEmpty &&
                  (a['actions'] as List).first is Map
              ? '${((a['actions'] as List).first as Map)['message'] ?? ''}'
              : null,
          onSaved: (v) => data['actions'] = [
            {'type': 'send_message', 'message': v}
          ],
        ),
        FBoolField(
          label: 'Active',
          initial: a?['is_active'] != false,
          onSaved: (v) => data['is_active'] = v,
        ),
      ],
      onSubmit: () => a == null
          ? Api.post('/wa-cloud/automations', data: data)
          : Api.patch('/wa-cloud/automations/${a['id']}', data: data),
    );
    if (ok) ref.invalidate(waCloudAutomationsProvider);
  }
}

// ══════════════════════════ Media Library ══════════════════════════

class MediaLibraryPage extends ConsumerWidget {
  const MediaLibraryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Media Library'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Files'),
            Tab(text: 'Folders'),
          ]),
        ),
        floatingActionButton: Builder(
          builder: (tabCtx) {
            final idx = DefaultTabController.of(tabCtx).index;
            return FloatingActionButton.extended(
              onPressed: () async {
                if (idx == 0) {
                  final ok = await pickAndUploadMedia(tabCtx);
                  if (ok) ref.invalidate(mediaLibraryProvider);
                } else {
                  final data = <String, dynamic>{};
                  final ok = await showFormSheet(
                    tabCtx,
                    title: 'New folder',
                    submitLabel: 'Create',
                    fields: (c) => [
                      FText(
                          label: 'Folder name',
                          required: true,
                          onSaved: (v) => data['name'] = v),
                    ],
                    onSubmit: () =>
                        Api.post('/media-library/folders', data: data),
                  );
                  if (ok) ref.invalidate(mediaFoldersProvider);
                }
              },
              icon: Icon(idx == 0
                  ? Icons.upload_rounded
                  : Icons.create_new_folder_rounded),
              label: Text(idx == 0 ? 'Upload' : 'New folder'),
            );
          },
        ),
        body: TabBarView(children: [
          ProviderList(
            provider: mediaLibraryProvider,
            emptyLabel: 'No media files',
            emptyIcon: Icons.perm_media_rounded,
            tile: (context, m) => RecordCard(
              title: str(m['name'] ?? m['filename'] ?? m['original_name'], 'File'),
              subtitle:
                  '${str(m['mime_type'] ?? m['type'] ?? m['extension'])} · ${_size(m['size'] ?? m['file_size'])}',
              leadingIcon: switch (
                  '${m['mime_type'] ?? m['type'] ?? ''}'.toLowerCase()) {
                final t when t.contains('image') => Icons.image_rounded,
                final t when t.contains('video') => Icons.videocam_rounded,
                final t when t.contains('audio') => Icons.audiotrack_rounded,
                final t when t.contains('pdf') => Icons.picture_as_pdf_rounded,
                _ => Icons.insert_drive_file_rounded,
              },
              trailing: RowMenu(items: [
                (
                  'Rename',
                  Icons.drive_file_rename_outline_rounded,
                  () async {
                    final data = <String, dynamic>{};
                    final ok = await showFormSheet(
                      context,
                      title: 'Rename file',
                      submitLabel: 'Rename',
                      fields: (c) => [
                        FText(
                            label: 'Name',
                            required: true,
                            initial: str(m['name'] ?? m['filename']),
                            onSaved: (v) => data['name'] = v),
                      ],
                      onSubmit: () => Api.patch(
                          '/media-library/${m['id']}/rename',
                          data: data),
                    );
                    if (ok) ref.invalidate(mediaLibraryProvider);
                  }
                ),
                (
                  'Delete',
                  Icons.delete_rounded,
                  () async {
                    if (!await confirm(context,
                        title: 'Delete file?',
                        destructive: true,
                        confirmLabel: 'Delete')) { return; }
                    final ok = await runAction(context,
                        () => Api.delete('/media-library/${m['id']}'),
                        success: 'Deleted');
                    if (ok) ref.invalidate(mediaLibraryProvider);
                  }
                ),
              ]),
            ),
          ),
          ProviderList(
            provider: mediaFoldersProvider,
            emptyLabel: 'No folders',
            emptyIcon: Icons.folder_rounded,
            tile: (context, f) => RecordCard(
              title: str(f['name']),
              subtitle:
                  '${str(f['files_count'] ?? f['media_count'] ?? '0')} files',
              leadingIcon: Icons.folder_rounded,
              leadingColor: AppPalette.warning,
              trailing: RowMenu(items: [
                (
                  'Rename',
                  Icons.drive_file_rename_outline_rounded,
                  () async {
                    final data = <String, dynamic>{};
                    final ok = await showFormSheet(
                      context,
                      title: 'Rename folder',
                      submitLabel: 'Rename',
                      fields: (c) => [
                        FText(
                            label: 'Name',
                            required: true,
                            initial: str(f['name']),
                            onSaved: (v) => data['name'] = v),
                      ],
                      onSubmit: () => Api.patch(
                          '/media-library/folders/${f['id']}',
                          data: data),
                    );
                    if (ok) ref.invalidate(mediaFoldersProvider);
                  }
                ),
                (
                  'Delete',
                  Icons.delete_rounded,
                  () async {
                    if (!await confirm(context,
                        title: 'Delete folder?',
                        destructive: true,
                        confirmLabel: 'Delete')) { return; }
                    final ok = await runAction(
                        context,
                        () => Api.delete('/media-library/folders/${f['id']}'),
                        success: 'Deleted');
                    if (ok) ref.invalidate(mediaFoldersProvider);
                  }
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  String _size(Object? bytes) {
    final b = num.tryParse('${bytes ?? 0}') ?? 0;
    if (b >= 1e9) return '${(b / 1e9).toStringAsFixed(1)} GB';
    if (b >= 1e6) return '${(b / 1e6).toStringAsFixed(1)} MB';
    if (b >= 1e3) return '${(b / 1e3).toStringAsFixed(0)} KB';
    return '$b B';
  }
}
