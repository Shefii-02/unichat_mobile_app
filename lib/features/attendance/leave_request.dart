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
          label: 'Leave type — paid leave and other (unpaid) leave',
          // a type with no days left cannot be chosen; each shows paid / unpaid and what is left this year
          options: types.where((t) => t['left'] == null || (num.tryParse('${t['left']}') ?? 1) > 0).toList(),
          labelOf: (t) {
            final left = t['left'] == null ? 'no limit' : '${t['left']} left';
            final paid = (t['is_paid'] == true || t['is_paid'] == 1) ? 'Paid' : 'Unpaid';
            return '${str(t['name'] ?? t['label'])} · $paid · $left';
          },
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
    onSubmit: () {
      // check what can be checked on the phone first; the server checks again (overlaps, the yearly allowance)
      final a = DateTime.tryParse('${data['start_date']}');
      final b = DateTime.tryParse('${data['end_date']}');
      if (a != null && b != null) {
        if (b.isBefore(a)) throw Exception('The end date is before the start date.');
        final days = b.difference(a).inDays + 1;
        final type = types.where((t) => t['id'] == data['leave_type_id']).cast<Rec?>().firstWhere((_) => true, orElse: () => null);
        final left = type == null ? null : num.tryParse('${type['left'] ?? ''}');
        if (left != null && days > left) {
          throw Exception('Only $left day(s) of ${str(type?['name'])} left this year — you asked for $days.');
        }
      }
      return Api.post('/hr/leave', data: data);
    },
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
