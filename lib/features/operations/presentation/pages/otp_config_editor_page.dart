// The "Auth OTP API" / "Utility" / "Invoice Share" tabs of the Api Service page — full CRUD for
// `wa_api_configs` rows, mirroring frontend/src/pages/wa-chat/components/ApiConfigManager.tsx.
// One list widget + one editor page, parameterized by `kind` ('auth' | 'utility' | 'invoice').
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

const _kindTitles = {
  'auth': 'Auth OTP API',
  'utility': 'Utility Message API',
  'invoice': 'Invoice / Document Share API',
};
const _kindSubtitles = {
  'auth': 'Named OTP configurations. Clients pick one with the "service" field; template, code length, expiry and attempt cap come from here.',
  'utility': 'Named utility-message configurations. Choose a prebuilt template or supply custom content.',
  'invoice': 'Named document configurations — a file URL plus a default filename and caption.',
};
const _kindEmptyHints = {
  'auth': 'No OTP configs yet.',
  'utility': 'No utility configs yet.',
  'invoice': 'No invoice configs yet.',
};

class ApiConfigListTab extends StatefulWidget {
  const ApiConfigListTab({super.key, required this.kind});
  final String kind;
  @override
  State<ApiConfigListTab> createState() => _ApiConfigListTabState();
}

class _ApiConfigListTabState extends State<ApiConfigListTab> {
  List<Rec>? _configs;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final configs = await Api.list('/otp-service/configs', query: {'kind': widget.kind});
      if (mounted) setState(() { _configs = configs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  Future<void> _openEditor({Rec? existing}) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ApiConfigEditorPage(kind: widget.kind, existing: existing),
    ));
    if (changed == true) _load();
  }

  Future<void> _delete(Rec c) async {
    if (!await confirm(context, title: 'Delete config?', message: 'Delete "${str(c['name'])}"? This cannot be undone.', destructive: true, confirmLabel: 'Delete')) {
      return;
    }
    final ok = await runAction(context, () => Api.delete('/otp-service/configs/${c['id']}'), success: 'Deleted');
    if (ok) _load();
  }

  Future<void> _showStats(Rec c) async {
    Rec stats;
    try {
      stats = await Api.one('/otp-service/configs/${c['id']}/stats');
      final inner = stats['data'];
      if (inner is Map) stats = inner.cast<String, dynamic>();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(context: context, showDragHandle: true, builder: (ctx) => _StatsSheet(stats: stats));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_kindTitles[widget.kind]!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(_kindSubtitles[widget.kind]!, style: TextStyle(fontSize: 12, color: context.mutedColor)),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New Config'),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("Couldn't load configs — $_error", textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      );
    }
    final configs = _configs ?? [];
    if (configs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          const SizedBox(height: 60),
          Center(
            child: Column(children: [
              Icon(Icons.description_outlined, size: 36, color: context.mutedColor.withValues(alpha: 0.4)),
              const SizedBox(height: 8),
              Text(_kindEmptyHints[widget.kind]!, style: TextStyle(color: context.mutedColor)),
            ]),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: configs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _configCard(configs[i]),
      ),
    );
  }

  Widget _configCard(Rec c) {
    final active = c['is_active'] != false;
    final tpl = c['prebuilt_template'] as Map?;
    final customContent = str(c['custom_content'], '');
    final caption = str(c['caption'], '');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(str(c['name']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            if (!active) const Text('inactive', style: TextStyle(color: AppPalette.danger, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (tpl != null)
              StatusPill('${str(tpl['name'])} · ${str(tpl['language'])}', color: AppPalette.info)
            else if (customContent.isNotEmpty)
              StatusPill('custom content', color: AppPalette.muted)
            else if (widget.kind == 'invoice')
              StatusPill(caption.isNotEmpty ? 'file + caption' : 'file only', color: AppPalette.muted),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 2, children: [
            if (widget.kind == 'auth') ...[
              Text('Length: ${c['otp_length'] ?? 6}', style: TextStyle(fontSize: 11, color: context.mutedColor)),
              Text('Expiry: ${c['otp_expiry_minutes'] ?? 10}m', style: TextStyle(fontSize: 11, color: context.mutedColor)),
              Text('Attempts: ${c['max_attempts'] ?? 5}', style: TextStyle(fontSize: 11, color: context.mutedColor)),
            ],
            Text('Session: ${str(c['session_id'], 'default')}', style: TextStyle(fontSize: 11, color: context.mutedColor)),
          ]),
          if (customContent.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(customContent, style: const TextStyle(fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis)),
          if (widget.kind == 'invoice' && caption.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(caption, style: const TextStyle(fontSize: 13))),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(
              onPressed: () => _showStats(c),
              icon: const Icon(Icons.bar_chart_rounded, size: 14),
              label: const Text('Stats', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
            ),
            TextButton(
              onPressed: () => _openEditor(existing: c),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
              child: const Text('Edit', style: TextStyle(fontSize: 12)),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => _delete(c),
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppPalette.danger),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(6),
            ),
          ]),
        ],
      ),
    );
  }
}

