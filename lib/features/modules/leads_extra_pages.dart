// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'module_providers.dart';
import '_shared.dart';
import 'crm_extra_pages.dart' show LabelsPage;
import '../leads/lead_stage.dart';

// ══════════════════════════ Lead Categories ══════════════════════════

class LeadCategoriesPage extends ConsumerWidget {
  const LeadCategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lead Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add category'),
      ),
      body: ProviderList(
        provider: leadCategoriesProvider,
        emptyLabel: 'No lead categories yet',
        emptyIcon: Icons.sell_outlined,
        tile: (context, c) {
          final color = LabelsPage.parseColor(c['color'] as String?);
          final leadsCount = c['leads_count'] ?? 0;
          return RecordCard(
            title: str(c['name']),
            subtitle: '$leadsCount leads'
                '${c['is_active'] == false ? ' · Inactive' : ''}'
                '${c['description'] != null ? ' · ${c['description']}' : ''}',
            leadingIcon: Icons.sell_rounded,
            leadingColor: color,
            trailing: RowMenu(items: [
              ('Edit', Icons.edit_rounded, () => _edit(context, ref, c)),
              ('Delete', Icons.delete_outline_rounded, () async {
                final ok = await confirm(context, title: 'Delete "${c['name']}"?', destructive: true, confirmLabel: 'Delete');
                if (!ok) return;
                final done = await runAction(context, () => Api.delete('/lead-categories/${c['id']}'), success: 'Deleted');
                if (done) ref.invalidate(leadCategoriesProvider);
              }),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec? existing) async {
    final data = <String, dynamic>{'color': existing?['color'] ?? '#1D9E75'};
    final ok = await showFormSheet(
      context,
      title: existing == null ? 'Add category' : 'Edit category',
      fields: (ctx) => [
        FText(label: 'Name', initial: existing?['name'] as String?, required: true, onSaved: (v) => data['name'] = v),
        FText(label: 'Color (hex, e.g. #1D9E75)', initial: data['color'] as String, required: true,
            onSaved: (v) => data['color'] = v),
        FText(label: 'Description', initial: existing?['description'] as String?, maxLines: 2,
            onSaved: (v) => v.isEmpty ? null : data['description'] = v),
        if (existing != null)
          FBoolField(label: 'Active', initial: existing['is_active'] != false, onSaved: (v) => data['is_active'] = v),
      ],
      onSubmit: () => existing == null
          ? Api.post('/lead-categories', data: data)
          : Api.put('/lead-categories/${existing['id']}', data: data),
    );
    if (ok) ref.invalidate(leadCategoriesProvider);
  }
}

// ══════════════════════════ Leads by Staff ══════════════════════════

class LeadsByStaffPage extends ConsumerWidget {
  const LeadsByStaffPage({super.key});

  static num _lv(Rec s, String key) {
    final nested = s['leads'];
    if (nested is Map && nested[key] != null) return num.tryParse('${nested[key]}') ?? 0;
    return num.tryParse('${s['${key}_leads'] ?? s[key] ?? 0}') ?? 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leads by Staff')),
      body: ProviderList(
        provider: staffPerformanceProvider,
        emptyLabel: 'No staff performance data',
        emptyIcon: Icons.groups_outlined,
        tile: (context, s) {
          final total = _lv(s, 'total');
          final newC = _lv(s, 'new');
          final enrolled = _lv(s, 'enrolled');
          final conversion = s['conversion_rate'];
          return RecordCard(
            title: str(s['name']),
            subtitle: '$total total · $newC new · $enrolled won'
                '${conversion != null ? ' · $conversion% conv.' : ''}',
            leadingIcon: Icons.person_rounded,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(
                '/leads-by-staff/${s['id'] ?? s['user_id']}?name=${Uri.encodeComponent(str(s['name']))}'),
          );
        },
      ),
    );
  }
}

class StaffLeadsPage extends ConsumerStatefulWidget {
  const StaffLeadsPage({super.key, required this.staffId, required this.staffName});
  final int staffId;
  final String staffName;

  @override
  ConsumerState<StaffLeadsPage> createState() => _StaffLeadsPageState();
}

class _StaffLeadsPageState extends ConsumerState<StaffLeadsPage> {
  List<Rec> _leads = [];
  bool _loading = true;
  String? _stage;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Api.list('/leads', query: {'assigned_to': widget.staffId, 'per_page': 200});
      setState(() {
        _leads = rows;
        _loading = false;
        _selected.clear();
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<Rec> get _filtered =>
      _stage == null ? _leads : _leads.where((l) => l['stage'] == _stage).toList();

  @override
  Widget build(BuildContext context) {
    final selecting = _selected.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.staffName),
        actions: selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.swap_horiz_rounded),
                  tooltip: 'Reassign selected',
                  onPressed: _reassignSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Delete selected',
                  onPressed: _deleteSelected,
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: const Text('All'), selected: _stage == null,
                      onSelected: (_) => setState(() => _stage = null)),
                ),
                for (final s in stageTint.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(stageLabel(s)), selected: _stage == s,
                        onSelected: (_) => setState(() => _stage = s)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(child: Text('No leads', style: TextStyle(color: context.mutedColor)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final lead = _filtered[i];
                            final id = lead['id'] as int;
                            final contact = (lead['contact'] is Map) ? (lead['contact'] as Map) : const {};
                            final stage = str(lead['stage'], 'new');
                            final tint = stageTint[stage];
                            return RecordCard(
                              title: str(contact['name'], 'Unknown'),
                              subtitle: '${contact['phone'] ?? ''} · ${stageLabel(stage)}',
                              leadingIcon: _selected.contains(id) ? Icons.check_circle_rounded : Icons.person_outline_rounded,
                              leadingColor: _selected.contains(id) ? Theme.of(context).colorScheme.primary : tint?.$2,
                              onTap: () {
                                if (selecting) {
                                  setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
                                } else {
                                  context.push('/lead-detail/$id');
                                }
                              },
                              trailing: RowMenu(items: [
                                (_selected.contains(id) ? 'Deselect' : 'Select', Icons.check_box_outlined,
                                    () => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id))),
                              ]),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _reassignSelected() async {
    List<Rec> staff;
    try {
      staff = await Api.list('/staff');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    final ids = _selected.toList();
    int? toStaff;
    final ok = await showFormSheet(
      context,
      title: 'Reassign ${ids.length} lead(s)',
      submitLabel: 'Reassign',
      fields: (ctx) => [
        FSelect<Rec>(label: 'New staff', options: staff, labelOf: (s) => str(s['name']),
            onSaved: (s) => toStaff = s?['id'] as int?),
      ],
      onSubmit: () => Api.post('/leads/bulk-assign', data: {'lead_ids': ids, 'staff_id': toStaff}),
    );
    if (ok) _load();
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    final ok = await confirm(context, title: 'Delete ${ids.length} lead(s)?', destructive: true, confirmLabel: 'Delete');
    if (!ok) return;
    final done = await runAction(context, () => Api.post('/leads/bulk-delete', data: {'lead_ids': ids}), success: 'Deleted');
    if (done) _load();
  }
}

// ══════════════════════════ Lead Logs ══════════════════════════

const _leadEvents = [
  'note_added', 'stage_changed', 'assigned', 'reassigned_bulk',
  'lead_assigned', 'lead_assignment_accepted', 'lead_assignment_declined',
  'lead_assignment_timeout', 'lead_assignment_transferred',
  'lead_assignment_completed', 'lead_ai_handoff', 'lead_sla_breached',
];

String _eventLabel(String e) => e.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

class LeadLogsPage extends StatefulWidget {
  const LeadLogsPage({super.key});
  @override
  State<LeadLogsPage> createState() => _LeadLogsPageState();
}

class _LeadLogsPageState extends State<LeadLogsPage> {
  List<Rec> _logs = [];
  bool _loading = true;
  String? _event;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Api.list('/leads/logs', query: {
        'per_page': 50,
        if (_event != null) 'event': _event,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Lead Activity Logs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: DropdownButtonFormField<String?>(
              initialValue: _event,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Filter by event', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('All events')),
                for (final e in _leadEvents) DropdownMenuItem(value: e, child: Text(_eventLabel(e))),
              ],
              onChanged: (v) {
                setState(() => _event = v);
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(child: Text('No activity', style: TextStyle(color: context.mutedColor)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _logs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final log = _logs[i];
                            final lead = (log['lead'] is Map) ? (log['lead'] as Map) : null;
                            final contact = (lead?['contact'] is Map) ? (lead!['contact'] as Map) : null;
                            final payload = (log['payload'] is Map) ? (log['payload'] as Map) : const {};
                            return RecordCard(
                              title: _eventLabel(str(log['event'], 'event')),
                              subtitle: [
                                if (contact?['name'] != null) contact!['name'],
                                if (payload['from'] != null && payload['to'] != null) '${payload['from']} → ${payload['to']}',
                                str(log['user'], 'System'),
                                when(log['created_at']),
                              ].join(' · '),
                              leadingIcon: Icons.history_rounded,
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

// ══════════════════════════ Lead Summary ══════════════════════════

class LeadSummaryPage extends StatefulWidget {
  const LeadSummaryPage({super.key});
  @override
  State<LeadSummaryPage> createState() => _LeadSummaryPageState();
}

class _LeadSummaryPageState extends State<LeadSummaryPage> {
  Rec? _summary;
  bool _loading = true;
  final _from = TextEditingController();
  final _to = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.one('/leads/summary', query: {
        if (_from.text.isNotEmpty) 'from': _from.text,
        if (_to.text.isNotEmpty) 'to': _to.text,
      });
      setState(() {
        _summary = res;
        _loading = false;
        _from.text = str(res['range']?['from'], _from.text);
        _to.text = str(res['range']?['to'], _to.text);
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Lead Summary')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : s == null
              ? Center(child: Text('Could not load summary', style: TextStyle(color: context.mutedColor)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(children: [
                        Expanded(child: TextField(controller: _from, decoration: const InputDecoration(labelText: 'From (YYYY-MM-DD)', isDense: true))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: _to, decoration: const InputDecoration(labelText: 'To (YYYY-MM-DD)', isDense: true))),
                        const SizedBox(width: 8),
                        IconButton(icon: const Icon(Icons.search_rounded), onPressed: _load),
                      ]),
                      const SizedBox(height: 16),
                      StatGrid([
                        ('All leads', '${s['totals']?['all'] ?? 0}', Icons.groups_rounded),
                        ('In range', '${s['totals']?['in_range'] ?? 0}', Icons.date_range_rounded),
                        ('New today', '${s['totals']?['new_today'] ?? 0}', Icons.fiber_new_rounded),
                        ('New this week', '${s['totals']?['new_week'] ?? 0}', Icons.calendar_view_week_rounded),
                        ('New this month', '${s['totals']?['new_month'] ?? 0}', Icons.calendar_month_rounded),
                        ('Unassigned', '${s['totals']?['unassigned'] ?? 0}', Icons.person_off_rounded),
                        ('Enrolled', '${s['totals']?['enrolled'] ?? 0}', Icons.check_circle_rounded),
                        ('Conversion', '${s['totals']?['conversion_rate'] ?? 0}%', Icons.trending_up_rounded),
                      ]),
                      const SizedBox(height: 20),
                      _BarSection(title: 'By stage', data: s['by_stage']),
                      _BarSection(title: 'By source', data: s['by_source']),
                      _BarSection(title: 'By priority', data: s['by_priority']),
                      if (s['by_agent'] is List && (s['by_agent'] as List).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('By agent', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 8),
                        ...(s['by_agent'] as List).whereType<Map>().map(
                              (a) => KvRow(str(a['agent']), '${a['total']}'),
                            ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _BarSection extends StatelessWidget {
  const _BarSection({required this.title, required this.data});
  final String title;
  final dynamic data;

  @override
  Widget build(BuildContext context) {
    if (data is! Map || (data as Map).isEmpty) return const SizedBox.shrink();
    final entries = (data as Map).entries.toList()
      ..sort((a, b) => (num.tryParse('${b.value}') ?? 0).compareTo(num.tryParse('${a.value}') ?? 0));
    final max = entries.fold<num>(1, (m, e) => (num.tryParse('${e.value}') ?? 0) > m ? num.tryParse('${e.value}') ?? 0 : m);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${e.key}', style: const TextStyle(fontSize: 13)),
                      Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (num.tryParse('${e.value}') ?? 0) / max,
                      minHeight: 6,
                      backgroundColor: context.altSurface,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════ Lead Report ══════════════════════════

const _reportGroupBy = ['stage', 'source', 'category', 'agent', 'day'];
const _reportDateField = ['created_at', 'assigned_at', 'enrolled_at'];

class LeadReportPage extends ConsumerStatefulWidget {
  const LeadReportPage({super.key});
  @override
  ConsumerState<LeadReportPage> createState() => _LeadReportPageState();
}

class _LeadReportPageState extends ConsumerState<LeadReportPage> {
  Rec? _report;
  bool _loading = true;
  String _groupBy = 'stage';
  String _dateField = 'created_at';
  String? _stageFilter;
  bool _unassignedOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.one('/leads/report', query: {
        'group_by': _groupBy,
        'date_field': _dateField,
        if (_stageFilter != null) 'filters[stage]': _stageFilter,
        if (_unassignedOnly) 'filters[unassigned]': '1',
      });
      setState(() {
        _report = res;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Lead Report'), actions: [
        IconButton(icon: const Icon(Icons.bookmark_outline_rounded), onPressed: () => _showSavedReports(context), tooltip: 'Saved reports'),
        IconButton(icon: const Icon(Icons.save_outlined), onPressed: () => _saveReport(context), tooltip: 'Save this report'),
      ]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _groupBy,
                  decoration: const InputDecoration(labelText: 'Group by', isDense: true),
                  items: _reportGroupBy.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: (v) { setState(() => _groupBy = v ?? 'stage'); _load(); },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _dateField,
                  decoration: const InputDecoration(labelText: 'Date field', isDense: true),
                  items: _reportDateField.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: (v) { setState(() => _dateField = v ?? 'created_at'); _load(); },
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(spacing: 6, children: [
              ChoiceChip(label: const Text('All stages'), selected: _stageFilter == null,
                  onSelected: (_) { setState(() => _stageFilter = null); _load(); }),
              for (final s in stageTint.keys)
                ChoiceChip(label: Text(stageLabel(s)), selected: _stageFilter == s,
                    onSelected: (_) { setState(() => _stageFilter = s); _load(); }),
              FilterChip(label: const Text('Unassigned only'), selected: _unassignedOnly,
                  onSelected: (v) { setState(() => _unassignedOnly = v); _load(); }),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : r == null
                    ? Center(child: Text('Could not load report', style: TextStyle(color: context.mutedColor)))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text('Total: ${r['total'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          const SizedBox(height: 16),
                          if (r['breakdown'] is List)
                            ...(r['breakdown'] as List).whereType<Map>().map(
                                  (b) => KvRow(str(b['label']), '${b['total']}'),
                                ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveReport(BuildContext context) async {
    final data = <String, dynamic>{
      'group_by': _groupBy,
      'date_field': _dateField,
      'filters': {
        if (_stageFilter != null) 'stage': _stageFilter,
        if (_unassignedOnly) 'unassigned': true,
      },
    };
    final ok = await showFormSheet(
      context,
      title: 'Save report',
      submitLabel: 'Save',
      fields: (ctx) => [
        FText(label: 'Name', required: true, onSaved: (v) => data['name'] = v),
        FBoolField(label: 'Share with team', onSaved: (v) => data['is_shared'] = v),
      ],
      onSubmit: () => Api.post('/leads/saved-reports', data: data),
    );
    if (ok) ref.invalidate(leadSavedReportsProvider);
  }

  Future<void> _showSavedReports(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scrollController) => Consumer(
          builder: (ctx, ref, _) {
            final async = ref.watch(leadSavedReportsProvider);
            return async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (rows) => rows.isEmpty
                  ? const Center(child: Text('No saved reports'))
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final rep = rows[i];
                        return RecordCard(
                          title: str(rep['name']),
                          subtitle: 'Group by ${rep['group_by']} · ${rep['date_field']}',
                          leadingIcon: Icons.bookmark_rounded,
                          onTap: () {
                            Navigator.pop(context);
                            final filters = (rep['filters'] is Map) ? rep['filters'] as Map : const {};
                            setState(() {
                              _groupBy = str(rep['group_by'], 'stage');
                              _dateField = str(rep['date_field'], 'created_at');
                              _stageFilter = filters['stage'] as String?;
                              _unassignedOnly = filters['unassigned'] == true;
                            });
                            _load();
                          },
                          trailing: RowMenu(items: [
                            ('Delete', Icons.delete_outline_rounded, () async {
                              final done = await runAction(context, () => Api.delete('/leads/saved-reports/${rep['id']}'), success: 'Deleted');
                              if (done) ref.invalidate(leadSavedReportsProvider);
                            }),
                          ]),
                        );
                      },
                    ),
            );
          },
        ),
      ),
    );
  }
}

// ══════════════════════════ Assignment Queue ══════════════════════════

const _assignmentStatuses = [
  'pending', 'notified', 'accepted', 'assigned',
  'ai_handling', 'ai_offered', 'transferred', 'completed', 'dropped',
];

class AssignmentQueuePage extends StatefulWidget {
  const AssignmentQueuePage({super.key});
  @override
  State<AssignmentQueuePage> createState() => _AssignmentQueuePageState();
}

class _AssignmentQueuePageState extends State<AssignmentQueuePage> {
  List<Rec> _rows = [];
  Rec? _stats;
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
      final results = await Future.wait([
        Api.list('/lead-assignments', query: _status != null ? {'status': _status} : null),
        Api.one('/lead-assignments/stats'),
      ]);
      setState(() {
        _rows = results[0] as List<Rec>;
        _stats = results[1] as Rec;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      appBar: AppBar(title: const Text('Assignment Queue')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (s != null)
                    StatGrid([
                      ('Today', '${s['total_today'] ?? 0}', Icons.today_rounded),
                      ('Auto-assigned', '${s['auto_assigned'] ?? 0}', Icons.bolt_rounded),
                      ('AI handling', '${s['ai_handling'] ?? 0}', Icons.smart_toy_rounded),
                      ('SLA breached', '${s['sla_breached'] ?? 0}', Icons.warning_amber_rounded),
                      ('Avg response', str(s['avg_response_time']), Icons.timer_rounded),
                      ('Conversion', str(s['conversion_rate']), Icons.trending_up_rounded),
                    ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(label: const Text('All'), selected: _status == null,
                              onSelected: (_) { setState(() => _status = null); _load(); }),
                        ),
                        for (final st in _assignmentStatuses)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(label: Text(st), selected: _status == st,
                                onSelected: (_) { setState(() => _status = st); _load(); }),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(child: Text('No assignments', style: TextStyle(color: context.mutedColor))),
                    )
                  else
                    ..._rows.map((row) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _AssignmentCard(row: row, onChanged: _load),
                        )),
                ],
              ),
            ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({required this.row, required this.onChanged});
  final Rec row;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final contact = (row['contact'] is Map) ? (row['contact'] as Map) : const {};
    final staff = (row['staff'] is Map) ? (row['staff'] as Map) : const {};
    final status = str(row['status'], 'pending');
    final active = !['completed', 'dropped'].contains(status);
    return RecordCard(
      title: str(contact['name'], 'Unknown'),
      subtitle: '${contact['phone'] ?? ''} · ${str(row['source_type'])}'
          '${staff['name'] != null ? ' · ${staff['name']}' : ''}',
      leadingIcon: Icons.assignment_ind_rounded,
      trailing: active
          ? RowMenu(items: [
              ('Accept', Icons.check_rounded, () async {
                final ok = await runAction(context, () => Api.post('/lead-assignments/${row['id']}/accept'), success: 'Accepted');
                if (ok) onChanged();
              }),
              ('Decline', Icons.close_rounded, () async {
                final ok = await runAction(context, () => Api.post('/lead-assignments/${row['id']}/decline'), success: 'Declined');
                if (ok) onChanged();
              }),
              ('Complete', Icons.check_circle_outline_rounded, () async {
                final ok = await runAction(context, () => Api.post('/lead-assignments/${row['id']}/complete'), success: 'Completed');
                if (ok) onChanged();
              }),
              ('Transfer', Icons.swap_horiz_rounded, () => _transfer(context)),
            ])
          : StatusPill(status),
    );
  }

  Future<void> _transfer(BuildContext context) async {
    List<Rec> staff;
    try {
      staff = await Api.list('/staff/availability');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Transfer lead',
      submitLabel: 'Transfer',
      fields: (ctx) => [
        FSelect<Rec>(label: 'Transfer to', options: staff, labelOf: (s) => str(s['name']),
            onSaved: (s) => data['to_staff_id'] = s?['id']),
        FText(label: 'Reason', onSaved: (v) => v.isEmpty ? null : data['reason'] = v),
      ],
      onSubmit: () => Api.post('/lead-assignments/${row['id']}/transfer', data: data),
    );
    if (ok) onChanged();
  }
}

// ══════════════════════════ Assignment Rules ══════════════════════════

const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

String _hhmm(String s) => s.length >= 5 ? s.substring(0, 5) : s;

class AssignmentRulesPage extends StatefulWidget {
  const AssignmentRulesPage({super.key});
  @override
  State<AssignmentRulesPage> createState() => _AssignmentRulesPageState();
}

class _AssignmentRulesPageState extends State<AssignmentRulesPage> {
  bool _loading = true;
  bool _saving = false;
  List<Rec> _hours = [];
  List<Rec> _holidays = [];

  final _sla = TextEditingController();
  final _aiTakeover = TextEditingController();
  final _gap = TextEditingController();
  final _timeout = TextEditingController();
  final _rounds = TextEditingController();
  final _dupWindow = TextEditingController();
  final _wStart = TextEditingController();
  final _wEnd = TextEditingController();
  final _timezone = TextEditingController();
  final _wAvail = TextEditingController();
  final _wMaxLeads = TextEditingController();
  final _wPerf = TextEditingController();
  final _wWorkload = TextEditingController();

  String _strategy = 'round_robin';
  String _notificationMode = 'auto';
  String _duplicateAction = 'assign_same_staff';
  bool _autoAssign = true;
  Set<int> _workingDays = {1, 2, 3, 4, 5};

  @override
  void dispose() {
    for (final c in [_sla, _aiTakeover, _gap, _timeout, _rounds, _dupWindow, _wStart, _wEnd, _timezone, _wAvail, _wMaxLeads, _wPerf, _wWorkload]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        Api.one('/lead-assignment-rules'),
        Api.one('/working-hours'),
      ]);
      final rule = results[0];
      final wh = results[1];
      setState(() {
        _strategy = str(rule['strategy'], 'round_robin');
        _notificationMode = str(rule['notification_mode'], 'auto');
        _duplicateAction = str(rule['duplicate_action'], 'assign_same_staff');
        _autoAssign = rule['auto_assign_enabled'] != false;
        _sla.text = str(rule['sla_minutes'], '');
        _aiTakeover.text = str(rule['ai_takeover_after_minutes'], '');
        _gap.text = str(rule['notification_gap_seconds'], '');
        _timeout.text = str(rule['notification_timeout_seconds'], '');
        _rounds.text = str(rule['max_notification_rounds'], '');
        _dupWindow.text = str(rule['duplicate_window_days'], '');
        _wStart.text = _hhmm(str(rule['working_hours_start'], '09:00'));
        _wEnd.text = _hhmm(str(rule['working_hours_end'], '18:00'));
        _timezone.text = str(rule['timezone'], '');
        _wAvail.text = str(rule['weight_availability'], '');
        _wMaxLeads.text = str(rule['weight_max_leads'], '');
        _wPerf.text = str(rule['weight_performance'], '');
        _wWorkload.text = str(rule['weight_workload'], '');
        final days = rule['working_days'];
        if (days is List) _workingDays = days.map((d) => int.tryParse('$d') ?? -1).where((d) => d >= 0).toSet();
        final hoursList = wh['hours'];
        _hours = hoursList is List ? hoursList.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
        final holidaysList = wh['holidays'];
        _holidays = holidaysList is List ? holidaysList.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveRule() async {
    setState(() => _saving = true);
    final ok = await runAction(context, () => Api.post('/lead-assignment-rules', data: {
      'auto_assign_enabled': _autoAssign,
      'strategy': _strategy,
      'weight_availability': num.tryParse(_wAvail.text) ?? 0,
      'weight_max_leads': num.tryParse(_wMaxLeads.text) ?? 0,
      'weight_performance': num.tryParse(_wPerf.text) ?? 0,
      'weight_workload': num.tryParse(_wWorkload.text) ?? 0,
      'sla_minutes': num.tryParse(_sla.text),
      'ai_takeover_after_minutes': num.tryParse(_aiTakeover.text),
      'notification_mode': _notificationMode,
      'notification_gap_seconds': num.tryParse(_gap.text),
      'notification_timeout_seconds': num.tryParse(_timeout.text),
      'max_notification_rounds': num.tryParse(_rounds.text),
      'duplicate_window_days': num.tryParse(_dupWindow.text),
      'duplicate_action': _duplicateAction,
      'working_hours_start': _wStart.text,
      'working_hours_end': _wEnd.text,
      'working_days': _workingDays.toList()..sort(),
      'timezone': _timezone.text,
    }), success: 'Assignment rules saved');
    setState(() => _saving = false);
    if (ok) _load();
  }

  Future<void> _saveHours() async {
    final ok = await runAction(context, () => Api.raw.put('/working-hours', data: {
      'hours': _hours.map((h) => {
            'weekday': h['weekday'],
            'is_open': h['is_open'],
            'start_time': (h['start_time'] as String?)?.substring(0, 5) ?? '09:00',
            'end_time': (h['end_time'] as String?)?.substring(0, 5) ?? '18:00',
          }).toList(),
    }), success: 'Working hours saved');
    if (ok) _load();
  }

  Future<void> _addHoliday() async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Add holiday',
      fields: (ctx) => [
        FText(label: 'Date (YYYY-MM-DD)', required: true, onSaved: (v) => data['date'] = v),
        FText(label: 'Name', required: true, onSaved: (v) => data['name'] = v),
      ],
      onSubmit: () => Api.post('/working-hours/holidays', data: data),
    );
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Assignment Rules')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Routing strategy', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-assign enabled'),
            value: _autoAssign,
            onChanged: (v) => setState(() => _autoAssign = v),
          ),
          Row(children: [
            Expanded(
              child: RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Round robin'),
                value: 'round_robin',
                groupValue: _strategy,
                onChanged: (v) => setState(() => _strategy = v ?? 'round_robin'),
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Algorithm'),
                value: 'algorithm',
                groupValue: _strategy,
                onChanged: (v) => setState(() => _strategy = v ?? 'round_robin'),
              ),
            ),
          ]),
          if (_strategy == 'algorithm') ...[
            const SizedBox(height: 8),
            Text('Weights (should sum to 100)', style: TextStyle(color: context.mutedColor, fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _wAvail, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Availability', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _wMaxLeads, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max leads', isDense: true))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _wPerf, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Performance', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _wWorkload, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Workload', isDense: true))),
            ]),
          ],
          const SizedBox(height: 20),
          const Text('SLA & AI takeover', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _sla, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'SLA (minutes)', isDense: true))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _aiTakeover, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'AI takeover (min)', isDense: true))),
          ]),
          const SizedBox(height: 20),
          const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _notificationMode,
            decoration: const InputDecoration(labelText: 'Mode', isDense: true),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('Auto')),
              DropdownMenuItem(value: 'uber', child: Text('Uber-style (one at a time)')),
              DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
            ],
            onChanged: (v) => setState(() => _notificationMode = v ?? 'auto'),
          ),
          if (_notificationMode != 'auto') ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _gap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Gap (sec)', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _timeout, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Timeout (sec)', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _rounds, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max rounds', isDense: true))),
            ]),
          ],
          const SizedBox(height: 20),
          const Text('Duplicate handling', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _duplicateAction,
                decoration: const InputDecoration(labelText: 'Action', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'assign_same_staff', child: Text('Same staff')),
                  DropdownMenuItem(value: 'create_new', child: Text('Create new')),
                  DropdownMenuItem(value: 'merge', child: Text('Merge')),
                  DropdownMenuItem(value: 'notify_admin', child: Text('Notify admin')),
                ],
                onChanged: (v) => setState(() => _duplicateAction = v ?? 'assign_same_staff'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _dupWindow, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Window (days)', isDense: true))),
          ]),
          const SizedBox(height: 20),
          const Text('Working days & timezone', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (var d = 0; d < 7; d++)
              FilterChip(
                label: Text(_dayLabels[d]),
                selected: _workingDays.contains(d),
                onSelected: (v) => setState(() => v ? _workingDays.add(d) : _workingDays.remove(d)),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _wStart, decoration: const InputDecoration(labelText: 'Start (HH:mm)', isDense: true))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _wEnd, decoration: const InputDecoration(labelText: 'End (HH:mm)', isDense: true))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _timezone, decoration: const InputDecoration(labelText: 'Timezone', isDense: true)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _saveRule,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save assignment rules'),
          ),
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Office weekly hours', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            TextButton(onPressed: _saveHours, child: const Text('Save hours')),
          ]),
          const SizedBox(height: 8),
          for (final h in _hours) _HourRow(row: h, onChanged: (updated) {
            setState(() {
              final i = _hours.indexWhere((x) => x['weekday'] == h['weekday']);
              if (i != -1) _hours[i] = updated;
            });
          }),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Holidays', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            TextButton.icon(onPressed: _addHoliday, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add')),
          ]),
          const SizedBox(height: 8),
          if (_holidays.isEmpty)
            Text('No holidays configured', style: TextStyle(color: context.mutedColor, fontSize: 13))
          else
            ..._holidays.map((h) => KvRow(str(h['name']), str(h['date']))),
        ],
      ),
    );
  }
}

