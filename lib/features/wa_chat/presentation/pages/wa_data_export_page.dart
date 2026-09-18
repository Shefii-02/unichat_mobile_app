// ignore_for_file: use_build_context_synchronously
import "dart:async";
import "package:dio/dio.dart";
import "package:fl_chart/fl_chart.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";
import "package:url_launcher/url_launcher.dart";
import "package:unichat_mobile_app/core/network/wa_chat_api_service.dart";
import "package:unichat_mobile_app/core/widgets/app_empty_state.dart";
import "package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/wa_chat_api.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Data Export ══════════════════════════
// Mirrors the queued CSV-export flow in frontend/src/pages/wa-chat/pages/WaDataExport.tsx —
// the Laravel-backed job queue (chats / contacts / groups), which is the primary export path.
// This is a Laravel feature (`/wa-export`, permission `reports.manage`), not a gateway one: the
// gateway has no export/job concept of its own — RunWaExport pulls from it server-side.

const _exportTypes = <(String, String)>[
  ('chats', 'Chat List'),
  ('contacts', 'Saved Contacts'),
  ('groups', 'Groups'),
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
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
  }

  bool get _hasRunningJob =>
      _jobs.any((j) => j['status'] == 'pending' || j['status'] == 'processing');

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deleteJob(Rec job) async {
    if (!await confirm(context, title: 'Delete this export?', destructive: true, confirmLabel: 'Delete')) return;
    try {
      await WaChatApi.deleteExportJob(job['id'] as int);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _download(Rec job) async {
    final url = str(job['file_url'], '');
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open the download link.")));
      }
    }
  }

  Color _statusColor(String status) => switch (status) {
        'done' => AppPalette.success,
        'failed' => AppPalette.danger,
        'processing' => AppPalette.info,
        _ => AppPalette.warning,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data Export')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: AppPalette.danger)),
                    ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.lineColor),
                    ),
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
                            error: (e, _) => Text("Couldn't load sessions — ${apiErrorMessage(e)}",
                                style: const TextStyle(fontSize: 12, color: AppPalette.danger)),
                            data: (sessions) {
                              if (sessions.isEmpty) {
                                return Text('No sessions available', style: TextStyle(fontSize: 13, color: context.mutedColor));
                              }
                              _sessionId ??= str(sessions.first['session_name'], str(sessions.first['id'], ''));
                              return DropdownButtonFormField<String>(
                                initialValue: _sessionId,
                                isExpanded: true,
                                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                                items: sessions.map((s) {
                                  final id = str(s['session_name'], str(s['id'], ''));
                                  return DropdownMenuItem(value: id, child: Text(str(s['display_name'] ?? s['name'], 'Session'), style: const TextStyle(fontSize: 13)));
                                }).toList(),
                                onChanged: (v) => setState(() => _sessionId = v),
                              );
                            },
                          );
                        }),
                        const SizedBox(height: 12),
                        const Text('Export Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final (value, label) in _exportTypes)
                              ChoiceChip(
                                label: Text(label),
                                selected: _exportType == value,
                                onSelected: (_) => setState(() => _exportType = value),
                              ),
                          ],
                        ),
                        if (_exportType == 'groups')
                          CheckboxListTile(
                            value: _includeParticipants,
                            onChanged: (v) => setState(() => _includeParticipants = v ?? false),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Include group participants', style: TextStyle(fontSize: 13)),
                          ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: (_submitting || _hasRunningJob) ? null : _startExport,
                            icon: _submitting
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.download_rounded),
                            label: Text(_hasRunningJob ? 'Export in progress…' : 'Start Export'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Export History',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (_jobs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No exports yet', style: TextStyle(color: context.mutedColor))),
                    )
                  else
                    ..._jobs.map((job) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: RecordCard(
                            title: exportTypeLabel(str(job['export_type'], '')),
                            subtitle: 'Session: ${str(job['session_id'], '')}'
                                '${job['row_count'] != null ? ' · ${job['row_count']} rows' : ''}',
                            leadingIcon: Icons.description_rounded,
                            leadingColor: _statusColor(str(job['status'], '')),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (str(job['status'], '') == 'done' && str(job['file_url'], '').isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.download_rounded),
                                    tooltip: 'Download CSV',
                                    onPressed: () => _download(job),
                                  )
                                else if (str(job['status'], '') == 'processing')
                                  const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppPalette.danger),
                                  tooltip: 'Delete',
                                  onPressed: () => _deleteJob(job),
                                ),
                              ],
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
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
