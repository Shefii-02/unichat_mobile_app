// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'books_common.dart';

class _Line {
  _Line({this.itemId, String desc = '', String hsn = '', Object? qty = 1, Object? rate, this.gst = 18})
      : desc = TextEditingController(text: desc),
        hsn = TextEditingController(text: hsn),
        qty = TextEditingController(text: '${qty ?? 1}'),
        rate = TextEditingController(text: rate == null || numOf(rate) == 0 ? '' : '$rate');
  final TextEditingController desc, hsn, qty, rate;
  num gst;
  int? itemId;
  void dispose() { desc.dispose(); hsn.dispose(); qty.dispose(); rate.dispose(); }
}

class _JLine {
  _JLine({this.ledger, Object? debit, Object? credit})
      : debit = TextEditingController(text: debit == null || numOf(debit) == 0 ? '' : '$debit'),
        credit = TextEditingController(text: credit == null || numOf(credit) == 0 ? '' : '$credit');
  int? ledger;
  final TextEditingController debit, credit;
}

/// Create / edit one voucher. Same fields and the same server rules as the web form; the tax split
/// shown at the bottom is a preview of what the server posts (other state => IGST).
class BooksVoucherFormPage extends StatefulWidget {
  const BooksVoucherFormPage({super.key, required this.type, this.voucher});
  final String type;
  final Rec? voucher;
  @override
  State<BooksVoucherFormPage> createState() => _BooksVoucherFormPageState();
}

class _BooksVoucherFormPageState extends State<BooksVoucherFormPage> {
  List<Rec> _ledgers = [];
  List<Rec> _catalog = [];
  Map<String, dynamic> _company = {};
  bool _ready = false;
  bool _saving = false;
  String? _loadError;

  late DateTime _date = DateTime.now();
  int? _party, _ledger, _account;
  String? _pos;
  String? _tdsSection;
  final _tdsRate = TextEditingController(text: '0');
  num _gstRate = 0;
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  final _hsn = TextEditingController();
  final _ref = TextEditingController();
  final _narr = TextEditingController();
  final List<_Line> _items = [];
  final List<_JLine> _entries = [];

  String get _t => widget.type;
  /// Vouchers entered as GST line items; and the ones whose party is a customer.
  bool get _itemBased => const ['sales', 'purchase', 'credit_note', 'debit_note'].contains(_t);
  bool get _customerSide => const ['sales', 'receipt', 'credit_note'].contains(_t);
  bool get _editing => widget.voucher != null;

  @override
  void initState() {
    super.initState();
    _prefill();
    _loadLookups();
  }

  @override
  void dispose() {
    for (final c in [_amount, _desc, _hsn, _ref, _narr, _tdsRate]) { c.dispose(); }
    for (final i in _items) { i.dispose(); }
    super.dispose();
  }

  void _prefill() {
    final v = widget.voucher;
    if (v == null) {
      _items.add(_Line());
      _entries..add(_JLine())..add(_JLine());
      return;
    }
    _date = DateTime.tryParse('${v['date']}') ?? _date;
    _party = (v['party_ledger_id'] as num?)?.toInt();
    _ledger = (v['ledger_id'] as num?)?.toInt();
    _account = (v['account_ledger_id'] as num?)?.toInt();
    _pos = v['place_of_supply'] as String?;
    _tdsSection = (v['tds_section'] as String?)?.isNotEmpty == true ? v['tds_section'] as String : null;
    _tdsRate.text = '${numOf(v['tds_rate'])}';
    _ref.text = '${v['reference_no'] ?? ''}';
    _narr.text = '${v['narration'] ?? ''}';
    final items = asRecs(v['items']);
    _amount.text = ['receipt', 'payment', 'contra'].contains(_t) ? '${v['total']}' : '${v['taxable']}';
    if (items.isNotEmpty) {
      _gstRate = numOf(items.first['gst_rate']);
      _desc.text = '${items.first['description'] ?? ''}';
      _hsn.text = '${items.first['hsn'] ?? ''}';
      for (final i in items) {
        _items.add(_Line(itemId: (i['item_id'] as num?)?.toInt(), desc: '${i['description']}', hsn: '${i['hsn'] ?? ''}', qty: i['qty'], rate: i['rate'], gst: numOf(i['gst_rate'])));
      }
    } else {
      _items.add(_Line());
    }
    if (_t == 'journal') {
      for (final e in asRecs(v['entries'])) {
        _entries.add(_JLine(ledger: (e['ledger_id'] as num?)?.toInt(), debit: e['debit'], credit: e['credit']));
      }
    }
    while (_entries.length < 2) { _entries.add(_JLine()); }
  }