class _HourRow extends StatefulWidget {
  const _HourRow({required this.row, required this.onChanged});
  final Rec row;
  final void Function(Rec) onChanged;

  @override
  State<_HourRow> createState() => _HourRowState();
}

class _HourRowState extends State<_HourRow> {
  late final _start = TextEditingController(text: (widget.row['start_time'] as String?)?.substring(0, 5) ?? '09:00');
  late final _end = TextEditingController(text: (widget.row['end_time'] as String?)?.substring(0, 5) ?? '18:00');

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged({
      ...widget.row,
      'start_time': _start.text,
      'end_time': _end.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final weekday = widget.row['weekday'] as int? ?? 0;
    final isOpen = widget.row['is_open'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 44, child: Text(_dayLabels[weekday], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        Switch(
          value: isOpen,
          onChanged: (v) => widget.onChanged({...widget.row, 'is_open': v}),
        ),
        if (isOpen) ...[
          Expanded(
            child: TextField(controller: _start, decoration: const InputDecoration(isDense: true), onChanged: (_) => _emit()),
          ),
          const SizedBox(width: 6),
          const Text('–'),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(controller: _end, decoration: const InputDecoration(isDense: true), onChanged: (_) => _emit()),
          ),
        ] else
          Expanded(child: Text('Closed', style: TextStyle(color: context.mutedColor))),
      ]),
    );
  }
}
