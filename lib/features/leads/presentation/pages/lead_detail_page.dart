// ignore_for_file: use_build_context_synchronously
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/features/leads/lead_stage.dart';
import 'package:unichat_mobile_app/features/leads/presentation/widgets/lead_detail_tabs.dart';
import 'package:unichat_mobile_app/features/leads/presentation/widgets/lead_form_fields.dart';
import 'package:unichat_mobile_app/features/leads/presentation/widgets/lead_installments.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

// Riverpod 3 re-requests a failed call again and again. A 403 / 404 ("not your lead", "not found") will never succeed on retry, so stop at once.
Duration? _retryUnless4xx(int count, Object error) {
  if (error is DioException) {
    final c = error.response?.statusCode ?? 0;
    if (c >= 400 && c < 500) return null;
  }
  return count >= 3 ? null : Duration(seconds: 1 << count);
}

final _leadProvider = FutureProvider.family<Rec, int>(
  (ref, id) => Api.one('/leads/$id'),
  retry: _retryUnless4xx,
);
final _leadActivitiesProvider = FutureProvider.family<List<Rec>, int>(
  (ref, id) => Api.list('/leads/$id/activities'),
  retry: _retryUnless4xx,
);
final _leadEventsProvider = FutureProvider.family<List<Rec>, int>(
  (ref, id) async => _rows(await Api.one('/leads/$id/events'), 'events'),
  retry: _retryUnless4xx,
);

