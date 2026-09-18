// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Staff setup ══════════════════════════

/// Split out of the former shared `HrAdminPage` (tab 5, "Staff Setup").
class HrStaffSetupPage extends ConsumerWidget {
  const HrStaffSetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff Setups')),
      body: ProviderList(
      provider: hrStaffProfilesProvider,
      emptyLabel: 'No staff found',
      emptyIcon: Icons.groups_rounded,
      tile: (context, row) {
        final user = (row['user'] is Map) ? (row['user'] as Map).cast<String, dynamic>() : <String, dynamic>{};
        return RecordCard(
          title: str(user['name'], 'Staff'),
          subtitle: '${str(row['work_mode'], 'wfo').toUpperCase()} · ${str(row['attendance_type'], 'manual')}'
              '${row['monthly_target'] != null ? ' · Target ${money(row['monthly_target'])}' : ''}',
          leadingIcon: Icons.person_rounded,
          trailing: IconButton(icon: const Icon(Icons.edit_rounded, size: 18), onPressed: () => _edit(context, ref, user, row)),
        );
      },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec user, Rec profile) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: str(user['name'], 'Staff'),
      fields: (ctx) => [
        FSelect<String>(label: 'Attendance type', options: const ['manual', 'gps'],
            initial: str(profile['attendance_type'], 'manual'), onSaved: (v) => data['attendance_type'] = v),
        FSelect<String>(label: 'Work mode', options: const ['wfo', 'wfh', 'hybrid'],
            initial: str(profile['work_mode'], 'wfo'), onSaved: (v) => data['work_mode'] = v),
        FText(label: 'Duty start (HH:mm)', initial: profile['duty_start'] as String?, onSaved: (v) => v.isEmpty ? null : data['duty_start'] = v),
        FText(label: 'Duty end (HH:mm)', initial: profile['duty_end'] as String?, onSaved: (v) => v.isEmpty ? null : data['duty_end'] = v),
        FNumber(label: 'Monthly salary', initial: profile['monthly_salary'] as num?, onSaved: (v) => data['monthly_salary'] = v),
        FNumber(label: 'Monthly sales target', initial: profile['monthly_target'] as num?, onSaved: (v) => data['monthly_target'] = v),
      ],
      onSubmit: () => Api.put('/hr/staff-profiles/${user['id']}', data: data),
    );
    if (ok) ref.invalidate(hrStaffProfilesProvider);
  }
}

