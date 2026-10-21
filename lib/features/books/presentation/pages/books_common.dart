// ignore_for_file: use_build_context_synchronously
import 'dart:io';

import 'package:dio/dio.dart' show DioException, Options, ResponseType;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// ₹1,23,456.00
String inr(Object? v) => _inr.format(num.tryParse('${v ?? 0}') ?? 0);

num numOf(Object? v) => num.tryParse('${v ?? 0}') ?? 0;

String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Indian financial year (Apr–Mar) containing today.
DateTimeRange currentFy() {
  final n = DateTime.now();
  final y = n.month >= 4 ? n.year : n.year - 1;
  return DateTimeRange(start: DateTime(y, 4, 1), end: DateTime(y + 1, 3, 31));
}

const voucherTypes = <String, (String, IconData, Color)>{
  'sales': ('Sales Invoice', Icons.receipt_long_rounded, Color(0xFF16A34A)),
  'purchase': ('Purchase Bill', Icons.shopping_cart_rounded, Color(0xFFEA580C)),
  'receipt': ('Receipt', Icons.call_received_rounded, Color(0xFF16A34A)),
  'payment': ('Payment', Icons.call_made_rounded, Color(0xFFDC2626)),
  'expense': ('Expense', Icons.payments_rounded, Color(0xFFDC2626)),
  'income': ('Other Income', Icons.savings_rounded, Color(0xFF16A34A)),
  'journal': ('Journal', Icons.menu_book_rounded, Color(0xFF5C6570)),
  'contra': ('Contra (Cash/Bank)', Icons.swap_horiz_rounded, Color(0xFF5C6570)),
  'credit_note': ('Credit Note (sales return)', Icons.undo_rounded, Color(0xFFDC2626)),
  'debit_note': ('Debit Note (purchase return)', Icons.redo_rounded, Color(0xFF16A34A)),
};

const gstRates = [0, 5, 12, 18, 28];

/// Common TDS sections: key -> (label, usual rate %). The rate stays editable on the form.
const tdsSections = <String, (String, num)>{
  '194C': ('Contractors (194C)', 1), '194J': ('Professional / technical fees (194J)', 10), '194H': ('Commission / brokerage (194H)', 5),
  '194I': ('Rent (194I)', 10), '194A': ('Interest other than securities (194A)', 10), '194Q': ('Purchase of goods (194Q)', 0.1),
};

const gstStates = <String, String>{
  '01': 'Jammu & Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh', '05': 'Uttarakhand',
  '06': 'Haryana', '07': 'Delhi', '08': 'Rajasthan', '09': 'Uttar Pradesh', '10': 'Bihar', '11': 'Sikkim',
  '12': 'Arunachal Pradesh', '13': 'Nagaland', '14': 'Manipur', '15': 'Mizoram', '16': 'Tripura', '17': 'Meghalaya',
  '18': 'Assam', '19': 'West Bengal', '20': 'Jharkhand', '21': 'Odisha', '22': 'Chhattisgarh', '23': 'Madhya Pradesh',
  '24': 'Gujarat', '26': 'Dadra & Nagar Haveli and Daman & Diu', '27': 'Maharashtra', '29': 'Karnataka', '30': 'Goa',
  '31': 'Lakshadweep', '32': 'Kerala', '33': 'Tamil Nadu', '34': 'Puducherry', '35': 'Andaman & Nicobar',
  '36': 'Telangana', '37': 'Andhra Pradesh', '38': 'Ladakh', '97': 'Other Territory',
};

/// Ledger types: key -> (accounting nature, label)
const ledgerGroups = <String, (String, String)>{
  'debtor': ('asset', 'Customer (receivable)'),
  'creditor': ('liability', 'Supplier / vendor (payable)'),
  'cash': ('asset', 'Cash'),
  'bank': ('asset', 'Bank account'),
  'fixed_asset': ('asset', 'Fixed asset'),
  'gst_input': ('asset', 'GST input credit'),
  'gst_output': ('liability', 'GST payable'),
  'tds': ('liability', 'TDS payable'),
  'loan': ('liability', 'Loan'),
  'capital': ('equity', 'Capital / drawings'),
  'sales': ('income', 'Sales income'),
  'direct_income': ('income', 'Direct income'),
  'indirect_income': ('income', 'Other income'),
  'purchase': ('expense', 'Purchases'),
  'direct_expense': ('expense', 'Direct expense'),
  'indirect_expense': ('expense', 'Office / indirect expense'),
  'other': ('asset', 'Other asset'),
};

/// Laravel envelopes here are plain objects (`{ ledgers: [...] }`, `{ rows: ... }`), so read the raw body.
Future<Map<String, dynamic>> getJson(String path, {Map<String, dynamic>? query}) async {
  final res = await Api.raw.get(path, queryParameters: query);
  return (res.data as Map).cast<String, dynamic>();
}

List<Rec> asRecs(Object? v) =>
    ((v as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

/// Downloads a report as CSV (server `?format=csv`) and opens the share sheet.
Future<void> shareCsv(BuildContext context, String path, Map<String, dynamic> query, String filename) async {
  await runAction(context, () async {
    final res = await Api.raw.get(path, queryParameters: {...query, 'format': 'csv'}, options: Options(responseType: ResponseType.bytes));
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(List<int>.from(res.data as List));
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')]);
  });
}

/// Downloads a JSON file from the server (e-invoice export) and opens the share sheet.
Future<void> shareJson(BuildContext context, String path, Map<String, dynamic> query, String filename) async {
  try {
    final res = await Api.raw.get(path, queryParameters: query, options: Options(responseType: ResponseType.bytes));
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(List<int>.from(res.data as List));
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')]);
  } on DioException catch (e) {
    // an error body arrives as bytes — pull the server's message out of it
    var msg = apiErrorMessage(e);
    final body = e.response?.data;
    if (body is List<int>) {
      final m = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(String.fromCharCodes(body));
      if (m != null) msg = m.group(1)!;
    }
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
  }
}

/// "1 Apr 2026 – 31 Mar 2027" tappable range selector with quick presets.
class RangeBar extends StatelessWidget {
  const RangeBar({super.key, required this.range, required this.onChanged});
  final DateTimeRange range;
  final ValueChanged<DateTimeRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('d MMM yyyy');
    final n = DateTime.now();
    final presets = <String, DateTimeRange>{
      'This month': DateTimeRange(start: DateTime(n.year, n.month, 1), end: DateTime(n.year, n.month + 1, 0)),
      'Last month': DateTimeRange(start: DateTime(n.year, n.month - 1, 1), end: DateTime(n.year, n.month, 0)),
      'This FY': currentFy(),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.date_range_rounded, size: 18),
        label: Text('${f.format(range.start)} – ${f.format(range.end)}'),
        onPressed: () async {
          final r = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2018),
            lastDate: DateTime(n.year + 2),
            initialDateRange: range,
          );
          if (r != null) onChanged(r);
        },
      ),
      Wrap(spacing: 6, children: [
        for (final e in presets.entries) ActionChip(label: Text(e.key), onPressed: () => onChanged(e.value)),
      ]),
    ]);
  }
}

/// Label on the left, amount on the right.
class AmountRow extends StatelessWidget {
  const AmountRow(this.label, this.amount, {super.key, this.bold = false, this.color});
  final String label;
  final Object? amount;
  final bool bold;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(inr(amount), style: style),
      ]),
    );
  }
}
