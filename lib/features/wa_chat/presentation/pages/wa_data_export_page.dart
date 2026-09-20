// ignore_for_file: use_build_context_synchronously
import "dart:async";
import "dart:io";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:path_provider/path_provider.dart";
import "package:share_plus/share_plus.dart";
import "package:url_launcher/url_launcher.dart";
import "package:unichat_mobile_app/core/network/wa_chat_api_service.dart";
import "package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/wa_chat_api.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Data Export ══════════════════════════
// Mirrors frontend/src/pages/wa-chat/pages/WaDataExport.tsx, which mixes two different export
// paths: chats/contacts/groups are Laravel-queued jobs (RunWaExport pulls from the gateway
// server-side); group_participants/broadcast_groups/labels are generated client-side and
// downloaded instantly — the former hits the gateway directly (session groups + per-group
// participants), the latter paginates Laravel's /contacts?label_id= filter. The reference reads
// its label list from a `/contact-labels` route that doesn't actually exist on this backend (the
// real route is `/labels` — `/contact-labels` 404s and is silently swallowed there); this port
// uses the real `/labels` endpoint so the Labels export actually works.

const _exportTypes = <(String, String)>[
  ('chats', 'Chat List'),
  ('contacts', 'Saved Contacts'),
  ('groups', 'Groups (all groups)'),
  ('group_participants', 'Group Participants (select groups)'),
  ('labels', '📋 Labels — export contacts by label'),
  ('broadcast_groups', '📢 Broadcast Groups — select groups to export'),
];

class WaDataExportPage extends ConsumerStatefulWidget {
  const WaDataExportPage({super.key});
  @override
  ConsumerState<WaDataExportPage> createState() => _WaDataExportPageState();
}

class _WaDataExportPageState extends ConsumerState<WaDataExportPage> {
  List<Rec> _jobs = [];
  bool _loading = true;
  String? _error;
  String? _sessionId;
  String _exportType = 'chats';
  bool _includeParticipants = false;
  bool _showGroupPreview = false;
  bool _submitting = false;
  Timer? _pollTimer;

  // Gateway-backed group data (for groups preview / group_participants / broadcast_groups).
  List<Rec> _groups = [];
  bool _groupsLoading = false;
  final Set<String> _selectedGroupIds = {};
  bool _downloadingCsv = false;
  Rec? _singleGroupInfo;
  bool _singleGroupLoading = false;

  // Labels export — the WhatsApp Business app's own labels (gateway-backed), not the CRM's.
  List<Rec> _labels = [];
  bool _labelsLoading = false;
  String? _labelsError;
  final Set<String> _selectedLabelIds = {};
  bool _exportingLabels = false;

  // Mints the company's first wa_chat_token if none exists yet — safe (no existing key to
  // revoke). See campaign_composer.dart's `_ensureApiKey` for the full reasoning.
  String? _apiKeyOverride;
  Future<String?>? _apiKeyProvisioning;
  String? get _apiKey => _apiKeyOverride ?? ref.read(authProvider).value?.waContactToken;

  Future<String?> _ensureApiKey() {
    if (_apiKey != null) return Future.value(_apiKey);
    return _apiKeyProvisioning ??= () async {
      try {
        final res = await WaChatApi.reconnectToken();
        final key = res['wa_chat_token'] as String?;
        if (key != null && key.isNotEmpty && mounted) setState(() => _apiKeyOverride = key);
        return key;
      } catch (_) {
        return null;
      } finally {
        _apiKeyProvisioning = null;
      }
    }();
  }

