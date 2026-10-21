// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'books_common.dart';

class BooksReportsTab extends StatefulWidget {
  const BooksReportsTab({super.key});
  @override
  State<BooksReportsTab> createState() => _BooksReportsTabState();
}

class _BooksReportsTabState extends State<BooksReportsTab> with AutomaticKeepAliveClientMixin {
  static const _reports = [
    ('profit-loss', 'Profit & Loss'), ('balance-sheet', 'Balance Sheet'), ('trial-balance', 'Trial Balance'),
    ('day-book', 'Day Book'), ('ledger', 'Ledger'), ('bank-reconciliation', 'Bank Rec.'), ('tds', 'TDS'), ('receivables', 'Receivables'), ('payables', 'Payables'),
  ];
  String _name = 'profit-loss';
  DateTimeRange _range = currentFy();
  List<Rec> _ledgers = [];
  int? _ledgerId;
  final Set<int> _picked = {};
  final _stmt = TextEditingController();
  DateTime _clearOn = DateTime.now();
  bool _busy = false;
  bool get _needsLedger => _name == 'ledger' || _name == 'bank-reconciliation';
  Map<String, dynamic>? _d;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  Map<String, dynamic> get _query => {'from': isoDate(_range.start), 'to': isoDate(_range.end), if (_ledgerId != null) 'ledger_id': _ledgerId};

  @override
  void initState() {
    super.initState();
    getJson('/accounts/ledgers').then((d) { if (mounted) setState(() => _ledgers = asRecs(d['ledgers'])); }).catchError((_) {});
    _load();
  }

