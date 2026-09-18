// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

/// Split out of the former shared `HrAdminPage` (tab 7, "Leave Types").
class HrLeaveTypesPage extends ConsumerWidget {
  const HrLeaveTypesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave Types')),
      floatingActionButton: FloatingActionButton(onPressed: () => _editLeaveType(context), child: const Icon(Icons.add_rounded)),
      body: ProviderList(
      provider: hrLeaveTypesAdminProvider,
      emptyLabel: 'No leave types configured',
      emptyIcon: Icons.beach_access_rounded,
      tile: (context, lt) => RecordCard(
        title: str(lt['name']),
        subtitle: '${lt['max_days_per_year'] != null ? '${lt['max_days_per_year']} days/yr' : 'No limit'}'
            '${lt['requires_approval'] == true ? ' · Approval' : ' · Auto'}${lt['is_paid'] == true ? ' · Paid' : ' · Unpaid'}',
        leadingIcon: Icons.beach_access_rounded,
        trailing: RowMenu(items: [
          ('Edit', Icons.edit_rounded, () => _editLeaveType(context, existing: lt)),
          ('Delete', Icons.delete_outline_rounded, () async {
            final ok = await confirm(context, title: 'Delete "${lt['name']}"?', destructive: true, confirmLabel: 'Delete');
            if (!ok) return;
            final done = await runAction(context, () => Api.delete('/hr/leave-types/${lt['id']}'), success: 'Deleted');
            if (done) ref.invalidate(hrLeaveTypesAdminProvider);
          }),
        ]),
      ),
      ),
    );
  }
}

Future<void> _editLeaveType(BuildContext context, {Rec? existing}) async {
  final data = <String, dynamic>{};
  final ok = await showFormSheet(
    context,
    title: existing == null ? 'Add leave type' : 'Edit leave type',
    fields: (ctx) => [
      FText(label: 'Name', initial: existing?['name'] as String?, required: true, onSaved: (v) => data['name'] = v),
      FNumber(label: 'Max days/year', initial: existing?['max_days_per_year'] as num?, onSaved: (v) => data['max_days_per_year'] = v),
    ],
    onSubmit: () => existing == null
        ? Api.post('/hr/leave-types', data: data)
        : Api.patch('/hr/leave-types/${existing['id']}', data: data),
  );
  if (ok && context.mounted) {
    ProviderScope.containerOf(context, listen: false).invalidate(hrLeaveTypesAdminProvider);
  }
}

