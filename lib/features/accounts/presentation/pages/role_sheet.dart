import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/features/accounts/permission_sections.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Create, view or edit one role. Permissions are listed by section (WA Chat, WA Cloud, Leads …) and group, with a tick each; a system role is read-only
/// (only its description changes). Backed by GET /roles/permissions, POST /roles and PUT /roles/{id}.
Future<bool> showRoleSheet(BuildContext context, {Map<String, dynamic>? role}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RoleSheet(role: role),
  );
  return saved == true;
}

class _RoleSheet extends StatefulWidget {
  const _RoleSheet({this.role});
  final Map<String, dynamic>? role;
  @override
  State<_RoleSheet> createState() => _RoleSheetState();
}

class _RoleSheetState extends State<_RoleSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  List<Map<String, dynamic>> _catalogue = []; // {id, key, label, group}
  final _picked = <String>{};
  bool _loading = true, _saving = false;
  String? _error;
  String _q = '';

  bool get _isNew => widget.role == null;
  bool get _system => widget.role?['is_system'] == true;
  bool get _canEdit => PermissionGuard.can('roles.manage');
  bool get _locked => !_canEdit || (_system && !_isNew);

  @override
  void initState() {
    super.initState();
    _name.text = str(widget.role?['label'] ?? widget.role?['name'], '');
    _desc.text = str(widget.role?['description'], '');
    _picked.addAll(((widget.role?['permissions'] as List?) ?? const []).map((e) => '$e'));
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Api.one('/roles/permissions');
      final out = <Map<String, dynamic>>[];
      for (final g in (res['permissions'] as List? ?? const [])) {
        final grp = '${(g as Map)['group']}';
        for (final p in (g['permissions'] as List? ?? const [])) {
          out.add({...Map<String, dynamic>.from(p as Map), 'group': grp});
        }
      }
      if (mounted) setState(() { _catalogue = out; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = apiErrorMessage(e); });
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final ids = [for (final p in _catalogue) if (_picked.contains('${p['key']}')) (p['id'] as num).toInt()];
      if (_system && !_isNew) {
        await Api.put('/roles/${widget.role!['id']}', data: {'description': _desc.text.trim()});
      } else {
        final body = {'name': _name.text.trim(), 'description': _desc.text.trim(), 'permission_ids': ids};
        _isNew ? await Api.post('/roles', data: body) : await Api.put('/roles/${widget.role!['id']}', data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = apiErrorMessage(e); });
    }
  }

  void _setSection(Iterable<Map<String, dynamic>> perms, bool on) {
    setState(() { for (final p in perms) { on ? _picked.add('${p['key']}') : _picked.remove('${p['key']}'); } });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _catalogue.where((p) => _q.isEmpty || '${p['label']} ${p['key']} ${p['group']}'.toLowerCase().contains(_q)).toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        child: _loading
            ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            : ListView(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
                shrinkWrap: true,
                children: [
                  Text(_isNew ? 'New role' : (_locked ? 'Role — ${_name.text}' : 'Edit role'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (_system && !_isNew) const Padding(padding: EdgeInsets.only(top: 4), child: Text('A system role: its permissions are fixed. Only the description can change.', style: TextStyle(fontSize: 12))),
                  const SizedBox(height: 10),
                  TextField(controller: _name, enabled: !_locked, decoration: const InputDecoration(labelText: 'Role name', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  TextField(controller: _desc, enabled: _canEdit, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder(), isDense: true)),
                  if ((widget.role?['access_main'] ?? '') != '' || ((widget.role?['access_subs'] as List?)?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      const Text('Access sections:', style: TextStyle(fontSize: 12)),
                      if ((widget.role?['access_main'] ?? '') != '') Chip(label: Text('${widget.role!['access_main']} (main)'), visualDensity: VisualDensity.compact),
                      for (final s in (widget.role?['access_subs'] as List? ?? const [])) Chip(label: Text('$s'), visualDensity: VisualDensity.compact),
                    ]),
                  ],
                  const Divider(height: 24),
                  Row(children: [
                    Text('Permissions', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${_picked.length} selected', style: const TextStyle(fontSize: 12)),
                  ]),
                  const SizedBox(height: 6),
                  TextField(
                    decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded), hintText: 'Search permissions', border: OutlineInputBorder()),
                    onChanged: (v) => setState(() => _q = v.toLowerCase()),
                  ),
                  const SizedBox(height: 4),
                  for (final (section, groups) in sectioned(shown)) _sectionTile(section, groups),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C)))),
                  const SizedBox(height: 12),
                  if (_canEdit)
                    FilledButton(
                      onPressed: _saving || _name.text.trim().isEmpty && !_system ? null : _save,
                      child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_isNew ? 'Create role' : 'Save role'),
                    ),
                ],
              ),
      ),
    );
  }

  /// One app section (WA Cloud, Leads …) — collapsible, with a count and a "tick all" for the section.
  Widget _sectionTile(String section, List<(String, List<Map<String, dynamic>>)> groups) {
    final all = [for (final g in groups) ...g.$2];
    final on = all.where((p) => _picked.contains('${p['key']}')).length;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      initiallyExpanded: _q.isNotEmpty,
      title: Text(section, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('$on of ${all.length}', style: const TextStyle(fontSize: 11)),
      trailing: _locked
          ? null
          : TextButton(onPressed: () => _setSection(all, on != all.length), child: Text(on == all.length ? 'None' : 'All')),
      children: [
        for (final g in groups) ...[
          Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(g.$1.toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey)))),
          for (final p in g.$2)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _picked.contains('${p['key']}'),
              onChanged: _locked ? null : (v) => setState(() => v == true ? _picked.add('${p['key']}') : _picked.remove('${p['key']}')),
              title: Text('${p['label']}', style: const TextStyle(fontSize: 13.5)),
            ),
        ],
      ],
    );
  }
}
