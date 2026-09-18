// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/core/constants/api_constants.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Settings (Meta credentials) ══════════════════════════

class WaCloudSettingsPage extends ConsumerWidget {
  const WaCloudSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('WA Cloud Settings')),
      body: ProviderObject(
        provider: waCloudSettingsProvider,
        builder: (context, c) {
          final connected = c['wa_connected'] == true;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.altSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.lineColor),
                ),
                child: Row(children: [
                  Icon(connected ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: connected ? AppPalette.success : AppPalette.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(connected ? 'Connected to Meta Cloud API' : 'Not connected',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              KvRow('Phone number ID', str(c['wa_phone_id'])),
              KvRow('Business account ID', str(c['wa_business_id'])),
              KvRow('Access token', c['wa_access_token'] != null && '${c['wa_access_token']}'.isNotEmpty ? '•••••••• (set)' : 'Not set'),
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: () => _editCredentials(context, ref, c),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit credentials'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _verify(context, ref),
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: const Text('Verify connection'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _testSend(context),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Test send'),
                ),
              ]),
              const SizedBox(height: 24),
              _webhookConfigCard(context, c),
            ],
            ),
          );
        },
      ),
    );
  }

  Widget _webhookConfigCard(BuildContext context, Rec c) {
    final callbackUrl = '${ApiConstants.laravelOrigin}/api/v1/webhook/whatsapp';
    final verifyToken = str(c['webhook_verify_token'], '');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Webhook Config', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          Text('Callback URL — paste in Meta Developer Console → Webhooks:', style: TextStyle(fontSize: 12, color: context.mutedColor)),
          const SizedBox(height: 4),
          _copyableCode(context, callbackUrl),
          const SizedBox(height: 14),
          Text('Verify Token:', style: TextStyle(fontSize: 12, color: context.mutedColor)),
          const SizedBox(height: 4),
          _copyableCode(context, verifyToken.isEmpty ? 'Ask from Support Team — WHATSAPP_VERIFY_TOKEN' : verifyToken),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppPalette.info.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: const Text(
              'Subscribe to these webhook fields in Meta: messages · message_template_status_update · message_template_quality_update · calls (for Inbox Analytics call stats)',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _copyableCode(BuildContext context, String value) {
    return Row(children: [
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(6)),
          child: SelectableText(value, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.copy_rounded, size: 16),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
        },
      ),
    ]);
  }

  Future<void> _editCredentials(BuildContext context, WidgetRef ref, Rec c) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Meta Cloud API credentials',
      fields: (ctx) => [
        FText(label: 'Phone number ID', initial: c['wa_phone_id'] as String?, required: true,
            onSaved: (v) => data['wa_phone_id'] = v),
        FText(label: 'Access token', required: true, maxLines: 3,
            hint: 'Paste the permanent or long-lived Meta access token',
            onSaved: (v) => data['wa_access_token'] = v),
        FText(label: 'Business account ID', initial: c['wa_business_id'] as String?,
            onSaved: (v) => v.isEmpty ? null : data['wa_business_id'] = v),
      ],
      onSubmit: () => Api.post('/settings/wa-credentials', data: data),
    );
    if (ok) ref.invalidate(waCloudSettingsProvider);
  }

  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    try {
      final res = await Api.one('/settings/verify-wa');
      if (!context.mounted) return;
      final ok = res['connected'] == true;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(ok ? 'Connected' : 'Not connected'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: ok
                ? [
                    KvRow('Phone number', str(res['phone_number'])),
                    KvRow('Verified name', str(res['verified_name'])),
                    KvRow('Quality rating', str(res['quality_rating'])),
                    KvRow('Messaging tier', str(res['messaging_limit_tier'])),
                  ]
                : [Text(str(res['error'], 'Could not verify credentials.'))],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _testSend(BuildContext context) async {
    final data = <String, dynamic>{};
    await showFormSheet(
      context,
      title: 'Send a test message',
      submitLabel: 'Send',
      fields: (ctx) => [
        FText(label: 'Phone number (digits only, with country code)', required: true,
            keyboardType: TextInputType.phone, onSaved: (v) => data['phone'] = v),
        FText(label: 'Message', maxLines: 3, onSaved: (v) => v.isEmpty ? null : data['message'] = v),
      ],
      onSubmit: () => Api.post('/settings/test-send', data: data),
    );
  }
}

