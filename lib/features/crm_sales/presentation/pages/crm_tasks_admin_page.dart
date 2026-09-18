// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

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

