// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";
import "package:unichat_mobile_app/features/leads/lead_stage.dart";

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

