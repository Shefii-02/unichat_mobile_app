// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'module_providers.dart';
import '_shared.dart';

// ══════════════════════════ Labels ══════════════════════════

class LabelsPage extends ConsumerWidget {
  const LabelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Labels')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add label'),
      ),
      body: ProviderList(
        provider: crmLabelsProvider,
        emptyLabel: 'No labels yet',
        emptyIcon: Icons.label_outline_rounded,
        tile: (context, l) {
          final color = parseColor(l['color'] as String?);
          return RecordCard(
            title: str(l['name']),
            subtitle: '${l['contacts_count'] ?? 0} contacts',
            leadingIcon: Icons.label_rounded,
            leadingColor: color,
            trailing: RowMenu(items: [
              ('Edit', Icons.edit_rounded, () => _edit(context, ref, l)),
              ('Delete', Icons.delete_outline_rounded, () async {
                final ok = await confirm(context, title: 'Delete "${l['name']}"?', destructive: true, confirmLabel: 'Delete');
                if (!ok) return;
                final done = await runAction(context, () => Api.delete('/labels/${l['id']}'), success: 'Deleted');
                if (done) ref.invalidate(crmLabelsProvider);
              }),
            ]),
          );
        },
      ),
    );
  }

  static Color? parseColor(String? hex) {
    if (hex == null || !hex.startsWith('#') || hex.length != 7) return null;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec? existing) async {
    final data = <String, dynamic>{'color': existing?['color'] ?? '#0F766E'};
    final ok = await showFormSheet(
      context,
      title: existing == null ? 'Add label' : 'Edit label',
      fields: (ctx) => [
        FText(label: 'Name', initial: existing?['name'] as String?, required: true, onSaved: (v) => data['name'] = v),
        FText(label: 'Color (hex, e.g. #0F766E)', initial: data['color'] as String, required: true,
            onSaved: (v) => data['color'] = v),
      ],
      onSubmit: () => existing == null
          ? Api.post('/labels', data: data)
          : Api.put('/labels/${existing['id']}', data: data),
    );
    if (ok) ref.invalidate(crmLabelsProvider);
  }
}

// ══════════════════════════ Deal pipelines (Kanban-lite) ══════════════════════════

const _dealStages = ['new', 'qualified', 'proposal', 'negotiation', 'won', 'lost'];
const _dealStageLabels = {
  'new': 'New', 'qualified': 'Qualified', 'proposal': 'Proposal',
  'negotiation': 'Negotiation', 'won': 'Won', 'lost': 'Lost',
};

