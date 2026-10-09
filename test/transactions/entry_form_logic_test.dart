import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';
import 'package:money_manager/transactions/entry_form_logic.dart';

void main() {
  final day = DateTime(2026, 10, 9);

  group('validateEntry', () {
    test('a valid entry has no errors', () {
      final e = validateEntry(
        hasPerson: true,
        amountText: '1000',
        date: day,
        dueDate: DateTime(2026, 11, 1),
      );
      expect(e.hasAny, isFalse);
    });

    test('person is required', () {
      expect(
        validateEntry(hasPerson: false, amountText: '10', date: day).person,
        isNotNull,
      );
    });

    test('amount must be a positive valid amount', () {
      String? err(String t) =>
          validateEntry(hasPerson: true, amountText: t, date: day).amount;
      expect(err(''), isNotNull);
      expect(err('abc'), isNotNull);
      expect(err('0'), isNotNull);
      expect(err('1.234'), isNotNull);
      expect(err('₹1,500.50'), isNull);
    });

    test('due date cannot be before the entry date', () {
      final e = validateEntry(
        hasPerson: true,
        amountText: '10',
        date: day,
        dueDate: DateTime(2026, 10, 1),
      );
      expect(e.dueDate, isNotNull);
      // Same day is fine.
      expect(
        validateEntry(
          hasPerson: true,
          amountText: '10',
          date: day,
          dueDate: day,
        ).dueDate,
        isNull,
      );
    });
  });

  MoneyTransaction txn(TransactionType type, int total, int paid) =>
      MoneyTransaction(
        type: type,
        personId: 'p',
        personName: 'Asha',
        title: 't',
        totalAmount: Money.fromRupees(total),
        paidTotal: Money.fromRupees(paid),
        createdAt: day,
      );

  group('display helpers', () {
    test('paidFraction is clamped between 0 and 1', () {
      expect(paidFraction(txn(TransactionType.lent, 1000, 250)), 0.25);
      expect(paidFraction(txn(TransactionType.lent, 1000, 0)), 0);
      expect(paidFraction(txn(TransactionType.lent, 1000, 1000)), 1);
      expect(paidFraction(txn(TransactionType.lent, 0, 0)), 0);
    });

    test('summary line for money you lent', () {
      expect(
        summaryLine(txn(TransactionType.lent, 1000, 500)),
        'Received ₹500 of ₹1,000 · Balance ₹500',
      );
    });

    test('summary line for money you borrowed', () {
      expect(
        summaryLine(txn(TransactionType.borrowed, 20000, 5000)),
        'Paid ₹5,000 of ₹20,000 · Balance ₹15,000',
      );
    });

    test('action label depends on direction', () {
      expect(
        payActionLabel(txn(TransactionType.lent, 1, 0)),
        'Receive Payment',
      );
      expect(payActionLabel(txn(TransactionType.borrowed, 1, 0)), 'Pay Now');
    });

    test('status labels', () {
      expect(statusLabel(TransactionStatus.pending), 'Pending');
      expect(statusLabel(TransactionStatus.partiallyPaid), 'Partially Paid');
      expect(statusLabel(TransactionStatus.overdue), 'Overdue');
      expect(statusLabel(TransactionStatus.paid), 'Paid');
    });

    test(
      'effective status is computed from the due date, not the stored one',
      () {
        final stale = MoneyTransaction(
          type: TransactionType.lent,
          personId: 'p',
          personName: 'A',
          title: 't',
          totalAmount: Money.fromRupees(100),
          status: TransactionStatus.pending,
          dueDate: DateTime(2026, 10, 1),
          createdAt: day,
        );
        expect(effectiveStatus(stale, now: day), TransactionStatus.overdue);
      },
    );
  });
}
