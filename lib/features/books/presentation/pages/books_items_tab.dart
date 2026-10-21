// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'books_common.dart';

/// Products and services; stock-tracked items show quantity and value on hand.
class BooksItemsTab extends StatefulWidget {
  const BooksItemsTab({super.key});
  @override
  State<BooksItemsTab> createState() => _BooksItemsTabState();
}

class _BooksItemsTabState extends State<BooksItemsTab> with AutomaticKeepAliveClientMixin {
  List<Rec> _rows = [];
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await getJson('/accounts/items', query: {if (_search.text.isNotEmpty) 'search': _search.text});
      if (mounted) setState(() { _rows = asRecs(d['items']); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  Future<void> _delete(Rec r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Delete "${r['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes == true && await runAction(context, () => Api.delete('/accounts/items/${r['id']}'), success: 'Deleted.')) _load();
  }

  Future<void> _form(Rec? r) async {
    String s(String k) => r == null || r[k] == null ? '' : '${r[k]}';
    num? n(String k) => r == null || numOf(r[k]) == 0 ? null : numOf(r[k]);
    var name = s('name'), sku = s('sku'), hsn = s('hsn'), unit = r == null ? 'NOS' : s('unit');
    num gst = r == null ? 18 : numOf(r['gst_rate']);
    num? sale = n('sale_rate'), purchase = n('purchase_rate'), openQty = n('opening_qty'), openVal = n('opening_value');
    num? reorder = r == null || r['reorder_level'] == null ? null : numOf(r['reorder_level']);
    var track = r == null ? true : r['track_stock'] != false;
    var active = r == null ? true : r['is_active'] != false;

    final saved = await showFormSheet(
      context,
      title: r == null ? 'New item' : 'Edit item',
      fields: (ctx) => [
        FText(label: 'Name', initial: name, required: true, onSaved: (v) => name = v),
        FText(label: 'SKU / code', initial: sku, onSaved: (v) => sku = v),
        FText(label: 'HSN / SAC', initial: hsn, onSaved: (v) => hsn = v),
        FText(label: 'Unit', initial: unit, onSaved: (v) => unit = v.toUpperCase()),
        FSelect<num>(label: 'GST %', options: gstRates, initial: gstRates.contains(gst) ? gst : 18, labelOf: (v) => '$v%', onSaved: (v) => gst = v ?? 18),
        FNumber(label: 'Sale rate', initial: sale, onSaved: (v) => sale = v),
        FNumber(label: 'Purchase rate', initial: purchase, onSaved: (v) => purchase = v),
        FBoolField(label: 'Track stock (off for a service)', initial: track, onSaved: (v) => track = v),
        FNumber(label: 'Opening quantity', initial: openQty, onSaved: (v) => openQty = v),
        FNumber(label: 'Opening value (total cost)', initial: openVal, onSaved: (v) => openVal = v),
        FNumber(label: 'Reorder level (low-stock alert)', initial: reorder, onSaved: (v) => reorder = v),
        if (r != null) FBoolField(label: 'Active', initial: active, onSaved: (v) => active = v),
      ],
      onSubmit: () async {
        final body = {
          'name': name, 'sku': sku.isEmpty ? null : sku, 'hsn': hsn.isEmpty ? null : hsn, 'unit': unit.isEmpty ? 'NOS' : unit, 'gst_rate': gst,
          'sale_rate': sale ?? 0, 'purchase_rate': purchase ?? 0, 'track_stock': track,
          'opening_qty': openQty ?? 0, 'opening_value': openVal ?? 0, 'reorder_level': reorder, 'is_active': active,
        };
        r == null ? await Api.post('/accounts/items', data: body) : await Api.put('/accounts/items/${r['id']}', data: body);
      },
    );
    if (saved) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final total = _rows.fold<num>(0, (s, r) => s + numOf(r['stock_value']));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _form(null), icon: const Icon(Icons.add_rounded), label: const Text('Item')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(controller: _search, onSubmitted: (_) => _load(), decoration: const InputDecoration(isDense: true, hintText: 'Search items…', prefixIcon: Icon(Icons.search_rounded, size: 20))),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), child: Align(alignment: Alignment.centerLeft, child: Text('Stock value: ${inr(total)}', style: TextStyle(color: context.mutedColor)))),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _rows.isEmpty
                      ? Center(child: Text('No items yet', style: TextStyle(color: context.mutedColor)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final r = _rows[i];
                              final stock = r['track_stock'] != false;
                              return RecordCard(
                                title: str(r['name']),
                                subtitle: '${r['hsn'] != null ? 'HSN ${r['hsn']} · ' : ''}GST ${r['gst_rate']}% · sale ${inr(r['sale_rate'])}',
                                leadingIcon: Icons.inventory_2_rounded,
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text(stock ? '${r['stock_qty'] ?? 0} ${r['unit']}' : 'Service', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    if (stock) Text(inr(r['stock_value']), style: TextStyle(color: context.mutedColor, fontSize: 11)),
                                    if (r['low'] == true) const Text('LOW', style: TextStyle(color: AppPalette.danger, fontSize: 10, fontWeight: FontWeight.w800)),
                                  ]),
                                  RowMenu(items: [
                                    ('Edit', Icons.edit_rounded, () => _form(r)),
                                    ('Delete', Icons.delete_outline_rounded, () => _delete(r)),
                                  ]),
                                ]),
                                onTap: () => _form(r),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