class DealsPage extends ConsumerWidget {
  const DealsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(crmDealsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Deal Pipelines')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDeal(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New deal'),
      ),
      body: AsyncView<List<Rec>>(
        value: async,
        onRefresh: () async => ref.invalidate(crmDealsProvider),
        isEmpty: (d) => d.isEmpty,
        emptyLabel: 'No deals yet',
        emptyIcon: Icons.handshake_outlined,
        data: (deals) {
          final byStage = {for (final s in _dealStages) s: deals.where((d) => d['stage'] == s).toList()};
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            children: _dealStages.map((stage) {
              final rows = byStage[stage] ?? const [];
              final total = rows.fold<num>(0, (sum, d) => sum + (num.tryParse('${d['value']}') ?? 0));
              return Container(
                width: 240,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        children: [
                          Text(_dealStageLabels[stage] ?? stage, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          Text('(${rows.length})', style: TextStyle(color: context.mutedColor, fontSize: 12)),
                          const Spacer(),
                          Text(money(total), style: TextStyle(color: context.mutedColor, fontSize: 11)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final deal = rows[i];
                          final contact = (deal['contact'] is Map) ? (deal['contact'] as Map) : const {};
                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openDeal(context, ref, deal),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(str(deal['title']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    if (contact['name'] != null)
                                      Text(str(contact['name']), style: TextStyle(fontSize: 11.5, color: context.mutedColor)),
                                    const SizedBox(height: 6),
                                    Text(money(deal['value']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Future<void> _openDeal(BuildContext context, WidgetRef ref, Rec deal) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(str(deal['title']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(money(deal['value']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(height: 16),
            const Text('Move to stage', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: _dealStages.map((s) {
                final selected = deal['stage'] == s;
                return ChoiceChip(
                  label: Text(_dealStageLabels[s] ?? s),
                  selected: selected,
                  onSelected: (_) async {
                    Navigator.pop(ctx);
                    final ok = await runAction(context, () => Api.patch('/crm/deals/${deal['id']}/stage', data: {'stage': s}),
                        success: 'Moved to ${_dealStageLabels[s]}');
                    if (ok) ref.invalidate(crmDealsProvider);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final sure = await confirm(context, title: 'Delete this deal?', destructive: true, confirmLabel: 'Delete');
                if (!sure) return;
                final ok = await runAction(context, () => Api.delete('/crm/deals/${deal['id']}'), success: 'Deleted');
                if (ok) ref.invalidate(crmDealsProvider);
              },
              icon: const Icon(Icons.delete_outline_rounded, color: AppPalette.danger),
              label: const Text('Delete deal', style: TextStyle(color: AppPalette.danger)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addDeal(BuildContext context, WidgetRef ref) async {
    List<Rec> contacts;
    try {
      contacts = await Api.list('/contacts', query: {'per_page': 100});
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    final data = <String, dynamic>{'stage': 'new'};
    final ok = await showFormSheet(
      context,
      title: 'New deal',
      fields: (ctx) => [
        FText(label: 'Title', required: true, onSaved: (v) => data['title'] = v),
        FNumber(label: 'Value', required: true, onSaved: (v) => data['value'] = v),
        if (contacts.isNotEmpty)
          FSelect<Rec>(label: 'Contact (optional)', options: contacts,
              labelOf: (c) => '${c['name'] ?? c['phone']}', onSaved: (c) => data['contact_id'] = c?['id']),
      ],
      onSubmit: () => Api.post('/crm/deals', data: data),
    );
    if (ok) ref.invalidate(crmDealsProvider);
  }
}

// ══════════════════════════ Tasks & followups (all staff) ══════════════════════════

class CrmTasksAdminPage extends ConsumerStatefulWidget {
  const CrmTasksAdminPage({super.key});
  @override
  ConsumerState<CrmTasksAdminPage> createState() => _CrmTasksAdminPageState();
}

class _CrmTasksAdminPageState extends ConsumerState<CrmTasksAdminPage> {
  String _filter = 'open';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(crmAllTasksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks & Followups')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addTask(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New task'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: ['open', 'done', 'all'].map((f) {
                final selected = _filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(f[0].toUpperCase() + f.substring(1)),
                    selected: selected,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: AsyncView<List<Rec>>(
              value: async,
              onRefresh: () async => ref.invalidate(crmAllTasksProvider),
              isEmpty: (d) => d.where(_matchesFilter).isEmpty,
              emptyLabel: 'No tasks',
              emptyIcon: Icons.checklist_rounded,
              data: (rows) {
                final filtered = rows.where(_matchesFilter).toList();
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final t = filtered[i];
                    final done = str(t['status'], 'open') == 'done';
                    final assignee = (t['assignee'] is Map) ? (t['assignee'] as Map) : const {};
                    final contact = (t['contact'] is Map) ? (t['contact'] as Map) : const {};
                    return RecordCard(
                      title: str(t['title']),
                      subtitle: [
                        str(t['type'], 'todo'),
                        if (assignee['name'] != null) assignee['name'],
                        if (contact['name'] != null) contact['name'],
                        if (t['due_at'] != null) 'Due ${when(t['due_at'])}',
                      ].join(' · '),
                      leadingIcon: done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      leadingColor: done ? AppPalette.success : null,
                      trailing: RowMenu(items: [
                        (done ? 'Reopen' : 'Mark done', Icons.check_rounded, () async {
                          final ok = await runAction(context, () => Api.post('/crm/tasks/${t['id']}/toggle'));
                          if (ok) ref.invalidate(crmAllTasksProvider);
                        }),
                        ('Delete', Icons.delete_outline_rounded, () async {
                          final sure = await confirm(context, title: 'Delete this task?', destructive: true, confirmLabel: 'Delete');
                          if (!sure) return;
                          final ok = await runAction(context, () => Api.delete('/crm/tasks/${t['id']}'), success: 'Deleted');
                          if (ok) ref.invalidate(crmAllTasksProvider);
                        }),
                      ]),
                      onTap: () async {
                        final ok = await runAction(context, () => Api.post('/crm/tasks/${t['id']}/toggle'));
                        if (ok) ref.invalidate(crmAllTasksProvider);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesFilter(Rec t) {
    if (_filter == 'all') return true;
    return str(t['status'], 'open') == _filter;
  }

  Future<void> _addTask(BuildContext context, WidgetRef ref) async {
    List<Rec> staff;
    List<Rec> contacts;
    try {
      staff = await Api.list('/staff');
      contacts = await Api.list('/contacts', query: {'per_page': 100});
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    final data = <String, dynamic>{'type': 'todo', 'priority': 'medium'};
    final ok = await showFormSheet(
      context,
      title: 'New task',
      fields: (ctx) => [
        FText(label: 'Title', required: true, onSaved: (v) => data['title'] = v),
        FSelect<String>(label: 'Type', options: const ['todo', 'call', 'email', 'whatsapp', 'meeting'],
            initial: 'todo', onSaved: (v) => data['type'] = v ?? 'todo'),
        FSelect<String>(label: 'Priority', options: const ['low', 'medium', 'high'],
            initial: 'medium', onSaved: (v) => data['priority'] = v ?? 'medium'),
        FSelect<Rec>(label: 'Assign to', options: staff, labelOf: (s) => str(s['name']), onSaved: (s) => data['assigned_to'] = s?['id']),
        if (contacts.isNotEmpty)
          FSelect<Rec>(label: 'Contact (optional)', options: contacts,
              labelOf: (c) => '${c['name'] ?? c['phone']}', onSaved: (c) => data['contact_id'] = c?['id']),
        FText(label: 'Due (YYYY-MM-DD HH:mm)', hint: '2026-09-20 14:00', onSaved: (v) => v.isEmpty ? null : data['due_at'] = v),
      ],
      onSubmit: () => Api.post('/crm/tasks', data: data),
    );
    if (ok) ref.invalidate(crmAllTasksProvider);
  }
}

// ══════════════════════════ Calendar ══════════════════════════

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  List<Rec> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.one('/crm/calendar-events');
      final events = res['events'];
      setState(() {
        _events = events is List ? events.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _events.sort((a, b) => str(a['starts_at']).compareTo(str(b['starts_at'])));
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _book(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Book'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _events.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Icon(Icons.event_available_outlined, size: 56, color: context.mutedColor),
                      const SizedBox(height: 12),
                      Center(child: Text('No upcoming events', style: TextStyle(color: context.mutedColor))),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _events.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _EventCard(event: _events[i], onChanged: _load),
                    ),
            ),
    );
  }

  Future<void> _book(BuildContext context) async {
    List<Rec> contacts;
    List<Rec> staff;
    try {
      contacts = await Api.list('/contacts', query: {'per_page': 100});
      staff = await Api.list('/staff');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    final data = <String, dynamic>{'type': 'appointment'};
    final ok = await showFormSheet(
      context,
      title: 'Book event',
      fields: (ctx) => [
        FText(label: 'Title', required: true, onSaved: (v) => data['title'] = v),
        FSelect<String>(label: 'Type', options: const ['appointment', 'followup', 'callback', 'meeting'],
            initial: 'appointment', onSaved: (v) => data['type'] = v ?? 'appointment'),
        FText(label: 'Starts (YYYY-MM-DD HH:mm)', required: true, hint: '2026-09-20 14:00', onSaved: (v) => data['starts_at'] = v),
        FText(label: 'Ends (YYYY-MM-DD HH:mm)', required: true, hint: '2026-09-20 15:00', onSaved: (v) => data['ends_at'] = v),
        FText(label: 'Location', onSaved: (v) => v.isEmpty ? null : data['location'] = v),
        if (contacts.isNotEmpty)
          FSelect<Rec>(label: 'Contact (optional)', options: contacts,
              labelOf: (c) => '${c['name'] ?? c['phone']}', onSaved: (c) => data['contact_id'] = c?['id']),
        FSelect<Rec>(label: 'Assign to (optional)', options: staff, labelOf: (s) => str(s['name']),
            onSaved: (s) => data['assigned_to'] = s?['id']),
      ],
      onSubmit: () => Api.post('/crm/calendar-events', data: data),
    );
    if (ok) _load();
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onChanged});
  final Rec event;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final status = str(event['status'], 'scheduled');
    final contact = (event['contact'] is Map) ? (event['contact'] as Map) : const {};
    return RecordCard(
      title: str(event['title']),
      subtitle: '${str(event['type'], 'appointment')} · ${when(event['starts_at'])}'
          '${contact['name'] != null ? ' · ${contact['name']}' : ''}',
      leadingIcon: Icons.event_rounded,
      trailing: status == 'scheduled'
          ? RowMenu(items: [
              ('Complete', Icons.check_circle_outline_rounded, () async {
                final ok = await runAction(context, () => Api.post('/crm/calendar-events/${event['id']}/complete'), success: 'Marked completed');
                if (ok) onChanged();
              }),
              ('No-show', Icons.person_off_outlined, () async {
                final ok = await runAction(context, () => Api.post('/crm/calendar-events/${event['id']}/no-show'), success: 'Marked no-show');
                if (ok) onChanged();
              }),
              ('Cancel', Icons.close_rounded, () async {
                final sure = await confirm(context, title: 'Cancel this event?', destructive: true, confirmLabel: 'Cancel event');
                if (!sure) return;
                final ok = await runAction(context, () => Api.delete('/crm/calendar-events/${event['id']}'), success: 'Cancelled');
                if (ok) onChanged();
              }),
            ])
          : StatusPill(status),
    );
  }
}

// ══════════════════════════ Segments ══════════════════════════

class SegmentsPage extends ConsumerWidget {
  const SegmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Segments')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSegment(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New segment'),
      ),
      body: ProviderList(
        provider: crmSegmentsProvider,
        emptyLabel: 'No segments yet',
        emptyIcon: Icons.filter_alt_outlined,
        tile: (context, s) => RecordCard(
          title: str(s['name']),
          subtitle: '${s['contact_count'] ?? 0} contacts${s['description'] != null ? ' · ${s['description']}' : ''}',
          leadingIcon: Icons.filter_alt_rounded,
          trailing: RowMenu(items: [
            ('Delete', Icons.delete_outline_rounded, () async {
              final ok = await confirm(context, title: 'Delete "${s['name']}"?', destructive: true, confirmLabel: 'Delete');
              if (!ok) return;
              final done = await runAction(context, () => Api.delete('/crm/segments/${s['id']}'), success: 'Deleted');
              if (done) ref.invalidate(crmSegmentsProvider);
            }),
          ]),
        ),
      ),
    );
  }

  Future<void> _addSegment(BuildContext context, WidgetRef ref) async {
    final filters = <String, dynamic>{};
    final data = <String, dynamic>{};

    final ok = await showFormSheet(
      context,
      title: 'New segment',
      fields: (ctx) => [
        FText(label: 'Name', required: true, onSaved: (v) => data['name'] = v),
        FText(label: 'Description', onSaved: (v) => v.isEmpty ? null : data['description'] = v),
        FSelect<String>(label: 'Lead stage (optional)',
            options: const ['new', 'contacted', 'follow_up', 'enrolled', 'lost'],
            onSaved: (v) => v == null ? null : filters['lead_stage'] = v),
        FNumber(label: 'Min lead score', onSaved: (v) => v == null ? null : filters['score_min'] = v),
        FSelect<String>(label: 'Opted in?', options: const ['yes', 'no'],
            onSaved: (v) => v == null ? null : filters['opted_in'] = v == 'yes'),
        FNumber(label: 'Inactive for (days, optional)', onSaved: (v) => v == null ? null : filters['last_message_days'] = v),
      ],
      onSubmit: () {
        data['filters'] = filters;
        return Api.post('/crm/segments', data: data);
      },
    );
    if (ok) ref.invalidate(crmSegmentsProvider);
  }
}

// ══════════════════════════ Blacklist ══════════════════════════

class BlacklistPage extends ConsumerWidget {
  const BlacklistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blacklist')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addNumber(context, ref),
        icon: const Icon(Icons.block_rounded),
        label: const Text('Block number'),
      ),
      body: ProviderList(
        provider: blacklistProvider,
        emptyLabel: 'No blocked numbers',
        emptyIcon: Icons.block_flipped,
        tile: (context, b) => RecordCard(
          title: str(b['phone']),
          subtitle: str(b['reason'], ''),
          leadingIcon: Icons.phone_disabled_rounded,
          leadingColor: AppPalette.danger,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            onPressed: () async {
              final ok = await confirm(context, title: 'Unblock ${b['phone']}?', confirmLabel: 'Unblock');
              if (!ok) return;
              final done = await runAction(context, () => Api.delete('/blacklist/${b['id']}'), success: 'Removed');
              if (done) ref.invalidate(blacklistProvider);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _addNumber(BuildContext context, WidgetRef ref) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Block a number',
      submitLabel: 'Block',
      fields: (ctx) => [
        FText(label: 'Phone number', required: true, keyboardType: TextInputType.phone, onSaved: (v) => data['phone'] = v),
        FText(label: 'Reason', onSaved: (v) => v.isEmpty ? null : data['reason'] = v),
      ],
      onSubmit: () => Api.post('/blacklist', data: data),
    );
    if (ok) ref.invalidate(blacklistProvider);
  }
}
