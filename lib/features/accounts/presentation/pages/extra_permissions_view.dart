import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/features/accounts/permission_sections.dart';

/// "Additional access": tick any permission to grant it to THIS person only, on top of their role and access sections.
/// Permissions they already get from the role or a section show ticked and locked, saying where they come from.
/// Two views: By screen (the app's screens, view / manage) and By permission (grouped by section).
class ExtraPermissionsView extends StatefulWidget {
  const ExtraPermissionsView({
    super.key,
    required this.name,
    required this.catalogue,
    required this.fromRole,
    required this.fromSections,
    required this.extra,
    required this.onChanged,
  });
  final String name;
  final List<Map<String, dynamic>> catalogue;
  final Set<String> fromRole, fromSections;
  final Set<String> extra;
  final VoidCallback onChanged;

  @override
  State<ExtraPermissionsView> createState() => _ExtraPermissionsViewState();
}

class _ExtraPermissionsViewState extends State<ExtraPermissionsView> {
  bool _byScreen = true;
  String _q = '';

  String? _inherited(String key) => widget.fromRole.contains(key) ? 'role' : (widget.fromSections.contains(key) ? 'section' : null);
  bool _known(String key) => widget.catalogue.any((p) => p['key'] == key);
  String _label(String key) => '${widget.catalogue.firstWhere((p) => p['key'] == key, orElse: () => {'label': key})['label']}';

  void _toggle(String key, bool on) {
    setState(() => on ? widget.extra.add(key) : widget.extra.remove(key));
    widget.onChanged();
  }

  Widget _tick(String key, String label, {String? caption}) {
    final inh = _inherited(key);
    final on = inh != null || widget.extra.contains(key);
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: on,
      onChanged: inh != null ? null : (v) => _toggle(key, v == true),
      title: Text(label, style: TextStyle(fontSize: 13.5, color: inh != null ? Colors.grey : null)),
      subtitle: caption != null ? Text(caption, style: const TextStyle(fontSize: 11)) : null,
      secondary: inh != null
          ? _tag('from $inh', Colors.grey)
          : (widget.extra.contains(key) ? _tag('extra', Colors.green) : null),
    );
  }

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Permissions given to ${widget.name} alone, on top of the role and sections. You can only grant what you hold yourself.', style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      Row(children: [
        ChoiceChip(label: const Text('By screen'), selected: _byScreen, onSelected: (_) => setState(() => _byScreen = true)),
        const SizedBox(width: 8),
        ChoiceChip(label: const Text('By permission'), selected: !_byScreen, onSelected: (_) => setState(() => _byScreen = false)),
        const Spacer(),
        Text('${widget.extra.length} extra', style: const TextStyle(fontSize: 12)),
      ]),
      if (!_byScreen)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded), hintText: 'Search permissions', border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
          ),
        ),
      const SizedBox(height: 4),
      if (_byScreen) ..._screens() else ..._permissions(),
    ]);
  }

  /// The app's own screens: one row per screen for "can open it", and one for "can manage it".
  List<Widget> _screens() {
    final out = <Widget>[];
    for (final g in ModuleGroup.values) {
      final mods = AppModules.all.where((m) => m.group == g && m.permission != null && _known(m.permission!)).toList();
      if (mods.isEmpty) continue;
      out.add(Padding(padding: const EdgeInsets.only(top: 10, bottom: 2), child: Text(g.label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey))));
      for (final m in mods) {
        out.add(_tick(m.permission!, m.title, caption: m.subtitle));
        if (m.managePermission != null && m.managePermission != m.permission && _known(m.managePermission!)) {
          out.add(Padding(padding: const EdgeInsets.only(left: 28), child: _tick(m.managePermission!, '${m.title} — manage')));
        }
      }
    }
    return out;
  }

  List<Widget> _permissions() {
    final perms = widget.catalogue.where((p) => _q.isEmpty || '${p['label']} ${p['key']} ${p['group']}'.toLowerCase().contains(_q)).toList();
    final out = <Widget>[];
    for (final (section, groups) in sectioned(perms)) {
      for (final (group, items) in groups) {
        out.add(Padding(padding: const EdgeInsets.only(top: 10, bottom: 2), child: Text('${section.toUpperCase()} · ${group.toUpperCase()}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey))));
        for (final p in items) { out.add(_tick('${p['key']}', _label('${p['key']}'))); }
      }
    }
    return out;
  }
}
