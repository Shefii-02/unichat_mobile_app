// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════ Tasks (to-do list + scheduled) and Follow-ups — one page, two menu entries ══════════════
// Mirrors the web CRM pages: /crm/tasks (To-do list · Scheduled tabs) and /crm/followups.

class CrmTasksAdminPage extends ConsumerStatefulWidget {
  const CrmTasksAdminPage({super.key, this.followups = false});

  /// true → the Follow-ups page (no tabs); false → Tasks (To-do list / Scheduled tabs).
  final bool followups;
  @override
  ConsumerState<CrmTasksAdminPage> createState() => _CrmTasksAdminPageState();
}

class _CrmTasksAdminPageState extends ConsumerState<CrmTasksAdminPage> with SingleTickerProviderStateMixin {
  static const _scheduledTypes = ['call', 'email', 'whatsapp', 'meeting'];
  static const _icons = {
    'todo': Icons.check_box_outlined,
    'call': Icons.call_rounded,
    'email': Icons.mail_outline_rounded,
    'whatsapp': Icons.chat_bubble_outline_rounded,
    'meeting': Icons.event_rounded,
    'followup': Icons.repeat_rounded,
  };

  late final TabController _tabs = TabController(length: widget.followups ? 1 : 2, vsync: this)
    ..addListener(() { if (!_tabs.indexIsChanging) setState(() {}); });
  String _scope = 'all'; // all | mine | by_me
  bool _showDone = false;

