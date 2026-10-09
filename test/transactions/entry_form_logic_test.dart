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

  group('with interest', () {
    final now = DateTime(2026, 10, 9);
    MoneyTransaction loan({
      int paid = 0,
      TransactionStatus status = TransactionStatus.pending,
      DateTime? settledAt,
    }) => MoneyTransaction(
      type: TransactionType.borrowed,
      personId: 'p',
      personName: 'Ravi',
      title: 't',
      totalAmount: Money.fromRupees(10000),
      paidTotal: Money.fromRupees(paid),
      status: status,
      interestType: InterestType.simple,
      interestRate: 12,
      createdAt: DateTime(2025, 10, 9),
      date: DateTime(2025, 10, 9),
      settledAt: settledAt,
    );

    test('summary shows the amount due and the interest included', () {
      expect(
        summaryLine(loan(paid: 5000), now: now),
        'Paid ₹5,000 of ₹11,200 · Balance ₹6,200 · incl. ₹1,200 interest',
      );
    });

    test('progress is measured against principal plus interest', () {
      expect(paidFraction(loan(paid: 5600), now: now), 0.5);
    });

    test('paying only the principal is not Paid while interest is owed', () {
      expect(
        effectiveStatus(loan(paid: 10000), now: now),
        TransactionStatus.partiallyPaid,
      );
      expect(
        effectiveStatus(loan(paid: 11200), now: now),
        TransactionStatus.paid,
      );
    });

    test('a stored Paid stays Paid as time passes', () {
      final settled = loan(
        paid: 11200,
        status: TransactionStatus.paid,
        settledAt: now,
      );
      expect(
        effectiveStatus(settled, now: DateTime(2028, 1, 1)),
        TransactionStatus.paid,
      );
    });
  });

  group('validateEntry interest rate', () {
    String? rateError(InterestType type, String rate) => validateEntry(
      hasPerson: true,
      amountText: '100',
      date: DateTime(2026, 10, 9),
      interestType: type,
      rateText: rate,
    ).rate;

    test('not needed without interest', () {
      expect(rateError(InterestType.none, ''), isNull);
      expect(rateError(InterestType.none, 'junk'), isNull);
    });

    test('required and between 0 and 100 with interest', () {
      expect(rateError(InterestType.simple, ''), isNotNull);
      expect(rateError(InterestType.simple, 'abc'), isNotNull);
      expect(rateError(InterestType.compound, '0'), isNotNull);
      expect(rateError(InterestType.simple, '-5'), isNotNull);
      expect(rateError(InterestType.simple, '101'), isNotNull);
      expect(rateError(InterestType.simple, '12.5'), isNull);
      expect(rateError(InterestType.compound, '100'), isNull);
    });
  });

  test('formatRate drops a trailing .0', () {
    expect(formatRate(12), '12');
    expect(formatRate(12.5), '12.5');
    expect(formatRate(7.25), '7.25');
  });

  test('labels', () {
    expect(interestTypeLabel(InterestType.none), 'No interest');
    expect(interestTypeLabel(InterestType.simple), 'Simple');
    expect(interestTypeLabel(InterestType.compound), 'Compound');
    expect(repaymentLabel(RepaymentType.oneTime), 'One-time');
    expect(repaymentLabel(RepaymentType.weekly), 'Weekly instalments');
    expect(repaymentLabel(RepaymentType.monthly), 'Monthly instalments');
    expect(repaymentLabel(RepaymentType.flexible), 'Flexible');
  });
}
