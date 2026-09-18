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
}
