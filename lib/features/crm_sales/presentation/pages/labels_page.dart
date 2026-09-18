// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

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

