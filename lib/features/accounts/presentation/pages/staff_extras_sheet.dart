import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// A staff member's profile details: designation (a list the company grows), joining date, whose leads they may also see, and their documents.
/// Backed by /staff/{id}/extras, /staff/extras/designations, /staff/extras/document-types and /staff/{id}/documents.
Future<void> showStaffExtrasSheet(BuildContext context, Map<String, dynamic> staff) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StaffExtrasSheet(staff: staff),
  );
}

class _StaffExtrasSheet extends StatefulWidget {
  const _StaffExtrasSheet({required this.staff});
  final Map<String, dynamic> staff;
  @override
  State<_StaffExtrasSheet> createState() => _StaffExtrasSheetState();
}

class _StaffExtrasSheetState extends State<_StaffExtrasSheet> {
  int get _id => (widget.staff['id'] as num).toInt();
  bool _loading = true, _saving = false, _uploading = false;
  String? _error;
  String? _designation;
  DateTime? _joined;
  final _accessible = <int>{};
  List<String> _designations = [];
  List<Map<String, dynamic>> _people = [], _docs = [];
  List<String> _docTypes = [];
  String? _docType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final extras = await Api.one('/staff/$_id/extras');
      final des = await Api.list('/staff/extras/designations');
      final types = await Api.list('/staff/extras/document-types');
      final docs = await Api.list('/staff/$_id/documents');
      final people = await Api.list('/staff', query: {'per_page': 200});
      if (!mounted) return;
      setState(() {
        _designation = (extras['designation'] as String?)?.isEmpty == true ? null : extras['designation'] as String?;
        _joined = DateTime.tryParse('${extras['joined_on'] ?? ''}');
        _accessible..clear()..addAll(((extras['accessible_user_ids'] as List?) ?? const []).map((e) => (e as num).toInt()));
        _designations = [for (final d in des) '${d['name']}'];
        _docTypes = [for (final t in types) '${t['name']}'];
        _docType = _docTypes.isNotEmpty ? _docTypes.first : null;
        _docs = docs;
        _people = people.where((p) => (p['id'] as num).toInt() != _id && p['is_active'] != false).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = apiErrorMessage(e); });
    }
  }

  String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await Api.put('/staff/$_id/extras', data: {
        'designation': _designation,
        'joined_on': _joined == null ? null : _date(_joined!),
        'accessible_user_ids': _accessible.toList(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = apiErrorMessage(e); });
    }
  }

  Future<String?> _ask(String title, String hint) async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> _addDesignation() async {
    final name = await _ask('New designation', 'e.g. Sales Executive');
    if (name == null) return;
    try {
      final r = await Api.post('/staff/extras/designations', data: {'name': name});
      setState(() { _designations = [for (final d in (r['data'] as List? ?? const [])) '${(d as Map)['name']}']; _designation = name; });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  Future<void> _addDocType() async {
    final name = await _ask('New document type', 'Max 30 characters');
    if (name == null) return;
    try {
      final r = await Api.post('/staff/extras/document-types', data: {'name': name});
      setState(() { _docTypes = [for (final d in (r['data'] as List? ?? const [])) '${(d as Map)['name']}']; _docType = name; });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  Future<void> _upload() async {
    if (_docType == null) return;
    final pick = await FilePicker.platform.pickFiles(withData: false);
    final path = pick?.files.single.path;
    if (path == null) return;
    setState(() { _uploading = true; _error = null; });
    try {
      final form = FormData.fromMap({'type': _docType, 'file': await MultipartFile.fromFile(path, filename: pick!.files.single.name)});
      final res = await Api.raw.post('/staff/$_id/documents', data: form);
      final data = (res.data as Map?)?['data'] as List? ?? const [];
      if (mounted) setState(() { _docs = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(); _uploading = false; });
    } catch (e) {
      if (mounted) setState(() { _uploading = false; _error = apiErrorMessage(e); });
    }
  }

  Future<void> _removeDoc(Map<String, dynamic> d) async {
    try {
      final res = await Api.raw.delete('/staff/$_id/documents/${d['id']}');
      final data = (res.data as Map?)?['data'] as List? ?? const [];
      if (mounted) setState(() => _docs = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: _loading
            ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                shrinkWrap: true,
                children: [
                  Text('Profile — ${str(widget.staff['name'])}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _designations.contains(_designation) ? _designation : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Designation', border: OutlineInputBorder(), isDense: true),
                        items: [for (final d in _designations) DropdownMenuItem(value: d, child: Text(d))],
                        onChanged: (v) => setState(() => _designation = v),
                      ),
                    ),
                    IconButton.filledTonal(onPressed: _addDesignation, icon: const Icon(Icons.add_rounded), tooltip: 'Add a designation'),
                  ]),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(context: context, initialDate: _joined ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (d != null) setState(() => _joined = d);
                    },
                    icon: const Icon(Icons.event_rounded),
                    label: Text(_joined == null ? 'Joining date' : 'Joined ${_date(_joined!)}'),
                  ),
                  const Divider(height: 28),
                  Text('Accessible users', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Whose leads ${str(widget.staff['name'])} can also see, besides their own.', style: const TextStyle(fontSize: 12)),
                  for (final p in _people)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _accessible.contains((p['id'] as num).toInt()),
                      onChanged: (v) => setState(() => v == true ? _accessible.add((p['id'] as num).toInt()) : _accessible.remove((p['id'] as num).toInt())),
                      title: Text(str(p['name']), style: const TextStyle(fontSize: 13.5)),
                    ),
                  const Divider(height: 28),
                  Text('Documents', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _docType,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder(), isDense: true),
                        items: [for (final t in _docTypes) DropdownMenuItem(value: t, child: Text(t))],
                        onChanged: (v) => setState(() => _docType = v),
                      ),
                    ),
                    IconButton.filledTonal(onPressed: _addDocType, icon: const Icon(Icons.add_rounded), tooltip: 'Add a document type'),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : _upload,
                    icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file_rounded),
                    label: const Text('Choose a file & upload'),
                  ),
                  if (_docs.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No documents uploaded.', style: TextStyle(fontSize: 12))),
                  for (final d in _docs)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(str(d['title']), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(str(d['type'])),
                      onTap: d['url'] != null ? () => launchUrl(Uri.parse('${d['url']}'), mode: LaunchMode.externalApplication) : null,
                      trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _removeDoc(d)),
                    ),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C)))),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save details'),
                  ),
                ],
              ),
      ),
    );
  }
}
