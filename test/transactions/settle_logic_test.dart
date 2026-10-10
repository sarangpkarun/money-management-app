import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/emi/emi_schedule.dart';
import 'package:money_manager/core/models/emi_plan.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/transactions/settle_logic.dart';

EmiPlan plan({int paid = 0}) {
  final s = generateEmiSchedule(
    price: Money.fromRupees(12000),
    annualRatePercent: 0,
    months: 4,
    startDate: DateTime(2030, 1, 1),
  );
  final p = EmiPlan.fromSchedule(
    s,
    price: Money.fromRupees(12000),
    downPayment: Money.zero,
    annualRatePercent: 0,
    startDate: DateTime(2030, 1, 1),
  );
  return p.copyWithRows([
    for (final r in p.rows)
      r.number <= paid ? r.copyWith(paidAmount: r.amount) : r,
  ]);
}

void main() {
  group('paymentSettles', () {
    test('paying everything that is left settles it', () {
      expect(
        paymentSettles(
          amount: Money.fromRupees(500),
          available: Money.fromRupees(500),
        ),
        isTrue,
      );
    });

    test('paying less does not', () {
      expect(
        paymentSettles(
          amount: Money.fromRupees(499),
          available: Money.fromRupees(500),
        ),
        isFalse,
      );
    });

    test('nothing owed means nothing is settled by a payment', () {
      expect(
        paymentSettles(amount: Money.fromRupees(1), available: Money.zero),
        isFalse,
      );
    });

    test('one paisa short is not settled', () {
      expect(
        paymentSettles(
          amount: const Money(49999),
          available: const Money(50000),
        ),
        isFalse,
      );
    });
  });

  group('rowPaymentSettles', () {
    test('the last unpaid row paid in full settles the plan', () {
      final p = plan(paid: 3);
      expect(
        rowPaymentSettles(p, p.rowNumbered(4)!, Money.fromRupees(3000)),
        isTrue,
      );
    });

    test('a row with other rows still unpaid does not', () {
      final p = plan(paid: 2);
      expect(
        rowPaymentSettles(p, p.rowNumbered(3)!, Money.fromRupees(3000)),
        isFalse,
      );
    });

    test('part of the last row does not', () {
      final p = plan(paid: 3);
      expect(
        rowPaymentSettles(p, p.rowNumbered(4)!, Money.fromRupees(2999)),
        isFalse,
      );
    });

    test('rows paid out of order: the final unpaid one settles', () {
      var p = plan();
      for (final n in [2, 3, 4]) {
        final r = p.rowNumbered(n)!;
        p = p.copyWithRow(r.copyWith(paidAmount: r.amount));
      }
      expect(
        rowPaymentSettles(p, p.rowNumbered(1)!, Money.fromRupees(3000)),
        isTrue,
      );
    });

    test('a part-paid last row needs only what is left on it', () {
      var p = plan(paid: 3);
      final r = p.rowNumbered(4)!;
      p = p.copyWithRow(r.copyWith(paidAmount: Money.fromRupees(1000)));
      expect(
        rowPaymentSettles(p, p.rowNumbered(4)!, Money.fromRupees(2000)),
        isTrue,
      );
    });

    test('an already paid row settles nothing', () {
      final p = plan(paid: 4);
      expect(
        rowPaymentSettles(p, p.rowNumbered(4)!, Money.fromRupees(1)),
        isFalse,
      );
    });
  });
}