  bool get _needsGroups =>
      _exportType == 'group_participants' || _exportType == 'broadcast_groups' || (_exportType == 'groups' && _showGroupPreview);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await WaChatApi.exportJobs();
      final jobs = res['data'];
      setState(() {
        _jobs = jobs is List ? jobs.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = apiErrorMessage(e); });
    }
    _schedulePollIfNeeded();
  }

  /// Mirrors WaDataExport.tsx's refetchInterval: poll every 4s only while a job is actively
  /// running, and give up on a job stuck "processing" for more than 15 minutes — otherwise a
  /// started export that never flips to done/failed would poll forever.
  void _schedulePollIfNeeded() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_hasRunningJob) return;
    _pollTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) _load();
    });
  }

  bool get _hasRunningJob => _jobs.any((j) {
        if (j['status'] != 'pending' && j['status'] != 'processing') return false;
        final createdAt = DateTime.tryParse(str(j['created_at'], ''));
        if (createdAt == null) return true;
        return DateTime.now().difference(createdAt) < const Duration(minutes: 15);
      });

  void _onSessionOrTypeChanged() {
    _selectedGroupIds.clear();
    _showGroupPreview = false;
    _singleGroupInfo = null;
    if (_needsGroups) _loadGroups();
    if (_exportType == 'labels' && _labels.isEmpty && !_labelsLoading) _loadLabels();
  }

  Future<void> _loadGroups() async {
    final sid = _sessionId;
    if (sid == null || sid.isEmpty) return;
    final apiKey = await _ensureApiKey();
    if (apiKey == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't connect to WhatsApp Chat.")));
      return;
    }
    setState(() => _groupsLoading = true);
    try {
      final groups = await WaChatApiService.getGroups(sid, apiKey);
      if (mounted) setState(() { _groups = groups; _groupsLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _groupsLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load groups — ${apiErrorMessage(e)}")));
      }
    }
  }

  Future<void> _loadSingleGroupInfo() async {
    final sid = _sessionId;
    final apiKey = _apiKey;
    if (sid == null || apiKey == null || _selectedGroupIds.length != 1) {
      setState(() => _singleGroupInfo = null);
      return;
    }
    setState(() { _singleGroupLoading = true; _singleGroupInfo = null; });
    try {
      final info = await WaChatApiService.getGroupInfo(sid, apiKey, _selectedGroupIds.first);
      if (mounted) setState(() { _singleGroupInfo = info; _singleGroupLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _singleGroupLoading = false);
    }
  }

  void _toggleGroup(String id) {
    setState(() {
      if (_selectedGroupIds.contains(id)) {
        _selectedGroupIds.remove(id);
      } else {
        _selectedGroupIds.add(id);
      }
    });
    if (_exportType == 'group_participants') _loadSingleGroupInfo();
  }

  Future<void> _loadLabels() async {
    setState(() => _labelsLoading = true);
    try {
      final sid = _sessionId;
      final apiKey = await _ensureApiKey();
      if (sid == null || apiKey == null) {
        if (mounted) setState(() { _labelsLoading = false; _labelsError = "Couldn't connect to WhatsApp Chat."; });
        return;
      }
      final labels = await WaChatApiService.getLabels(sid, apiKey);
      if (mounted) setState(() { _labels = labels; _labelsLoading = false; _labelsError = null; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _labelsLoading = false;
          _labelsError = e is DioException && e.response?.statusCode == 400
              ? 'This session is not a WhatsApp Business account — labels are unavailable.'
              : "Couldn't load labels — ${apiErrorMessage(e)}";
        });
      }
    }
  }

  void _toggleLabel(String id) => setState(() {
        if (_selectedLabelIds.contains(id)) {
          _selectedLabelIds.remove(id);
        } else {
          _selectedLabelIds.add(id);
        }
      });

  Future<void> _startExport() async {
    final sid = _sessionId;
    if (sid == null || sid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a session first.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      switch (_exportType) {
        case 'contacts':
          await WaChatApi.exportContacts(sid);
        case 'groups':
          await WaChatApi.exportGroups(sid, includeParticipants: _includeParticipants);
        default:
          await WaChatApi.exportChats(sid);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export queued.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Fetches participants for every selected group (bounded concurrency, not a full retry/cache
  /// layer like the reference's getGroupInfoCached — a reasonable mobile simplification), dedupes
  /// by phone number across groups, and shares the CSV. Backs both "Group Participants" and
  /// "Broadcast Groups" (same data shape, different button copy in the reference).
  Future<void> _doParticipantsExport() async {
    final sid = _sessionId;
    final apiKey = await _ensureApiKey();
    if (sid == null || sid.isEmpty || _selectedGroupIds.isEmpty || apiKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a session and at least one group.')));
      return;
    }
    setState(() => _downloadingCsv = true);
    try {
      final groupIds = _selectedGroupIds.toList();
      final infos = <String, Rec?>{};
      const batchSize = 3;
      for (var i = 0; i < groupIds.length; i += batchSize) {
        final batch = groupIds.skip(i).take(batchSize);
        final results = await Future.wait(batch.map((gid) async {
          try {
            return MapEntry(gid, await WaChatApiService.getGroupInfo(sid, apiKey, gid));
          } catch (_) {
            return MapEntry(gid, null);
          }
        }));
        for (final r in results) {
          infos[r.key] = r.value;
        }
      }

      final seen = <String>{};
      final rows = <List<String>>[
        ['Phone Number', 'Name', 'Is Admin', 'Is Super Admin', 'Source Group', 'Group ID'],
      ];
      for (final gid in groupIds) {
        final info = infos[gid];
        if (info == null) continue;
        final groupName = str(_groups.where((g) => str(g['id']) == gid).firstOrNull?['name'], gid);
        final participants = (info['participants'] as List?)?.whereType<Map>() ?? const [];
        for (final p in participants) {
          final number = str(p['number'], '');
          if (number.isEmpty || seen.contains(number)) continue;
          seen.add(number);
          rows.add([number, str(p['name'], ''), p['isAdmin'] == true ? 'Yes' : 'No', p['isSuperAdmin'] == true ? 'Yes' : 'No', groupName, gid]);
        }
      }

      if (rows.length <= 1) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No participants found in the selected group(s).')));
        return;
      }

      final safeName = groupIds.length == 1
          ? str(_groups.where((g) => str(g['id']) == groupIds.first).firstOrNull?['name'], 'group').replaceAll(RegExp('[^a-z0-9]', caseSensitive: false), '_').toLowerCase()
          : '${groupIds.length}_groups';
      await _shareCsv(rows, 'participants_${safeName}_${DateTime.now().millisecondsSinceEpoch}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _downloadingCsv = false);
    }
  }

  /// Exports the WhatsApp Business chats carrying each selected label (`GET
  /// /labels/:id/chats` on the gateway) — the labels set inside the WhatsApp Business app
  /// itself, not the CRM's own `contact_labels`. whatsapp-web.js only; a Baileys session
  /// answers 501, surfaced below as a clear message rather than a raw error.
  Future<void> _doLabelsExport() async {
    final sid = _sessionId;
    final apiKey = await _ensureApiKey();
    if (sid == null || apiKey == null || _selectedLabelIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a session and at least one label.')));
      return;
    }
    setState(() => _exportingLabels = true);
    try {
      final seen = <String>{};
      final rows = <List<String>>[
        ['Chat ID', 'Phone', 'Name', 'Type', 'Last Message', 'Label'],
      ];
      for (final id in _selectedLabelIds) {
        final labelName = str(_labels.where((l) => str(l['id']) == id).firstOrNull?['name'], id);
        final chats = await WaChatApiService.getChatsByLabel(sid, apiKey, id);
        for (final c in chats) {
          final chatId = str(c['id'], '');
          if (chatId.isEmpty || seen.contains(chatId)) continue;
          seen.add(chatId);
          final isGroup = c['isGroup'] == true;
          rows.add([
            chatId,
            isGroup ? '' : chatId.split('@').first,
            str(c['name'], ''),
            str(c['kind'], isGroup ? 'group' : 'individual'),
            str(c['lastMessage'], ''),
            labelName,
          ]);
        }
      }
      if (rows.length <= 1) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No chats found for the selected label(s).')));
        return;
      }
      await _shareCsv(rows, 'whatsapp_labels_${DateTime.now().millisecondsSinceEpoch}');
    } catch (e) {
      final message = e is DioException && e.response?.statusCode == 501
          ? "This session's WhatsApp engine can't list chats by label."
          : apiErrorMessage(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _exportingLabels = false);
    }
  }

  Future<void> _shareCsv(List<List<String>> rows, String filenameNoExt) async {
    final csv = rows.map((r) => r.map((c) => '"${c.replaceAll('"', '""')}"').join(',')).join('\n');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filenameNoExt.csv');
    await file.writeAsString(csv);
    if (mounted) await Share.shareXFiles([XFile(file.path)], text: 'Data export');
  }

  Future<void> _deleteJob(Rec job) async {
    if (!await confirm(context, title: 'Delete this export?', destructive: true, confirmLabel: 'Delete')) return;
    try {
      await WaChatApi.deleteExportJob(job['id'] as int);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _download(Rec job) async {
    final url = str(job['file_url'], '');
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open the download link.")));
    }
  }

  Color _statusColor(String status) => switch (status) {
        'done' => AppPalette.success,
        'failed' => AppPalette.danger,
        'processing' => AppPalette.info,
        _ => AppPalette.warning,
      };

  Color? _parseHexColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned.length == 6 ? 'FF$cleaned' : cleaned, radix: 16);
    return value == null ? null : Color(value);
  }

  @override
  Widget build(BuildContext context) {
    final isGroupParticipants = _exportType == 'group_participants';
    final isLabels = _exportType == 'labels';
    final isBroadcastGroups = _exportType == 'broadcast_groups';

    return Scaffold(
      appBar: AppBar(title: const Text('Data Export'), actions: [
        IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: AppPalette.danger))),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.lineColor)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('New Export', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 12),
                        const Text('WhatsApp Session', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Consumer(builder: (context, ref, _) {
                          final sessionsAsync = ref.watch(wahaSessionsProvider);
                          return sessionsAsync.when(
                            loading: () => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                            error: (e, _) => Text("Couldn't load sessions — ${apiErrorMessage(e)}", style: const TextStyle(fontSize: 12, color: AppPalette.danger)),
                            data: (sessions) {
                              if (sessions.isEmpty) {
                                return Text('No sessions available', style: TextStyle(fontSize: 13, color: context.mutedColor));
                              }
                              final firstEverSet = _sessionId == null;
                              _sessionId ??= str(sessions.first['session_name'], str(sessions.first['id'], ''));
                              if (firstEverSet) WidgetsBinding.instance.addPostFrameCallback((_) => _onSessionOrTypeChanged());
                              return DropdownButtonFormField<String>(
                                initialValue: _sessionId,
                                isExpanded: true,
                                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                                items: sessions.map((s) {
                                  final id = str(s['session_name'], str(s['id'], ''));
                                  final phone = str(s['phone'], '');
                                  final label = str(s['display_name'] ?? s['name'], 'Session');
                                  return DropdownMenuItem(value: id, child: Text('$label${phone.isNotEmpty ? ' ($phone)' : ''}', style: const TextStyle(fontSize: 13)));
                                }).toList(),
                                onChanged: (v) {
                                  setState(() => _sessionId = v);
                                  _onSessionOrTypeChanged();
                                },
                              );
                            },
                          );
                        }),
                        const SizedBox(height: 12),
                        const Text('Export Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (value, label) in _exportTypes)
                              ChoiceChip(
                                label: Text(label),
                                selected: _exportType == value,
                                onSelected: (_) {
                                  setState(() => _exportType = value);
                                  _onSessionOrTypeChanged();
                                },
                              ),
                          ],
                        ),
                        if (_exportType == 'groups') ..._groupsExportOptions(),
                        if (isGroupParticipants) ..._groupMultiSelectSection(title: 'Select Groups'),
                        if (isBroadcastGroups) ..._groupMultiSelectSection(title: 'Select Broadcast Groups'),
                        if (isLabels) ..._labelsSection(),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: isLabels
                              ? FilledButton.icon(
                                  onPressed: (_exportingLabels || _selectedLabelIds.isEmpty) ? null : _doLabelsExport,
                                  icon: _exportingLabels
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.download_rounded),
                                  label: Text(_exportingLabels
                                      ? 'Fetching chats…'
                                      : _selectedLabelIds.isEmpty
                                          ? 'Select labels first'
                                          : 'Export Chats from ${_selectedLabelIds.length} Label${_selectedLabelIds.length != 1 ? 's' : ''}'),
                                )
                              : (isGroupParticipants || isBroadcastGroups)
                                  ? FilledButton.icon(
                                      onPressed: (_downloadingCsv || _sessionId == null || _selectedGroupIds.isEmpty) ? null : _doParticipantsExport,
                                      icon: _downloadingCsv
                                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Icon(Icons.download_rounded),
                                      label: Text(_downloadingCsv
                                          ? (isGroupParticipants ? 'Fetching & deduplicating…' : 'Fetching…')
                                          : _selectedGroupIds.isEmpty
                                              ? 'Select groups first'
                                              : isBroadcastGroups
                                                  ? 'Export ${_selectedGroupIds.length} Broadcast Group${_selectedGroupIds.length != 1 ? 's' : ''}'
                                                  : _selectedGroupIds.length > 1
                                                      ? 'Export Unique Contacts from ${_selectedGroupIds.length} Groups'
                                                      : 'Export Participants CSV'),
                                    )
                                  : FilledButton.icon(
                                      onPressed: (_submitting || _hasRunningJob) ? null : _startExport,
                                      icon: _submitting
                                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Icon(Icons.download_rounded),
                                      label: Text(_hasRunningJob ? 'Export in progress…' : 'Start Export'),
                                    ),
                        ),
                      ],
                    ),
                  ),
                  if (isGroupParticipants)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(children: [
                        const Icon(Icons.check_circle_rounded, color: AppPalette.success, size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Participants are fetched directly from WhatsApp and downloaded instantly — duplicate contacts across groups are automatically removed.',
                            style: TextStyle(fontSize: 12, color: context.mutedColor),
                          ),
                        ),
                      ]),
                    ),
                  if (!isGroupParticipants) ...[
                    const SizedBox(height: 20),
                    Text('Export History', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_jobs.isEmpty)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No exports yet', style: TextStyle(color: context.mutedColor))))
                    else
                      ..._jobs.map((job) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: RecordCard(
                              title: exportTypeLabel(str(job['export_type'], '')),
                              subtitle: 'Session: ${str(job['session_id'], '')}'
                                  '${job['row_count'] != null ? ' · ${job['row_count']} rows' : ''}'
                                  '${str(job['error_message'], '').isNotEmpty ? ' · ${job['error_message']}' : ''}',
                              leadingIcon: Icons.description_rounded,
                              leadingColor: _statusColor(str(job['status'], '')),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (str(job['status'], '') == 'done' && str(job['file_url'], '').isNotEmpty)
                                    IconButton(icon: const Icon(Icons.download_rounded), tooltip: 'Download CSV', onPressed: () => _download(job))
                                  else if (str(job['status'], '') == 'processing')
                                    const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                                  IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppPalette.danger), tooltip: 'Delete', onPressed: () => _deleteJob(job)),
                                ],
                              ),
                            ),
                          )),
                  ],
                ],
              ),
            ),
    );
  }

  List<Widget> _groupsExportOptions() {
    return [
      CheckboxListTile(
        value: _includeParticipants,
        onChanged: (v) => setState(() => _includeParticipants = v ?? false),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Include group participants', style: TextStyle(fontSize: 13)),
      ),
      if (_sessionId != null) ...[
        TextButton.icon(
          onPressed: () {
            setState(() => _showGroupPreview = !_showGroupPreview);
            if (_showGroupPreview && _groups.isEmpty) _loadGroups();
          },
          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          icon: Icon(_showGroupPreview ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 14),
          label: Text('${_showGroupPreview ? 'Hide' : 'Preview'} groups in this session', style: const TextStyle(fontSize: 12)),
        ),
        if (_showGroupPreview)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(8)),
            constraints: const BoxConstraints(maxHeight: 200),
            child: _groupsLoading
                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                : _groups.isEmpty
                    ? Padding(padding: const EdgeInsets.all(12), child: Center(child: Text('No groups found.', style: TextStyle(fontSize: 12, color: context.mutedColor))))
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            color: context.altSurface,
                            child: Text('${_groups.length} group${_groups.length != 1 ? 's' : ''} — all will be exported', style: TextStyle(fontSize: 11, color: context.mutedColor)),
                          ),
                          for (final g in _groups)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.groups_rounded, size: 16),
                              title: Text(str(g['name']), style: const TextStyle(fontSize: 13)),
                              trailing: g['participantsCount'] != null ? Text('${g['participantsCount']} members', style: TextStyle(fontSize: 11, color: context.mutedColor)) : null,
                            ),
                        ],
                      ),
          ),
      ],
    ];
  }

  List<Widget> _groupMultiSelectSection({required String title}) {
    return [
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        if (_groups.isNotEmpty) ...[
          TextButton(
            onPressed: () => setState(() { _selectedGroupIds.addAll(_groups.map((g) => str(g['id']))); }),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('Select all', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => setState(_selectedGroupIds.clear),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('Clear', style: TextStyle(fontSize: 12)),
          ),
        ],
      ]),
      const SizedBox(height: 6),
      if (_sessionId == null)
        Text('Select a session first.', style: TextStyle(fontSize: 13, color: context.mutedColor))
      else if (_groupsLoading)
        Row(children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('Loading groups…', style: TextStyle(fontSize: 13, color: context.mutedColor)),
        ])
      else if (_groups.isEmpty)
        const Text('No groups found for this session.', style: TextStyle(fontSize: 13, color: AppPalette.danger))
      else
        Container(
          decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(8)),
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _groups.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final g = _groups[i];
              final id = str(g['id']);
              final checked = _selectedGroupIds.contains(id);
              return CheckboxListTile(
                dense: true,
                value: checked,
                onChanged: (_) => _toggleGroup(id),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(str(g['name']), style: TextStyle(fontSize: 13, fontWeight: checked ? FontWeight.w600 : FontWeight.normal)),
                secondary: g['participantsCount'] != null ? Text('${g['participantsCount']}', style: TextStyle(fontSize: 11, color: context.mutedColor)) : null,
              );
            },
          ),
        ),
      if (_selectedGroupIds.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppPalette.accent, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text('${_selectedGroupIds.length} group${_selectedGroupIds.length != 1 ? 's' : ''} selected', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.accent))),
          ]),
        ),
      if (_exportType == 'group_participants' && _selectedGroupIds.length == 1) ..._singleGroupPreview(),
    ];
  }

  List<Widget> _singleGroupPreview() {
    if (_singleGroupLoading) {
      return [
        const SizedBox(height: 8),
        Row(children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('Loading participants…', style: TextStyle(fontSize: 13, color: context.mutedColor)),
        ]),
      ];
    }
    final participants = (_singleGroupInfo?['participants'] as List?)?.whereType<Map>().toList() ?? const [];
    if (participants.isEmpty) return const [];
    final admins = participants.where((p) => p['isAdmin'] == true).length;
    return [
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(8)),
        constraints: const BoxConstraints(maxHeight: 200),
        child: ListView(
          shrinkWrap: true,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: AppPalette.success.withValues(alpha: 0.08),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: AppPalette.success, size: 14),
                const SizedBox(width: 6),
                Text('${participants.length} participants', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppPalette.success)),
                const Spacer(),
                Text('$admins admins', style: TextStyle(fontSize: 11, color: context.mutedColor)),
              ]),
            ),
            for (final p in participants)
              ListTile(
                dense: true,
                leading: Icon(Icons.person_rounded, size: 15, color: p['isAdmin'] == true ? AppPalette.accent : context.mutedColor),
                title: Text(str(p['number']), style: const TextStyle(fontSize: 13)),
                trailing: p['isAdmin'] == true ? const StatusPill('Admin', color: AppPalette.accent) : null,
                subtitle: str(p['name'], '').isNotEmpty ? Text(str(p['name']), style: const TextStyle(fontSize: 11)) : null,
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _labelsSection() {
    return [
      const SizedBox(height: 4),
      Row(children: [
        const Expanded(child: Text('Select Labels', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        if (_labels.isNotEmpty) ...[
          TextButton(
            onPressed: () => setState(() { _selectedLabelIds.addAll(_labels.map((l) => str(l['id']))); }),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('Select all', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => setState(_selectedLabelIds.clear),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('Clear', style: TextStyle(fontSize: 12)),
          ),
        ],
      ]),
      Text('WhatsApp Business labels for this session — not the CRM\'s own labels.', style: TextStyle(fontSize: 11, color: context.mutedColor)),
      const SizedBox(height: 6),
      if (_sessionId == null)
        Text('Select a session first.', style: TextStyle(fontSize: 13, color: context.mutedColor))
      else if (_labelsLoading)
        Row(children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('Loading labels…', style: TextStyle(fontSize: 13, color: context.mutedColor)),
        ])
      else if (_labelsError != null)
        Text(_labelsError!, style: const TextStyle(fontSize: 13, color: AppPalette.danger))
      else if (_labels.isEmpty)
        const Text('No WhatsApp labels found on this session.', style: TextStyle(fontSize: 13, color: AppPalette.danger))
      else
        Container(
          decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(8)),
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _labels.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final l = _labels[i];
              final id = str(l['id']);
              final checked = _selectedLabelIds.contains(id);
              final hex = str(l['hexColor'], '');
              final swatch = hex.isNotEmpty ? _parseHexColor(hex) : null;
              return CheckboxListTile(
                dense: true,
                value: checked,
                onChanged: (_) => _toggleLabel(id),
                controlAffinity: ListTileControlAffinity.leading,
                secondary: swatch != null
                    ? Container(width: 14, height: 14, decoration: BoxDecoration(color: swatch, shape: BoxShape.circle))
                    : Icon(Icons.label_rounded, size: 15, color: checked ? AppPalette.accent : context.mutedColor),
                title: Text(str(l['name']), style: TextStyle(fontSize: 13, fontWeight: checked ? FontWeight.w600 : FontWeight.normal)),
              );
            },
          ),
        ),
      if (_selectedLabelIds.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppPalette.accent, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${_selectedLabelIds.length} label${_selectedLabelIds.length != 1 ? 's' : ''} selected — all contacts with these labels will be exported',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.accent),
              ),
            ),
          ]),
        ),
    ];
  }
}

String exportTypeLabel(String type) => switch (type) {
      'chat_list' => 'Chat List',
      'contact_list' => 'Saved Contacts',
      'group_list' => 'Group List',
      'group_participants' => 'Group Participants',
      'message_history' => 'Message History',
      _ => type,
    };
