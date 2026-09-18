// The "Auth OTP API" / "Utility" / "Invoice Share" tabs of WA Cloud's Api Service page —
// mirrors frontend/src/pages/wa-cloud/components/WaCloudApiConfigManager.tsx. Unlike the
// WA Chat (open-wa) version, every config here is backed by a real Meta message template that
// must be submitted for approval — so each row carries a `template_status` lifecycle
// (draft → pending → approved/rejected) with Submit/Resubmit + Sync actions, and there is no
// WhatsApp "session" concept (WA Cloud has one company-wide Meta phone number).
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

const _kindTitles = {
  'auth': 'Auth OTP API',
  'utility': 'Utility Message API',
  'invoice': 'Invoice / Document Share API',
};
const _kindSubtitles = {
  'auth': 'Named OTP configurations. Each registers an AUTHENTICATION template with Meta; clients pick one with the "service" field.',
  'utility': 'Named utility-message configurations. Each registers a UTILITY template with Meta.',
  'invoice': 'Named document configurations — a UTILITY template with a document header. Upload a sample document before submitting.',
};
const _kindEmptyHints = {
  'auth': 'No OTP configs yet.',
  'utility': 'No utility configs yet.',
  'invoice': 'No invoice configs yet.',
};

const _statusColors = {
  'approved': AppPalette.success,
  'pending': AppPalette.warning,
  'draft': AppPalette.muted,
  'rejected': AppPalette.danger,
  'error': AppPalette.danger,
};
const _lockedStatuses = {'approved', 'pending', 'pending_deletion', 'disabled'};

class WaCloudApiConfigListTab extends StatefulWidget {
  const WaCloudApiConfigListTab({super.key, required this.kind});
  final String kind;
  @override
  State<WaCloudApiConfigListTab> createState() => _WaCloudApiConfigListTabState();
}

