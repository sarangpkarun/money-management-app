import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';
import 'package:money_manager/home/home_totals.dart';

void main() {
  final now = DateTime(2026, 10, 9);

  MoneyTransaction txn(
    TransactionType type,
    int total, {
    int paid = 0,
    DateTime? due,
    InterestType interest = InterestType.none,
    double? rate,
    DateTime? date,
    TransactionStatus status = TransactionStatus.pending,
    DateTime? settledAt,
  }) => MoneyTransaction(
    type: type,
    personId: 'p',
    personName: 'A',
    title: 't',
    totalAmount: Money.fromRupees(total),
    paidTotal: Money.fromRupees(paid),
    dueDate: due,
    interestType: interest,
    interestRate: rate,
    status: status,
    settledAt: settledAt,
    createdAt: date ?? DateTime(2026, 9, 1),
    date: date ?? DateTime(2026, 9, 1),
  );

  test('empty gives zero everywhere', () {
    final t = computeHomeTotals([], now: now);
    expect(t.toReceive, Money.zero);
    expect(t.toPay, Money.zero);
    expect(t.net, Money.zero);
    expect(t.overdueCount, 0);
    expect(t.overdueAmount, Money.zero);
  });

  test('lent counts to receive, borrowed to pay, net is the difference', () {
    final t = computeHomeTotals([
      txn(TransactionType.lent, 1000),
      txn(TransactionType.borrowed, 200),
    ], now: now);
    expect(t.toReceive, Money.fromRupees(1000));
    expect(t.toPay, Money.fromRupees(200));
    expect(t.net, Money.fromRupees(800));
  });

  test('emi and instalment entries count as money to pay', () {
    final t = computeHomeTotals([
      txn(TransactionType.emi, 5000),
      txn(TransactionType.instalment, 3000),
    ], now: now);
    expect(t.toPay, Money.fromRupees(8000));
  });

  test(
    'partial payments reduce what is owed; settled entries count nothing',
    () {
      final t = computeHomeTotals([
        txn(TransactionType.lent, 1000, paid: 400),
        txn(
          TransactionType.borrowed,
          500,
          paid: 500,
          status: TransactionStatus.paid,
          settledAt: DateTime(2026, 9, 20),
        ),
      ], now: now);
      expect(t.toReceive, Money.fromRupees(600));
      expect(t.toPay, Money.zero);
    },
  );

  test('interest is included in what you owe', () {
    final t = computeHomeTotals([
      txn(
        TransactionType.borrowed,
        10000,
        interest: InterestType.simple,
        rate: 12,
        date: DateTime(2025, 10, 9),
      ),
    ], now: now);
    expect(t.toPay, Money.fromRupees(11200));
    expect(t.net, Money.fromRupees(-11200));
  });

  test(
    'overdue entries are counted from the due date, with what is still owed',
    () {
      final t = computeHomeTotals([
        txn(TransactionType.lent, 1000, paid: 400, due: DateTime(2026, 10, 1)),
        txn(TransactionType.borrowed, 300, due: DateTime(2026, 9, 1)),
        txn(TransactionType.lent, 700, due: DateTime(2026, 11, 1)), // not yet
        txn(TransactionType.lent, 50, due: DateTime(2026, 10, 9)), // due today
      ], now: now);
      expect(t.overdueCount, 2);
      expect(t.overdueAmount, Money.fromRupees(900)); // 600 + 300
    },
  );

  test('a settled entry is never overdue', () {
    final t = computeHomeTotals([
      txn(
        TransactionType.lent,
        100,
        paid: 100,
        due: DateTime(2026, 1, 1),
        status: TransactionStatus.paid,
        settledAt: DateTime(2026, 1, 5),
      ),
    ], now: now);
    expect(t.overdueCount, 0);
  });

  test('recentEntries returns the latest by activity, limited', () {
    final a = txn(TransactionType.lent, 1, date: DateTime(2026, 9, 1));
    final b = txn(TransactionType.lent, 2, date: DateTime(2026, 9, 5));
    final c = txn(TransactionType.lent, 3, date: DateTime(2026, 9, 3));
    final recent = recentEntries([a, b, c], limit: 2);
    expect(recent.map((t) => t.totalAmount.paise ~/ 100), [2, 3]);
  });
}
