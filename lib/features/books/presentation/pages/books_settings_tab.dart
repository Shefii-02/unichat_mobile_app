import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'books_common.dart';

class BooksSettingsTab extends StatefulWidget {
  const BooksSettingsTab({super.key});
  @override
  State<BooksSettingsTab> createState() => _BooksSettingsTabState();
}

class _BooksSettingsTabState extends State<BooksSettingsTab> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _s;
  String? _error;
  bool _saving = false;
  final _key = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c = {
    for (final k in ['legal_name', 'gstin', 'pan', 'address', 'city', 'pincode', 'invoice_prefix']) k: TextEditingController(),
  };
  String? _state;
  int _fy = 4;
  bool _registered = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = (await getJson('/accounts/settings'))['settings'] as Map;
      if (!mounted) return;
      setState(() {
        _s = s.cast<String, dynamic>();
        for (final e in _c.entries) { e.value.text = '${s[e.key] ?? ''}'; }
        _state = (s['state_code'] as String?)?.isNotEmpty == true ? s['state_code'] as String : null;
        _fy = (s['fy_start_month'] as num?)?.toInt() ?? 4;
        _registered = s['gst_registered'] != false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  Future<void> _save() async {
    if (!(_key.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    String? v(String k) => _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();
    final ok = await runAction(context, () => Api.put('/accounts/settings', data: {
      'legal_name': v('legal_name'), 'gstin': v('gstin')?.toUpperCase(), 'pan': v('pan')?.toUpperCase(),
      'address': v('address'), 'city': v('city'), 'pincode': v('pincode'), 'invoice_prefix': v('invoice_prefix'), 'state_code': _state, 'fy_start_month': _fy, 'gst_registered': _registered,
    }), success: 'Saved.');
    if (mounted) setState(() => _saving = false);
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return Center(child: Text(_error!));
    if (_s == null) return const Center(child: CircularProgressIndicator());
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return Form(
      key: _key,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        FField(label: 'Legal / trade name', child: TextFormField(controller: _c['legal_name'])),
        FField(label: 'GSTIN', child: TextFormField(
          controller: _c['gstin'], textCapitalization: TextCapitalization.characters,
          validator: (x) => x == null || x.trim().isEmpty || RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]$', caseSensitive: false).hasMatch(x.trim()) ? null : 'Not a valid GSTIN',
        )),
        FField(label: 'PAN', child: TextFormField(
          controller: _c['pan'], textCapitalization: TextCapitalization.characters,
          validator: (x) => x == null || x.trim().isEmpty || RegExp(r'^[A-Z]{5}\d{4}[A-Z]$', caseSensitive: false).hasMatch(x.trim()) ? null : 'Not a valid PAN',
        )),
        FField(label: 'State (place of business)', child: DropdownButtonFormField<String>(
          initialValue: _state, isExpanded: true,
          items: [for (final e in gstStates.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} — ${e.value}'))],
          onChanged: (v) => setState(() => _state = v),
        )),
        FField(label: 'City', child: TextFormField(controller: _c['city'])),
        FField(label: 'Pincode', child: TextFormField(controller: _c['pincode'], keyboardType: TextInputType.number, maxLength: 6)),
        FField(label: 'Invoice prefix', child: TextFormField(controller: _c['invoice_prefix'])),
        FField(label: 'Financial year starts', child: DropdownButtonFormField<int>(
          initialValue: _fy, isExpanded: true,
          items: [for (var i = 0; i < 12; i++) DropdownMenuItem(value: i + 1, child: Text(months[i]))],
          onChanged: (v) => setState(() => _fy = v ?? 4),
        )),
        FField(label: 'Address (printed on invoices)', child: TextFormField(controller: _c['address'], maxLines: 2)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero, value: _registered, onChanged: (v) => setState(() => _registered = v),
          title: const Text('GST registered'),
          subtitle: const Text('Off: no GST on sales and no input credit claimed'),
        ),
        const Text('The state decides CGST + SGST (same state) or IGST (other state) on every invoice and bill.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ]),
    );
  }
}
