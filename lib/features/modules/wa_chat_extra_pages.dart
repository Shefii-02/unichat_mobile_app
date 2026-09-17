// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:unichat_mobile_app/core/network/wa_chat_api_service.dart';
import 'package:unichat_mobile_app/core/widgets/app_empty_state.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'module_providers.dart';
import 'wa_chat_api.dart';
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
                    final ok = await runAction(context, () => WaChatApi.toggleAutomationRule(r['id']));
                    if (ok) ref.invalidate(waChatAutomationRulesProvider);
                  }),
                  ('Edit', Icons.edit_rounded, () => _edit(context, ref, r)),
                  ('Delete', Icons.delete_outline_rounded, () async {
                    final sure = await confirm(context, title: 'Delete "${r['name']}"?', destructive: true, confirmLabel: 'Delete');
                    if (!sure) return;
                    final done = await runAction(context, () => WaChatApi.deleteAutomationRule(r['id']), success: 'Deleted');
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
      sessions = await WaChatApi.sessions();
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
            ? WaChatApi.createAutomationRule(data)
            : WaChatApi.updateAutomationRule(existing['id'], data);
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
      final rows = await WaChatApi.automationLogs(query: {
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
    setState(() { _loading = true; _error = null; });
    try {
      final res = await WaChatApi.auditLog(severity: _severity, limit: 50);
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
      final rows = await WaChatApi.sessionContacts(widget.sessionId);
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
      await WaChatApi.syncContact(widget.sessionId, id);
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
      final res = await WaChatApi.syncAllContacts(widget.sessionId);
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

// ══════════════════════════ Dashboard ══════════════════════════
// Mirrors frontend/src/pages/wa-chat/pages/Dashboard.tsx: sessions + session-stats + webhooks
// straight from the gateway with the company's own scoped key (all three are readable by an
// OPERATOR-role key), plus /api/stats/overview and /api/stats/messages, which degrade rather
// than failing the whole page if a future guard change ever makes either admin-only.

const _dashboardPeriods = ['24h', '7d', '30d'];

/// Stable, distinct color per message type — mirrors DashboardCharts.tsx's TYPE_COLORS so the
/// pie legend reads the same on both platforms. Falls back to a deterministic name hash for any
/// type not in this map, so an unmapped type still gets a stable color across rebuilds.
const _typeColors = <String, Color>{
  'text': Color(0xFF25D366),
  'image': Color(0xFF3B82F6),
  'contact': Color(0xFFA855F7),
  'document': Color(0xFFF59E0B),
  'audio': Color(0xFF06B6D4),
  'voice': Color(0xFFEC4899),
  'video': Color(0xFF14B8A6),
  'sticker': Color(0xFFEF4444),
  'location': Color(0xFF84CC16),
  'poll': Color(0xFF6366F1),
  'revoked': Color(0xFFF43F5E),
  'masked': Color(0xFF8B5CF6),
  'unknown': Color(0xFF64748B),
};
const _typeColorFallbacks = [
  Color(0xFF0EA5E9), Color(0xFFD946EF), Color(0xFFF97316),
  Color(0xFF10B981), Color(0xFF6366F1), Color(0xFFEAB308),
];
Color _colorForType(String name) {
  final mapped = _typeColors[name];
  if (mapped != null) return mapped;
  var hash = 0;
  for (final c in name.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  return _typeColorFallbacks[hash % _typeColorFallbacks.length];
}

String _shortChatId(String chatId) => chatId.split('@').first;

/// Mirrors Dashboard.tsx's `formatLastActive` exactly (same thresholds and wording).
String _formatLastActive(String? iso) {
  if (iso == null || iso.isEmpty) return 'Never';
  final date = DateTime.tryParse(iso);
  if (date == null) return 'Never';
  final diff = DateTime.now().toUtc().difference(date.toUtc());
  if (diff.inMilliseconds < 60000) return 'Just now';
  if (diff.inMilliseconds < 3600000) return '${diff.inMinutes} min ago';
  if (diff.inMilliseconds < 86400000) return '${diff.inHours} hours ago';
  return '${date.day}/${date.month}/${date.year}';
}

class WaChatDashboardPage extends ConsumerStatefulWidget {
  const WaChatDashboardPage({super.key});
  @override
  ConsumerState<WaChatDashboardPage> createState() => _WaChatDashboardPageState();
}

class _WaChatDashboardPageState extends ConsumerState<WaChatDashboardPage> {
  List<Rec> _sessions = [];
  Rec _stats = {};
  Rec? _overview;
  int _webhookCount = 0;
  bool _loading = true;
  String? _error;
  bool _reconnecting = false;
  String? _apiKeyOverride;

  String _period = '24h';
  Rec? _messageStats;
  bool _statsLoading = false;
  bool _statsForbidden = false;
  String? _statsError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? get _apiKey => _apiKeyOverride ?? ref.read(authProvider).value?.waContactToken;

  Future<void> _load() async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This company has no WhatsApp gateway token configured yet.';
      });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final sessions = await WaChatApiService.getSessions(key);
      final stats = await WaChatApiService.getSessionStats(key);
      List<Rec> webhooks = [];
      Rec? overview;
      try {
        webhooks = await WaChatApiService.getWebhooks(key);
      } catch (_) {}
      try {
        overview = await WaChatApiService.getStatsOverview(key);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _stats = stats;
        _webhookCount = webhooks.length;
        _overview = overview;
        _loading = false;
      });
      unawaited(_loadMessageStats());
    } catch (e) {
      if (!mounted) return;
      // Deliberately NOT auto-reconnected on a 401 — reconnecting mints a fresh gateway key and
      // REVOKES THE OLD ONE (WaChatTokenService::provision), and that key is shared by every
      // client on the company's account (the web app, other devices, ...). Auto-firing it here
      // the moment this one page sees a transient 401 would kick every other concurrently-open
      // client off. Leave it to the manual "Reconnect WA Chat" button.
      setState(() { _loading = false; _error = apiErrorMessage(e); });
    }
  }

  Future<void> _loadMessageStats() async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return;
    setState(() { _statsLoading = true; _statsError = null; _statsForbidden = false; });
    try {
      final stats = await WaChatApiService.getMessageStats(key, _period);
      if (!mounted) return;
      setState(() { _messageStats = stats; _statsLoading = false; });
    } catch (e) {
      if (!mounted) return;
      // Non-admin keys 403 on /stats/messages for an unscoped key — but a session-scoped key (every
      // company's own token) reads its own sessions' aggregate fine, so a 403 here would mean a
      // future guard change; hide the section rather than showing a scary error, same as the React
      // dashboard's `forbidden` branch in DashboardCharts.tsx.
      final forbidden = e is DioException && e.response?.statusCode == 403;
      setState(() {
        _statsLoading = false;
        _statsForbidden = forbidden;
        _statsError = forbidden ? null : apiErrorMessage(e);
      });
    }
  }

  void _setPeriod(String p) {
    if (p == _period) return;
    setState(() => _period = p);
    _loadMessageStats();
  }

  Future<void> _reconnect() async {
    setState(() => _reconnecting = true);
    try {
      final res = await WaChatApi.reconnectToken();
      final key = res['wa_chat_token'] as String?;
      if (key == null || key.isEmpty) throw Exception('Gateway did not return a key.');
      if (!mounted) return;
      setState(() { _apiKeyOverride = key; _reconnecting = false; });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _reconnecting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't reconnect — ${apiErrorMessage(e)}")));
    }
  }

  Future<void> _disconnectSession(Rec s) async {
    final key = _apiKey;
    final sessionId = str(s['id'], '');
    if (key == null || sessionId.isEmpty) return;
    if (!await confirm(context, title: 'Disconnect this session?', confirmLabel: 'Disconnect')) return;
    try {
      await WaChatApiService.stopSession(sessionId, key);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Disconnecting…')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesToday = _overview != null
        ? (num.tryParse('${_overview!['messages']?['today']?['sent'] ?? 0}') ?? 0) +
            (num.tryParse('${_overview!['messages']?['today']?['received'] ?? 0}') ?? 0)
        : null;
    final totalMessages = _overview != null
        ? (num.tryParse('${_overview!['messages']?['sent'] ?? 0}') ?? 0) +
            (num.tryParse('${_overview!['messages']?['received'] ?? 0}') ?? 0)
        : null;
    final anyConnected = _sessions.any((s) => str(s['status'], '') == 'ready');

    return Scaffold(
      appBar: AppBar(title: const Text('WA Chat Dashboard')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppEmptyState(
                  icon: Icons.error_outline,
                  title: "Couldn't load the dashboard",
                  subtitle: _error,
                  action: TextButton(
                    onPressed: _reconnecting ? null : _reconnect,
                    child: _reconnecting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Reconnect WA Chat'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await _load();
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Overview of your WhatsApp sessions and activity',
                                style: TextStyle(color: context.mutedColor, fontSize: 13)),
                          ),
                          StatusPill(anyConnected ? 'Connected' : 'Disconnected'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 15,
                        runSpacing: 10,
                        children: [
                          _statCard('Sessions List', '${_stats['ready'] ?? 0}',
                              '${_stats['active'] ?? 0} running · ${_stats['total'] ?? 0} total',
                              Icons.smartphone_rounded),
                          _statCard('Messages Today', messagesToday?.toStringAsFixed(0) ?? '—', null,
                              Icons.send_rounded),
                          _statCard('Webhooks Config.', '$_webhookCount', null, Icons.webhook_rounded),
                          _statCard('Total Messages', totalMessages?.toStringAsFixed(0) ?? '—', null,
                              Icons.bar_chart_rounded),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _messageAnalytics(),
                      const SizedBox(height: 24),
                      Text('Sessions Overview',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text('Showing ${_sessions.length} of ${_stats['total'] ?? _sessions.length} sessions',
                          style: TextStyle(fontSize: 12, color: context.mutedColor)),
                      const SizedBox(height: 10),
                      if (_sessions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('No sessions yet', style: TextStyle(color: context.mutedColor))),
                        )
                      else
                        ..._sessions.map((s) => _sessionRow(s)),
                    ],
                  ),
                ),
    );
  }

  Widget _statCard(String label, String value, String? detail, IconData icon) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: context.mutedColor)),
              Icon(icon, size: 18, color: context.mutedColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(detail, style: TextStyle(fontSize: 11, color: context.mutedColor)),
          ],
        ],
      ),
    );
  }

  Widget _sessionRow(Rec s) {
    final status = str(s['status'], '');
    final canDisconnect = ['ready', 'initializing', 'qr_ready'].contains(status);
    final id = str(s['id'], '');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(id.length > 12 ? id.substring(0, 12) : id,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              StatusPill(status.isEmpty ? 'unknown' : status),
            ],
          ),
          const SizedBox(height: 6),
          Text(str(s['name'], 'Session'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 2),
          Text('${str(s['phone'], 'No number')} · ${_formatLastActive(str(s['lastActive'] ?? s['connectedAt'], ''))}',
              style: TextStyle(fontSize: 12, color: context.mutedColor)),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => context.push('/wa-chat/sessions'),
                child: const Text('View'),
              ),
              if (canDisconnect)
                TextButton(
                  onPressed: () => _disconnectSession(s),
                  style: TextButton.styleFrom(foregroundColor: AppPalette.danger),
                  child: const Text('Disconnect'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Message Analytics ──────────────────────────────────────────────────
  // Mirrors DashboardCharts.tsx: a period toggle plus a messages-over-time area chart, a
  // by-type breakdown, and a top-chats ranking, all sourced from one /api/stats/messages call.

  Widget _messageAnalytics() {
    if (_statsForbidden) return const SizedBox.shrink();

    final timeSeries = (_messageStats?['timeSeries'] as List?)?.cast<Rec>() ?? const [];
    final byTypeRaw = (_messageStats?['byType'] as Map?)?.cast<String, dynamic>() ?? const {};
    final byType = byTypeRaw.entries.map((e) => (e.key, (num.tryParse('${e.value}') ?? 0).toInt())).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final topChatsRaw = (_messageStats?['topChats'] as List?)?.cast<Rec>() ?? const [];
    final topChats = topChatsRaw.take(8).map((c) {
      final name = str(c['chatName'], '').isNotEmpty ? str(c['chatName']) : _shortChatId(str(c['chatId'], ''));
      return (name, (num.tryParse('${c['messageCount'] ?? 0}') ?? 0).toInt());
    }).toList();
    final hasData = timeSeries.isNotEmpty || byType.isNotEmpty || topChats.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Icon(Icons.bar_chart_rounded, size: 18),
              const SizedBox(width: 8),
              Text('Message Analytics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            Wrap(
              spacing: 6,
              children: [
                for (final p in _dashboardPeriods)
                  ChoiceChip(label: Text(p), selected: _period == p, onSelected: (_) => _setPeriod(p)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_statsLoading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
        else if (_statsError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(_statsError!, style: const TextStyle(color: AppPalette.danger)),
          )
        else if (!hasData)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No message activity in this period', style: TextStyle(color: context.mutedColor))),
          )
        else ...[
          if (timeSeries.isNotEmpty) _timeSeriesCard(timeSeries),
          const SizedBox(height: 12),
          if (byType.isNotEmpty) _byTypeCard(byType),
          const SizedBox(height: 12),
          if (topChats.isNotEmpty) _topChatsCard(topChats),
        ],
      ],
    );
  }

  Widget _chartCard(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _timeSeriesCard(List<Rec> timeSeries) {
    String tick(String ts) => _period == '24h'
        ? (ts.length >= 16 ? ts.substring(11, 16) : ts)
        : (ts.length >= 10 ? ts.substring(5, 10) : ts);

    final sentSpots = <FlSpot>[];
    final receivedSpots = <FlSpot>[];
    for (var i = 0; i < timeSeries.length; i++) {
      final p = timeSeries[i];
      sentSpots.add(FlSpot(i.toDouble(), (num.tryParse('${p['sent'] ?? 0}') ?? 0).toDouble()));
      receivedSpots.add(FlSpot(i.toDouble(), (num.tryParse('${p['received'] ?? 0}') ?? 0).toDouble()));
    }
    final step = (timeSeries.length / 5).ceil().clamp(1, timeSeries.length);

    return _chartCard(
      'Messages over time',
      Column(
        children: [
          SizedBox(
            height: 220,
            child: LineChart(LineChartData(
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32,
                    getTitlesWidget: (v, meta) => Text(v.toInt().toString(),
                        style: TextStyle(fontSize: 10, color: context.mutedColor)))),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: step.toDouble(),
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= timeSeries.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(tick(str(timeSeries[i]['timestamp'], '')),
                          style: TextStyle(fontSize: 10, color: context.mutedColor)),
                    );
                  },
                )),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: sentSpots, isCurved: true, color: AppPalette.success, barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: AppPalette.success.withValues(alpha: 0.15)),
                ),
                LineChartBarData(
                  spots: receivedSpots, isCurved: true, color: const Color(0xFF3B82F6), barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: const Color(0xFF3B82F6).withValues(alpha: 0.15)),
                ),
              ],
            )),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 16, children: [
            _legendDot(AppPalette.success, 'Sent'),
            _legendDot(const Color(0xFF3B82F6), 'Received'),
          ]),
        ],
      ),
    );
  }

  Widget _byTypeCard(List<(String, int)> byType) {
    final total = byType.fold<int>(0, (a, b) => a + b.$2);
    return _chartCard(
      'Messages by type',
      Column(
        children: [
          SizedBox(
            height: 180,
            child: PieChart(PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: byType.map((e) {
                final pct = total == 0 ? 0.0 : e.$2 / total * 100;
                return PieChartSectionData(
                  value: e.$2.toDouble(),
                  color: _colorForType(e.$1),
                  radius: 46,
                  title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
                  titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                );
              }).toList(),
            )),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: byType.map((e) => _legendDot(_colorForType(e.$1), '${e.$1} (${e.$2})')).toList(),
          ),
        ],
      ),
    );
  }

  Widget _topChatsCard(List<(String, int)> topChats) {
    final maxCount = topChats.fold<int>(1, (m, c) => c.$2 > m ? c.$2 : m);
    return _chartCard(
      'Top chats',
      Column(
        children: topChats.map((c) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(c.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: c.$2 / maxCount,
                      minHeight: 14,
                      backgroundColor: context.lineColor,
                      valueColor: const AlwaysStoppedAnimation(AppPalette.success),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${c.$2}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 11, color: context.mutedColor)),
    ]);
  }
}

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
