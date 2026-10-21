import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/books/presentation/pages/books_page.dart';

import 'support/fake_api.dart';

dynamic _server(dynamic o) {
  final path = (o as dynamic).path as String;
  switch (path) {
    case '/accounts/dashboard':
      return {
        'from': '2026-04-01', 'to': '2027-03-31', 'income': 10000, 'expense': 4000, 'profit': 6000, 'cash': 2000, 'bank': 91200,
        'receivable': 7980, 'payable': 0, 'chart': [{'month': '2026-10', 'income': 10000, 'expense': 4000}],
        'top_expenses': [{'name': 'Office Rent', 'amount': 4000}], 'gst': {'total_payable': 180},
      };
    case '/accounts/vouchers':
      return {'data': [{'id': 1, 'type': 'sales', 'number': 'INV-0001', 'date': '2026-10-10T00:00:00Z', 'total': 11800, 'party': {'name': 'Cust A'}}], 'total': 1};
    case '/accounts/ledgers':
      return {'ledgers': [
        {'id': 1, 'name': 'Bank Account', 'nature': 'asset', 'group': 'bank', 'system_key': 'bank', 'balance': 91200, 'is_active': true},
        {'id': 2, 'name': 'Cust A', 'nature': 'asset', 'group': 'debtor', 'gstin': '32AAAAA0000A1Z5', 'state_code': '32', 'balance': 7980, 'is_active': true},
        {'id': 3, 'name': 'Sales', 'nature': 'income', 'group': 'sales', 'system_key': 'sales', 'balance': -10000, 'is_active': true},
      ]};
    case '/accounts/items':
      return {'items': [{'id': 1, 'name': 'Widget', 'unit': 'NOS', 'gst_rate': 18, 'sale_rate': 200, 'purchase_rate': 100, 'hsn': '9983', 'track_stock': true, 'stock_qty': 4, 'stock_value': 440, 'low': true, 'is_active': true}]};
    case '/accounts/settings':
      return {'settings': {'legal_name': 'Test Co', 'gstin': '32ABCDE1234F1Z5', 'state_code': '32', 'fy_start_month': 4, 'gst_registered': true, 'invoice_prefix': 'INV'}};
    case '/accounts/gst':
      return {
        'gstin': '32ABCDE1234F1Z5',
        'summary': {
          'outward': {'taxable': 11000, 'cgst': 900, 'sgst': 900, 'igst': 180},
          'itc': {'taxable': 10000, 'cgst': 900, 'sgst': 900, 'igst': 0},
          'net_payable': {'cgst': 0, 'sgst': 0, 'igst': 180}, 'total_payable': 180,
        },
        'b2b': [{'id': 1, 'number': 'INV-0001', 'party': 'Cust A', 'gstin': '32AAAAA0000A1Z5', 'date': '2026-10-10', 'taxable': 10000, 'cgst': 900, 'sgst': 900, 'igst': 0, 'total': 11800}],
        'b2c': [], 'notes': [], 'purchases': [], 'hsn': [], 'by_rate': [],
      };
    case '/accounts/reports/profit-loss':
      return {'income': [{'name': 'Sales', 'amount': 10000}], 'expense': [{'name': 'Office Rent', 'amount': 4000}], 'total_income': 10000, 'total_expense': 4000, 'gross_profit': 10000, 'net_profit': 6000};
    case '/accounts/reports/tds':
      return {'total_deducted': 1000, 'deposited_to_government': 0, 'payable_now': 1000, 'by_section': [{'section': '194J', 'count': 1, 'taxable': 10000, 'tds': 1000}], 'rows': []};
    case '/accounts/reports/bank-reconciliation':
      return {'book_balance': 4000, 'reconciled_balance': 1000, 'unreconciled_net': 3000, 'pending': [
        {'entry_id': 7, 'date': '2026-10-01', 'number': 'JV-0001', 'debit': 5000, 'credit': 0, 'narration': 'Capital'},
      ]};
  }
  return {};
}

void main() {
  testWidgets('accounts: every tab loads, voucher form opens with the tax preview, TDS and bank reconciliation views work', (tester) async {
    final api = FakeApi(_server)..install();
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const BooksPage()));
    await tester.pumpAndSettle();
    Finder tab(String t) => find.descendant(of: find.byType(TabBar), matching: find.text(t));
    for (final t in ['Dashboard', 'Vouchers', 'Ledgers', 'Items', 'Reports', 'GST', 'Settings']) {
      expect(tab(t), findsOneWidget, reason: 'tab $t');
    }

    // dashboard
    expect(find.text('₹10,000.00'), findsWidgets);
    expect(find.text('Net profit'), findsOneWidget);
    expect(find.text('Office Rent'), findsOneWidget);

    // vouchers: list, then the new-voucher menu lists every type including credit / debit notes
    await tester.tap(tab('Vouchers'));
    await tester.pumpAndSettle();
    expect(find.textContaining('INV-0001'), findsOneWidget);
    await tester.tap(find.text('Voucher'));
    await tester.pumpAndSettle();
    for (final t in ['Sales Invoice', 'Purchase Bill', 'Receipt', 'Payment', 'Expense', 'Other Income', 'Journal', 'Contra (Cash/Bank)', 'Credit Note (sales return)', 'Debit Note (purchase return)']) {
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(t)), findsOneWidget, reason: 'voucher type $t');
    }
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Credit Note (sales return)')));
    await tester.pumpAndSettle();
    expect(find.text('New Credit Note (sales return)'), findsOneWidget);
    expect(find.text('Customer'), findsOneWidget, reason: 'a credit note is raised against a customer');
    expect(find.text('Taxable value'), findsOneWidget);
    expect(find.text('Items'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // ledgers + items (stock, low-stock flag)
    await tester.tap(tab('Ledgers'));
    await tester.pumpAndSettle();
    expect(find.text('Bank Account'), findsOneWidget);
    expect(find.text('Cust A'), findsOneWidget);
    await tester.tap(tab('Items'));
    await tester.pumpAndSettle();
    expect(find.text('Widget'), findsOneWidget);
    expect(find.text('LOW'), findsOneWidget);
    expect(find.text('4 NOS'), findsOneWidget);

    // reports: profit & loss by default, then TDS and bank reconciliation
    await tester.tap(tab('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Total income'), findsOneWidget);
    // the report chips are a sideways-scrolling row, and TDS / Bank Rec. sit beyond the first screenful
    final chipRow = find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.horizontal).first;
    final chips = find.descendant(of: chipRow, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.widgetWithText(ChoiceChip, 'TDS'), 150, scrollable: chips.first);
    await tester.tap(find.widgetWithText(ChoiceChip, 'TDS'));
    await tester.pumpAndSettle();
    expect(find.text('Payable now'), findsOneWidget);
    expect(find.textContaining('194J'), findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(ChoiceChip, 'Bank Rec.'), -150, scrollable: chips.first);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bank Rec.'));
    await tester.pumpAndSettle();
    expect(find.text('Pick an account.'), findsOneWidget, reason: 'reconciliation needs a bank account chosen first');

    // GST
    await tester.tap(tab('GST'));
    await tester.pumpAndSettle();
    expect(find.text('GSTR-3B net payable'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Cr/Dr notes'), findsOneWidget);
    expect(find.textContaining('e-Invoice JSON'), findsOneWidget);

    // settings
    await tester.tap(tab('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('GSTIN'), findsOneWidget);
    expect(find.text('Pincode'), findsOneWidget);
    expect(api.calls.where((c) => c.path.startsWith('/accounts/')).length, greaterThan(8));
  });
}
