// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'books_common.dart';
import 'books_invoice.dart';
import 'books_voucher_form.dart';

class BooksVouchersTab extends StatefulWidget {
  const BooksVouchersTab({super.key});
  @override
  State<BooksVouchersTab> createState() => _BooksVouchersTabState();
}

class _BooksVouchersTabState extends State<BooksVouchersTab> with AutomaticKeepAliveClientMixin {
  DateTimeRange _range = currentFy();
  String _type = '';
  final _search = TextEditingController();
  List<Rec> _rows = [];
  bool _loading = true;
  String? _error;

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
      final d = await getJson('/accounts/vouchers', query: {
        'from': isoDate(_range.start), 'to': isoDate(_range.end), 'per_page': 100,
        if (_type.isNotEmpty) 'type': _type, if (_search.text.isNotEmpty) 'search': _search.text,
      });
      if (mounted) setState(() { _rows = asRecs(d['data']); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  Future<void> _open(String type, {Rec? voucher}) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BooksVoucherFormPage(type: type, voucher: voucher)));
    if (saved == true) _load();
  }

  Future<void> _edit(Rec v) async {
    try {
      final d = await getJson('/accounts/vouchers/${v['id']}');
      await _open('${v['type']}', voucher: (d['voucher'] as Map).cast<String, dynamic>());
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _einvoice(Rec v) => shareJson(context, '/accounts/einvoice', {'voucher_id': v['id']}, 'einvoice-${v['number']}.json');

  Future<void> _print(Rec v) async {
    try {
      final d = await getJson('/accounts/vouchers/${v['id']}');
      await printInvoice((d['voucher'] as Map).cast<String, dynamic>(), ((d['company'] as Map?) ?? const {}).cast<String, dynamic>());
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _delete(Rec v) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete voucher?'),
        content: Text('Delete ${v['number']}? Its ledger entries are removed too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes == true && await runAction(context, () => Api.delete('/accounts/vouchers/${v['id']}'), success: 'Deleted.')) _load();
  }

  void _newMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final e in voucherTypes.entries)
            ListTile(
              leading: Icon(e.value.$2, color: e.value.$3),
              title: Text(e.value.$1),
              onTap: () { Navigator.pop(ctx); _open(e.key); },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(onPressed: _newMenu, icon: const Icon(Icons.add_rounded), label: const Text('Voucher')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RangeBar(range: _range, onChanged: (r) { _range = r; _load(); }),
            const SizedBox(height: 6),
            TextField(
              controller: _search, onSubmitted: (_) => _load(),
              decoration: const InputDecoration(isDense: true, hintText: 'Search number / ref / note…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
            ),
          ]),
        ),
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('All'), selected: _type.isEmpty, onSelected: (_) { setState(() => _type = ''); _load(); })),
            for (final e in voucherTypes.entries)
              Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(e.value.$1), selected: _type == e.key, onSelected: (_) { setState(() => _type = e.key); _load(); })),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _rows.isEmpty
                      ? Center(child: Text('No vouchers in this period', style: TextStyle(color: context.mutedColor)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final v = _rows[i];
                              final m = voucherTypes[v['type']];
                              final particulars = (v['party'] is Map ? v['party']['name'] : null) ??
                                  (v['ledger'] is Map ? v['ledger']['name'] : null) ??
                                  (v['account'] is Map ? v['account']['name'] : null) ?? '—';
                              return RecordCard(
                                title: '${v['number']} · $particulars',
                                subtitle: '${'${v['date']}'.split('T').first} · ${m?.$1 ?? v['type']}${v['narration'] != null ? '\n${v['narration']}' : ''}',
                                leadingIcon: m?.$2 ?? Icons.receipt_rounded,
                                leadingColor: m?.$3,
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text(inr(v['total']), style: const TextStyle(fontWeight: FontWeight.w700)),
                                  RowMenu(items: [
                                    if (const ['sales', 'purchase', 'credit_note', 'debit_note'].contains(v['type'])) ('Print / PDF', Icons.print_rounded, () => _print(v)),
                                    if (const ['sales', 'credit_note', 'debit_note'].contains(v['type'])) ('e-Invoice JSON', Icons.data_object_rounded, () => _einvoice(v)),
                                    ('Edit', Icons.edit_rounded, () => _edit(v)),
                                    ('Delete', Icons.delete_outline_rounded, () => _delete(v)),
                                  ]),
                                ]),
                                onTap: () => _edit(v),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
