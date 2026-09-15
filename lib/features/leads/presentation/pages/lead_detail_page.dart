// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/leads/lead_stage.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

final _leadProvider =
    FutureProvider.family<Rec, int>((ref, id) => Api.one('/leads/$id'));
final _leadNotesProvider =
    FutureProvider.family<List<Rec>, int>((ref, id) => Api.list('/leads/$id/notes'));
final _leadEventsProvider =
    FutureProvider.family<List<Rec>, int>((ref, id) => Api.list('/leads/$id/events'));

const _stages = ['new', 'contacted', 'follow_up', 'enrolled', 'lost'];
const _priorities = ['low', 'medium', 'high'];

class LeadDetailPage extends ConsumerWidget {
  const LeadDetailPage({super.key, required this.id});
  final int id;

  void _refresh(WidgetRef ref) {
    ref.invalidate(_leadProvider(id));
    ref.invalidate(_leadNotesProvider(id));
    ref.invalidate(_leadEventsProvider(id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_leadProvider(id));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lead'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'Notes'),
            Tab(text: 'Timeline'),
          ]),
          actions: [
            if (PermissionGuard.can('leads.manage'))
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'delete') {
                    if (!await confirm(context,
                        title: 'Delete lead?',
                        destructive: true,
                        confirmLabel: 'Delete')) {
                      return;
                    }
                    final ok = await runAction(
                        context, () => Api.delete('/leads/$id'),
                        success: 'Deleted');
                    if (ok && context.mounted) Navigator.of(context).pop();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Delete lead')),
                ],
              ),
          ],
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(apiErrorMessage(e))),
          data: (raw) {
            final lead = raw['lead'] as Map<String, dynamic>? ?? raw;
            return TabBarView(children: [
              _overview(context, ref, lead),
              _notes(context, ref),
              _timeline(ref),
            ]);
          },
        ),
      ),
    );
  }

  Widget _overview(BuildContext context, WidgetRef ref, Rec lead) {
    final contact = lead['contact'] as Map<String, dynamic>? ?? const {};
    final staff = lead['staff'] as Map<String, dynamic>? ??
        lead['assignee'] as Map<String, dynamic>?;
    final name = str(contact['name'], 'Unknown');
    final phone = str(contact['phone'], '');
    final score = num.tryParse('${lead['lead_score'] ?? lead['score'] ?? 0}') ?? 0;
    final stage = str(lead['stage'] ?? lead['status'], 'new');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(phone, style: TextStyle(color: context.mutedColor)),
                ],
              ),
            ),
            if (phone.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
                onPressed: () => launchUrl(
                  Uri.parse(
                      'https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.altSurface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text('Lead score',
                      style: TextStyle(color: context.mutedColor)),
                  const Spacer(),
                  Text('${score.toStringAsFixed(0)}/100',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: score / 100, minHeight: 8),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _EditableRow(
          label: 'Stage',
          value: stage,
          options: _stages,
          tintOf: (s) => stageTint[s],
          labelOf: stageLabel,
          onChanged: (v) async {
            final ok = await runAction(context,
                () => Api.put('/leads/$id', data: {'stage': v}),
                success: 'Stage updated');
            if (ok) _refresh(ref);
          },
        ),
        _EditableRow(
          label: 'Priority',
          value: str(lead['priority'], 'medium'),
          options: _priorities,
          onChanged: (v) async {
            final ok = await runAction(context,
                () => Api.put('/leads/$id', data: {'priority': v}),
                success: 'Priority updated');
            if (ok) _refresh(ref);
          },
        ),
        KvRow('Category', str(lead['category'])),
        KvRow('Assigned to', str(staff?['name'], 'Unassigned')),
        KvRow('Source', str(lead['source'] ?? lead['source_type'])),
        KvRow('Created', when(lead['created_at'])),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _assign(context, ref),
                icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                label: const Text('Assign'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _editCategory(context, ref, lead),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _notes(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_leadNotesProvider(id));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addNote(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add note'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (notes) => notes.isEmpty
            ? Center(
                child: Text('No notes yet',
                    style: TextStyle(color: context.mutedColor)))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: notes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final n = notes[i];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(str(n['content'] ?? n['note'] ?? n['body'])),
                          const SizedBox(height: 4),
                          Text(
                            '${str(n['user']?['name'] ?? n['author'] ?? n['created_by'])} · ${when(n['created_at'])}',
                            style: TextStyle(
                                color: context.mutedColor, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _timeline(WidgetRef ref) {
    final async = ref.watch(_leadEventsProvider(id));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(apiErrorMessage(e))),
      data: (events) => events.isEmpty
          ? const Center(child: Text('No activity yet'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              itemBuilder: (_, i) {
                final e = events[i];
                return ListTile(
                  leading: const Icon(Icons.circle, size: 10),
                  title: Text(str(
                      e['description'] ?? e['event'] ?? e['type'] ?? e['action'])),
                  subtitle: Text(when(e['created_at'])),
                );
              },
            ),
    );
  }

  Future<void> _addNote(BuildContext context, WidgetRef ref) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Add note',
      submitLabel: 'Save',
      fields: (ctx) => [
        FText(
          label: 'Note',
          required: true,
          maxLines: 4,
          onSaved: (v) => data['content'] = v,
        ),
      ],
      onSubmit: () => Api.post('/leads/$id/notes', data: data),
    );
    if (ok) ref.invalidate(_leadNotesProvider(id));
  }

  Future<void> _assign(BuildContext context, WidgetRef ref) async {
    // The full staff roster (names, emails) was fetched here regardless of whether the current
    // user holds staff.view — any role that could open a lead and tap Assign saw every other
    // staff member's name via this picker.
    if (!PermissionGuard.can('staff.view')) return;
    final staff = await Api.list('/staff').catchError((_) => <Rec>[]);
    if (!context.mounted || staff.isEmpty) return;
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Assign lead',
      submitLabel: 'Assign',
      fields: (ctx) => [
        FSelect<Rec>(
          label: 'Staff member',
          options: staff,
          labelOf: (s) => str(s['name']),
          onSaved: (s) => data['user_id'] = s?['id'],
        ),
      ],
      onSubmit: () => Api.post('/leads/$id/assign', data: data),
    );
    if (ok) _refresh(ref);
  }

  Future<void> _editCategory(BuildContext context, WidgetRef ref, Rec lead) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Edit lead',
      fields: (ctx) => [
        FText(
          label: 'Category',
          initial: lead['category'] as String?,
          onSaved: (v) => data['category'] = v.isEmpty ? null : v,
        ),
        FText(
          label: 'Notes',
          maxLines: 3,
          initial: lead['notes'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['notes'] = v,
        ),
      ],
      onSubmit: () => Api.put('/leads/$id', data: data),
    );
    if (ok) _refresh(ref);
  }
}

class _EditableRow extends StatelessWidget {
  const _EditableRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.tintOf,
    this.labelOf,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  /// Optional per-option colour (e.g. lead-stage tints), falling back to the theme default.
  final Tint? Function(String option)? tintOf;
  final String Function(String option)? labelOf;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: context.mutedColor)),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: options.map((o) {
                final sel = o == value;
                final tint = tintOf?.call(o);
                return ChoiceChip(
                  label: Text(labelOf?.call(o) ?? o.replaceAll('_', ' ')),
                  selected: sel,
                  onSelected: (_) => sel ? null : onChanged(o),
                  selectedColor: tint?.$1,
                  labelStyle: sel && tint != null ? TextStyle(color: tint.$2) : null,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
