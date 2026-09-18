// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";
import "package:unichat_mobile_app/features/leads/lead_stage.dart";
import "package:unichat_mobile_app/features/crm_sales/presentation/pages/labels_page.dart";

// ══════════════════════════ Lead Categories ══════════════════════════

class LeadCategoriesPage extends ConsumerWidget {
  const LeadCategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lead Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add category'),
      ),
      body: ProviderList(
        provider: leadCategoriesProvider,
        emptyLabel: 'No lead categories yet',
        emptyIcon: Icons.sell_outlined,
        tile: (context, c) {
          final color = LabelsPage.parseColor(c['color'] as String?);
          final leadsCount = c['leads_count'] ?? 0;
          return RecordCard(
            title: str(c['name']),
            subtitle: '$leadsCount leads'
                '${c['is_active'] == false ? ' · Inactive' : ''}'
                '${c['description'] != null ? ' · ${c['description']}' : ''}',
            leadingIcon: Icons.sell_rounded,
            leadingColor: color,
            trailing: RowMenu(items: [
              ('Edit', Icons.edit_rounded, () => _edit(context, ref, c)),
              ('Delete', Icons.delete_outline_rounded, () async {
                final ok = await confirm(context, title: 'Delete "${c['name']}"?', destructive: true, confirmLabel: 'Delete');
                if (!ok) return;
                final done = await runAction(context, () => Api.delete('/lead-categories/${c['id']}'), success: 'Deleted');
                if (done) ref.invalidate(leadCategoriesProvider);
              }),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec? existing) async {
    final data = <String, dynamic>{'color': existing?['color'] ?? '#1D9E75'};
    final ok = await showFormSheet(
      context,
      title: existing == null ? 'Add category' : 'Edit category',
      fields: (ctx) => [
        FText(label: 'Name', initial: existing?['name'] as String?, required: true, onSaved: (v) => data['name'] = v),
        FText(label: 'Color (hex, e.g. #1D9E75)', initial: data['color'] as String, required: true,
            onSaved: (v) => data['color'] = v),
        FText(label: 'Description', initial: existing?['description'] as String?, maxLines: 2,
            onSaved: (v) => v.isEmpty ? null : data['description'] = v),
        if (existing != null)
          FBoolField(label: 'Active', initial: existing['is_active'] != false, onSaved: (v) => data['is_active'] = v),
      ],
      onSubmit: () => existing == null
          ? Api.post('/lead-categories', data: data)
          : Api.put('/lead-categories/${existing['id']}', data: data),
    );
    if (ok) ref.invalidate(leadCategoriesProvider);
  }
}

