// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'module_providers.dart';
import '_shared.dart';

// ══════════════════════════ Pipelines ══════════════════════════

const _triggerTypes = ['message', 'webhook', 'cron', 'manual'];
const _stepTypes = ['send_message', 'http_request', 'rag_query', 'condition', 'set_variable', 'delay'];

String _stepTypeLabel(String v) => switch (v) {
      'send_message' => 'Send Message',
      'http_request' => 'HTTP Request',
      'rag_query' => 'AI RAG Query',
      'condition' => 'Condition Check',
      'set_variable' => 'Set Variable',
      'delay' => 'Delay',
      _ => v,
    };

class PipelinesPage extends ConsumerWidget {
  const PipelinesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Pipelines')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New pipeline'),
      ),
      body: ProviderList(
        provider: aiPipelinesProvider,
        emptyLabel: 'No pipelines yet',
        emptyIcon: Icons.account_tree_rounded,
        tile: (context, p) {
          final steps = (p['steps'] is List) ? (p['steps'] as List).length : 0;
          return RecordCard(
            title: str(p['name']),
            subtitle: '${str(p['trigger_type'], 'manual')} trigger · $steps step(s) · ${p['runs_count'] ?? 0} runs',
            leadingIcon: Icons.account_tree_rounded,
            leadingColor: p['is_active'] == false ? null : AppPalette.success,
            trailing: RowMenu(items: [
              ('Run now', Icons.play_arrow_rounded, () async {
                final ok = await runAction(context, () => Api.post('/wa-agent/pipelines/${p['id']}/run', data: {'trigger_data': {}}),
                    success: 'Pipeline queued');
                if (ok) ref.invalidate(aiPipelinesProvider);
              }),
              ('View runs', Icons.history_rounded, () => _viewRuns(context, p)),
              ('Edit', Icons.edit_rounded, () => _openEditor(context, ref, p)),
              ('Delete', Icons.delete_outline_rounded, () async {
                final sure = await confirm(context, title: 'Delete "${p['name']}"?', destructive: true, confirmLabel: 'Delete');
                if (!sure) return;
                final done = await runAction(context, () => Api.delete('/wa-agent/pipelines/${p['id']}'), success: 'Deleted');
                if (done) ref.invalidate(aiPipelinesProvider);
              }),
            ]),
          );
        },
      ),
    );
  }

  void _viewRuns(BuildContext context, Rec pipeline) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PipelineRunsPage(pipeline: pipeline)));
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref, Rec? existing) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _PipelineEditorPage(existing: existing)),
    );
    if (changed == true) ref.invalidate(aiPipelinesProvider);
  }
}

class _PipelineRunsPage extends StatefulWidget {
  const _PipelineRunsPage({required this.pipeline});
  final Rec pipeline;
  @override
  State<_PipelineRunsPage> createState() => _PipelineRunsPageState();
}

class _PipelineRunsPageState extends State<_PipelineRunsPage> {
  List<Rec> _runs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Api.list('/wa-agent/pipelines/${widget.pipeline['id']}/runs');
      setState(() { _runs = rows; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.pipeline['name']} — Runs')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _runs.isEmpty
              ? Center(child: Text('No runs yet', style: TextStyle(color: context.mutedColor)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _runs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = _runs[i];
                      return RecordCard(
                        title: 'Run #${r['id']}',
                        subtitle: 'Started ${when(r['started_at'])}'
                            '${r['completed_at'] != null ? ' · Completed ${when(r['completed_at'])}' : ''}'
                            '${r['error_message'] != null ? ' · ${r['error_message']}' : ''}',
                        leadingIcon: Icons.play_circle_outline_rounded,
                        trailing: StatusPill(str(r['status'], 'pending')),
                      );
                    },
                  ),
                ),
    );
  }
}

class _PipelineEditorPage extends StatefulWidget {
  const _PipelineEditorPage({this.existing});
  final Rec? existing;
  @override
  State<_PipelineEditorPage> createState() => _PipelineEditorPageState();
}

