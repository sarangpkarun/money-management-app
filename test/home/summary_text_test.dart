import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';
import 'package:money_manager/home/summary_text.dart';

MoneyTransaction entry(
  String id,
  int rupees,
  DateTime? due, {
  TransactionType type = TransactionType.lent,
  TransactionStatus status = TransactionStatus.pending,
  int paid = 0,
}) => MoneyTransaction(
  id: id,
  type: type,
  personId: 'p',
  personName: 'X',
  title: 'T',
  totalAmount: Money.fromRupees(rupees),
  paidTotal: Money.fromRupees(paid),
  status: status,
  dueDate: due,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  // Mon 7 Jan 2030.
  final now = DateTime(2030, 1, 7, 8);

  test('nothing at all', () {
    expect(
      summaryText(const [], now),
      'Nothing due this week (as of 7 Jan 2030)',
    );
  });

  test('overdue, due this week, owe and owed', () {
    final t = summaryText([
      entry('a', 1200, DateTime(2030, 1, 3), type: TransactionType.borrowed),
      entry('b', 800, DateTime(2030, 1, 9), type: TransactionType.borrowed),
      entry('c', 2500, DateTime(2030, 1, 10)),
    ], now);
    expect(
      t,
      '1 overdue · 2 due this week · You owe ₹2,000 · You are owed ₹2,500 '
      '(as of 7 Jan 2030)',
    );
  });

  test('only what applies is mentioned', () {
    expect(
      summaryText([entry('a', 500, DateTime(2030, 3, 1))], now),
      'You are owed ₹500 (as of 7 Jan 2030)',
    );
    expect(
      summaryText([
        entry('a', 500, DateTime(2030, 1, 8), type: TransactionType.borrowed),
      ], now),
      '1 due this week · You owe ₹500 (as of 7 Jan 2030)',
    );
  });

  test('paid entries are ignored', () {
    expect(
      summaryText([
        entry(
          'a',
          500,
          DateTime(2030, 1, 3),
          status: TransactionStatus.paid,
          paid: 500,
        ),
      ], now),
      'Nothing due this week (as of 7 Jan 2030)',
    );
  });

  test('uses the chosen currency and date format', () {
    // The text is built with the shared formatters, so it follows the settings.
    final t = summaryText([entry('a', 500, DateTime(2030, 1, 3))], now);
    expect(t, contains('₹500'));
    expect(t, endsWith('(as of 7 Jan 2030)'));
  });
}
