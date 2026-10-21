import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'books_common.dart';

/// Builds the printable tax invoice / purchase bill PDF (same layout as the web print view).
Future<Uint8List> buildInvoicePdf(Map<String, dynamic> v, Map<String, dynamic> co, PdfPageFormat format) async {
  final party = (v['party'] as Map?) ?? const {};
  final items = asRecs(v['items']);
  final inter = v['is_interstate'] == true;
  final isSales = v['type'] == 'sales' || v['type'] == 'credit_note';
  final title = const {'sales': 'TAX INVOICE', 'purchase': 'PURCHASE BILL', 'credit_note': 'CREDIT NOTE', 'debit_note': 'DEBIT NOTE'}[v['type']] ?? 'INVOICE';
  final date = '${v['date']}'.split('T').first;
  // The built-in PDF fonts have no ₹ glyph, so amounts use "Rs." here.
  String rs(Object? x) => inr(x).replaceFirst('₹', 'Rs. ');

  pw.Widget cell(String t, {bool bold = false, bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(t, textAlign: right ? pw.TextAlign.right : pw.TextAlign.left, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: format,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('${co['legal_name'] ?? 'Your business'}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (co['address'] != null) pw.Text('${co['address']}', style: const pw.TextStyle(fontSize: 9)),
            if (co['gstin'] != null) pw.Text('GSTIN: ${co['gstin']}', style: const pw.TextStyle(fontSize: 9)),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('No: ${v['number']}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Date: $date', style: const pw.TextStyle(fontSize: 10)),
          if (v['reference_no'] != null) pw.Text('Ref: ${v['reference_no']}', style: const pw.TextStyle(fontSize: 10)),
        ]),
      ]),
      pw.SizedBox(height: 14),
      pw.Text('${isSales ? 'Bill to' : 'Supplier'}: ${party['name'] ?? '-'}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      if (party['address'] != null) pw.Text('${party['address']}', style: const pw.TextStyle(fontSize: 9)),
      if (party['gstin'] != null) pw.Text('GSTIN: ${party['gstin']}', style: const pw.TextStyle(fontSize: 9)),
      if (v['place_of_supply'] != null) pw.Text('Place of supply: ${v['place_of_supply']}', style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 12),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400),
        columnWidths: const {0: pw.FixedColumnWidth(24), 1: pw.FlexColumnWidth(3), 2: pw.FlexColumnWidth(1.2), 3: pw.FixedColumnWidth(34), 4: pw.FlexColumnWidth(1.4), 5: pw.FixedColumnWidth(38), 6: pw.FlexColumnWidth(1.5)},
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
            cell('#', bold: true), cell('Description', bold: true), cell('HSN/SAC', bold: true), cell('Qty', bold: true, right: true),
            cell('Rate', bold: true, right: true), cell('GST', bold: true, right: true), cell('Amount', bold: true, right: true),
          ]),
          for (var i = 0; i < items.length; i++)
            pw.TableRow(children: [
              cell('${i + 1}'), cell('${items[i]['description']}'), cell('${items[i]['hsn'] ?? ''}'),
              cell('${items[i]['qty']}', right: true), cell(rs(items[i]['rate']), right: true),
              cell('${items[i]['gst_rate']}%', right: true), cell(rs(items[i]['amount']), right: true),
            ]),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
          width: 220,
          child: pw.Column(children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Taxable value'), pw.Text(rs(v['taxable']))]),
            if (inter)
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('IGST'), pw.Text(rs(v['igst']))])
            else ...[
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('CGST'), pw.Text(rs(v['cgst']))]),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('SGST'), pw.Text(rs(v['sgst']))]),
            ],
            pw.Divider(),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(rs(v['total']), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ]),
          ]),
        ),
      ),
      if (v['narration'] != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 12), child: pw.Text('${v['narration']}', style: const pw.TextStyle(fontSize: 9))),
    ],
  ));
  return doc.save();
}

/// Opens the system print / save-as-PDF / share sheet for an invoice or bill.
Future<void> printInvoice(Map<String, dynamic> voucher, Map<String, dynamic> company) {
  return Printing.layoutPdf(
    name: '${voucher['number']}',
    onLayout: (format) => buildInvoicePdf(voucher, company, format),
  );
}
