import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

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

