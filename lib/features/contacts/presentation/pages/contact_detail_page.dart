// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

final _contactProvider =
    FutureProvider.family<Rec, int>((ref, id) => Api.one('/contacts/$id'));

class ContactDetailPage extends ConsumerWidget {
  const ContactDetailPage({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_contactProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact'),
        actions: [
          async.maybeWhen(
            data: (_) {
              if (!PermissionGuard.can('contacts.manage')) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'delete') {
                    if (!await confirm(context,
                        title: 'Delete contact?',
                        destructive: true,
                        confirmLabel: 'Delete')) {
                      return;
                    }
                    final ok = await runAction(
                        context, () => Api.delete('/contacts/$id'),
                        success: 'Deleted');
                    if (ok && context.mounted) context.pop();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Delete contact')),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (raw) {
          final c = raw['contact'] as Map<String, dynamic>? ?? raw;
          final name = str(c['name'], 'Unknown');
          final phone = str(c['phone'], '');
          final email = str(c['email'], '');
          final opted = c['opted_in'] == true;
          final labels = (c['labels'] as List?) ?? const [];

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_contactProvider(id)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 36,
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 28)),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                Center(
                    child: Text(phone,
                        style: TextStyle(color: context.mutedColor))),
                if (email.isNotEmpty)
                  Center(
                      child: Text(email,
                          style: TextStyle(color: context.mutedColor))),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _act(context, Icons.chat_rounded, 'WhatsApp', () {
                      launchUrl(
                        Uri.parse(
                            'https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}'),
                        mode: LaunchMode.externalApplication,
                      );
                    }),
                    _act(context, Icons.trending_up_rounded, 'New lead',
                        () => _createLead(context, ref, c)),
                    _act(context, Icons.edit_rounded, 'Edit',
                        () => _edit(context, ref, c)),
                  ],
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Opted in to messaging'),
                  value: opted,
                  onChanged: (v) async {
                    final ok = await runAction(
                      context,
                      () => Api.patch(
                          '/contacts/$id/${v ? 'opt-in' : 'opt-out'}'),
                      success: v ? 'Opted in' : 'Opted out',
                    );
                    if (ok) ref.invalidate(_contactProvider(id));
                  },
                ),
                const Divider(),
                Row(
                  children: [
                    const Text('Labels',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _editLabels(context, ref, c, labels),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Edit'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: labels.isEmpty
                      ? [
                          Text('No labels',
                              style: TextStyle(color: context.mutedColor))
                        ]
                      : labels.whereType<Map>().map((l) {
                          return Chip(
                            label: Text(str(l['name'])),
                            backgroundColor: _hex(l['color']),
                          );
                        }).toList(),
                ),
                const Divider(),
                const SizedBox(height: 8),
                ..._flatten(c).map((e) => KvRow(e.$1, e.$2)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _act(BuildContext context, IconData icon, String label,
      VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          IconButton.filledTonal(onPressed: onTap, icon: Icon(icon)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Color? _hex(Object? v) {
    final s = '${v ?? ''}'.replaceAll('#', '');
    if (s.length != 6) return null;
    return Color(int.parse('FF$s', radix: 16)).withValues(alpha: 0.18);
  }

  List<(String, String)> _flatten(Map<String, dynamic> c) {
    const keep = {
      'wa_id',
      'source',
      'created_at',
      'updated_at',
      'last_message_at',
      'assigned_to',
      'lead_score',
    };
    return c.entries
        .where((e) => keep.contains(e.key) && e.value != null)
        .map((e) => (e.key.replaceAll('_', ' '), when(e.value)))
        .toList();
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec c) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Edit contact',
      fields: (ctx) => [
        FText(
          label: 'Name',
          initial: c['name'] as String?,
          onSaved: (v) => data['name'] = v.isEmpty ? null : v,
        ),
        FText(
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
          initial: c['email'] as String?,
          onSaved: (v) => data['email'] = v.isEmpty ? null : v,
        ),
      ],
      onSubmit: () => Api.put('/contacts/$id', data: data),
    );
    if (ok) ref.invalidate(_contactProvider(id));
  }

  Future<void> _editLabels(
      BuildContext context, WidgetRef ref, Rec c, List current) async {
    final all = await Api.list('/labels').catchError((_) => <Rec>[]);
    if (!context.mounted || all.isEmpty) return;
    final selected = current
        .whereType<Map>()
        .map((l) => l['id'])
        .toSet();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Labels',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...all.map((l) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(str(l['name'])),
                  value: selected.contains(l['id']),
                  onChanged: (v) => setState(() {
                    v == true ? selected.add(l['id']) : selected.remove(l['id']);
                  }),
                )),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await runAction(
                  context,
                  () => Api.post('/contacts/$id/labels',
                      data: {'label_ids': selected.toList()}),
                  success: 'Labels updated',
                );
                if (ok) ref.invalidate(_contactProvider(id));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createLead(BuildContext context, WidgetRef ref, Rec c) async {
    // Full staff roster was fetched here regardless of staff.view — the "Assign to" field
    // below already tolerates an empty list, so gating the fetch just omits that field.
    final staff = PermissionGuard.can('staff.view')
        ? await Api.list('/staff').catchError((_) => <Rec>[])
        : <Rec>[];
    if (!context.mounted) return;
    final data = <String, dynamic>{'contact_id': c['id']};
    await showFormSheet(
      context,
      title: 'New lead for ${str(c['name'] ?? c['phone'])}',
      submitLabel: 'Create',
      fields: (ctx) => [
        FSelect<String>(
          label: 'Priority',
          options: const ['low', 'medium', 'high'],
          initial: 'medium',
          onSaved: (v) => data['priority'] = v ?? 'medium',
        ),
        FText(
          label: 'Category',
          onSaved: (v) => v.isEmpty ? null : data['category'] = v,
        ),
        if (staff.isNotEmpty)
          FSelect<Rec>(
            label: 'Assign to',
            options: staff,
            labelOf: (s) => str(s['name']),
            onSaved: (s) =>
                s?['id'] != null ? data['assigned_to'] = s!['id'] : null,
          ),
        FText(
          label: 'Notes',
          maxLines: 3,
          onSaved: (v) => v.isEmpty ? null : data['notes'] = v,
        ),
      ],
      onSubmit: () => Api.post('/leads', data: data),
    );
  }
}
