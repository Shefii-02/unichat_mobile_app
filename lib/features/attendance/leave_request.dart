import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

/// Shared "Request leave" form — used from the HR tab and from the mandatory
/// clock-in screen (a staff member out sick shouldn't have to clock in just
/// to tell the app they won't be).
Future<void> requestLeave(BuildContext context, WidgetRef ref) async {
  List<Rec> types;
  try {
    types = await Api.list('/hr/leave/types');
  } catch (_) {
    types = const [];
  }
  if (!context.mounted) return;

  final data = <String, dynamic>{};
  final ok = await showFormSheet(
    context,
    title: 'Request leave',
    submitLabel: 'Submit',
    fields: (ctx) => [
      if (types.isNotEmpty)
        FSelect<Rec>(
          label: 'Leave type',
          options: types,
          labelOf: (t) => str(t['name'] ?? t['label']),
          onSaved: (t) => data['leave_type_id'] = t?['id'],
        )
      else
        FText(label: 'Type', required: true, onSaved: (v) => data['type'] = v),
      _DateField(
        label: 'Start date',
        onSaved: (v) => data['start_date'] = v,
      ),
      _DateField(
        label: 'End date',
        onSaved: (v) => data['end_date'] = v,
      ),
      FText(
        label: 'Reason',
        required: true,
        maxLines: 3,
        onSaved: (v) => data['reason'] = v,
      ),
    ],
    onSubmit: () => Api.post('/hr/leave', data: data),
  );
  if (ok) ref.invalidate(hrLeaveProvider);
}

class _DateField extends StatefulWidget {
  const _DateField({required this.label, required this.onSaved});
  final String label;
  final void Function(String) onSaved;
  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  DateTime? _date;
  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      validator: (_) => _date == null ? 'Pick a date' : null,
      onSaved: (_) => widget.onSaved(_date == null
          ? ''
          : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}'),
      builder: (state) => FField(
        label: widget.label,
        child: OutlinedButton.icon(
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _date ?? now,
              firstDate: now.subtract(const Duration(days: 30)),
              lastDate: now.add(const Duration(days: 365)),
            );
            if (picked != null) {
              setState(() => _date = picked);
              state.didChange(picked);
            }
          },
          icon: const Icon(Icons.calendar_today_rounded, size: 16),
          label: Text(_date == null
              ? 'Select'
              : '${_date!.day}/${_date!.month}/${_date!.year}'),
        ),
      ),
    );
  }
}
