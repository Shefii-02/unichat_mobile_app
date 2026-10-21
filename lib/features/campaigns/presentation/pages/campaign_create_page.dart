// ignore_for_file: use_build_context_synchronously
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// New WA Cloud campaign — same fields and rules as the web "New campaign" form. Saved as a draft,
/// or scheduled when a send time is set. (Template, number and audience are fixed once created.)
class CampaignCreatePage extends StatefulWidget {
  const CampaignCreatePage({super.key});
  @override
  State<CampaignCreatePage> createState() => _CampaignCreatePageState();
}

class _CampaignCreatePageState extends State<CampaignCreatePage> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _throttle = TextEditingController(text: '60');
  final _daily = TextEditingController();
  final _paste = TextEditingController();

  List<Rec> _templates = [], _numbers = [], _labels = [];
  bool _ready = false, _saving = false;
  String? _loadError;

  int? _template, _number;
  String _target = 'all'; // all | labels | csv
  final Set<int> _labelIds = {};
  PlatformFile? _csv;
  DateTime? _at;

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  @override
  void dispose() {
    for (final c in [_name, _desc, _throttle, _daily, _paste]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _loadLookups() async {
    try {
      final r = await Future.wait([
        Api.list('/templates', query: {'status': 'approved', 'per_page': 100}),
        Api.list('/phone-numbers'),
        Api.list('/labels'),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = r[0];
        _numbers = r[1].where((n) => '${n['status']}'.toUpperCase() != 'DISCONNECTED').toList();
        _labels = r[2];
        if (_numbers.length == 1) _number = (_numbers.first['id'] as num).toInt();
        _ready = true;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = apiErrorMessage(e));
    }
  }

  /// Numbers typed or pasted, cleaned to 8–15 digits, duplicates dropped — same rule as the web.
  ({List<String> valid, int invalid}) _parsePasted() {
    final seen = <String>{};
    final valid = <String>[];
    var invalid = 0;
    for (final tok in _paste.text.split(RegExp(r'[\s,;]+'))) {
      if (tok.isEmpty) continue;
      final d = tok.replaceAll(RegExp(r'\D'), '');
      if (!RegExp(r'^\d{8,15}$').hasMatch(d)) { invalid++; continue; }
      if (seen.add(d)) valid.add(d);
    }
    return (valid: valid, invalid: invalid);
  }

  String _fmt(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.day}/${d.month}/${d.year}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _save() async {
    String? err;
    if (_name.text.trim().isEmpty) {
      err = 'Campaign name required';
    } else if (_template == null) {
      err = 'Select a template';
    } else if (_number == null) {
      err = 'Select a sending number';
    } else if (_target == 'labels' && _labelIds.isEmpty) {
      err = 'Select at least one label';
    } else if (_target == 'csv' && _csv == null && _parsePasted().valid.isEmpty) {
      err = 'Paste at least one valid number or choose a CSV file';
    } else if (_at != null && !_at!.isAfter(DateTime.now())) {
      err = 'Send time must be in the future';
    }
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    final form = FormData();
    form.fields
      ..add(MapEntry('name', _name.text.trim()))
      ..add(MapEntry('template_id', '$_template'))
      ..add(MapEntry('wa_phone_number_id', '$_number'))
      ..add(MapEntry('target_type', _target))
      ..add(MapEntry('throttle_per_minute', _throttle.text.trim().isEmpty ? '60' : _throttle.text.trim()));
    if (_desc.text.trim().isNotEmpty) form.fields.add(MapEntry('description', _desc.text.trim()));
    if (_daily.text.trim().isNotEmpty) form.fields.add(MapEntry('daily_limit', _daily.text.trim()));
    if (_at != null) form.fields.add(MapEntry('scheduled_at', _at!.toUtc().toIso8601String()));
    if (_target == 'labels') {
      for (final id in _labelIds) { form.fields.add(MapEntry('target_labels[]', '$id')); }
    }
    if (_target == 'csv') {
      if (_csv?.path != null) {
        form.files.add(MapEntry('file', await MultipartFile.fromFile(_csv!.path!, filename: _csv!.name)));
      } else {
        form.files.add(MapEntry('file', MultipartFile.fromString('phone\n${_parsePasted().valid.join('\n')}\n', filename: 'pasted-numbers.csv')));
      }
    }

    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () => Api.raw.post('/campaigns', data: form),
      success: _at != null ? 'Campaign scheduled.' : 'Campaign created as draft.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New campaign')),
      body: _loadError != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_loadError!, textAlign: TextAlign.center)))
          : !_ready
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: _form()),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(
            onPressed: _saving || !_ready ? null : _save,
            child: Text(_saving ? 'Saving…' : _at != null ? 'Create & schedule' : 'Create draft'),
          ),
        ),
      ),
    );
  }

  List<Widget> _form() {
    final pasted = _parsePasted();
    return [
      FField(label: 'Campaign name', child: TextField(controller: _name)),
      FField(label: 'Description (optional)', child: TextField(controller: _desc, maxLines: 2)),
      FField(
        label: 'Template (approved)',
        child: DropdownButtonFormField<int>(
          initialValue: _template, isExpanded: true, hint: const Text('Select template'),
          items: [for (final t in _templates) DropdownMenuItem(value: (t['id'] as num).toInt(), child: Text('${t['name']}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _template = v),
        ),
      ),
      FField(
        label: 'Sending number',
        child: DropdownButtonFormField<int>(
          initialValue: _number, isExpanded: true, hint: const Text('Select number'),
          items: [for (final n in _numbers) DropdownMenuItem(value: (n['id'] as num).toInt(), child: Text('${n['label'] ?? n['display_number'] ?? n['display_phone_number'] ?? n['id']}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _number = v),
        ),
      ),
      const SectionHeader('Audience'),
      Wrap(spacing: 6, children: [
        for (final t in const [('all', 'All contacts'), ('labels', 'Labels'), ('csv', 'Numbers / CSV')])
          ChoiceChip(label: Text(t.$2), selected: _target == t.$1, onSelected: (_) => setState(() => _target = t.$1)),
      ]),
      const SizedBox(height: 8),
      if (_target == 'labels')
        Wrap(spacing: 6, children: [
          for (final l in _labels)
            FilterChip(
              label: Text('${l['name']}'),
              selected: _labelIds.contains((l['id'] as num).toInt()),
              onSelected: (v) => setState(() => v ? _labelIds.add((l['id'] as num).toInt()) : _labelIds.remove((l['id'] as num).toInt())),
            ),
          if (_labels.isEmpty) Text('No labels yet.', style: TextStyle(color: context.mutedColor)),
        ]),
      if (_target == 'csv') ...[
        FField(
          label: 'Paste numbers (one per line, with country code)',
          child: TextField(controller: _paste, maxLines: 5, keyboardType: TextInputType.multiline, onChanged: (_) => setState(() {})),
        ),
        if (_paste.text.trim().isNotEmpty)
          Text('✅ ${pasted.valid.length} valid${pasted.invalid > 0 ? ' · ${pasted.invalid} invalid (skipped)' : ''}', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: Text(_csv == null ? 'Or choose a CSV file' : _csv!.name),
          onPressed: () async {
            final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
            if (r != null && r.files.isNotEmpty) setState(() => _csv = r.files.first);
          },
        ),
      ],
      const SectionHeader('Sending'),
      Row(children: [
        Expanded(child: FField(label: 'Messages / minute', child: TextField(controller: _throttle, keyboardType: TextInputType.number))),
        const SizedBox(width: 12),
        Expanded(child: FField(label: 'Daily limit (optional)', child: TextField(controller: _daily, keyboardType: TextInputType.number))),
      ]),
      FField(
        label: 'Send at (leave empty to launch manually)',
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(_at == null ? 'Pick date & time' : _fmt(_at!)),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, initialDate: _at ?? now.add(const Duration(hours: 1)), firstDate: now, lastDate: now.add(const Duration(days: 365)));
                if (d == null) return;
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at ?? now.add(const Duration(hours: 1))));
                if (t == null) return;
                setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
              },
            ),
          ),
          if (_at != null) IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _at = null)),
        ]),
      ),
    ];
  }
}