class _StatsSheet extends StatelessWidget {
  const _StatsSheet({required this.stats});
  final Rec stats;

  @override
  Widget build(BuildContext context) {
    final byAction = (stats['by_action'] as Map?) ?? {};
    final byCodeStatus = (stats['by_code_status'] as Map?) ?? {};
    final lastUsed = stats['last_used_at'];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Usage', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _tile(context, 'Total', '${stats['total'] ?? 0}'),
              _tile(context, 'Last 30 days', '${stats['last_30_days'] ?? 0}'),
              for (final e in byAction.entries) _tile(context, '${e.key}', '${e.value}'),
            ]),
            if (byCodeStatus.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('OTP CODE STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.mutedColor, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [for (final e in byCodeStatus.entries) _tile(context, '${e.key}', '${e.value}')]),
            ],
            const SizedBox(height: 16),
            Text('Last used: ${lastUsed != null ? when(str(lastUsed)) : '—'}', style: TextStyle(fontSize: 12, color: context.mutedColor)),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, String label, String value) => Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppPalette.accent)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
        ]),
      );
}

/// Create/edit form for one config. A full page (not a bottom sheet) because the field set
/// reacts to a mode switch (template vs custom content / file vs file+caption) and to a
/// language-filtered template picker — richer than the generic `showFormSheet` supports.
class ApiConfigEditorPage extends StatefulWidget {
  const ApiConfigEditorPage({super.key, required this.kind, this.existing});
  final String kind;
  final Rec? existing;

  @override
  State<ApiConfigEditorPage> createState() => _ApiConfigEditorPageState();
}

class _ApiConfigEditorPageState extends State<ApiConfigEditorPage> {
  bool get _editing => widget.existing != null;

  late final _nameCtrl = TextEditingController(text: str(widget.existing?['name'], ''));
  late final _customContentCtrl = TextEditingController(text: str(widget.existing?['custom_content'], ''));
  late final _captionCtrl = TextEditingController(text: str(widget.existing?['caption'], ''));
  late int _otpLength = (widget.existing?['otp_length'] as num?)?.toInt() ?? 6;
  late int _otpExpiry = (widget.existing?['otp_expiry_minutes'] as num?)?.toInt() ?? 10;
  late int _maxAttempts = (widget.existing?['max_attempts'] as num?)?.toInt() ?? 5;
  late String? _sessionId = str(widget.existing?['session_id'], '').isEmpty ? null : str(widget.existing?['session_id']);
  late bool _isActive = widget.existing?['is_active'] != false;

  late int? _selectedTemplateId = (widget.existing?['prebuilt_template_id'] as num?)?.toInt();
  late String _utilMode = str(widget.existing?['custom_content'], '').isNotEmpty ? 'custom' : 'template';
  late String _invMode = str(widget.existing?['caption'], '').isNotEmpty ? 'file_text' : 'file';

  List<Rec>? _templates;
  List<Rec>? _sessions;
  bool _loadingMeta = true;
  bool _saving = false;
  String? _saveError;

