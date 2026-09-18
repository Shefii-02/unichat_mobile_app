import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Split out of the former shared `InstagramPage` (tab 1, "Automations" / "Auto DM Rules").
class InstagramAutomationsPage extends ConsumerWidget {
  const InstagramAutomationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auto DM Rules')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editAutomation(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Automation'),
      ),
      body: ProviderList(
        provider: igAutomationsProvider,
        emptyLabel: 'No keyword automations',
        emptyIcon: Icons.bolt_rounded,
        tile: (context, a) {
          final active = a['is_active'] == true || a['active'] == true;
          return RecordCard(
            title: str(a['name'] ?? a['keyword'], 'Automation'),
            subtitle:
                'Keyword: ${str((a['keywords'] as List?)?.join(', ') ?? a['keyword'])} → auto-DM',
            leadingIcon: Icons.bolt_rounded,
            leadingColor: const Color(0xFFE1306C),
            trailing: RowMenu(items: [
              (
                active ? 'Pause' : 'Activate',
                active ? Icons.pause_rounded : Icons.play_arrow_rounded,
                () async {
                  final ok = await runAction(context,
                      () => Api.post('/instagram/automations/${a['id']}/toggle'),
                      success: 'Updated');
                  if (ok) ref.invalidate(igAutomationsProvider);
                }
              ),
              ('Edit', Icons.edit_rounded,
                  () => _editAutomation(context, ref, a)),
              (
                'Delete',
                Icons.delete_rounded,
                () async {
                  if (!await confirm(context,
                      title: 'Delete automation?',
                      destructive: true,
                      confirmLabel: 'Delete')) { return; }
                  final ok = await runAction(context,
                      () => Api.delete('/instagram/automations/${a['id']}'),
                      success: 'Deleted');
                  if (ok) ref.invalidate(igAutomationsProvider);
                }
              ),
            ]),
          );
        },
      ),
    );
  }

  Future<List<Rec>> _safeList(String path) async {
    try {
      return await Api.list(path);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _editAutomation(
      BuildContext context, WidgetRef ref, Rec? existing) async {
    final accounts = await _safeList('/instagram/accounts');
    if (existing == null && accounts.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Connect an Instagram account first.')));
      }
      return;
    }
    final data = <String, dynamic>{};
    if (!context.mounted) return;
    final ok = await showFormSheet(
      context,
      title: existing == null ? 'New automation' : 'Edit automation',
      fields: (ctx) => [
        if (existing == null)
          FSelect<Rec>(
            label: 'Instagram account',
            options: accounts,
            labelOf: (a) => '@${str(a['username'] ?? a['name'])}',
            onSaved: (a) => data['instagram_account_id'] = a?['id'],
          ),
        FText(
          label: 'Name',
          required: true,
          initial: existing?['name'] as String?,
          onSaved: (v) => data['name'] = v,
        ),
        FSelect<String>(
          label: 'Trigger',
          options: const ['comment', 'dm', 'story_reply'],
          initial: (existing?['trigger'] as String?) ?? 'comment',
          onSaved: (v) => data['trigger'] = v ?? 'comment',
        ),
        FChips(
          label: 'Keywords',
          required: true,
          initial: ((existing?['keywords'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
          onSaved: (v) => data['keywords'] = v,
        ),
        FSelect<String>(
          label: 'Match type',
          options: const ['any', 'all', 'exact'],
          initial: (existing?['match_type'] as String?) ?? 'any',
          onSaved: (v) => data['match_type'] = v ?? 'any',
        ),
        FText(
          label: 'DM message',
          required: true,
          maxLines: 4,
          initial: existing?['dm_message'] as String?,
          onSaved: (v) => data['dm_message'] = v,
        ),
        FText(
          label: 'Public reply (optional)',
          maxLines: 2,
          initial: existing?['public_reply'] as String?,
          onSaved: (v) => data['public_reply'] = v.isEmpty ? null : v,
        ),
        FBoolField(
          label: 'Hand off to AI agent',
          initial: existing?['handoff_to_ai'] == true,
          onSaved: (v) => data['handoff_to_ai'] = v,
        ),
        FBoolField(
          label: 'Reply once per user',
          initial: existing?['reply_once_per_user'] != false,
          onSaved: (v) => data['reply_once_per_user'] = v,
        ),
        FBoolField(
          label: 'Active',
          initial: existing?['is_active'] != false,
          onSaved: (v) => data['is_active'] = v,
        ),
      ],
      onSubmit: () => existing == null
          ? Api.post('/instagram/automations', data: data)
          : Api.put('/instagram/automations/${existing['id']}',
              data: data..remove('instagram_account_id')),
    );
    if (ok) ref.invalidate(igAutomationsProvider);
  }
}