// these two endpoints answer {notes:[…]} / {events:[…]}, which the generic list helper does not unwrap
List<Rec> _rows(Rec body, String key) =>
    ((body[key] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

String _eventText(Rec e) {
  final p = e['payload'] is Map ? (e['payload'] as Map) : const {};
  final name = str(e['event']).replaceAll('_', ' ');
  final bits = [
    if (p['from'] != null && p['to'] != null) '${p['from']} → ${p['to']}',
    if (p['content'] != null) '${p['content']}',
    if (p['reason'] != null && '${p['reason']}'.isNotEmpty) 'Reason: ${p['reason']}',
  ];
  final by = e['user'] is Map ? ' · ${(e['user'] as Map)['name']}' : '';
  return '${name.isEmpty ? '' : name[0].toUpperCase() + name.substring(1)}${bits.isEmpty ? '' : ' — ${bits.join('; ')}'}$by';
}


class LeadDetailPage extends ConsumerWidget {
  const LeadDetailPage({super.key, required this.id});
  final int id;

  void _refresh(WidgetRef ref) {
    ref.invalidate(_leadProvider(id));
    ref.invalidate(_leadActivitiesProvider(id));
    ref.invalidate(_leadEventsProvider(id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_leadProvider(id));
    final lead0 = async.value == null ? null : (async.value!['lead'] as Map<String, dynamic>? ?? async.value!);
    final contact0 = lead0?['contact'] is Map ? (lead0!['contact'] as Map) : const {};
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(lead0 == null ? 'Lead' : str(contact0['name'], str(contact0['phone'], 'Lead')), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (lead0 != null)
              Text('${stageLabel(str(lead0['stage'], 'new'))} · ${str(lead0['priority'], 'medium')} priority${str(contact0['phone']).isEmpty ? '' : ' · ${contact0['phone']}'}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400)),
          ]),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '👤 Contact & pipeline'),
              Tab(text: '📋 Lead information'),
              Tab(text: '💬 Chat'),
              Tab(text: '🤝 Referred by'),
              Tab(text: '🧑‍💼 Assigned staff'),
              Tab(text: '🏷️ Category & labels'),
              Tab(text: '📣 Campaigns'),
              Tab(text: '💳 Installments'),
            ],
          ),
          actions: [
            // my star on this lead — tap to mark / unmark it
            IconButton(
              tooltip: async.value?['starred'] == true ? 'Starred — tap to unstar' : 'Star this lead',
              icon: Icon(
                async.value?['starred'] == true ? Icons.star_rounded : Icons.star_outline_rounded,
                color: async.value?['starred'] == true ? const Color(0xFFF59E0B) : null,
              ),
              onPressed: async.value == null
                  ? null
                  : () async {
                      final on = async.value?['starred'] == true;
                      final ok = await runAction(context, () => Api.put('/leads/$id/star', data: {'starred': !on}), success: on ? 'Star removed' : 'Starred');
                      if (ok) ref.invalidate(_leadProvider(id));
                    },
            ),
            IconButton(icon: const Icon(Icons.add_call), tooltip: 'Log activity', onPressed: () => _logActivity(context, ref)),
            if (PermissionGuard.can('leads.manage'))
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'delete') {
                    if (!await confirm(
                      context,
                      title: 'Delete lead?',
                      destructive: true,
                      confirmLabel: 'Delete',
                    )) {
                      return;
                    }
                    final ok = await runAction(
                      context,
                      () => Api.delete('/leads/$id'),
                      success: 'Deleted',
                    );
                    if (ok && context.mounted) Navigator.of(context).pop();
                  }
                },
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete lead'),
                      ),
                    ],
              ),
          ],
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(apiErrorMessage(e))),
          data: (raw) {
            final lead = raw['lead'] as Map<String, dynamic>? ?? raw;
            final stage = str(lead['stage'] ?? lead['status'], 'new');
            return TabBarView(
              children: [
                LeadMainTab(
                  onRefresh: () async {
                    _refresh(ref);
                    await ref.read(_leadProvider(id).future);
                  },
                  activityCount: ref.watch(_leadEventsProvider(id)).value?.length ?? 0,
                  main: Column(children: [
                    LeadContactCard(leadId: id, lead: lead),
                    LeadPipelineCard(stage: stage, onStage: (v) => _changeStage(context, ref, lead, v)),
                  ]),
                  call: _callsView(context, ref),
                  activity: _activityView(context, ref),
                ),
                LeadInfoTab(lead: lead, onEdit: () => _editCategory(context, ref, lead)),
                LeadChatTab(leadId: id, lead: lead),
                LeadReferredTab(leadId: id, lead: lead, onChanged: () => _refresh(ref)),
                LeadStaffTab(
                  lead: lead,
                  onAssign: () => _assign(context, ref),
                  onClaim: () async {
                    final ok = await runAction(context, () => Api.post('/leads/$id/claim'), success: 'Assigned to you');
                    if (ok) _refresh(ref);
                  },
                ),
                LeadCategoryTab(key: ValueKey('cat-${lead['updated_at'] ?? ''}'), leadId: id, lead: lead, onChanged: () => ref.invalidate(_leadProvider(id))),
                LeadCampaignsTab(leadId: id),
                LeadInstallmentsTab(leadId: id, saleValue: lead['sale_value']),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Move the lead to another stage. Closing as Lost, reopening a closed lead, or changing a closed lead's outcome needs a reason;
  /// converting asks for an optional note and then offers to set up the installment plan.
  Future<void> _changeStage(BuildContext context, WidgetRef ref, Rec lead, String v) async {
    final stage = str(lead['stage'] ?? lead['status'], 'new');
    if (v == stage) return;
    final closed = stage == 'enrolled' || stage == 'lost';
    final needs = v == 'lost' || closed;
    final data = <String, dynamic>{'stage': v};
    if (needs || v == 'enrolled') {
      final reason = await _askReason(context, needs);
      if (reason == null) return;
      if (reason.isNotEmpty) data['reason'] = reason;
    }
    final ok = await runAction(context, () => Api.put('/leads/$id', data: data), success: 'Stage updated');
    if (ok) _refresh(ref);
    if (ok && v == 'enrolled' && context.mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Paying in installments?'),
          content: const Text('Set up when each installment is due and how much, so it can be followed up and counted correctly.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Set up installments')),
          ],
        ),
      );
      if (go == true && context.mounted) {
        final fresh = await Api.one('/leads/$id').catchError((_) => <String, dynamic>{});
        final l = fresh['lead'] as Map<String, dynamic>? ?? fresh;
        await showInstallmentPlanSetup(context, id, l['sale_value'] ?? lead['sale_value']);
        _refresh(ref);
      }
    }
  }

  /// "Log a call": the form button and the calls already logged on this lead.
  Widget _callsView(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_leadActivitiesProvider(id));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _logActivity(context, ref), icon: const Icon(Icons.add_call), label: const Text('Log a call / follow-up'))),
      const SizedBox(height: 4),
      Text('The first one on a lead counts as a new-lead call; later ones are follow-ups.', style: TextStyle(fontSize: 11.5, color: context.mutedColor)),
      const SizedBox(height: 12),
      async.when(
        loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text(apiErrorMessage(e)),
        data: (rows) => rows.isEmpty
            ? Text('Nothing logged yet.', style: TextStyle(color: context.mutedColor))
            : Column(children: [
                for (final a in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(a['kind'] == 'call' ? Icons.call_rounded : Icons.notes_rounded, size: 20),
                    title: Text([str(a['kind']), if (str(a['outcome']).isNotEmpty) str(a['outcome']).replaceAll('_', ' ')].join(' · '), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    subtitle: Text('${when(a['happened_at'])}${str(a['by']).isEmpty ? '' : ' · ${a['by']}'}${str(a['notes']).isEmpty ? '' : '\n${a['notes']}'}'),
                    isThreeLine: str(a['notes']).isNotEmpty,
                  ),
              ]),
      ),
    ]);
  }

  /// Lead activities: add a note, and the feed of everything that happened on the lead.
  Widget _activityView(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_leadEventsProvider(id));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _addNote(context, ref), icon: const Icon(Icons.add_rounded), label: const Text('Add a note'))),
      const SizedBox(height: 12),
      async.when(
        loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text(apiErrorMessage(e)),
        data: (events) => events.isEmpty
            ? Text('No activity recorded yet.', style: TextStyle(color: context.mutedColor))
            : Column(children: [
                for (final e in events)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.circle, size: 9),
                    title: Text(_eventText(e), style: const TextStyle(fontSize: 13)),
                    subtitle: Text(when(e['created_at']), style: const TextStyle(fontSize: 11)),
                  ),
              ]),
      ),
    ]);
  }

  /// A reason for the stage change; null = cancelled, '' = skipped (only when [required] is false).
  Future<String?> _askReason(BuildContext context, bool required) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(required ? 'Reason' : 'Add a note (optional)'),
          content: TextField(controller: c, autofocus: true, maxLines: 3, maxLength: 500, onChanged: (_) => set(() {}), decoration: const InputDecoration(hintText: 'Why is this changing?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: required && c.text.trim().isEmpty ? null : () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  /// Log a call / message / meeting, with its outcome and an optional next follow-up.
  Future<void> _logActivity(BuildContext context, WidgetRef ref) async {
    final data = <String, dynamic>{};
    DateTime? next;
    final ok = await showFormSheet(
      context,
      title: 'Log activity',
      submitLabel: 'Save',
      fields: (ctx) => [
        FSelect<String>(label: 'Type', options: const ['call', 'message', 'meeting', 'visit', 'other'], initial: 'call', labelOf: (v) => v[0].toUpperCase() + v.substring(1), onSaved: (v) => data['kind'] = v ?? 'call'),
        FSelect<String>(label: 'Call direction', options: const ['outgoing', 'incoming', 'missed'], initial: 'outgoing', labelOf: (v) => {'outgoing': 'Outgoing — I called', 'incoming': 'Incoming — they called', 'missed': 'Missed call'}[v] ?? v, onSaved: (v) => data['direction'] = v ?? 'outgoing'),
        FSelect<String>(label: 'Outcome', options: const ['connected', 'not_reachable', 'callback', 'interested', 'not_interested', 'wrong_number'], labelOf: (v) => v.replaceAll('_', ' '), onSaved: (v) { if (v != null) data['outcome'] = v; }),
        FText(label: 'Notes', maxLines: 3, onSaved: (v) { if (v.isNotEmpty) data['notes'] = v; }),
        StatefulBuilder(
          builder: (c, set) => OutlinedButton.icon(
            icon: const Icon(Icons.event_rounded),
            label: Text(next == null ? 'Next follow-up (optional)' : 'Follow up ${next.toString().substring(0, 16)}'),
            onPressed: () async {
              final d = await showDatePicker(context: c, initialDate: DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)));
              if (d == null || !c.mounted) return;
              final t = await showTimePicker(context: c, initialTime: const TimeOfDay(hour: 10, minute: 0));
              if (t == null) return;
              set(() => next = DateTime(d.year, d.month, d.day, t.hour, t.minute));
            },
          ),
        ),
      ],
      onSubmit: () => Api.post('/leads/$id/activities', data: {...data, if (next != null) 'next_follow_up_at': next!.toIso8601String()}),
    );
    if (ok) _refresh(ref);
  }

  Future<void> _addNote(BuildContext context, WidgetRef ref) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Add note',
      submitLabel: 'Save',
      fields:
          (ctx) => [
            FText(
              label: 'Note',
              required: true,
              maxLines: 4,
              onSaved: (v) => data['content'] = v,
            ),
          ],
      onSubmit: () => Api.post('/leads/$id/notes', data: data),
    );
    if (ok) _refresh(ref);
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
      fields:
          (ctx) => [
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

  /// Edit lead — the same fields as the web form: priority, categories (several, first is primary), product / service, expected deal value, notes.
  Future<void> _editCategory(BuildContext context, WidgetRef ref, Rec lead) async {
    final data = <String, dynamic>{};
    final form = LeadFormState();
    form.categories.addAll((lead['categories'] as List?)?.map((e) => '$e') ?? [if (str(lead['category']).isNotEmpty) str(lead['category'])]);
    form.itemId = (lead['listing_id'] as num?)?.toInt();
    final before = [...form.categories];
    final ok = await showFormSheet(
      context,
      title: 'Edit lead',
      submitLabel: 'Save changes',
      fields: (ctx) => [
        FRadio<String>(label: 'Priority', options: const ['low', 'medium', 'high'], initial: str(lead['priority'], 'medium'), onSaved: (v) => data['priority'] = v ?? 'medium'),
        LeadCategoriesField(state: form),
        LeadItemField(state: form),
        FText(
          label: 'Expected deal value (₹)',
          initial: lead['sale_value'] == null ? '' : '${lead['sale_value']}',
          keyboardType: TextInputType.number,
          onSaved: (v) { if (v.trim().isNotEmpty) data['sale_value'] = num.tryParse(v.trim()); },
        ),
        FText(label: 'Notes', maxLines: 4, initial: str(lead['notes']), onSaved: (v) { if (v.isNotEmpty) data['notes'] = v; }),
      ],
      onSubmit: () async {
        if (form.itemId != null) data['listing_id'] = form.itemId;
        await Api.put('/leads/$id', data: data);
        if (form.categories.join('|') != before.join('|')) await Api.put('/leads/$id/categories', data: {'categories': form.categories});
      },
    );
    Future.delayed(const Duration(milliseconds: 500), form.dispose);   // after the sheet has finished closing
    if (ok) _refresh(ref);
  }
}
