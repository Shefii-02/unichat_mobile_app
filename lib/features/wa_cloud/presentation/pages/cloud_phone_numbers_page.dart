// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// WA Cloud's "Phone Numbers" — official Meta WhatsApp Business API numbers, registered and
/// managed entirely through Laravel (`/phone-numbers`). Unrelated to WA Chat's open-wa
/// `Sessions` (see wa_sessions_page.dart): different product, different backend, no gateway
/// involved here at all — Meta's own Cloud API is the "gateway" for this feature.
class CloudPhoneNumbersPage extends ConsumerWidget {
  const CloudPhoneNumbersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phone Numbers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newPhone(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add number'),
      ),
      body: ProviderList(
        provider: phoneNumbersProvider,
        emptyLabel: 'No cloud numbers',
        emptyIcon: Icons.smartphone_rounded,
        tile: (context, p) => RecordCard(
          title: str(p['display_number'] ?? p['label'] ?? p['phone']),
          subtitle:
              '${str(p['verified_name'] ?? p['label'])} · quality ${str(p['quality_rating'] ?? p['quality'])}',
          leadingIcon: Icons.smartphone_rounded,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p['is_default'] == true)
                const StatusPill('default')
              else
                StatusPill(str(p['status'], 'active')),
              RowMenu(items: [
                (
                  'Verify',
                  Icons.verified_rounded,
                  () async {
                    final ok = await runAction(context,
                        () => Api.post('/phone-numbers/${p['id']}/verify'),
                        success: 'Verification requested');
                    if (ok) ref.invalidate(phoneNumbersProvider);
                  }
                ),
                if (p['is_default'] != true)
                  (
                    'Set default',
                    Icons.star_rounded,
                    () async {
                      final ok = await runAction(
                          context,
                          () => Api.post(
                              '/phone-numbers/${p['id']}/set-default'),
                          success: 'Set as default');
                      if (ok) ref.invalidate(phoneNumbersProvider);
                    }
                  ),
                (
                  'Delete',
                  Icons.delete_rounded,
                  () async {
                    if (!await confirm(context,
                        title: 'Remove number?',
                        destructive: true,
                        confirmLabel: 'Remove')) { return; }
                    final ok = await runAction(context,
                        () => Api.delete('/phone-numbers/${p['id']}'),
                        success: 'Removed');
                    if (ok) ref.invalidate(phoneNumbersProvider);
                  }
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _newPhone(BuildContext context, WidgetRef ref) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Add cloud number',
      submitLabel: 'Add',
      fields: (ctx) => [
        FText(label: 'Label', required: true, onSaved: (v) => data['label'] = v),
        FText(
          label: 'Phone number ID',
          required: true,
          hint: 'From Meta WhatsApp Manager',
          onSaved: (v) => data['phone_number_id'] = v,
        ),
        FText(
          label: 'Access token',
          required: true,
          obscure: true,
          onSaved: (v) => data['access_token'] = v,
        ),
        FText(
          label: 'Business account ID',
          onSaved: (v) => v.isEmpty ? null : data['business_account_id'] = v,
        ),
        FText(
          label: 'Display number',
          keyboardType: TextInputType.phone,
          onSaved: (v) => v.isEmpty ? null : data['display_number'] = v,
        ),
      ],
      onSubmit: () => Api.post('/phone-numbers', data: data),
    );
    if (ok) ref.invalidate(phoneNumbersProvider);
  }
}
