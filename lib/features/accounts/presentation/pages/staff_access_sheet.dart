import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Per-staff access: web-portal / mobile-app switches plus the prebuilt access sections (one main + any
/// number of sub sections) layered on top of the staff member's role. Mirrors the web "Staff Access" page.
Future<void> showStaffAccessSheet(BuildContext context, Map<String, dynamic> staff) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StaffAccessSheet(staff: staff),
  );
}

class _StaffAccessSheet extends StatefulWidget {
  const _StaffAccessSheet({required this.staff});
  final Map<String, dynamic> staff;
  @override
  State<_StaffAccessSheet> createState() => _StaffAccessSheetState();
}

class _StaffAccessSheetState extends State<_StaffAccessSheet> {
  List<Map<String, dynamic>> _sections = [];
  bool _loading = true, _saving = false, _portal = true, _mobile = true;
  String? _main, _error;
  final _subs = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cat = await Api.one('/staff/access/sections');
      final cur = await Api.one('/staff/${widget.staff['id']}/access');
      if (!mounted) return;
      setState(() {
        _sections = ((cat['sections'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _portal = cur['portal_access'] != false;
        _mobile = cur['mobile_access'] != false;
        _main = cur['main'] as String?;
        _subs..clear()..addAll(((cur['subs'] as List?) ?? const []).map((e) => '$e'));
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = apiErrorMessage(e); });
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await Api.put('/staff/${widget.staff['id']}/access',
          data: {'portal_access': _portal, 'mobile_access': _mobile, 'main': _main, 'subs': _subs.toList()});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = apiErrorMessage(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: _loading
            ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                shrinkWrap: true,
                children: [
                  Text('Access — ${str(widget.staff['name'])}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.desktop_windows_rounded),
                    title: const Text('Web portal'),
                    value: _portal,
                    onChanged: (v) => setState(() => _portal = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.smartphone_rounded),
                    title: const Text('Mobile app'),
                    value: _mobile,
                    onChanged: (v) => setState(() => _mobile = v),
                  ),
                  const Divider(),
                  Text('Access sections', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const Text('Pick one main section and any extra sub sections. They add to what the role allows.', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  for (final s in _sections) _sectionTile(theme, s),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C)))),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save access'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _sectionTile(ThemeData theme, Map<String, dynamic> s) {
    final key = '${s['key']}';
    final isMain = _main == key, isSub = _subs.contains(key);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isMain ? theme.colorScheme.primary : theme.dividerColor, width: isMain ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s['icon']} ${s['label']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${s['description']}', style: const TextStyle(fontSize: 12)),
          Row(children: [
            ChoiceChip(
              label: const Text('Main'),
              selected: isMain,
              onSelected: (v) => setState(() { _main = v ? key : null; if (v) _subs.remove(key); }),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Sub'),
              selected: isSub,
              onSelected: isMain ? null : (v) => setState(() => v ? _subs.add(key) : _subs.remove(key)),
            ),
          ]),
        ]),
      ),
    );
  }
}
