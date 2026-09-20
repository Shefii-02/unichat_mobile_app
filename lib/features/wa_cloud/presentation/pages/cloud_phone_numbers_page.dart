// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// WA Cloud's "Phone Numbers" — official Meta WhatsApp Business API numbers, registered and
/// managed entirely through Laravel (`/phone-numbers`). Mirrors
/// frontend/src/pages/superadmin/PhoneNumbersPage.tsx (company-scoped despite living under the
/// web app's superadmin folder — the route itself carries no admin-only middleware). Unrelated
/// to WA Chat's open-wa `Sessions` (see wa_sessions_page.dart): different product, different
/// backend, no gateway involved here — Meta's own Cloud API is the "gateway" for this feature.
class CloudPhoneNumbersPage extends ConsumerWidget {
  const CloudPhoneNumbersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp Phone Numbers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editPhone(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add number'),
      ),
      body: ProviderList(
        provider: phoneNumbersProvider,
        emptyLabel: 'No phone numbers yet — add your WhatsApp Business phone number to start sending messages',
        emptyIcon: Icons.smartphone_rounded,
        header: Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppPalette.info.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: const Text(
            'Each phone number is a separate WhatsApp Business number. Your plan determines how many you can add.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        tile: (context, p) {
          final isDefault = p['is_default'] == true;
          final isActive = p['is_active'] != false;
          final status = str(p['status'], 'active');
          final lastVerified = p['last_verified_at'];
          return RecordCard(
            title: str(p['label'], 'Phone number'),
            subtitle: [
              str(p['phone_number_id'], ''),
              if (str(p['display_number'], '').isNotEmpty) p['display_number'],
              if (lastVerified != null) 'Verified ${when(str(lastVerified))}',
            ].join(' · '),
            leadingIcon: Icons.smartphone_rounded,
            leadingColor: isDefault ? AppPalette.success : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDefault) const StatusPill('default', color: AppPalette.success),
                const SizedBox(width: 4),
                StatusPill(status, color: status == 'error' ? AppPalette.danger : status == 'active' ? AppPalette.success : AppPalette.muted),
                const SizedBox(width: 4),
                if (!isActive) const StatusPill('inactive', color: AppPalette.muted),
                RowMenu(items: [
                  (
                    'Verify',
                    Icons.verified_rounded,
                    () async {
                      try {
                        final res = await Api.post('/phone-numbers/${p['id']}/verify');
                        final verified = res['verified'] == true;
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(verified ? 'Connection verified ✓' : 'Verification failed: ${str(res['error'], 'Unknown error')}'),
                            backgroundColor: verified ? AppPalette.success : AppPalette.danger,
                          ));
                        }
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
                      }
                      ref.invalidate(phoneNumbersProvider);
                    }
                  ),
                  if (!isDefault)
                    (
                      'Set default',
                      Icons.star_rounded,
                      () async {
                        final ok = await runAction(context, () => Api.post('/phone-numbers/${p['id']}/set-default'), success: 'Default number updated.');
                        if (ok) ref.invalidate(phoneNumbersProvider);
                      }
                    ),
                  ('Edit', Icons.edit_rounded, () => _editPhone(context, ref, p)),
                  if (!isDefault)
                    (
                      'Remove',
                      Icons.delete_rounded,
                      () async {
                        if (!await confirm(context,
                            title: 'Remove phone number?',
                            message: 'Remove "${str(p['label'])}"? Campaigns using this number will need to be updated.',
                            destructive: true,
                            confirmLabel: 'Remove')) {
                          return;
                        }
                        final ok = await runAction(context, () => Api.delete('/phone-numbers/${p['id']}'), success: 'Removed.');
                        if (ok) ref.invalidate(phoneNumbersProvider);
                      }
                    ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _editPhone(BuildContext context, WidgetRef ref, Rec? existing) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: existing == null ? 'Add WhatsApp phone number' : 'Edit phone number',
      submitLabel: existing == null ? 'Add' : 'Save',
      fields: (ctx) => [
        FText(label: 'Label', hint: 'e.g. Sales Line', required: true, initial: existing?['label'] as String?, onSaved: (v) => data['label'] = v),
        if (existing == null)
          FText(
            label: 'Phone Number ID (from Meta)',
            hint: '1132805489918168',
            required: true,
            onSaved: (v) => data['phone_number_id'] = v,
          )
        else
          FField(
            label: 'Phone Number ID',
            child: Text(str(existing['phone_number_id'], ''), style: const TextStyle(fontSize: 14)),
          ),
        FText(
          label: existing == null ? 'Access Token' : 'Access Token (leave blank to keep current)',
          hint: 'EAAOU8L2...',
          required: existing == null,
          obscure: true,
          onSaved: (v) => v.isEmpty ? null : data['access_token'] = v,
        ),
        if (existing == null)
          FText(label: 'Business Account ID (optional)', onSaved: (v) => v.isEmpty ? null : data['business_account_id'] = v),
        FText(
          label: 'Display Number (optional)',
          hint: '+91 80865 44828',
          keyboardType: TextInputType.phone,
          initial: existing?['display_number'] as String?,
          onSaved: (v) => data['display_number'] = v.isEmpty ? null : v,
        ),
        if (existing != null)
          FBoolField(label: 'Active', initial: existing['is_active'] != false, onSaved: (v) => data['is_active'] = v),
      ],
      onSubmit: () => existing == null ? Api.post('/phone-numbers', data: data) : Api.put('/phone-numbers/${existing['id']}', data: data),
    );
    if (ok) ref.invalidate(phoneNumbersProvider);
  }
}
