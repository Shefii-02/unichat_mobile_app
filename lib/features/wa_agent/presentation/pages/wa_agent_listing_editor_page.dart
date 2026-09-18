// Create/edit form for one catalog listing — mirrors CatalogPage.tsx's editor modal. Fields
// adapt to the company's industry template: a fixed set (title/description/price/status/
// location) plus a dynamic `attribute_schema` (text/number/enum/boolean), plus free-form
// custom fields and URL-only media (no Google Drive integration on mobile).
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

class WaAgentListingEditorPage extends StatefulWidget {
  const WaAgentListingEditorPage({super.key, required this.listingType, this.template, this.existing});
  final String listingType;
  final Rec? template;
  final Rec? existing;

  @override
  State<WaAgentListingEditorPage> createState() => _WaAgentListingEditorPageState();
}

class _WaAgentListingEditorPageState extends State<WaAgentListingEditorPage> {
  bool get _editing => widget.existing != null;

  late final _titleCtrl = TextEditingController(text: str(widget.existing?['title'], ''));
  late final _descCtrl = TextEditingController(text: str(widget.existing?['description'], ''));
  late final _priceCtrl = TextEditingController(text: str(widget.existing?['price'], ''));
  late final _priceUnitCtrl = TextEditingController(text: str(widget.existing?['price_unit'], ''));
  late final _incentiveCtrl = TextEditingController(text: str(widget.existing?['incentive_percentage'], ''));
  late final _locationCtrl = TextEditingController(text: str(widget.existing?['location'], ''));
  late final _mediaUrlCtrl = TextEditingController();

  late String _status = str(widget.existing?['status'], 'active');
  late final Map<String, dynamic> _attributes = ((widget.existing?['attributes'] as Map?) ?? {}).cast<String, dynamic>();
  late final List<Map<String, String>> _customRows = ((widget.existing?['custom_fields'] as List?) ?? [])
      .map((f) => {'key': str((f as Map)['key'], ''), 'value': str(f['value'], '')})
      .toList()
      .cast<Map<String, String>>();
  late final List<String> _media = ((widget.existing?['media'] as List?) ?? []).map((m) => str((m as Map)['url'], '')).toList();

  bool _saving = false;
  String? _saveError;

  List<Rec> get _attributeSchema => ((widget.template?['attribute_schema'] as List?) ?? []).cast<Rec>();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _priceUnitCtrl.dispose();
    _incentiveCtrl.dispose();
    _locationCtrl.dispose();
    _mediaUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _saveError = 'Give the listing a title.');
      return;
    }
    setState(() { _saving = true; _saveError = null; });
    final customFields = _customRows.where((r) => r['key']!.trim().isNotEmpty).map((r) => {'key': r['key']!.trim(), 'value': r['value']}).toList();
    final data = <String, dynamic>{
      'type': widget.listingType,
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      'status': _status,
      'price': _priceCtrl.text.trim().isEmpty ? null : num.tryParse(_priceCtrl.text.trim()),
      'price_unit': _priceUnitCtrl.text.trim().isEmpty ? null : _priceUnitCtrl.text.trim(),
      'incentive_percentage': _incentiveCtrl.text.trim().isEmpty ? null : num.tryParse(_incentiveCtrl.text.trim()),
      'location': _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
      'attributes': _attributes,
      'custom_fields': customFields,
      'media': _media.where((u) => u.trim().isNotEmpty).map((u) => {'url': u}).toList(),
    };
    try {
      if (_editing) {
        await Api.put('/listings/${widget.existing!['id']}', data: data);
      } else {
        await Api.post('/listings', data: data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_editing ? 'Updated.' : 'Added.')));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _saveError = apiErrorMessage(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit listing' : 'New ${widget.listingType}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title *')),
          const SizedBox(height: 12),
          TextField(controller: _descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _priceUnitCtrl, decoration: const InputDecoration(labelText: 'Unit', hintText: 'total / per_month'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _incentiveCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Staff incentive %', hintText: 'overrides the rule'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'draft', child: Text('Draft')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                  DropdownMenuItem(value: 'sold', child: Text('Sold / filled')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'active'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _locationCtrl, decoration: const InputDecoration(labelText: 'Location / area')),
          if (_attributeSchema.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${str(widget.template?['name'], '')} details', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 10),
                  for (final f in _attributeSchema) Padding(padding: const EdgeInsets.only(bottom: 10), child: _attrField(f)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _customFieldsSection(),
          const SizedBox(height: 16),
          _mediaSection(),
          if (_saveError != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_saveError!, style: const TextStyle(color: AppPalette.danger, fontSize: 12))),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _attrField(Rec f) {
    final key = str(f['key']);
    final type = str(f['type'], 'text');
    final matchable = f['matchable'] == true;
    final label = '${str(f['label'], key)}${matchable ? ' ·match' : ''}';

    if (type == 'boolean') {
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        value: _attributes[key] == true,
        onChanged: (v) => setState(() => _attributes[key] = v ?? false),
        title: Text(label, style: const TextStyle(fontSize: 13)),
      );
    }
    if (type == 'enum') {
      final options = ((f['options'] as List?) ?? []).map((o) => '$o').toList();
      final current = str(_attributes[key], '');
      return DropdownButtonFormField<String>(
        initialValue: options.contains(current) ? current : null,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('—')),
          ...options.map((o) => DropdownMenuItem(value: o, child: Text(o))),
        ],
        onChanged: (v) => setState(() => _attributes[key] = v),
      );
    }
    return TextFormField(
      initialValue: str(_attributes[key], ''),
      keyboardType: type == 'number' ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (v) => _attributes[key] = type == 'number' ? num.tryParse(v) : (v.isEmpty ? null : v),
    );
  }

  Widget _customFieldsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Custom fields', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
            TextButton(onPressed: () => setState(() => _customRows.add({'key': '', 'value': ''})), child: const Text('+ Add custom field', style: TextStyle(fontSize: 12))),
          ]),
          if (_customRows.isEmpty)
            Text("Anything this listing needs that isn't already covered above — add your own name and value.", style: TextStyle(fontSize: 11, color: context.mutedColor))
          else
            for (var i = 0; i < _customRows.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _customRows[i]['key'],
                      decoration: const InputDecoration(hintText: 'Field name', isDense: true),
                      onChanged: (v) => _customRows[i]['key'] = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: _customRows[i]['value'],
                      decoration: const InputDecoration(hintText: 'Value', isDense: true),
                      onChanged: (v) => _customRows[i]['value'] = v,
                    ),
                  ),
                  IconButton(onPressed: () => setState(() => _customRows.removeAt(i)), icon: const Icon(Icons.close_rounded, size: 18)),
                ]),
              ),
        ],
      ),
    );
  }

  Widget _mediaSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Photos / videos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 8),
          if (_media.isEmpty)
            Text('None', style: TextStyle(fontSize: 12, color: context.mutedColor))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < _media.length; i++)
                Chip(
                  label: Text(_media[i].length > 34 ? '${_media[i].substring(0, 34)}…' : _media[i], style: const TextStyle(fontSize: 11)),
                  onDeleted: () => setState(() => _media.removeAt(i)),
                ),
            ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _mediaUrlCtrl, decoration: const InputDecoration(hintText: 'Paste an image/video URL', isDense: true))),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                if (_mediaUrlCtrl.text.trim().isEmpty) return;
                setState(() { _media.add(_mediaUrlCtrl.text.trim()); _mediaUrlCtrl.clear(); });
              },
              child: const Text('Add URL'),
            ),
          ]),
        ],
      ),
    );
  }
}
