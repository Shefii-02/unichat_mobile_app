import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// What the "New lead" form picks besides the customer: which number / account / campaign the lead came from, and its categories.
class LeadFormState {
  Map<String, dynamic>? origin;          // one entry of GET /leads/origins
  bool other = false;                    // "not listed" — typed by hand
  final otherLabel = TextEditingController();
  final categories = <String>[];         // the first is the primary

  /// The origin part of the POST /leads body.
  Map<String, dynamic> originData() {
    if (origin != null) return {'origin_type': origin!['type'], 'origin_id': origin!['id']};
    final t = otherLabel.text.trim();
    return t.isEmpty ? {} : {'origin_label': t};
  }

  void dispose() => otherLabel.dispose();
}

/// "Lead origin" — choose which number / account / widget / ad account the lead came from (the list comes from what is connected),
/// or "Not listed" to type it. The source and label are then stored with the lead.
class LeadOriginField extends StatefulWidget {
  const LeadOriginField({super.key, required this.state});
  final LeadFormState state;
  @override
  State<LeadOriginField> createState() => _LeadOriginFieldState();
}

class _LeadOriginFieldState extends State<LeadOriginField> {
  List<Map<String, dynamic>> _options = [];
  bool _loading = true;

  LeadFormState get _s => widget.state;

  @override
  void initState() {
    super.initState();
    Api.list('/leads/origins').then((r) {
      if (mounted) setState(() { _options = r; _loading = false; });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  String _name(Map<String, dynamic> o) => '${o['icon'] ?? ''} ${o['source_label']} · ${o['label']}'.trim();

  Future<void> _pick() async {
    final notListed = <String, dynamic>{'type': '_other', 'id': 0, 'source_label': 'Not listed', 'label': 'Type it myself', 'icon': '✏️'};
    final picked = await showSearchPicker<Map<String, dynamic>>(
      context,
      title: 'lead origin',
      options: [..._options, notListed],
      labelOf: _name,
      subtitleOf: (o) => o['sub'] as String?,
      selected: _s.origin,
    );
    if (picked == null) return;
    setState(() {
      if (picked.value['type'] == '_other') { _s.origin = null; _s.other = true; } else { _s.origin = picked.value; _s.other = false; }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _s.origin != null ? _name(_s.origin!) : (_s.other ? 'Not listed — type it below' : null);
    return FField(
      label: 'Lead origin',
      hint: 'Which number / account / campaign the lead came from',
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _loading ? null : _pick,
          child: InputDecorator(
            decoration: InputDecoration(border: const OutlineInputBorder(), isDense: true, suffixIcon: _loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.search_rounded)),
            child: Text(shown ?? (_loading ? 'Loading…' : 'Search & select'), maxLines: 1, overflow: TextOverflow.ellipsis, style: shown == null ? TextStyle(color: context.mutedColor) : null),
          ),
        ),
        if (_s.other) ...[
          const SizedBox(height: 8),
          TextFormField(controller: _s.otherLabel, decoration: const InputDecoration(hintText: 'e.g. Phone call, referral, Diwali campaign', border: OutlineInputBorder(), isDense: true)),
        ],
      ]),
    );
  }
}

/// "Categories" — pick several. Typing searches the existing ones; a name that doesn't exist yet can be added on the spot.
class LeadCategoriesField extends StatefulWidget {
  const LeadCategoriesField({super.key, required this.state});
  final LeadFormState state;
  @override
  State<LeadCategoriesField> createState() => _LeadCategoriesFieldState();
}

class _LeadCategoriesFieldState extends State<LeadCategoriesField> {
  List<String> _all = [];
  String _q = '';
  String? _error;
  bool _adding = false;
  final _search = TextEditingController();

  List<String> get _picked => widget.state.categories;

  @override
  void initState() {
    super.initState();
    Api.one('/lead-categories', query: {'names_only': true}).then((r) {
      if (mounted) setState(() => _all = [for (final n in (r['categories'] as List? ?? const [])) '$n']);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String n) => setState(() => _picked.contains(n) ? _picked.remove(n) : _picked.add(n));

  Future<void> _addNew(String name) async {
    setState(() { _adding = true; _error = null; });
    try {
      await Api.post('/lead-categories', data: {'name': name});
      if (!mounted) return;
      setState(() { _all = [..._all, name]; _picked.add(name); _search.clear(); _q = ''; });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final matches = [for (final n in _all) if (q.isEmpty || n.toLowerCase().contains(q)) n];
    final exact = _all.any((n) => n.toLowerCase() == q);
    return FField(
      label: 'Categories',
      hint: _picked.isEmpty ? 'Pick one or more — the first is the main one' : 'Main: ${_picked.first}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_picked.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final n in _picked) InputChip(label: Text(n), onDeleted: () => _toggle(n), visualDensity: VisualDensity.compact),
          ]),
        const SizedBox(height: 6),
        TextField(
          controller: _search,
          onChanged: (v) => setState(() { _q = v.trim(); _error = null; }),
          decoration: const InputDecoration(hintText: 'Search or add a category', prefixIcon: Icon(Icons.search_rounded), border: OutlineInputBorder(), isDense: true),
        ),
        if (_q.isNotEmpty || _all.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final n in matches.take(24))
              FilterChip(label: Text(n), selected: _picked.contains(n), onSelected: (_) => _toggle(n), visualDensity: VisualDensity.compact),
            if (_q.isNotEmpty && !exact)
              ActionChip(
                avatar: _adding ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_rounded, size: 16),
                label: Text('Add "$_q"'),
                onPressed: _adding ? null : () => _addNew(_q),
                visualDensity: VisualDensity.compact,
              ),
          ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12))),
      ]),
    );
  }
}
