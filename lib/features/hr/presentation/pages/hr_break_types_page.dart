// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Break types / Leave types (generic CRUD) ══════════════════════════

/// Split out of the former shared `HrAdminPage` (tab 6, "Break Types").
class HrBreakTypesPage extends ConsumerWidget {
  const HrBreakTypesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Break Types')),
      floatingActionButton: FloatingActionButton(onPressed: () => _editBreakType(context), child: const Icon(Icons.add_rounded)),
      body: ProviderList(
      provider: hrBreakTypesAdminProvider,
      emptyLabel: 'No break types configured',
      emptyIcon: Icons.free_breakfast_rounded,
      tile: (context, bt) => RecordCard(
        title: str(bt['name']),
        subtitle: '${bt['max_minutes'] != null ? '${bt['max_minutes']}m max' : 'No limit'}'
            '${bt['daily_limit'] != null ? ' · ${bt['daily_limit']}/day' : ''}${bt['is_paid'] == true ? ' · Paid' : ' · Unpaid'}',
        leadingIcon: Icons.free_breakfast_rounded,
        trailing: RowMenu(items: [
          ('Edit', Icons.edit_rounded, () => _editBreakType(context, existing: bt)),
          ('Delete', Icons.delete_outline_rounded, () async {
            final ok = await confirm(context, title: 'Delete "${bt['name']}"?', destructive: true, confirmLabel: 'Delete');
            if (!ok) return;
            final done = await runAction(context, () => Api.delete('/hr/break-types/${bt['id']}'), success: 'Deleted');
            if (done) ref.invalidate(hrBreakTypesAdminProvider);
          }),
        ]),
      ),
      ),
    );
  }
}

Future<void> _editBreakType(BuildContext context, {Rec? existing}) async {
  final data = <String, dynamic>{};
  final ok = await showFormSheet(
    context,
    title: existing == null ? 'Add break type' : 'Edit break type',
    fields: (ctx) => [
      FText(label: 'Name', initial: existing?['name'] as String?, required: true, onSaved: (v) => data['name'] = v),
      FNumber(label: 'Max minutes', initial: existing?['max_minutes'] as num?, onSaved: (v) => data['max_minutes'] = v),
      FNumber(label: 'Per day limit', initial: existing?['daily_limit'] as num?, onSaved: (v) => data['daily_limit'] = v),
    ],
    onSubmit: () => existing == null
        ? Api.post('/hr/break-types', data: data)
        : Api.patch('/hr/break-types/${existing['id']}', data: data),
  );
  if (ok && context.mounted) {
    ProviderScope.containerOf(context, listen: false).invalidate(hrBreakTypesAdminProvider);
  }
}