class _PipelineEditorPageState extends State<_PipelineEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?['name'] as String? ?? '');
  late final _description = TextEditingController(text: widget.existing?['description'] as String? ?? '');
  late String _triggerType = str(widget.existing?['trigger_type'], 'manual');
  late bool _isActive = widget.existing?['is_active'] != false;
  late final List<Map<String, dynamic>> _steps = widget.existing?['steps'] is List
      ? (widget.existing!['steps'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
      : [
          {'type': 'send_message', 'session_id': '', 'phone': '{{contact_phone}}', 'message': ''}
        ];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _saving = true; _error = null; });
    final data = {
      'name': _name.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'trigger_type': _triggerType,
      'is_active': _isActive,
      'steps': _steps,
    };
    try {
      if (widget.existing == null) {
        await Api.post('/wa-agent/pipelines', data: data);
      } else {
        await Api.patch('/wa-agent/pipelines/${widget.existing!['id']}', data: data);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() { _saving = false; _error = apiErrorMessage(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New pipeline' : 'Edit pipeline')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _triggerType,
              decoration: const InputDecoration(labelText: 'Trigger'),
              items: _triggerTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => _triggerType = v ?? 'manual'),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: _isActive, onChanged: (v) => setState(() => _isActive = v)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Steps', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              TextButton.icon(
                onPressed: () => setState(() => _steps.add({'type': 'send_message', 'session_id': '', 'phone': '{{contact_phone}}', 'message': ''})),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add step'),
              ),
            ]),
            for (var i = 0; i < _steps.length; i++) _StepCard(
              index: i,
              step: _steps[i],
              onChanged: (updated) => setState(() => _steps[i] = updated),
              onRemove: _steps.length > 1 ? () => setState(() => _steps.removeAt(i)) : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppPalette.danger)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save pipeline'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.index, required this.step, required this.onChanged, this.onRemove});
  final int index;
  final Map<String, dynamic> step;
  final void Function(Map<String, dynamic>) onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final type = str(step['type'], 'send_message');
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Step ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const Spacer(),
            if (onRemove != null) IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: onRemove, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ]),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: type,
            isDense: true,
            decoration: const InputDecoration(isDense: true),
            items: _stepTypes.map((t) => DropdownMenuItem(value: t, child: Text(_stepTypeLabel(t)))).toList(),
            onChanged: (v) => onChanged({'type': v ?? 'send_message'}),
          ),
          const SizedBox(height: 8),
          if (type == 'send_message') ...[
            TextFormField(
              initialValue: str(step['session_id'], ''),
              decoration: const InputDecoration(labelText: 'Session ID', isDense: true),
              onChanged: (v) => onChanged({...step, 'session_id': v}),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: str(step['phone'], '{{contact_phone}}'),
              decoration: const InputDecoration(labelText: 'Phone', isDense: true),
              onChanged: (v) => onChanged({...step, 'phone': v}),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: str(step['message'], ''),
              decoration: const InputDecoration(labelText: 'Message', isDense: true),
              maxLines: 2,
              onChanged: (v) => onChanged({...step, 'message': v}),
            ),
          ] else if (type == 'http_request') ...[
            Row(children: [
              DropdownButtonFormField<String>(
                initialValue: str(step['method'], 'GET'),
                isDense: true,
                items: const ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => onChanged({...step, 'method': v ?? 'GET'}),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: str(step['url'], ''),
                  decoration: const InputDecoration(labelText: 'URL', isDense: true),
                  onChanged: (v) => onChanged({...step, 'url': v}),
                ),
              ),
            ]),
          ] else if (type == 'rag_query') ...[
            TextFormField(
              initialValue: str(step['query'], ''),
              decoration: const InputDecoration(labelText: 'Query', isDense: true, hintText: 'Use {{message}} for user input'),
              onChanged: (v) => onChanged({...step, 'query': v}),
            ),
          ] else if (type == 'delay') ...[
            TextFormField(
              initialValue: step['seconds']?.toString() ?? '',
              decoration: const InputDecoration(labelText: 'Seconds (1-30)', isDense: true),
              keyboardType: TextInputType.number,
              onChanged: (v) => onChanged({...step, 'seconds': int.tryParse(v)}),
            ),
          ] else
            Text('This step type has no configurable fields yet.', style: TextStyle(color: context.mutedColor, fontSize: 12)),
        ],
      ),
    );
  }
}

