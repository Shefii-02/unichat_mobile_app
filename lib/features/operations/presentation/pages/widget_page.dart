// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Chat Widget ══════════════════════════

class WidgetPage extends ConsumerWidget {
  const WidgetPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Website Chat Widget')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New widget'),
      ),
      body: ProviderList(
        provider: chatWidgetsProvider,
        emptyLabel: 'No widgets configured',
        emptyIcon: Icons.chat_bubble_rounded,
        tile: (context, w) => RecordCard(
          title: str(w['name'] ?? w['title'], 'Widget'),
          subtitle:
              '${str((w['allowed_origins'] as List?)?.join(', ') ?? w['domain'] ?? w['website'])} · key ${str(w['key'] ?? w['widget_key'])}',
          leadingIcon: Icons.chat_bubble_rounded,
          leadingColor: const Color(0xFF6366F1),
          onTap: () => _edit(context, ref, w),
          trailing: RowMenu(items: [
            ('Edit', Icons.edit_rounded, () => _edit(context, ref, w)),
            (
              'Delete',
              Icons.delete_rounded,
              () async {
                if (!await confirm(context,
                    title: 'Delete widget?',
                    destructive: true,
                    confirmLabel: 'Delete')) { return; }
                final ok = await runAction(context,
                    () => Api.delete('/widgets/${w['id']}'),
                    success: 'Deleted');
                if (ok) ref.invalidate(chatWidgetsProvider);
              }
            ),
          ]),
          footer: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '<script src=".../public/widget/${str(w['key'] ?? w['widget_key'], 'KEY')}.js"></script>',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: context.mutedColor),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec? w) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: w == null ? 'New widget' : 'Edit widget',
      fields: (ctx) => [
        FText(
          label: 'Name',
          required: true,
          initial: w?['name'] as String?,
          onSaved: (v) => data['name'] = v,
        ),
        FText(
          label: 'Agent name',
          initial: w?['agent_name'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['agent_name'] = v,
        ),
        FText(
          label: 'Greeting',
          maxLines: 3,
          initial: w?['greeting'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['greeting'] = v,
        ),
        FChips(
          label: 'Allowed website domains',
          hint: 'example.com, shop.example.com',
          initial: ((w?['allowed_origins'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
          onSaved: (v) => data['allowed_origins'] = v,
        ),
        FChips(
          label: 'Notify emails',
          initial: ((w?['notify_emails'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
          onSaved: (v) => data['notify_emails'] = v,
        ),
        FBoolField(
          label: 'Active',
          initial: w?['is_active'] != false,
          onSaved: (v) => data['is_active'] = v,
        ),
      ],
      onSubmit: () => w == null
          ? Api.post('/widgets', data: data)
          : Api.put('/widgets/${w['id']}', data: data),
    );
    if (ok) ref.invalidate(chatWidgetsProvider);
  }
}