  Future<void> _loadLookups() async {
    try {
      final l = await getJson('/accounts/ledgers');
      final s = await getJson('/accounts/settings');
      final cat = await getJson('/accounts/items').catchError((_) => <String, dynamic>{});
      if (!mounted) return;
      setState(() {
        _ledgers = asRecs(l['ledgers']).where((x) => x['is_active'] != false).toList();
        _catalog = asRecs(cat['items']).where((x) => x['is_active'] != false).toList();
        _company = ((s['settings'] as Map?) ?? const {}).cast<String, dynamic>();
        _ready = true;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = apiErrorMessage(e));
    }
  }

  List<Rec> _by(List<String> groups) => _ledgers.where((l) => groups.contains(l['group'])).toList();

  Widget _ledgerDrop(String label, int? value, List<Rec> rows, ValueChanged<int?> on) {
    final ids = rows.map((r) => (r['id'] as num).toInt()).toSet();
    return FField(
      label: label,
      child: DropdownButtonFormField<int>(
        initialValue: ids.contains(value) ? value : null,
        isExpanded: true,
        hint: const Text('Select…'),
        items: [for (final r in rows) DropdownMenuItem(value: (r['id'] as num).toInt(), child: Text('${r['name']}', overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() => on(v)),
      ),
    );
  }

  Widget _gstDrop(num value, ValueChanged<num> on) => FField(
        label: 'GST %',
        child: DropdownButtonFormField<num>(
          initialValue: gstRates.contains(value) ? value : 0,
          items: [for (final r in gstRates) DropdownMenuItem(value: r, child: Text('$r%'))],
          onChanged: (v) => setState(() => on(v ?? 0)),
        ),
      );

  /// Same rule as the server: other state than the business => IGST, otherwise CGST + SGST.
  ({bool inter, num taxable, num tax}) _calc() {
    final party = _ledgers.where((l) => l['id'] == _party).firstOrNull;
    final counter = _pos ?? party?['state_code'] as String?;
    final mine = _company['state_code'] as String?;
    final inter = counter != null && mine != null && mine.isNotEmpty && counter != mine;
    num taxable = 0, tax = 0;
    if (_itemBased) {
      for (final i in _items) {
        final a = (num.tryParse(i.qty.text) ?? 0) * (num.tryParse(i.rate.text) ?? 0);
        taxable += a;
        tax += a * i.gst / 100;
      }
    } else {
      taxable = num.tryParse(_amount.text) ?? 0;
      tax = taxable * _gstRate / 100;
    }
    return (inter: inter, taxable: taxable, tax: tax);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'type': _t, 'date': isoDate(_date),
      'party_ledger_id': _party, 'ledger_id': _ledger, 'account_ledger_id': _account,
      'place_of_supply': _pos,
      'tds_section': _tdsSection, 'tds_rate': num.tryParse(_tdsRate.text) ?? 0,
      'reference_no': _ref.text.trim().isEmpty ? null : _ref.text.trim(),
      'narration': _narr.text.trim().isEmpty ? null : _narr.text.trim(),
      if (_itemBased)
        'items': [for (final i in _items) {'item_id': i.itemId, 'description': i.desc.text.trim(), 'hsn': i.hsn.text.trim().isEmpty ? null : i.hsn.text.trim(), 'qty': num.tryParse(i.qty.text) ?? 1, 'rate': num.tryParse(i.rate.text) ?? 0, 'gst_rate': i.gst}],
      if (_t == 'expense' || _t == 'income') ...{
        'amount': num.tryParse(_amount.text) ?? 0, 'gst_rate': _gstRate,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(), 'hsn': _hsn.text.trim().isEmpty ? null : _hsn.text.trim(),
      },
      if (_t == 'receipt' || _t == 'payment' || _t == 'contra') 'amount': num.tryParse(_amount.text) ?? 0,
      if (_t == 'journal')
        'entries': [for (final e in _entries) {'ledger_id': e.ledger, 'debit': num.tryParse(e.debit.text) ?? 0, 'credit': num.tryParse(e.credit.text) ?? 0}],
    };
    final ok = await runAction(
      context,
      () => _editing ? Api.put('/accounts/vouchers/${widget.voucher!['id']}', data: body) : Api.post('/accounts/vouchers', data: body),
      success: 'Saved.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final meta = voucherTypes[_t]!;
    return Scaffold(
      appBar: AppBar(title: Text('${_editing ? 'Edit' : 'New'} ${meta.$1}')),
      body: _loadError != null
          ? Center(child: Text(_loadError!))
          : !_ready
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: _fields()),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(onPressed: _saving || !_ready ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        ),
      ),
    );
  }

  List<Widget> _fields() {
    final cashBank = _by(['cash', 'bank']);
    final partyKind = _customerSide ? ['debtor'] : ['creditor'];
    final w = <Widget>[
      FField(
        label: 'Date',
        child: OutlinedButton.icon(
          icon: const Icon(Icons.event_rounded, size: 18),
          label: Text(isoDate(_date)),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2018), lastDate: DateTime(DateTime.now().year + 2));
            if (d != null) setState(() => _date = d);
          },
        ),
      ),
      FField(
        label: _t == 'purchase' ? 'Supplier bill no.' : _t == 'receipt' || _t == 'payment' ? 'Cheque / UTR / ref' : 'Reference',
        child: TextFormField(controller: _ref),
      ),
    ];

    if (_itemBased) {
      w.add(_ledgerDrop(_customerSide ? 'Customer' : 'Supplier', _party, _by(partyKind), (v) => _party = v));
    }
    if (_t == 'receipt' || _t == 'payment') {
      w.add(_ledgerDrop('Party', _party, _by(['debtor', 'creditor', 'tds']), (v) => _party = v));
      w.add(_ledgerDrop(_t == 'receipt' ? 'Received in' : 'Paid from', _account, cashBank, (v) => _account = v));
      w.add(FField(label: 'Amount', child: TextFormField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true))));
    }
    if (_t == 'contra') {
      w.add(_ledgerDrop('From', _account, cashBank, (v) => _account = v));
      w.add(_ledgerDrop('To', _ledger, cashBank, (v) => _ledger = v));
      w.add(FField(label: 'Amount', child: TextFormField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true))));
    }
    if (_t == 'expense' || _t == 'income') {
      if (_t == 'expense') {
        w.add(_ledgerDrop('Expense head', _ledger, _by(['indirect_expense', 'direct_expense', 'purchase', 'fixed_asset']), (v) => _ledger = v));
        w.add(_ledgerDrop('Paid from', _account, [...cashBank, ..._by(['creditor'])], (v) => _account = v));
      } else {
        w.add(_ledgerDrop('Income head', _ledger, _by(['indirect_income', 'direct_income', 'sales']), (v) => _ledger = v));
        w.add(_ledgerDrop('Received in', _account, [...cashBank, ..._by(['debtor'])], (v) => _account = v));
      }
      w.add(FField(label: 'Description', child: TextFormField(controller: _desc)));
      w.add(FField(label: 'Amount (before GST)', child: TextFormField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))));
      w.add(_gstDrop(_gstRate, (v) => _gstRate = v));
      w.add(FField(label: 'HSN / SAC (optional)', child: TextFormField(controller: _hsn)));
    }
    if (_itemBased || _t == 'expense' || _t == 'income') {
      w.add(FField(
        label: 'Place of supply',
        child: DropdownButtonFormField<String>(
          initialValue: _pos, isExpanded: true, hint: const Text('Same as party state'),
          items: [for (final e in gstStates.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} — ${e.value}'))],
          onChanged: (v) => setState(() => _pos = v),
        ),
      ));
    }
    if (_t == 'purchase' || _t == 'expense') {
      w.add(FField(
        label: 'TDS deducted (optional)',
        child: DropdownButtonFormField<String>(
          initialValue: _tdsSection, isExpanded: true, hint: const Text('No TDS'),
          items: [
            const DropdownMenuItem(value: '', child: Text('No TDS')),
            for (final e in tdsSections.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1)),
          ],
          onChanged: (v) => setState(() {
            _tdsSection = (v == null || v.isEmpty) ? null : v;
            _tdsRate.text = _tdsSection == null ? '0' : '${tdsSections[_tdsSection]!.$2}';
          }),
        ),
      ));
      if (_tdsSection != null) w.add(FField(label: 'TDS rate %', child: TextFormField(controller: _tdsRate, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))));
    }
    if (_itemBased) {
      w.add(const SectionHeader('Items'));
      for (var n = 0; n < _items.length; n++) {
        final it = _items[n];
        w.add(Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              if (_catalog.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DropdownButtonFormField<int>(
                    initialValue: _catalog.any((c) => c['id'] == it.itemId) ? it.itemId : null,
                    isExpanded: true, hint: const Text('Pick an item (optional)'),
                    items: [for (final c in _catalog) DropdownMenuItem(value: (c['id'] as num).toInt(), child: Text('${c['name']}', overflow: TextOverflow.ellipsis))],
                    onChanged: (id) => setState(() {
                      final c = _catalog.where((x) => x['id'] == id).firstOrNull;
                      it.itemId = id;
                      if (c == null) return;
                      final useSale = _t == 'sales' || _t == 'credit_note';
                      it.desc.text = '${c['name']}';
                      it.hsn.text = '${c['hsn'] ?? ''}';
                      it.gst = numOf(c['gst_rate']);
                      final rate = numOf(useSale ? c['sale_rate'] : c['purchase_rate']);
                      if (rate > 0) it.rate.text = '$rate';
                    }),
                  ),
                ),
              Row(children: [
                Expanded(child: TextField(controller: it.desc, decoration: const InputDecoration(labelText: 'Description', isDense: true))),
                if (_items.length > 1) IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _items.removeAt(n).dispose())),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: it.hsn, decoration: const InputDecoration(labelText: 'HSN/SAC', isDense: true))),
                const SizedBox(width: 8),
                SizedBox(width: 64, child: TextField(controller: it.qty, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Qty', isDense: true))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: it.rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Rate', isDense: true))),
                const SizedBox(width: 8),
                SizedBox(
                  width: 118, // narrower than this the "18%" and the arrow no longer fit and the row overflows
                  child: DropdownButtonFormField<num>(
                    isExpanded: true,
                    initialValue: gstRates.contains(it.gst) ? it.gst : 0,
                    decoration: const InputDecoration(labelText: 'GST', isDense: true),
                    items: [for (final r in gstRates) DropdownMenuItem(value: r, child: Text('$r%'))],
                    onChanged: (v) => setState(() => it.gst = v ?? 0),
                  ),
                ),
              ]),
            ]),
          ),
        ));
      }
      w.add(Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _items.add(_Line())), icon: const Icon(Icons.add_rounded), label: const Text('Add item'))));
    }
    if (_t == 'journal') {
      w.add(const SectionHeader('Lines'));
      for (final e in _entries) {
        w.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(children: [
            DropdownButtonFormField<int>(
              initialValue: e.ledger, isExpanded: true, hint: const Text('Ledger'),
              items: [for (final l in _ledgers) DropdownMenuItem(value: (l['id'] as num).toInt(), child: Text('${l['name']}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => e.ledger = v),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: TextField(controller: e.debit, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Debit', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: e.credit, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Credit', isDense: true))),
            ]),
          ]),
        ));
      }
      final dr = _entries.fold<num>(0, (s, e) => s + (num.tryParse(e.debit.text) ?? 0));
      final cr = _entries.fold<num>(0, (s, e) => s + (num.tryParse(e.credit.text) ?? 0));
      w.add(Row(children: [
        TextButton.icon(onPressed: () => setState(() => _entries.add(_JLine())), icon: const Icon(Icons.add_rounded), label: const Text('Add line')),
        const Spacer(),
        Text('Dr ${inr(dr)} · Cr ${inr(cr)}', style: TextStyle(color: (dr - cr).abs() < 0.01 ? AppPalette.success : AppPalette.danger, fontSize: 12)),
      ]));
    }

    w.add(FField(label: 'Narration / notes', child: TextFormField(controller: _narr, maxLines: 2)));

    if (_itemBased || _t == 'expense' || _t == 'income') {
      final c = _calc();
      w.add(Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            AmountRow('Taxable value', c.taxable),
            if (c.inter) AmountRow('IGST', c.tax) else ...[AmountRow('CGST', c.tax / 2), AmountRow('SGST', c.tax / 2)],
            const Divider(),
            AmountRow('Total', c.taxable + c.tax, bold: true),
            if ((_t == 'purchase' || _t == 'expense') && _tdsSection != null && (num.tryParse(_tdsRate.text) ?? 0) > 0)
              AmountRow('TDS ($_tdsSection) — pay ${inr(c.taxable + c.tax - c.taxable * (num.tryParse(_tdsRate.text) ?? 0) / 100)}', c.taxable * (num.tryParse(_tdsRate.text) ?? 0) / 100, color: AppPalette.warning),
            if ((_company['state_code'] as String?)?.isNotEmpty != true)
              const Text('Set your state in Accounts → Settings so CGST/SGST vs IGST is decided correctly.', style: TextStyle(color: AppPalette.warning, fontSize: 11)),
          ]),
        ),
      ));
    }
    return w;
  }
}