  final _tplSearchCtrl = TextEditingController();
  late String _tplLang = str((widget.existing?['prebuilt_template'] as Map?)?['language'], 'en');

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _customContentCtrl.dispose();
    _captionCtrl.dispose();
    _tplSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final results = await Future.wait([
        if (widget.kind != 'invoice') Api.list('/otp-service/prebuilt-templates', query: {'type': widget.kind}) else Future.value(<Rec>[]),
        Api.list('/otp-service/sessions'),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0];
        _sessions = results[1];
        _loadingMeta = false;
        if (_sessionId == null) {
          final connected = _sessions!.where((s) => s['connected'] == true);
          if (connected.isNotEmpty) _sessionId = str(connected.first['id']);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  bool get _canSave {
    if (_saving || _nameCtrl.text.trim().isEmpty || _sessionId == null) return false;
    if (widget.kind == 'auth' && _selectedTemplateId == null) return false;
    if (widget.kind == 'utility') {
      if (_utilMode == 'template' && _selectedTemplateId == null) return false;
      if (_utilMode == 'custom' && _customContentCtrl.text.trim().isEmpty) return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() { _saving = true; _saveError = null; });
    final data = <String, dynamic>{
      'kind': widget.kind,
      'name': _nameCtrl.text.trim(),
      'is_active': _isActive,
      'session_id': _sessionId,
    };
    if (widget.kind == 'auth') {
      data['prebuilt_template_id'] = _selectedTemplateId;
      data['otp_length'] = _otpLength;
      data['otp_expiry_minutes'] = _otpExpiry;
      data['max_attempts'] = _maxAttempts;
    }
    if (widget.kind == 'utility') {
      final useTpl = _utilMode == 'template';
      data['prebuilt_template_id'] = useTpl ? _selectedTemplateId : null;
      data['custom_content'] = useTpl ? null : (_customContentCtrl.text.trim().isEmpty ? null : _customContentCtrl.text.trim());
    }
    if (widget.kind == 'invoice') {
      data['caption'] = _invMode == 'file_text' ? (_captionCtrl.text.trim().isEmpty ? null : _captionCtrl.text.trim()) : null;
    }
    try {
      if (_editing) {
        await Api.patch('/otp-service/configs/${widget.existing!['id']}', data: data);
      } else {
        await Api.post('/otp-service/configs', data: data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_editing ? 'Config updated' : 'Config created')));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _saveError = apiErrorMessage(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit Config' : 'New Config')),
      body: _loadingMeta
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                TextField(
                  controller: _nameCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Config Name', hintText: 'the "service" value clients send'),
                ),
                const SizedBox(height: 16),
                if (widget.kind == 'auth') _templatePicker(),
                if (widget.kind == 'utility') _utilitySection(),
                if (widget.kind == 'auth') _otpFields(),
                if (widget.kind == 'invoice') _invoiceSection(),
                const SizedBox(height: 8),
                _sessionDropdown(),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  title: const Text('Active', style: TextStyle(fontSize: 13)),
                ),
                if (_saveError != null)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text(_saveError!, style: const TextStyle(color: AppPalette.danger, fontSize: 12))),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ],
            ),
    );
  }

  Widget _templatePicker() {
    final templates = _templates ?? [];
    final languages = {for (final t in templates) str(t['language'], 'en')}.toList()..sort();
    final langs = languages.isEmpty ? ['en'] : languages;
    final effectiveLang = langs.contains(_tplLang) ? _tplLang : langs.first;
    final q = _tplSearchCtrl.text.trim().toLowerCase();
    final filtered = templates.where((t) => str(t['language'], 'en') == effectiveLang).where((t) {
      if (q.isEmpty) return true;
      return ('${str(t['name'])} ${str(t['content'])}').toLowerCase().contains(q);
    }).toList();
    final selected = templates.where((t) => t['id'] == _selectedTemplateId).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Template', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor)),
          const SizedBox(height: 6),
          Row(children: [
            DropdownButton<String>(
              value: effectiveLang,
              items: langs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setState(() => _tplLang = v ?? 'en'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _tplSearchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Search templates…', isDense: true),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            height: 240,
            decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(8)),
            child: filtered.isEmpty
                ? Center(child: Text('No $effectiveLang templates', style: TextStyle(color: context.mutedColor, fontSize: 12)))
                : ListView.separated(
                    padding: const EdgeInsets.all(6),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final t = filtered[i];
                      final sel = t['id'] == _selectedTemplateId;
                      return InkWell(
                        onTap: () => setState(() {
                          _selectedTemplateId = t['id'] as int?;
                          if (widget.kind == 'utility') _customContentCtrl.clear();
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: sel ? AppPalette.accent : context.lineColor),
                            borderRadius: BorderRadius.circular(6),
                            color: sel ? AppPalette.accent.withValues(alpha: 0.08) : null,
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 14, color: sel ? AppPalette.accent : context.mutedColor),
                              const SizedBox(width: 6),
                              Expanded(child: Text(str(t['name']), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? AppPalette.accent : null))),
                            ]),
                            const SizedBox(height: 2),
                            Text(str(t['content'], ''), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: context.mutedColor)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          if (selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Selected: ${str(selected.first['name'])} (${str(selected.first['language'])})', style: TextStyle(fontSize: 11, color: context.mutedColor)),
            ),
        ],
      ),
    );
  }

  Widget _utilitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: 'template',
              groupValue: _utilMode,
              onChanged: (v) => setState(() => _utilMode = v ?? 'template'),
              title: const Text('Template', style: TextStyle(fontSize: 13)),
            ),
          ),
          Expanded(
            child: RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: 'custom',
              groupValue: _utilMode,
              onChanged: (v) => setState(() => _utilMode = v ?? 'custom'),
              title: const Text('Custom content', style: TextStyle(fontSize: 13)),
            ),
          ),
        ]),
        if (_utilMode == 'template')
          _templatePicker()
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: _customContentCtrl,
              onChanged: (_) => setState(() {}),
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Custom Content', hintText: 'Write the message… {{company_name}} {{date}} supported'),
            ),
          ),
      ],
    );
  }

  Widget _otpFields() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        Expanded(
          child: TextField(
            keyboardType: TextInputType.number,
            controller: TextEditingController(text: '$_otpLength'),
            decoration: const InputDecoration(labelText: 'OTP Length', isDense: true),
            onChanged: (v) => _otpLength = int.tryParse(v) ?? 6,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            keyboardType: TextInputType.number,
            controller: TextEditingController(text: '$_otpExpiry'),
            decoration: const InputDecoration(labelText: 'Expiry (min)', isDense: true),
            onChanged: (v) => _otpExpiry = int.tryParse(v) ?? 10,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            keyboardType: TextInputType.number,
            controller: TextEditingController(text: '$_maxAttempts'),
            decoration: const InputDecoration(labelText: 'Max Attempts', isDense: true),
            onChanged: (v) => _maxAttempts = int.tryParse(v) ?? 5,
          ),
        ),
      ]),
    );
  }

  Widget _invoiceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(8)),
          child: Text(
            'The file URL and filename are passed per request through the /api-service/invoice-share API. This config only sets the session and an optional default caption.',
            style: TextStyle(fontSize: 11, color: context.mutedColor),
          ),
        ),
        Row(children: [
          Expanded(
            child: RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: 'file',
              groupValue: _invMode,
              onChanged: (v) => setState(() => _invMode = v ?? 'file'),
              title: const Text('File only', style: TextStyle(fontSize: 13)),
            ),
          ),
          Expanded(
            child: RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: 'file_text',
              groupValue: _invMode,
              onChanged: (v) => setState(() => _invMode = v ?? 'file_text'),
              title: const Text('File + caption', style: TextStyle(fontSize: 13)),
            ),
          ),
        ]),
        if (_invMode == 'file_text')
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: _captionCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Default Caption', hintText: 'Please find your invoice attached.'),
            ),
          ),
      ],
    );
  }

  Widget _sessionDropdown() {
    final connected = (_sessions ?? []).where((s) => s['connected'] == true).toList();
    final missing = _sessionId != null && !connected.any((s) => str(s['id']) == _sessionId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WhatsApp Session', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _sessionId,
          isExpanded: true,
          hint: const Text('Select a connected session'),
          items: [
            ...connected.map((s) {
              final displayName = str(s['display_name'], '');
              final id = str(s['id']);
              final label = (displayName.isNotEmpty && displayName != id) ? '$displayName — $id' : id;
              final phone = str(s['phone'], '');
              return DropdownMenuItem(value: id, child: Text('$label${phone.isNotEmpty ? ' · $phone' : ''}', overflow: TextOverflow.ellipsis));
            }),
            if (missing) DropdownMenuItem(value: _sessionId, child: Text('$_sessionId (offline / not found)')),
          ],
          onChanged: (v) => setState(() => _sessionId = v),
        ),
        if (connected.isEmpty && !missing)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('No WhatsApp Chat sessions found — add one on the Sessions page first.', style: TextStyle(fontSize: 11, color: AppPalette.warning)),
          ),
      ],
    );
  }
}
