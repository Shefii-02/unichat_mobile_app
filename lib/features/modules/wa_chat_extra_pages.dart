// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/wa_gateway_client.dart';
import 'package:unichat_mobile_app/core/widgets/app_empty_state.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'module_providers.dart';
import '_shared.dart';

// ══════════════════════════ Automation Rules ══════════════════════════

const _ruleTypes = <(String, String)>[
  ('welcome_message', 'Welcome Message'),
  ('out_of_office', 'Out of Office'),
  ('lead_qualifier', 'Lead Qualifier'),
  ('keyword_trigger', 'Keyword Trigger'),
  ('follow_up_reminder', 'Follow-up Reminder'),
  ('follow_up_agent', 'Follow-up Agent'),
  ('inactivity_trigger', 'Inactivity Trigger'),
];

String _ruleTypeLabel(String v) =>
    _ruleTypes.firstWhere((r) => r.$1 == v, orElse: () => (v, v)).$2;

const _scheduleDays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

class AutomationRulesPage extends ConsumerWidget {
  const AutomationRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Automation Rules'),
          bottom: const TabBar(tabs: [Tab(text: 'Rules'), Tab(text: 'Logs')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(context, ref, null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New rule'),
        ),
        body: TabBarView(children: [
          ProviderList(
            provider: waChatAutomationRulesProvider,
            emptyLabel: 'No automation rules yet',
            emptyIcon: Icons.auto_awesome_rounded,
            tile: (context, r) {
              final actions = (r['actions'] is List) ? r['actions'] as List : const [];
              final message = actions.isNotEmpty && actions.first is Map ? (actions.first as Map)['message'] : null;
              return RecordCard(
                title: str(r['name']),
                subtitle: '${_ruleTypeLabel(str(r['rule_type'], ''))} · ${str(r['session_id'])}'
                    '${message != null ? ' · "$message"' : ''}',
                leadingIcon: Icons.auto_awesome_rounded,
                leadingColor: r['is_active'] == false ? null : AppPalette.success,
                trailing: RowMenu(items: [
                  (r['is_active'] == false ? 'Activate' : 'Deactivate', Icons.power_settings_new_rounded, () async {
                    final ok = await runAction(context, () => Api.post('/wa-agent/automations/${r['id']}/toggle'));
                    if (ok) ref.invalidate(waChatAutomationRulesProvider);
                  }),
                  ('Edit', Icons.edit_rounded, () => _edit(context, ref, r)),
                  ('Delete', Icons.delete_outline_rounded, () async {
                    final sure = await confirm(context, title: 'Delete "${r['name']}"?', destructive: true, confirmLabel: 'Delete');
                    if (!sure) return;
                    final done = await runAction(context, () => Api.delete('/wa-agent/automations/${r['id']}'), success: 'Deleted');
                    if (done) ref.invalidate(waChatAutomationRulesProvider);
                  }),
                ]),
              );
            },
          ),
          const _AutomationLogsTab(),
        ]),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec? existing) async {
    List<Rec> sessions;
    try {
      sessions = await Api.list('/waha/sessions');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    final actions = (existing?['actions'] is List) ? existing!['actions'] as List : const [];
    final existingMessage = actions.isNotEmpty && actions.first is Map ? (actions.first as Map)['message'] as String? : null;
    final existingDays = (existing?['schedule_days'] is List)
        ? (existing!['schedule_days'] as List).map((d) => '$d').toSet()
        : <String>{};

    final data = <String, dynamic>{
      'rule_type': existing?['rule_type'] ?? 'welcome_message',
      'is_active': existing?['is_active'] ?? true,
    };
    var days = existingDays;

    final ok = await showFormSheet(
      context,
      title: existing == null ? 'New automation rule' : 'Edit rule',
      fields: (ctx) => [
        FText(label: 'Name', initial: existing?['name'] as String?, required: true, onSaved: (v) => data['name'] = v),
        FSelect<Rec>(label: 'Session', options: sessions,
            initial: existing == null
                ? null
                : sessions.cast<Rec?>().firstWhere((s) => s?['session_id'] == existing['session_id'], orElse: () => null),
            labelOf: (s) => str(s['session_name'] ?? s['session_id']),
            onSaved: (s) => data['session_id'] = s?['session_id']),
        FSelect<String>(label: 'Rule type', options: _ruleTypes.map((r) => r.$1).toList(),
            initial: str(data['rule_type'], 'welcome_message'), labelOf: _ruleTypeLabel,
            onSaved: (v) => data['rule_type'] = v ?? 'welcome_message'),
        FText(label: 'Reply message', initial: existingMessage, maxLines: 3, required: true,
            onSaved: (v) => data['actions'] = [{'type': 'send_message', 'message': v}]),
        FChips(label: 'Keywords (for Keyword Trigger)', initial: (existing?['keywords'] as List?)?.map((e) => '$e').toList() ?? const [],
            onSaved: (v) => data['keywords'] = v.isEmpty ? null : v),
        FNumber(label: 'Priority (0-100)', initial: existing?['priority'] as num?, onSaved: (v) => data['priority'] = v ?? 0),
        FNumber(label: 'Delay hours (Follow-up)', initial: existing?['delay_hours'] as num?, onSaved: (v) => data['delay_hours'] = v),
        FNumber(label: 'Inactivity hours (Inactivity Trigger)', initial: existing?['inactivity_hours'] as num?,
            onSaved: (v) => data['inactivity_hours'] = v),
        FText(label: 'Schedule start (HH:mm, optional)', initial: existing?['schedule_start'] as String?,
            onSaved: (v) => data['schedule_start'] = v.isEmpty ? null : v),
        FText(label: 'Schedule end (HH:mm, optional)', initial: existing?['schedule_end'] as String?,
            onSaved: (v) => data['schedule_end'] = v.isEmpty ? null : v),
        StatefulBuilder(builder: (ctx, setSheetState) {
          return FField(
            label: 'Schedule days (optional — blank = every day)',
            child: Wrap(
              spacing: 6,
              children: _scheduleDays.map((d) {
                final selected = days.contains(d);
                return FilterChip(
                  label: Text(d.substring(0, 3)),
                  selected: selected,
                  onSelected: (v) => setSheetState(() => v ? days.add(d) : days.remove(d)),
                );
              }).toList(),
            ),
          );
        }),
        FBoolField(label: 'Active', initial: data['is_active'] as bool, onSaved: (v) => data['is_active'] = v),
      ],
      onSubmit: () {
        data['schedule_days'] = days.isEmpty ? null : days.toList();
        return existing == null
            ? Api.post('/wa-agent/automations', data: data)
            : Api.patch('/wa-agent/automations/${existing['id']}', data: data);
      },
    );
    if (ok) ref.invalidate(waChatAutomationRulesProvider);
  }
}

class _AutomationLogsTab extends StatefulWidget {
  const _AutomationLogsTab();
  @override
  State<_AutomationLogsTab> createState() => _AutomationLogsTabState();
}

class _AutomationLogsTabState extends State<_AutomationLogsTab> {
  List<Rec> _logs = [];
  bool _loading = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Api.list('/wa-agent/automations/logs', query: {
        if (_status != null) 'status': _status,
      });
      setState(() {
        _logs = rows;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: ['', 'success', 'failed', 'skipped'].map((s) {
              final selected = _status == (s.isEmpty ? null : s);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(s.isEmpty ? 'All' : s[0].toUpperCase() + s.substring(1)),
                  selected: selected,
                  onSelected: (_) { setState(() => _status = s.isEmpty ? null : s); _load(); },
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _logs.isEmpty
                  ? Center(child: Text('No logs', style: TextStyle(color: context.mutedColor)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _logs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final log = _logs[i];
                          return RecordCard(
                            title: _ruleTypeLabel(str(log['rule_type'], '')),
                            subtitle: '${str(log['contact_phone'])} · ${str(log['action_taken'], '')}'
                                '${log['error_message'] != null ? ' · ${log['error_message']}' : ''} · ${when(log['created_at'])}',
                            leadingIcon: Icons.receipt_long_rounded,
                            trailing: StatusPill(str(log['status'], 'skipped')),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

// ══════════════════════════ Inbox Analytics ══════════════════════════

class InboxAnalyticsPage extends ConsumerWidget {
  const InboxAnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox Analytics')),
      body: ProviderObject(
        provider: waChatAnalyticsProvider,
        builder: (context, d) {
          final overview = (d['overview'] is Map) ? d['overview'] as Map : const {};
          final bySession = (d['by_session'] is List) ? d['by_session'] as List : const [];
          final hourly = (d['hourly_activity'] is List) ? d['hourly_activity'] as List : const [];
          final topChats = (d['top_chats'] is List) ? d['top_chats'] as List : const [];
          final maxHourly = hourly.fold<num>(1, (m, h) {
            final v = (num.tryParse('${(h as Map)['sent'] ?? 0}') ?? 0) + (num.tryParse('${h['received'] ?? 0}') ?? 0);
            return v > m ? v : m;
          });
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (d['connected'] == false)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: AppPalette.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: const Row(children: [
                    Icon(Icons.warning_amber_rounded, color: AppPalette.warning, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text('No WhatsApp sessions are currently reachable.')),
                  ]),
                ),
              StatGrid([
                ('Sessions', '${overview['sessions_connected'] ?? 0}/${overview['sessions_total'] ?? 0}', Icons.smartphone_rounded),
                ('Sent', '${overview['messages_sent'] ?? 0}', Icons.send_rounded),
                ('Received', '${overview['messages_received'] ?? 0}', Icons.inbox_rounded),
                ('Today', '${overview['messages_today'] ?? 0}', Icons.today_rounded),
                ('Failed', '${overview['messages_failed'] ?? 0}', Icons.error_outline_rounded),
              ]),
              const SizedBox(height: 24),
              if (hourly.isNotEmpty) ...[
                const Text('Hourly activity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 90,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: hourly.map((h) {
                      final m = h as Map;
                      final v = (num.tryParse('${m['sent'] ?? 0}') ?? 0) + (num.tryParse('${m['received'] ?? 0}') ?? 0);
                      final h24 = m['hour'] ?? 0;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Tooltip(
                            message: '$h24:00 — $v msgs',
                            child: Container(
                              height: 8 + (v / maxHourly) * 70,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              if (bySession.isNotEmpty) ...[
                const Text('By session', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 10),
                ...bySession.map((s) {
                  final m = s as Map;
                  return RecordCard(
                    title: str(m['name']),
                    subtitle: 'Sent ${m['sent'] ?? 0} · Received ${m['received'] ?? 0} · Today ${m['today'] ?? 0}'
                        '${(m['failed'] ?? 0) != 0 ? ' · Failed ${m['failed']}' : ''}',
                    leadingIcon: Icons.smartphone_rounded,
                    trailing: StatusPill(str(m['status'], 'unknown')),
                  );
                }),
                const SizedBox(height: 24),
              ],
              if (topChats.isNotEmpty) ...[
                const Text('Top chats', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 10),
                ...topChats.map((c) {
                  final m = c as Map;
                  return KvRow(str(m['chat_name'], 'Unknown'), '${m['count'] ?? 0} msgs');
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ══════════════════════════ Audit Analytics ══════════════════════════

const _auditSeverities = ['info', 'warn', 'error'];

class AuditAnalyticsPage extends ConsumerStatefulWidget {
  const AuditAnalyticsPage({super.key});
  @override
  ConsumerState<AuditAnalyticsPage> createState() => _AuditAnalyticsPageState();
}

class _AuditAnalyticsPageState extends ConsumerState<AuditAnalyticsPage> {
  List<Rec> _rows = [];
  bool _loading = true;
  String? _error;
  String? _severity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = ref.read(authProvider).value?.waContactToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This company has no WhatsApp gateway token configured yet — connect a session from the web dashboard first.';
      });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await WaGatewayClient.auditLogs(token, severity: _severity, limit: 50);
      final rows = res['data'];
      setState(() {
        _rows = rows is List ? rows.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Analytics')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: const Text('All'), selected: _severity == null,
                      onSelected: (_) { setState(() => _severity = null); _load(); }),
                ),
                for (final s in _auditSeverities)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(s), selected: _severity == s,
                        onSelected: (_) { setState(() => _severity = s); _load(); }),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor))),
                      )
                    : _rows.isEmpty
                        ? Center(child: Text('No audit events', style: TextStyle(color: context.mutedColor)))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _rows.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final row = _rows[i];
                                return RecordCard(
                                  title: str(row['action'], 'event'),
                                  subtitle: [
                                    if (row['sessionName'] != null) row['sessionName'],
                                    if (row['method'] != null && row['path'] != null) '${row['method']} ${row['path']}',
                                    if (row['statusCode'] != null) 'HTTP ${row['statusCode']}',
                                    if (row['errorMessage'] != null) row['errorMessage'],
                                    when(row['createdAt']),
                                  ].join(' · '),
                                  leadingIcon: Icons.fact_check_rounded,
                                  trailing: StatusPill(str(row['severity'], 'info')),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════ WA Contacts (per session) ══════════════════════════

/// One session's WhatsApp contacts (see docs.open-wa.org/api-reference/contacts) — each row
/// syncs into this company's own CRM contacts with a single tap (`Contact.wa_id`/`phone`),
/// or a "Sync all" pass does every contact at once. Reached from a session's row menu on the
/// Sessions page.
class WaContactsPage extends StatefulWidget {
  const WaContactsPage({super.key, required this.sessionId, required this.sessionLabel});
  final int sessionId;
  final String sessionLabel;

  @override
  State<WaContactsPage> createState() => _WaContactsPageState();
}

class _WaContactsPageState extends State<WaContactsPage> {
  List<Rec> _contacts = [];
  bool _loading = true;
  String? _error;
  final Set<String> _syncing = {};
  bool _syncingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await Api.list('/waha/sessions/${widget.sessionId}/contacts');
      if (!mounted) return;
      setState(() { _contacts = rows; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  String _cid(Rec c) => str(c['id'] ?? c['_serialized'] ?? c['contactId'] ?? c['number'], '');
  String _cname(Rec c) => str(c['name'] ?? c['pushname'] ?? c['formattedName'] ?? c['shortName'], 'Unknown');
  String _cphone(Rec c) {
    final raw = str(c['number'] ?? _cid(c), '');
    return raw.split('@').first;
  }

  Future<void> _syncOne(Rec c) async {
    final id = _cid(c);
    if (id.isEmpty) return;
    setState(() => _syncing.add(id));
    try {
      await Api.post('/waha/sessions/${widget.sessionId}/contacts/${Uri.encodeComponent(id)}/sync');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Synced to CRM contacts.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _syncing.remove(id));
    }
  }

  Future<void> _syncAll() async {
    setState(() => _syncingAll = true);
    try {
      final res = await Api.post('/waha/sessions/${widget.sessionId}/contacts/sync');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(str(res['message'], 'Sync complete.'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _syncingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.sessionLabel} · Contacts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _syncingAll ? null : _syncAll,
        icon: _syncingAll
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.sync_rounded),
        label: const Text('Sync all to CRM'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppEmptyState(icon: Icons.error_outline, title: "Couldn't load contacts", subtitle: _error)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _contacts.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 80),
                          AppEmptyState(icon: Icons.contacts_rounded, title: 'No WhatsApp contacts found'),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _contacts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final c = _contacts[i];
                            final id = _cid(c);
                            final syncing = _syncing.contains(id);
                            return RecordCard(
                              title: _cname(c),
                              subtitle: _cphone(c),
                              leadingIcon: Icons.person_rounded,
                              trailing: syncing
                                  ? const SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : IconButton(
                                      icon: const Icon(Icons.sync_rounded),
                                      tooltip: 'Sync to CRM',
                                      onPressed: id.isEmpty ? null : () => _syncOne(c),
                                    ),
                            );
                          },
                        ),
                ),
    );
  }
}
