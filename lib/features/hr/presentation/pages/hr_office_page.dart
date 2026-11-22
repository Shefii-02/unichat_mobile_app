// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Office (settings) ══════════════════════════

/// Split out of the former shared `HrAdminPage` (tab 8, "Office").
class HrOfficePage extends ConsumerWidget {
  const HrOfficePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Office Details')),
      body: ProviderObject(
      provider: hrSettingsProvider,
      builder: (context, s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KvRow('Office hours', '${str(s['office_start'])} – ${str(s['office_end'])}'),
          KvRow('Geofence radius', '${s['geofence_radius_m'] ?? '—'} m'),
          KvRow('Geofence mandatory', s['geofence_mandatory'] == true ? 'Yes' : 'No'),
          KvRow('Late grace', '${s['grace_minutes'] ?? 0} min'),
          KvRow('Late clock-in reason', _lateNoteLabel(_lateNoteMode(s))),
          KvRow('Selfie photos stored in', _storageLabel(_selfieStorage(s))),
          KvRow('Attendance Google Sheet', s['attendance_sheet_enabled'] == true ? 'On' : 'Off'),
          KvRow('Timezone', str(s['timezone'])),
          KvRow('Reopen requests', s['reopen_auto_approve'] == true ? 'Auto-approved' : 'Needs manager approval'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _editSettings(context, ref, s),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Edit office details'),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _editSettings(BuildContext context, WidgetRef ref, Rec s) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Office details',
      fields: (ctx) => [
        FText(label: 'Office start (HH:mm)', initial: (s['office_start'] as String?)?.substring(0, 5), onSaved: (v) => v.isEmpty ? null : data['office_start'] = v),
        FText(label: 'Office end (HH:mm)', initial: (s['office_end'] as String?)?.substring(0, 5), onSaved: (v) => v.isEmpty ? null : data['office_end'] = v),
        FNumber(label: 'Geofence radius (m)', initial: s['geofence_radius_m'] as num?, onSaved: (v) => data['geofence_radius_m'] = v),
        FNumber(label: 'Late grace (minutes)', initial: s['grace_minutes'] as num?, onSaved: (v) => data['grace_minutes'] = v),
        FSelect<String>(
          label: 'Late clock-in reason',
          options: const ['required', 'optional', 'off'],
          initial: _lateNoteMode(s),
          labelOf: _lateNoteLabel,
          onSaved: (v) => data['late_note_mode'] = v ?? 'required',
        ),
        FSelect<String>(
          label: 'Selfie photos are stored in',
          options: const ['media_library', 'google_drive'],
          initial: _selfieStorage(s),
          labelOf: _storageLabel,
          onSaved: (v) => data['selfie_storage'] = v ?? 'media_library',
        ),
        FBoolField(
          label: 'Also save attendance to a Google Sheet',
          hint: 'Every clock in/out and break is added as a row as it happens. Needs Google Sheets in the plan and a connected Google account. Google Drive for selfies needs Drive in the plan and a connected account too.',
          initial: s['attendance_sheet_enabled'] == true,
          onSaved: (v) => data['attendance_sheet_enabled'] = v,
        ),
        FText(label: 'Timezone', initial: s['timezone'] as String?, onSaved: (v) => v.isEmpty ? null : data['timezone'] = v),
        FBoolField(
          label: 'Auto-approve reopen requests',
          hint: "Off: a manager must approve each \"accidentally clocked out\" request. On: it's granted instantly.",
          initial: s['reopen_auto_approve'] == true,
          onSaved: (v) => data['reopen_auto_approve'] = v,
        ),
      ],
      onSubmit: () => Api.put('/hr/settings', data: data),
    );
    if (ok) ref.invalidate(hrSettingsProvider);
  }

  static String _selfieStorage(Rec s) => s['selfie_storage'] == 'google_drive' ? 'google_drive' : 'media_library';

  static String _storageLabel(String m) => m == 'google_drive' ? 'Google Drive' : 'Media Library';

  static String _lateNoteMode(Rec s) {
    final m = s['late_note_mode'];
    if (m == 'required' || m == 'optional' || m == 'off') return m as String;
    return s['require_late_note'] == false ? 'off' : 'required';
  }

  static String _lateNoteLabel(String m) => switch (m) {
        'required' => 'Required',
        'optional' => 'Optional (can skip)',
        _ => 'Off (never asked)',
      };
}