// ══════════════════════════ Lead Intelligence ══════════════════════════

class LeadIntelligencePage extends ConsumerStatefulWidget {
  const LeadIntelligencePage({super.key});
  @override
  ConsumerState<LeadIntelligencePage> createState() => _LeadIntelligencePageState();
}

class _LeadIntelligencePageState extends ConsumerState<LeadIntelligencePage> {
  List<Rec> _contacts = [];
  bool _loading = true;
  String? _stage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Api.list('/meta-ai/lead-scores', query: {
        if (_stage != null) 'stage': _stage,
      });
      setState(() { _contacts = rows; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(metaAiStatsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Lead Intelligence')),
      body: RefreshIndicator(
        onRefresh: () async { ref.invalidate(metaAiStatsProvider); await _load(); },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            statsAsync.when(
              loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text("Couldn't load stats — ${apiErrorMessage(e)}", style: TextStyle(color: context.mutedColor)),
              data: (s) => StatGrid([
                ('Analyzed', '${s['total_analyzed'] ?? 0}', Icons.psychology_rounded),
                ('Avg score', '${s['avg_lead_score'] ?? 0}', Icons.speed_rounded),
                ('Hot leads', '${s['hot_leads'] ?? 0}', Icons.local_fire_department_rounded),
                ('Conversions (mo)', '${s['conversions_month'] ?? 0}', Icons.emoji_events_rounded),
              ]),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 6, children: [
              ChoiceChip(label: const Text('All'), selected: _stage == null, onSelected: (_) { setState(() => _stage = null); _load(); }),
              for (final s in ['new', 'contacted', 'follow_up', 'enrolled', 'lost'])
                ChoiceChip(label: Text(s), selected: _stage == s, onSelected: (_) { setState(() => _stage = s); _load(); }),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator()))
            else if (_contacts.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Text('No analyzed contacts', style: TextStyle(color: context.mutedColor))))
            else
              ..._contacts.map((c) {
                final score = num.tryParse('${c['lead_score'] ?? 0}') ?? 0;
                return RecordCard(
                  title: str(c['name'], c['phone']),
                  subtitle: '${str(c['detected_intent'], 'unknown')} · ${str(c['last_sentiment'], 'neutral')} · ${str(c['score_label'], '')}',
                  leadingIcon: Icons.person_rounded,
                  leadingColor: score >= 70 ? AppPalette.danger : score >= 40 ? AppPalette.warning : AppPalette.info,
                  trailing: Text('${score.toInt()}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () => _showIntelligence(context, c),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _showIntelligence(BuildContext context, Rec contact) async {
    Rec? detail;
    String? error;
    try {
      detail = await Api.one('/contacts/${contact['id']}/intelligence');
    } catch (e) {
      error = apiErrorMessage(e);
    }
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: error != null
              ? [Text(error)]
              : [
                  Text(str(contact['name'], contact['phone']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 12),
                  KvRow('Lead score', '${detail?['lead_score'] ?? '—'} (${str(detail?['lead_score_label'], '')})'),
                  KvRow('Sentiment', str(detail?['last_sentiment'])),
                  KvRow('Intent', str(detail?['detected_intent'])),
                  KvRow('Buying signals', '${detail?['buying_signals_count'] ?? 0}'),
                  KvRow('Objections', '${detail?['objections_count'] ?? 0}'),
                  const SizedBox(height: 12),
                  if (detail?['conversation_summary'] != null) ...[
                    const Text('Summary', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(str(detail?['conversation_summary'])),
                    const SizedBox(height: 12),
                  ],
                  if (detail?['recommended_next_action'] != null) ...[
                    const Text('Recommended next action', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(str(detail?['recommended_next_action'])),
                  ],
                ],
        ),
      ),
    );
  }
}

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
