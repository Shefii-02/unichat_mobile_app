import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'books_common.dart';

class BooksGstTab extends StatefulWidget {
  const BooksGstTab({super.key});
  @override
  State<BooksGstTab> createState() => _BooksGstTabState();
}

class _BooksGstTabState extends State<BooksGstTab> with AutomaticKeepAliveClientMixin {
  static const _parts = [('b2b', 'B2B'), ('b2c', 'B2C'), ('notes', 'Cr/Dr notes'), ('rate', 'Rate-wise'), ('hsn', 'HSN'), ('purchases', 'Purchases')];
  DateTimeRange _range = currentFy();
  String _part = 'b2b';
  Map<String, dynamic>? _d;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  Map<String, dynamic> get _query => {'from': isoDate(_range.start), 'to': isoDate(_range.end)};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _d = null; _error = null; });
    try {
      final d = await getJson('/accounts/gst', query: _query);
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = _d;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        RangeBar(range: _range, onChanged: (r) { _range = r; _load(); }),
        if (_error != null) Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)),
        if (d == null && _error == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (d != null) ..._content(d),
      ]),
    );
  }

  List<Widget> _content(Map<String, dynamic> d) {
    final s = (d['summary'] as Map).cast<String, dynamic>();
    final out = (s['outward'] as Map).cast<String, dynamic>();
    final itc = (s['itc'] as Map).cast<String, dynamic>();
    final net = (s['net_payable'] as Map).cast<String, dynamic>();
    return [
      if (d['gstin'] == null) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Add your GSTIN in Settings to use these for filing.', style: TextStyle(color: AppPalette.warning, fontSize: 12))),
      const SectionHeader('Output tax (sales)'),
      AmountRow('Taxable value', out['taxable']), AmountRow('CGST', out['cgst']), AmountRow('SGST', out['sgst']), AmountRow('IGST', out['igst']),
      const SectionHeader('Input tax credit'),
      AmountRow('Eligible purchases', itc['taxable']), AmountRow('CGST', itc['cgst']), AmountRow('SGST', itc['sgst']), AmountRow('IGST', itc['igst']),
      const SectionHeader('GSTR-3B net payable'),
      AmountRow('CGST', net['cgst']), AmountRow('SGST', net['sgst']), AmountRow('IGST', net['igst']),
      AmountRow('Total', s['total_payable'], bold: true),
      Text('Negative = credit carried forward.', style: TextStyle(color: context.mutedColor, fontSize: 11)),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.data_object_rounded, size: 18), label: const Text('e-Invoice JSON (B2B sales)'),
          onPressed: () => shareJson(context, '/accounts/einvoice', {..._query, 'format': 'json'}, 'einvoice-bulk.json'),
        ),
      ),
      const SectionHeader('Details'),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final p in _parts)
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(p.$2), selected: _part == p.$1, onSelected: (_) => setState(() => _part = p.$1))),
        ]),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.ios_share_rounded, size: 18), label: const Text('Export CSV'),
          onPressed: () => shareCsv(context, '/accounts/gst', {..._query, 'part': _part}, 'gst-$_part.csv'),
        ),
      ),
      ..._detail(d),
    ];
  }

  List<Widget> _detail(Map<String, dynamic> d) {
    Widget inv(Rec r) => RecordCard(
          title: '${r['number']} · ${r['party'] ?? '—'}',
          subtitle: '${r['date']}${r['gstin'] != null ? ' · ${r['gstin']}' : ''}\nTaxable ${inr(r['taxable'])}  CGST ${inr(r['cgst'])}  SGST ${inr(r['sgst'])}  IGST ${inr(r['igst'])}',
          leadingIcon: Icons.receipt_long_rounded,
          trailing: Text(inr(r['total']), style: const TextStyle(fontWeight: FontWeight.w600)),
        );
    List<Widget> spaced(Iterable<Widget> w) => [for (final x in w) Padding(padding: const EdgeInsets.only(bottom: 8), child: x)];
    switch (_part) {
      case 'b2c':
        return spaced(asRecs(d['b2c']).map(inv));
      case 'notes':
        return spaced(asRecs(d['notes']).map(inv));
      case 'purchases':
        return spaced(asRecs(d['purchases']).map(inv));
      case 'rate':
        return spaced(asRecs(d['by_rate']).map((r) => RecordCard(
              title: '${r['gst_rate']}% GST',
              subtitle: 'Taxable ${inr(r['taxable'])}\nCGST ${inr(r['cgst'])}  SGST ${inr(r['sgst'])}  IGST ${inr(r['igst'])}',
              leadingIcon: Icons.percent_rounded,
            )));
      case 'hsn':
        return spaced(asRecs(d['hsn']).map((r) => RecordCard(
              title: 'HSN/SAC ${r['hsn']} · ${r['gst_rate']}%',
              subtitle: 'Qty ${r['qty']} · Taxable ${inr(r['taxable'])}\nCGST ${inr(r['cgst'])}  SGST ${inr(r['sgst'])}  IGST ${inr(r['igst'])}',
              leadingIcon: Icons.tag_rounded,
            )));
      default:
        return spaced(asRecs(d['b2b']).map(inv));
    }
  }
}
