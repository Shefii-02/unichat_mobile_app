// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";
import "package:unichat_mobile_app/features/leads/lead_stage.dart";

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