class _WaCloudApiConfigListTabState extends State<WaCloudApiConfigListTab> {
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
      final configs = await Api.list('/wa-cloud/otp-service/configs', query: {'kind': widget.kind});
      if (mounted) setState(() { _configs = configs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  Future<void> _openEditor({Rec? existing}) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => WaCloudApiConfigEditorPage(kind: widget.kind, existing: existing),
    ));
    if (changed == true) _load();
  }

  Future<void> _delete(Rec c) async {
    if (!await confirm(context, title: 'Delete config?', message: 'Delete "${str(c['name'])}"? The Meta template is also deleted.', destructive: true, confirmLabel: 'Delete')) {
      return;
    }
    final ok = await runAction(context, () => Api.delete('/wa-cloud/otp-service/configs/${c['id']}'), success: 'Deleted');
    if (ok) _load();
  }

  Future<void> _submit(Rec c) async {
    final ok = await runAction(context, () => Api.post('/wa-cloud/otp-service/configs/${c['id']}/submit'), success: 'Submitted to Meta');
    if (ok) _load();
  }

  Future<void> _sync(Rec c) async {
    final ok = await runAction(context, () => Api.post('/wa-cloud/otp-service/configs/${c['id']}/sync'), success: 'Synced from Meta');
    if (ok) _load();
  }

  Future<void> _uploadSample(Rec c) async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: false);
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final form = FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: picked!.files.single.name)});
      await Api.raw.post('/wa-cloud/otp-service/configs/${c['id']}/upload-header-media', data: form);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sample document uploaded')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _showStats(Rec c) async {
    Rec stats;
    try {
      final res = await Api.one('/wa-cloud/otp-service/configs/${c['id']}/stats');
      final inner = res['data'];
      stats = inner is Map ? inner.cast<String, dynamic>() : res;
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
                child: FilledButton.icon(onPressed: () => _openEditor(), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New Config')),
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
    final status = str(c['template_status'], 'draft');
    final locked = _lockedStatuses.contains(status);
    final rejection = str(c['rejection_reason'], '');
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
            StatusPill(status, color: _statusColors[status] ?? AppPalette.muted),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 2, children: [
            if (widget.kind == 'auth') ...[
              Text('Delivery: ${str(c['auth_delivery_method'], 'copy_code')}', style: TextStyle(fontSize: 11, color: context.mutedColor)),
              Text('Length: ${c['otp_length'] ?? 6}', style: TextStyle(fontSize: 11, color: context.mutedColor)),
              Text('Expiry: ${c['otp_expiry_minutes'] ?? 10}m', style: TextStyle(fontSize: 11, color: context.mutedColor)),
              Text('Attempts: ${c['max_attempts'] ?? 5}', style: TextStyle(fontSize: 11, color: context.mutedColor)),
            ],
            Text('Lang: ${str(c['template_language'], 'en')}', style: TextStyle(fontSize: 11, color: context.mutedColor)),
          ]),
          if (rejection.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(rejection, style: const TextStyle(fontSize: 12, color: AppPalette.danger))),
          if (widget.kind == 'invoice') Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  str(c['header_sample_url'], '').isNotEmpty ? 'Sample document uploaded' : 'No sample document uploaded',
                  style: TextStyle(fontSize: 12, color: str(c['header_sample_url'], '').isNotEmpty ? AppPalette.info : AppPalette.warning),
                ),
              ),
              TextButton.icon(
                onPressed: () => _uploadSample(c),
                icon: const Icon(Icons.upload_file_rounded, size: 14),
                label: Text(str(c['header_sample_url'], '').isNotEmpty ? 'Replace' : 'Upload', style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: [
            if (['draft', 'rejected', 'error'].contains(status))
              TextButton.icon(
                onPressed: () => _submit(c),
                icon: const Icon(Icons.send_rounded, size: 14),
                label: Text(str(c['wa_template_id'], '').isNotEmpty ? 'Resubmit' : 'Submit to Meta', style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
              ),
            TextButton.icon(
              onPressed: () => _sync(c),
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Sync', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
            ),
            TextButton.icon(
              onPressed: () => _showStats(c),
              icon: const Icon(Icons.bar_chart_rounded, size: 14),
              label: const Text('Stats', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
            ),
            TextButton(
              onPressed: locked ? null : () => _openEditor(existing: c),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
              child: Text('Edit', style: TextStyle(fontSize: 12, color: locked ? context.mutedColor : null)),
            ),
            IconButton(onPressed: () => _delete(c), icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppPalette.danger), constraints: const BoxConstraints(), padding: const EdgeInsets.all(6)),
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

class WaCloudApiConfigEditorPage extends StatefulWidget {
  const WaCloudApiConfigEditorPage({super.key, required this.kind, this.existing});
  final String kind;
  final Rec? existing;

  @override
  State<WaCloudApiConfigEditorPage> createState() => _WaCloudApiConfigEditorPageState();
}

class _WaCloudApiConfigEditorPageState extends State<WaCloudApiConfigEditorPage> {
  bool get _editing => widget.existing != null;

  late final _nameCtrl = TextEditingController(text: str(widget.existing?['name'], ''));
  late final _customContentCtrl = TextEditingController(text: str(widget.existing?['custom_content'], ''));
  late final _footerCtrl = TextEditingController(text: str(widget.existing?['footer_text'], ''));

  late int _otpLength = (widget.existing?['otp_length'] as num?)?.toInt() ?? 6;
  late int _otpExpiry = (widget.existing?['otp_expiry_minutes'] as num?)?.toInt() ?? 10;
  late int _maxAttempts = (widget.existing?['max_attempts'] as num?)?.toInt() ?? 5;
  late bool _isActive = widget.existing?['is_active'] != false;

  late int? _selectedTemplateId = (widget.existing?['prebuilt_template_id'] as num?)?.toInt();
  late String _utilMode = str(widget.existing?['custom_content'], '').isNotEmpty ? 'custom' : 'template';
  late String _tplLang = str((widget.existing?['prebuilt_template'] as Map?)?['language'], str(widget.existing?['template_language'], 'en'));

  late String _authMethod = str(widget.existing?['auth_delivery_method'], 'copy_code');
  late bool _authAddExpiry = widget.existing?['auth_add_expiry'] != false;
  late int _authCodeExpiry = (widget.existing?['auth_code_expiration_minutes'] as num?)?.toInt() ?? 10;
  late bool _authAddSecurityRec = widget.existing?['auth_add_security_recommendation'] != false;
  late bool _authZeroTapAccepted = widget.existing?['auth_zero_tap_terms_accepted'] == true;
  late List<Map<String, String>> _authApps = ((widget.existing?['auth_apps'] as List?) ?? [])
      .map((a) => {'package_name': str((a as Map)['package_name'], ''), 'signature_hash': str(a['signature_hash'], '')})
      .toList()
      .cast<Map<String, String>>();

  final _bodyExamples = <String, TextEditingController>{};

  List<Rec>? _templates;
  bool _loadingMeta = true;
  bool _saving = false;
  String? _saveError;
  final _tplSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _customContentCtrl.dispose();
    _footerCtrl.dispose();
    _tplSearchCtrl.dispose();
    for (final c in _bodyExamples.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final templates = await Api.list('/wa-cloud/otp-service/prebuilt-templates', query: {'type': widget.kind == 'auth' ? 'auth' : 'utility'});
      if (!mounted) return;
      setState(() { _templates = templates; _loadingMeta = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  String get _bodySource {
    if (_utilMode == 'custom') return _customContentCtrl.text;
    final tpl = (_templates ?? []).where((t) => t['id'] == _selectedTemplateId);
    return tpl.isEmpty ? '' : str(tpl.first['content'], '');
  }

  List<String> get _bodyVars {
    final set = <String>{};
    for (final m in RegExp(r'\{\{\s*(.+?)\s*\}\}').allMatches(_bodySource)) {
      set.add(m.group(1)!.trim());
    }
    return set.toList();
  }

  bool get _utilityIncomplete => (widget.kind == 'utility' || widget.kind == 'invoice')
      ? (_utilMode == 'template' ? _selectedTemplateId == null : _customContentCtrl.text.trim().isEmpty)
      : false;

  bool get _authIncomplete {
    if (widget.kind != 'auth' || _authMethod == 'copy_code') return false;
    if (_authApps.isEmpty || _authApps.any((a) => a['package_name']!.trim().isEmpty || a['signature_hash']!.trim().isEmpty)) return true;
    if (_authMethod == 'zero_tap' && !_authZeroTapAccepted) return true;
    return false;
  }

  bool get _canSave => !_saving && _nameCtrl.text.trim().isNotEmpty && !_utilityIncomplete && !_authIncomplete;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() { _saving = true; _saveError = null; });
    final data = <String, dynamic>{
      'kind': widget.kind,
      'name': _nameCtrl.text.trim(),
      'is_active': _isActive,
      'template_language': _tplLang,
      'footer_text': _footerCtrl.text.trim().isEmpty ? null : _footerCtrl.text.trim(),
    };
    if (widget.kind == 'auth') {
      data['prebuilt_template_id'] = _selectedTemplateId;
      data['otp_length'] = _otpLength;
      data['otp_expiry_minutes'] = _otpExpiry;
      data['max_attempts'] = _maxAttempts;
      data['auth_delivery_method'] = _authMethod;
      data['auth_apps'] = _authMethod == 'copy_code' ? [] : _authApps;
      data['auth_add_expiry'] = _authAddExpiry;
      data['auth_code_expiration_minutes'] = _authCodeExpiry;
      data['auth_add_security_recommendation'] = _authAddSecurityRec;
      data['auth_zero_tap_terms_accepted'] = _authMethod == 'zero_tap' ? _authZeroTapAccepted : false;
    }
    if (widget.kind == 'utility' || widget.kind == 'invoice') {
      final useTpl = _utilMode == 'template';
      data['prebuilt_template_id'] = useTpl ? _selectedTemplateId : null;
      data['custom_content'] = useTpl ? null : (_customContentCtrl.text.trim().isEmpty ? null : _customContentCtrl.text.trim());
      data['body_examples'] = {for (final n in _bodyVars) n: _bodyExamples[n]?.text ?? ''};
    }
    try {
      if (_editing) {
        await Api.patch('/wa-cloud/otp-service/configs/${widget.existing!['id']}', data: data);
      } else {
        await Api.post('/wa-cloud/otp-service/configs', data: data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_editing ? 'Config updated' : 'Config created — submitted to Meta if credentials are connected')));
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
                if (widget.kind == 'auth') ...[
                  _templatePicker(),
                  _authDeliverySection(),
                  _otpFields(),
                ],
                if (widget.kind == 'utility' || widget.kind == 'invoice') _utilitySection(),
                if (widget.kind == 'utility' || widget.kind == 'invoice') _variableSamples(),
                if (widget.kind == 'utility' || widget.kind == 'invoice')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextField(controller: _footerCtrl, maxLength: 60, decoration: const InputDecoration(labelText: 'Footer (optional)')),
                  ),
                if (widget.kind == 'invoice')
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'The text shown with the document is the template body above — Meta\'s document header carries only the file and filename, not a caption.'
                      '${_editing ? ' Upload the sample document from the config list after saving.' : ''}',
                      style: TextStyle(fontSize: 11, color: context.mutedColor),
                    ),
                  ),
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
                      : const Text('Save & submit to Meta'),
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
          Text(widget.kind == 'auth' ? 'Base template / language' : 'Template', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor)),
          const SizedBox(height: 6),
          Row(children: [
            DropdownButton<String>(
              value: effectiveLang,
              items: langs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setState(() { _tplLang = v ?? 'en'; }),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _tplSearchCtrl, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Search templates…', isDense: true))),
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
                        onTap: () => setState(() { _selectedTemplateId = t['id'] as int?; _tplLang = str(t['language'], 'en'); }),
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
          if (selected.isNotEmpty && widget.kind != 'auth')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Selected: ${str(selected.first['name'])} (${str(selected.first['language'])})', style: TextStyle(fontSize: 11, color: context.mutedColor)),
            ),
        ],
      ),
    );
  }

  Widget _authDeliverySection() {
    const methods = [('copy_code', 'Copy code'), ('one_tap', 'One-tap autofill'), ('zero_tap', 'Zero-tap autofill')];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delivery method', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor)),
          const SizedBox(height: 4),
          for (final m in methods)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: m.$1,
              groupValue: _authMethod,
              onChanged: (v) => setState(() => _authMethod = v ?? 'copy_code'),
              title: Text(m.$2, style: const TextStyle(fontSize: 13)),
            ),
          if (_authMethod != 'copy_code') ...[
            Text('Android apps (package name + APK signature hash)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor)),
            const SizedBox(height: 6),
            for (var i = 0; i < _authApps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _authApps[i]['package_name'],
                      decoration: const InputDecoration(labelText: 'Package name', isDense: true),
                      onChanged: (v) => _authApps[i]['package_name'] = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: _authApps[i]['signature_hash'],
                      decoration: const InputDecoration(labelText: 'Signature hash', isDense: true),
                      onChanged: (v) => _authApps[i]['signature_hash'] = v,
                    ),
                  ),
                  IconButton(onPressed: () => setState(() => _authApps.removeAt(i)), icon: const Icon(Icons.close_rounded, size: 18)),
                ]),
              ),
            OutlinedButton.icon(
              onPressed: () => setState(() => _authApps.add({'package_name': '', 'signature_hash': ''})),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add app'),
            ),
            const SizedBox(height: 12),
            if (_authMethod == 'zero_tap')
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _authZeroTapAccepted,
                onChanged: (v) => setState(() => _authZeroTapAccepted = v ?? false),
                title: const Text('I accept the zero-tap autofill terms', style: TextStyle(fontSize: 13)),
              ),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _authAddExpiry,
            onChanged: (v) => setState(() => _authAddExpiry = v ?? true),
            title: const Text('Add expiry warning to the message', style: TextStyle(fontSize: 13)),
          ),
          if (_authAddExpiry)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 8),
              child: TextField(
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: '$_authCodeExpiry'),
                decoration: const InputDecoration(labelText: 'Code expiration (min)', isDense: true),
                onChanged: (v) => _authCodeExpiry = int.tryParse(v) ?? 10,
              ),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _authAddSecurityRec,
            onChanged: (v) => setState(() => _authAddSecurityRec = v ?? true),
            title: const Text('Add "don\'t share this code" recommendation', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _otpFields() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
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
          const SizedBox(height: 6),
          Text("OTP length only controls the code we generate — Meta's AUTHENTICATION template does not carry a length.", style: TextStyle(fontSize: 11, color: context.mutedColor)),
          const SizedBox(height: 12),
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
            child: Column(children: [
              TextField(
                controller: _customContentCtrl,
                onChanged: (_) => setState(() {}),
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Custom Content', hintText: 'Write the message… use {{name}} placeholders'),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _variableSamples() {
    final vars = _bodyVars;
    if (vars.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Variable samples (Meta needs one example per {{…}} for review)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor)),
          const SizedBox(height: 6),
          for (final name in vars)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(4)),
                  child: Text('{{$name}}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _bodyExamples.putIfAbsent(name, () => TextEditingController()),
                    decoration: InputDecoration(hintText: 'example for $name', isDense: true),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
