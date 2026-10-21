import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:unichat_mobile_app/features/books/presentation/pages/books_invoice.dart';

void main() {
  test('invoice PDF is generated for an inter-state sale', () async {
    final bytes = await buildInvoicePdf(
      {
        'type': 'sales', 'number': 'INV-0001', 'date': '2026-10-20T00:00:00.000000Z', 'is_interstate': true,
        'taxable': 1000, 'cgst': 0, 'sgst': 0, 'igst': 180, 'total': 1180,
        'party': {'name': 'Cust B', 'gstin': '29ABCDE1234F1Z5'},
        'items': [{'description': 'Plan', 'hsn': '9983', 'qty': 1, 'rate': 1000, 'gst_rate': 18, 'amount': 1000}],
      },
      {'legal_name': 'Test Co', 'gstin': '32ABCDE1234F1Z5'},
      PdfPageFormat.a4,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(500));
  });
}
