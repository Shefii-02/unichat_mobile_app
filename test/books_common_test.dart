import 'package:flutter_test/flutter_test.dart';
import 'package:unichat_mobile_app/features/books/presentation/pages/books_common.dart';

void main() {
  test('inr formats Indian grouping with rupee sign', () {
    expect(inr(123456.5), '₹1,23,456.50');
    expect(inr(null), '₹0.00');
    expect(inr('1180'), '₹1,180.00');
  });

  test('isoDate pads month and day', () {
    expect(isoDate(DateTime(2026, 4, 1)), '2026-04-01');
  });

  test('currentFy spans April to March', () {
    final fy = currentFy();
    expect(fy.start.month, 4);
    expect(fy.start.day, 1);
    expect(fy.end.month, 3);
    expect(fy.end.year, fy.start.year + 1);
  });

  test('every voucher type and ledger group the server accepts is known', () {
    expect(voucherTypes.keys, containsAll(['sales', 'purchase', 'receipt', 'payment', 'expense', 'income', 'journal', 'contra']));
    expect(ledgerGroups['debtor']!.$1, 'asset');
    expect(ledgerGroups['creditor']!.$1, 'liability');
  });
}
