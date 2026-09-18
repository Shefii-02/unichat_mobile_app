// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";
import "package:unichat_mobile_app/features/leads/lead_stage.dart";

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

