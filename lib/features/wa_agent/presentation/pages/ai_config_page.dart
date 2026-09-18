import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ AI Config ══════════════════════════

class AiConfigPage extends ConsumerStatefulWidget {
  const AiConfigPage({super.key});
  @override
  ConsumerState<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends ConsumerState<AiConfigPage> {
  static const _toggleFields = [
    ('is_enabled', 'AI analysis enabled'),
    ('meta_ai_enabled', 'Meta AI features enabled'),
    ('analyze_on_message', 'Analyze on every message'),
    ('analyze_sentiment', 'Analyze sentiment'),
    ('detect_buying_signals', 'Detect buying signals'),
    ('auto_qualify_leads', 'Auto-qualify leads'),
    ('auto_create_tasks', 'Auto-create follow-up tasks'),
    ('inject_company_profile', 'Inject company profile into prompts'),
    ('inject_services', 'Inject services into prompts'),
    ('inject_pricing', 'Inject pricing into prompts'),
    ('inject_past_conversations', 'Inject past conversations'),
  ];

  Map<String, dynamic> _values = {};
  bool _initialised = false;
  bool _saving = false;

  void _initFrom(Rec c) {
    if (_initialised) return;
    _initialised = true;
    _values = Map.of(c);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await runAction(context, () => Api.post('/meta-ai/config', data: _values), success: 'AI config saved');
    setState(() => _saving = false);
    if (ok) ref.invalidate(metaAiConfigProvider);
  }

  Future<void> _testAnalysis() async {
    final data = <String, dynamic>{};
    await showFormSheet(
      context,
      title: 'Test analysis',
      submitLabel: 'Run',
      fields: (ctx) => [
        FText(label: 'Message to analyze', required: true, maxLines: 3, onSaved: (v) => data['message'] = v),
      ],
      onSubmit: () => Api.post('/meta-ai/test-analysis', data: data),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Config'), actions: [
        IconButton(icon: const Icon(Icons.science_outlined), tooltip: 'Test analysis', onPressed: _testAnalysis),
      ]),
      body: ProviderObject(
        provider: metaAiConfigProvider,
        builder: (context, c) {
          _initFrom(c);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final f in _toggleFields)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(f.$2),
                  value: _values[f.$1] == true,
                  onChanged: (v) => setState(() => _values[f.$1] = v),
                ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: str(_values['meta_ai_model'], ''),
                decoration: const InputDecoration(labelText: 'Meta AI model'),
                onChanged: (v) => _values['meta_ai_model'] = v,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _values['hand_off_threshold']?.toString() ?? '',
                decoration: const InputDecoration(labelText: 'Hand-off threshold (0–1)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => _values['hand_off_threshold'] = double.tryParse(v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _values['max_context_messages']?.toString() ?? '',
                decoration: const InputDecoration(labelText: 'Max context messages (5–50)'),
                keyboardType: TextInputType.number,
                onChanged: (v) => _values['max_context_messages'] = int.tryParse(v),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save config'),
              ),
            ],
          );
        },
      ),
    );
  }
}