  String get _tab => widget.followups ? 'followup' : (_tabs.index == 0 ? 'todo' : 'scheduled');
  String get _key => '$_tab|$_scope';

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  void _refresh() => ref.invalidate(crmTabTasksProvider(_key));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(crmTabTasksProvider(_key));
    final label = widget.followups ? 'Follow-up' : (_tab == 'scheduled' ? 'Scheduled task' : 'To-do');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.followups ? 'Follow-ups' : 'Tasks'),
        bottom: widget.followups
            ? null
            : TabBar(controller: _tabs, tabs: const [Tab(text: 'To-do list'), Tab(text: 'Scheduled')]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _form(context),
        icon: const Icon(Icons.add_rounded),
        label: Text('New $label'),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              for (final s in const [('all', 'All'), ('mine', 'Assigned to me'), ('by_me', 'Assigned by me')])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text(s.$2), selected: _scope == s.$1, onSelected: (_) => setState(() => _scope = s.$1)),
                ),
              FilterChip(label: const Text('Show completed'), selected: _showDone, onSelected: (v) => setState(() => _showDone = v)),
            ]),
          ),
          Expanded(
            child: AsyncView<List<Rec>>(
              value: async,
              onRefresh: () async => _refresh(),
              isEmpty: (d) => d.where(_visible).isEmpty,
              emptyLabel: 'Nothing here yet',
              emptyIcon: Icons.checklist_rounded,
              data: (rows) {
                final list = rows.where(_visible).toList();
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _row(context, list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _visible(Rec t) => _showDone || str(t['status'], 'open') != 'done';

  Widget _row(BuildContext context, Rec t) {
    final done = str(t['status'], 'open') == 'done';
    final assignee = t['assignee'] is Map ? t['assignee'] as Map : const {};
    final creator = t['creator'] is Map ? t['creator'] as Map : const {};
    final contact = t['contact'] is Map ? t['contact'] as Map : const {};
    final lead = t['lead'] is Map ? t['lead'] as Map : null;
    final leadContact = lead != null && lead['contact'] is Map ? lead['contact'] as Map : const {};
    final due = DateTime.tryParse('${t['due_at'] ?? ''}')?.toLocal();
    final overdue = !done && due != null && due.isBefore(DateTime.now());
    final type = str(t['type'], 'todo');

    Future<void> toggle() async {
      final ok = await runAction(context, () => Api.post('/crm/tasks/${t['id']}/toggle'));
      if (ok) _refresh();
    }

    return RecordCard(
      title: str(t['title']),
      subtitle: [
        if (due != null) 'Due ${_fmt(due)}${overdue ? ' (overdue)' : ''}',
        if (lead != null) 'Lead: ${leadContact['name'] ?? leadContact['phone'] ?? '#${t['lead_id']}'}'
        else if (contact['name'] != null) '${contact['name']}',
        if (assignee['name'] != null) '→ ${assignee['name']}',
        if (creator['name'] != null) 'by ${creator['name']}',
        if (t['synced_task_id'] != null) 'synced',
      ].join(' · '),
      leadingIcon: done ? Icons.check_circle_rounded : (_icons[type] ?? Icons.radio_button_unchecked_rounded),
      leadingColor: done ? AppPalette.success : (overdue ? AppPalette.danger : null),
      trailing: RowMenu(items: [
        (done ? 'Reopen' : 'Mark done', Icons.check_rounded, toggle),
        ('Edit', Icons.edit_outlined, () => _form(context, existing: t)),
        ('Delete', Icons.delete_outline_rounded, () async {
          final sure = await confirm(context, title: 'Delete this?', destructive: true, confirmLabel: 'Delete');
          if (!sure) return;
          final ok = await runAction(context, () => Api.delete('/crm/tasks/${t['id']}'), success: 'Deleted');
          if (ok) _refresh();
        }),
      ]),
      onTap: toggle,
    );
  }

  String _fmt(DateTime d) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
  }

  /// Create (existing == null) or edit. Follow-ups get an optional lead and the "also add to to-do" toggle.
  Future<void> _form(BuildContext context, {Rec? existing}) async {
    List<Rec> staff = const [];
    List<Rec> leads = const [];
    try {
      staff = await Api.list('/staff');
      if (widget.followups) leads = await Api.list('/leads', query: {'per_page': 100});
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;

    final editing = existing != null;
    final type = editing ? str(existing['type'], 'todo') : (widget.followups ? 'followup' : (_tab == 'scheduled' ? 'call' : 'todo'));
    final data = <String, dynamic>{'type': type, 'priority': editing ? str(existing['priority'], 'medium') : 'medium'};
    bool sync = false;
    Rec? pick(List<Rec> l, Object? id) { for (final r in l) { if ('${r['id']}' == '$id') return r; } return null; }
    final due = DateTime.tryParse('${existing?['due_at'] ?? ''}')?.toLocal();

    final ok = await showFormSheet(
      context,
      title: editing ? 'Edit' : 'New ${widget.followups ? 'follow-up' : (_tab == 'scheduled' ? 'scheduled task' : 'to-do')}',
      fields: (ctx) => [
        FText(label: 'Title', required: true, initial: existing == null ? null : str(existing['title'], ''), onSaved: (v) => data['title'] = v),
        FText(label: 'Details', maxLines: 2, initial: existing == null ? null : str(existing['description'], ''), onSaved: (v) => data['description'] = v.isEmpty ? null : v),
        if (!widget.followups && _tab == 'scheduled')
          FSelect<String>(label: 'Type', options: _scheduledTypes, initial: _scheduledTypes.contains(type) ? type : 'call', onSaved: (v) => data['type'] = v ?? 'call'),
        FSelect<String>(label: 'Priority', options: const ['low', 'medium', 'high'], initial: data['priority'] as String, onSaved: (v) => data['priority'] = v ?? 'medium'),
        FText(
          label: 'Due (YYYY-MM-DD HH:mm)', hint: '2026-10-25 14:00',
          initial: due == null ? null : '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')} ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}',
          onSaved: (v) => data['due_at'] = v.isEmpty ? null : v,
        ),
        FSelect<Rec>(
          label: 'Assign to', options: staff, labelOf: (s) => str(s['name']),
          initial: existing == null ? null : pick(staff, (existing['assignee'] is Map ? (existing['assignee'] as Map)['id'] : null)),
          onSaved: (s) => data['assigned_to'] = s?['id'],
        ),
        if (widget.followups)
          FSelect<Rec>(
            label: 'Lead (optional — empty for a general follow-up)', options: leads,
            labelOf: (l) {
              final c = l['contact'] is Map ? l['contact'] as Map : const {};
              return '${c['name'] ?? c['phone'] ?? 'Lead #${l['id']}'}';
            },
            initial: existing == null ? null : pick(leads, existing['lead_id']),
            onSaved: (l) => data['lead_id'] = l?['id'],
          ),
        if (widget.followups && !editing)
          FBoolField(label: 'Also add to my to-do list', hint: 'Completing either one completes both', onSaved: (v) => sync = v),
      ],
      onSubmit: () {
        if (widget.followups && !editing && sync) data['sync_todo'] = true;
        return editing ? Api.patch('/crm/tasks/${existing['id']}', data: data) : Api.post('/crm/tasks', data: data);
      },
    );
    if (ok) {
      _refresh();
      // a synced follow-up also lands in the To-do list
      ref.invalidate(crmTabTasksProvider('todo|all'));
      ref.invalidate(crmTabTasksProvider('todo|mine'));
    }
  }
}
