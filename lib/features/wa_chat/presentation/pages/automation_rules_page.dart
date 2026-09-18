// ignore_for_file: use_build_context_synchronously
import "dart:async";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/wa_chat_api.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

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

class AutomationRulesPage extends ConsumerStatefulWidget {
  const AutomationRulesPage({super.key});

  @override
  ConsumerState<AutomationRulesPage> createState() => _AutomationRulesPageState();
}

class _AutomationRulesPageState extends ConsumerState<AutomationRulesPage> {
  List<Rec> _sessions = [];
  String? _filterSessionId;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<List<Rec>> _loadSessions() async {
    try {
      final sessions = await WaChatApi.sessions();
      if (mounted) setState(() => _sessions = sessions);
      return sessions;
    } catch (_) {
      return _sessions;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Automation Rules'),
          bottom: const TabBar(tabs: [Tab(text: 'Rules'), Tab(text: 'Logs')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New rule'),
        ),
        body: TabBarView(children: [
          Column(
            children: [
              if (_sessions.isNotEmpty) _sessionFilterBar(),
              Expanded(child: _rulesList(context)),
            ],
          ),
          const _AutomationLogsTab(),
        ]),
      ),
    );
  }

  Widget _sessionFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: const Text('All sessions'),
                selected: _filterSessionId == null,
                onSelected: (_) => setState(() => _filterSessionId = null),
              ),
            ),
            for (final s in _sessions)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(str(s['session_name'] ?? s['session_id'])),
                  selected: _filterSessionId == str(s['session_id']),
                  onSelected: (_) => setState(() => _filterSessionId = str(s['session_id'])),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Rec> _filtered(List<Rec> rows) =>
      _filterSessionId == null ? rows : rows.where((r) => str(r['session_id']) == _filterSessionId).toList();

  Widget _rulesList(BuildContext context) {
    final async = ref.watch(waChatAutomationRulesProvider);
    return AsyncView<List<Rec>>(
      value: async,
      onRefresh: () async => ref.invalidate(waChatAutomationRulesProvider),
      isEmpty: (d) => _filtered(d).isEmpty,
      emptyLabel: _filterSessionId == null ? 'No automation rules yet' : 'No rules for this session',
      emptyIcon: Icons.auto_awesome_rounded,
      data: (rows) {
        final filtered = _filtered(rows);
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _ruleCard(context, filtered[i]),
        );
      },
    );
  }

  Widget _ruleCard(BuildContext context, Rec r) {
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
        ('Edit', Icons.edit_rounded, () => _edit(context, r)),
        ('Copy to another session', Icons.content_copy_rounded, () => _copyToSession(context, r)),
        ('Delete', Icons.delete_outline_rounded, () async {
          final sure = await confirm(context, title: 'Delete "${r['name']}"?', destructive: true, confirmLabel: 'Delete');
          if (!sure) return;
          final done = await runAction(context, () => WaChatApi.deleteAutomationRule(r['id']), success: 'Deleted');
          if (done) ref.invalidate(waChatAutomationRulesProvider);
        }),
      ]),
    );
  }

  Future<void> _copyToSession(BuildContext context, Rec r) async {
    final sessions = _sessions.isNotEmpty ? _sessions : await _loadSessions();
    final others = sessions.where((s) => str(s['session_id']) != str(r['session_id'])).toList();
    if (others.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other sessions to copy to')));
      return;
    }
    if (!context.mounted) return;
    final target = await showModalBottomSheet<Rec>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Copy "${str(r['name'])}" to session', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            ...others.map((s) => ListTile(
                  leading: const Icon(Icons.smartphone_rounded),
                  title: Text(str(s['session_name'] ?? s['session_id'])),
                  onTap: () => Navigator.pop(ctx, s),
                )),
          ],
        ),
      ),
    );
    if (target == null) return;
    final payload = <String, dynamic>{
      'session_id': target['session_id'],
      'rule_type': r['rule_type'],
      'name': r['name'],
      'is_active': r['is_active'] ?? true,
      'priority': r['priority'] ?? 0,
      'actions': r['actions'],
      'keywords': r['keywords'],
      'conditions': r['conditions'],
      'schedule_start': r['schedule_start'],
      'schedule_end': r['schedule_end'],
      'schedule_days': r['schedule_days'],
      'delay_hours': r['delay_hours'],
      'inactivity_hours': r['inactivity_hours'],
    };
    if (!context.mounted) return;
    final ok = await runAction(context, () => WaChatApi.createAutomationRule(payload),
        success: 'Copied to ${str(target['session_name'] ?? target['session_id'])}');
    if (ok) ref.invalidate(waChatAutomationRulesProvider);
  }

  Future<void> _edit(BuildContext context, Rec? existing) async {
    List<Rec> sessions = _sessions;
    if (sessions.isEmpty) {
      try {
        sessions = await _loadSessions();
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
        return;
      }
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

