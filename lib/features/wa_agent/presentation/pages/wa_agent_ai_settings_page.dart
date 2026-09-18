import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ WA Agent Settings (provider / model) ══════════════════════════

class WaAgentAiSettingsPage extends ConsumerWidget {
  const WaAgentAiSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('WA Agent Settings')),
      body: ProviderObject(
        provider: waAgentAiSettingsProvider,
        builder: (context, s) {
          final providers = (s['providers'] is List) ? s['providers'] as List : const [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  KvRow('Active provider', str(s['active_provider'])),
                  KvRow('Active model', str(s['active_model'])),
                  KvRow('Source', str(s['resolved_source'])),
                ]),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _editProvider(context, ref, s),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Change provider / model'),
              ),
              const SizedBox(height: 20),
              const Text('Providers', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              ...providers.map((p) {
                final m = p as Map;
                return RecordCard(
                  title: str(m['provider']),
                  subtitle: 'Source: ${str(m['source'], 'none')}'
                      '${m['has_company_key'] == true ? ' · Company key set' : ''}'
                      '${m['has_platform_key'] == true ? ' · Platform key available' : ''}',
                  leadingIcon: Icons.smart_toy_rounded,
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editProvider(BuildContext context, WidgetRef ref, Rec settings) async {
    List<Rec> models;
    List<Rec> apiKeys;
    try {
      models = await Api.list('/wa-agent/available-models');
      apiKeys = await Api.list('/settings/api-keys');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'AI provider & model',
      fields: (ctx) => [
        FSelect<Rec>(label: 'Provider', options: models,
            labelOf: (m) => str(m['provider']),
            onSaved: (m) => data['ai_provider'] = m?['provider']),
        FText(label: 'Model', initial: settings['active_model'] as String?, onSaved: (v) => v.isEmpty ? null : data['ai_model'] = v),
        if (apiKeys.isNotEmpty)
          FSelect<Rec>(label: 'API key (optional override)', options: apiKeys,
              labelOf: (k) => str(k['name'] ?? k['provider']),
              onSaved: (k) {
                final provider = str(k?['provider'], '');
                if (provider == 'openai') data['openai_key_id'] = k?['id'];
                if (provider == 'anthropic') data['anthropic_key_id'] = k?['id'];
              }),
      ],
      onSubmit: () => Api.post('/wa-agent/config', data: data),
    );
    if (ok) ref.invalidate(waAgentAiSettingsProvider);
  }
}