  Future<void> _load() async {
    if (_needsLedger && _ledgerId == null) { setState(() { _d = null; _error = null; }); return; }
    setState(() { _d = null; _error = null; _picked.clear(); });
    try {
      final d = await getJson('/accounts/reports/$_name', query: _query);
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  Future<void> _markCleared() async {
    setState(() => _busy = true);
    final ok = await runAction(context, () => Api.post('/accounts/reconcile', data: {'entry_ids': _picked.toList(), 'date': isoDate(_clearOn)}), success: 'Marked as cleared.');
    if (mounted) setState(() => _busy = false);
    if (ok) _load();
  }

  @override
  void dispose() {
    _stmt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(padding: const EdgeInsets.all(12), children: [
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final r in _reports)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(r.$2), selected: _name == r.$1, onSelected: (_) { _name = r.$1; _load(); }),
            ),
        ]),
      ),
      RangeBar(range: _range, onChanged: (r) { _range = r; _load(); }),
      if (_needsLedger)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DropdownButtonFormField<int>(
            initialValue: _ledgerId, isExpanded: true, hint: Text(_name == 'bank-reconciliation' ? 'Select bank / cash account' : 'Select ledger'),
            items: [for (final l in _ledgers.where((l) => _name != 'bank-reconciliation' || l['group'] == 'bank' || l['group'] == 'cash')) DropdownMenuItem(value: (l['id'] as num).toInt(), child: Text(str(l['name'])))],
            onChanged: (v) { _ledgerId = v; _load(); },
          ),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.ios_share_rounded, size: 18), label: const Text('Export CSV'),
          onPressed: _d == null ? null : () => shareCsv(context, '/accounts/reports/$_name', _query, '$_name.csv'),
        ),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)),
      if (_d == null && _error == null)
        Padding(
          padding: const EdgeInsets.all(40),
          child: Center(child: _needsLedger && _ledgerId == null ? Text('Pick an account.', style: TextStyle(color: context.mutedColor)) : const CircularProgressIndicator()),
        ),
      if (_d != null) ..._body(_d!),
    ]);
  }

  List<Widget> _body(Map<String, dynamic> d) {
    switch (_name) {
      case 'profit-loss':
        final net = numOf(d['net_profit']);
        return [
          const SectionHeader('Income'),
          for (final r in asRecs(d['income'])) AmountRow('${r['name']}', r['amount']),
          AmountRow('Total income', d['total_income'], bold: true),
          const SectionHeader('Expenses'),
          for (final r in asRecs(d['expense'])) AmountRow('${r['name']}', r['amount']),
          AmountRow('Total expenses', d['total_expense'], bold: true),
          const Divider(height: 24),
          AmountRow(net >= 0 ? 'Net profit' : 'Net loss', net.abs(), bold: true, color: net >= 0 ? AppPalette.success : AppPalette.danger),
          AmountRow('Gross profit', d['gross_profit']),
        ];
      case 'balance-sheet':
        final diff = numOf(d['total_assets']) - numOf(d['total_liabilities']);
        return [
          const SectionHeader('Assets'),
          for (final r in asRecs(d['assets'])) AmountRow('${r['name']}', r['amount']),
          AmountRow('Total assets', d['total_assets'], bold: true),
          const SectionHeader('Liabilities & equity'),
          for (final r in asRecs(d['liabilities'])) AmountRow('${r['name']}', r['amount']),
          AmountRow('Total', d['total_liabilities'], bold: true),
          if (diff.abs() > 0.01)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text("Totals differ by ${inr(diff)} — opening balances of your ledgers don't balance. Add the difference to Capital as an opening balance.",
                  style: const TextStyle(color: AppPalette.warning, fontSize: 12)),
            ),
        ];
      case 'trial-balance':
        return [
          for (final r in asRecs(d['rows']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text('${r['name']}')),
                SizedBox(width: 100, child: Text(numOf(r['debit']) > 0 ? inr(r['debit']) : '', textAlign: TextAlign.right)),
                SizedBox(width: 100, child: Text(numOf(r['credit']) > 0 ? inr(r['credit']) : '', textAlign: TextAlign.right)),
              ]),
            ),
          const Divider(),
          Row(children: [
            const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800))),
            SizedBox(width: 100, child: Text(inr(d['total_debit']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
            SizedBox(width: 100, child: Text(inr(d['total_credit']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
        ];
      case 'day-book':
        return [
          for (final r in asRecs(d['rows']))
            RecordCard(
              title: '${r['number']}',
              subtitle: '${r['date']} · ${r['particulars'] ?? '—'}',
              leadingIcon: voucherTypes[r['type']]?.$2 ?? Icons.receipt_rounded,
              leadingColor: voucherTypes[r['type']]?.$3,
              trailing: Text(inr(r['total']), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ];
      case 'bank-reconciliation':
        final stmt = num.tryParse(_stmt.text);
        final diff = stmt == null ? null : stmt - numOf(d['reconciled_balance']);
        final pending = asRecs(d['pending']);
        return [
          AmountRow('Balance as per books', d['book_balance']),
          AmountRow('Cleared by bank', d['reconciled_balance']),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: TextField(controller: _stmt, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(isDense: true, labelText: 'Closing balance on bank statement')),
          ),
          if (diff != null)
            Text(diff.abs() < 0.01 ? 'Reconciled ✓' : 'Difference ${inr(diff)}', style: TextStyle(fontWeight: FontWeight.w700, color: diff.abs() < 0.01 ? AppPalette.success : AppPalette.danger)),
          const SectionHeader('Not yet cleared'),
          Row(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded, size: 18), label: Text(isoDate(_clearOn)),
              onPressed: () async {
                final x = await showDatePicker(context: context, initialDate: _clearOn, firstDate: DateTime(2018), lastDate: DateTime(DateTime.now().year + 1));
                if (x != null) setState(() => _clearOn = x);
              },
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _picked.isEmpty || _busy ? null : _markCleared, child: Text('Mark ${_picked.length} cleared')),
          ]),
          if (pending.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('Everything up to this date is reconciled.', style: TextStyle(color: context.mutedColor))),
          for (final r in pending)
            CheckboxListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              value: _picked.contains((r['entry_id'] as num).toInt()),
              onChanged: (v) => setState(() => v == true ? _picked.add((r['entry_id'] as num).toInt()) : _picked.remove((r['entry_id'] as num).toInt())),
              title: Text('${r['number'] ?? '—'}  ·  ${r['date']}'),
              subtitle: Text('${r['narration'] ?? r['reference_no'] ?? ''}'),
              secondary: Text(numOf(r['debit']) > 0 ? '+${inr(r['debit'])}' : '-${inr(r['credit'])}', style: TextStyle(fontWeight: FontWeight.w600, color: numOf(r['debit']) > 0 ? AppPalette.success : AppPalette.danger)),
            ),
        ];
      case 'tds':
        return [
          AmountRow('TDS deducted', d['total_deducted']),
          AmountRow('Deposited to government', d['deposited_to_government']),
          AmountRow('Payable now', d['payable_now'], bold: true, color: AppPalette.warning),
          Text('To deposit TDS, add a Payment voucher with the "TDS Payable" ledger as the party and your bank as the account.', style: TextStyle(color: context.mutedColor, fontSize: 11)),
          const SectionHeader('By section'),
          for (final r in asRecs(d['by_section'])) AmountRow('${r['section']}  ·  ${r['count']} entries  ·  taxable ${inr(r['taxable'])}', r['tds']),
          const SectionHeader('Entries'),
          for (final r in asRecs(d['rows']))
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text('${r['number']} · ${r['party'] ?? '—'}'),
              subtitle: Text('${r['date']} · ${r['section']} @ ${r['rate']}%${r['pan'] != null ? ' · PAN ${r['pan']}' : ''}'),
              trailing: Text(inr(r['tds']), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ];
      case 'ledger':
        final l = (d['ledger'] as Map?) ?? const {};
        return [
          Text('${l['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          AmountRow('Opening', d['opening']),
          for (final r in asRecs(d['rows']))
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text('${r['number'] ?? '—'}  ·  ${r['date']}'),
              subtitle: Text(numOf(r['debit']) > 0 ? 'Dr ${inr(r['debit'])}' : 'Cr ${inr(r['credit'])}'),
              trailing: Text(inr(r['balance']), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          AmountRow('Closing', d['closing'], bold: true),
        ];
      default: // receivables | payables
        return [
          for (final r in asRecs(d['rows'])) AmountRow('${r['name']}${r['phone'] != null ? '  ·  ${r['phone']}' : ''}', r['amount']),
          AmountRow('Total', d['total'], bold: true),
        ];
    }
  }
}
