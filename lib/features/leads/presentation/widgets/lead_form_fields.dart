import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// What the "New lead" form picks besides the customer: which number / account / campaign the lead came from, and its categories.
class LeadFormState {
  Map<String, dynamic>? origin;          // one entry of GET /leads/origins
  bool other = false;                    // "not listed" — typed by hand
  final otherLabel = TextEditingController();
  final categories = <String>[];         // the first is the primary
  int? itemId;                           // the item / listing the customer enquired about (null = none)

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

  static const _otherKey = '_other';

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    Widget row(String key, String text, String? sub, bool on, VoidCallback tap) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: on ? primary : context.mutedColor),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
                if (sub != null && sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 11.5, color: context.mutedColor)),
              ])),
            ]),
          ),
        );

    return FField(
      label: 'Lead origin',
      hint: 'Which number / account / campaign the lead came from',
      child: _loading
          ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final o in _options)
                row('${o['type']}:${o['id']}', _name(o), o['sub'] as String?, _s.origin != null && _s.origin!['type'] == o['type'] && _s.origin!['id'] == o['id'],
                    () => setState(() { _s.origin = o; _s.other = false; })),
              row(_otherKey, '✏️ Not listed — type it myself', null, _s.other, () => setState(() { _s.origin = null; _s.other = true; })),
              if (_s.other) ...[
                const SizedBox(height: 6),
                TextFormField(controller: _s.otherLabel, decoration: const InputDecoration(hintText: 'e.g. Phone call, referral, Diwali campaign', border: OutlineInputBorder(), isDense: true)),
              ],
            ]),
    );
  }
}

/// "Product / Service" — what the customer enquired about (from the listings catalogue), as radio buttons with a type filter and a search box
/// for long lists. The same customer on a different one is a new lead; the same one is a duplicate. "None" is allowed.
class LeadItemField extends StatefulWidget {
  const LeadItemField({super.key, required this.state});
  final LeadFormState state;
  @override
  State<LeadItemField> createState() => _LeadItemFieldState();
}

class _LeadItemFieldState extends State<LeadItemField> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _type = '';
  String _q = '';

  @override
  void initState() {
    super.initState();
    Api.list('/listings').then((r) {
      if (mounted) setState(() { _items = r; _loading = false; });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  String _typeOf(Map<String, dynamic> it) => '${it['type'] ?? 'product'}';
  String _title(Map<String, dynamic> it) => '${it['title'] ?? it['name'] ?? 'Item ${it['id']}'}';

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final s = widget.state;
    final types = _items.map(_typeOf).toSet().toList()..sort();
    final shown = _items.where((it) => (_type.isEmpty || _typeOf(it) == _type) && (_q.isEmpty || _title(it).toLowerCase().contains(_q.toLowerCase()))).toList();

    Widget row(int? id, String text, {String? sub}) {
      final on = s.itemId == id;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => s.itemId = id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          child: Row(children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: on ? primary : context.mutedColor),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w600 : FontWeight.w400))),
            if (sub != null) Text(sub, style: TextStyle(fontSize: 11.5, color: context.mutedColor)),
          ]),
        ),
      );
    }

    return FField(
      label: 'Product / Service',
      hint: 'What the customer enquired about — a different one makes a new lead',
      child: _loading
          ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (types.length > 1)
                Wrap(spacing: 6, children: [
                  for (final t in ['', ...types])
                    ChoiceChip(
                      label: Text(t.isEmpty ? 'All' : '${t[0].toUpperCase()}${t.substring(1)}', style: const TextStyle(fontSize: 11.5)),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = t),
                      visualDensity: VisualDensity.compact,
                    ),
                ]),
              if (_items.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim()),
                    decoration: const InputDecoration(hintText: 'Search products / services…', prefixIcon: Icon(Icons.search_rounded), border: OutlineInputBorder(), isDense: true),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    row(null, 'None'),
                    for (final it in shown)
                      row((it['id'] as num).toInt(), _title(it), sub: [if (types.length > 1) _typeOf(it), if (it['price'] != null && '${it['price']}' != '0' && '${it['price']}' != '0.00') '₹${it['price']}'].join(' · ')),
                    if (shown.isEmpty && _items.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text('Nothing matches.', style: TextStyle(color: context.mutedColor))),
                  ]),
                ),
              ),
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
