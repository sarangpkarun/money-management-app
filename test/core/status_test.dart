import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';

void main() {
  final now = DateTime(2026, 10, 9, 15, 30);
  final total = Money.fromRupees(1000);

  group('computeStatus', () {
    test('nothing paid, no due date -> pending', () {
      expect(
        computeStatus(total: total, paid: Money.zero, dueDate: null, now: now),
        TransactionStatus.pending,
      );
    });

    test('nothing paid, due in future -> pending', () {
      expect(
        computeStatus(
          total: total,
          paid: Money.zero,
          dueDate: DateTime(2026, 10, 20),
          now: now,
        ),
        TransactionStatus.pending,
      );
    });

    test('part paid -> partially paid', () {
      expect(
        computeStatus(
          total: total,
          paid: Money.fromRupees(500),
          dueDate: null,
          now: now,
        ),
        TransactionStatus.partiallyPaid,
      );
    });

    test('fully paid -> paid, even if the due date passed', () {
      expect(
        computeStatus(
          total: total,
          paid: total,
          dueDate: DateTime(2026, 1, 1),
          now: now,
        ),
        TransactionStatus.paid,
      );
    });

    test('balance left and due date passed -> overdue (beats pending)', () {
      expect(
        computeStatus(
          total: total,
          paid: Money.zero,
          dueDate: DateTime(2026, 10, 1),
          now: now,
        ),
        TransactionStatus.overdue,
      );
    });

    test('overdue beats partially paid', () {
      expect(
        computeStatus(
          total: total,
          paid: Money.fromRupees(500),
          dueDate: DateTime(2026, 10, 1),
          now: now,
        ),
        TransactionStatus.overdue,
      );
    });

    test('due today is not overdue yet, whatever the time of day', () {
      expect(
        computeStatus(
          total: total,
          paid: Money.zero,
          dueDate: DateTime(2026, 10, 9),
          now: now,
        ),
        TransactionStatus.pending,
      );
    });

    test('overdue the day after the due date', () {
      expect(
        computeStatus(
          total: total,
          paid: Money.zero,
          dueDate: DateTime(2026, 10, 8, 23, 59),
          now: now,
        ),
        TransactionStatus.overdue,
      );
    });
  });

  group('validatePayment', () {
    final balance = Money.fromRupees(500);

    test('accepts partial and full payment', () {
      expect(
        validatePayment(balance: balance, amount: Money.fromRupees(200)),
        PaymentValidation.ok,
      );
      expect(
        validatePayment(balance: balance, amount: balance),
        PaymentValidation.ok,
      );
    });

    test('blocks overpayment', () {
      expect(
        validatePayment(balance: balance, amount: Money.fromRupees(501)),
        PaymentValidation.exceedsBalance,
      );
    });

    test('blocks zero and negative amounts', () {
      expect(
        validatePayment(balance: balance, amount: Money.zero),
        PaymentValidation.notPositive,
      );
      expect(
        validatePayment(balance: balance, amount: const Money(-100)),
        PaymentValidation.notPositive,
      );
    });
  });
}
