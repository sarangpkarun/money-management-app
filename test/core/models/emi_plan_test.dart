import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/emi/emi_schedule.dart';
import 'package:money_manager/core/models/emi_plan.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/payment.dart';
import 'package:money_manager/core/money/money.dart';

EmiPlan samplePlan() {
  final schedule = generateEmiSchedule(
    price: Money.fromRupees(60000),
    downPayment: Money.fromRupees(10000),
    annualRatePercent: 12,
    months: 6,
    startDate: DateTime(2026, 1, 31),
  );
  return EmiPlan.fromSchedule(
    schedule,
    price: Money.fromRupees(60000),
    downPayment: Money.fromRupees(10000),
    annualRatePercent: 12,
    startDate: DateTime(2026, 1, 31),
  );
}

void main() {
  group('EmiPlan.fromSchedule', () {
    test('copies the schedule rows with nothing paid', () {
      final plan = samplePlan();
      expect(plan.months, 6);
      expect(plan.rows.length, 6);
      expect(plan.rows.first.number, 1);
      expect(plan.rows.first.dueDate, DateTime(2026, 1, 31));
      expect(plan.rows[1].dueDate, DateTime(2026, 2, 28));
      expect(plan.rows.every((r) => r.paidAmount.isZero), isTrue);
      expect(plan.rows.every((r) => r.paidOn == null), isTrue);
      expect(plan.price, Money.fromRupees(60000));
      expect(plan.downPayment, Money.fromRupees(10000));
      expect(plan.annualRatePercent, 12);
    });

    test('total payable is the sum of the rows', () {
      final plan = samplePlan();
      final sum = plan.rows.fold(Money.zero, (a, r) => a + r.amount);
      expect(plan.totalPayable, sum);
    });
  });

  group('EmiRow', () {
    final row = EmiRow(
      number: 1,
      dueDate: DateTime(2026, 10, 9),
      amount: Money.fromRupees(1000),
      principal: Money.fromRupees(900),
      interest: Money.fromRupees(100),
    );
    final today = DateTime(2026, 10, 9);

    test('remaining and paid flags', () {
      expect(row.remaining, Money.fromRupees(1000));
      expect(row.isPaid, isFalse);
      final part = row.copyWith(paidAmount: Money.fromRupees(400));
      expect(part.remaining, Money.fromRupees(600));
      expect(part.isPaid, isFalse);
      final full = row.copyWith(paidAmount: Money.fromRupees(1000));
      expect(full.remaining, Money.zero);
      expect(full.isPaid, isTrue);
    });

    test('upcoming until the day after its due date', () {
      expect(row.statusAt(DateTime(2026, 10, 1)), EmiRowStatus.upcoming);
      expect(row.statusAt(today), EmiRowStatus.upcoming); // due today
      expect(row.statusAt(DateTime(2026, 10, 10)), EmiRowStatus.overdue);
    });

    test('a part payment is "partial" before the due date, overdue after', () {
      final part = row.copyWith(paidAmount: Money.fromRupees(400));
      expect(part.statusAt(DateTime(2026, 10, 1)), EmiRowStatus.partial);
      expect(part.statusAt(DateTime(2026, 11, 1)), EmiRowStatus.overdue);
    });

    test('a fully paid row is paid whatever the date', () {
      final full = row.copyWith(
        paidAmount: Money.fromRupees(1000),
        paidOn: DateTime(2026, 10, 5),
      );
      expect(full.statusAt(DateTime(2030, 1, 1)), EmiRowStatus.paid);
    });
  });

  group('serialisation', () {
    test('a transaction with a plan round-trips through a map', () {
      final plan = samplePlan();
      final paidRow = plan.rows.first.copyWith(
        paidAmount: plan.rows.first.amount,
        paidOn: DateTime(2026, 1, 30),
      );
      final withPaid = plan.copyWithRow(paidRow);
      final txn = MoneyTransaction(
        type: TransactionType.emi,
        personId: 'store',
        personName: 'Croma',
        title: 'Phone',
        totalAmount: plan.totalPayable,
        emiPlan: withPaid,
        createdAt: DateTime(2026, 1, 1),
      );
      final map = txn.toMap();
      expect(map['schedule'], isA<List>());
      expect((map['schedule'] as List).length, 6);

      final back = MoneyTransaction.fromMap('id', map);
      expect(back.type, TransactionType.emi);
      final p = back.emiPlan!;
      expect(p.months, 6);
      expect(p.emi, plan.emi);
      expect(p.downPayment, Money.fromRupees(10000));
      expect(p.rows.length, 6);
      expect(p.rows.first.paidAmount, plan.rows.first.amount);
      expect(p.rows.first.paidOn, DateTime(2026, 1, 30));
      expect(p.rows[1].paidAmount, Money.zero);
      expect(p.rows[1].dueDate, DateTime(2026, 2, 28));
      expect(p.rows.last.balanceAfter, Money.zero);
    });

    test('ordinary transactions have no plan and no schedule field', () {
      final txn = MoneyTransaction(
        type: TransactionType.lent,
        personId: 'p',
        personName: 'A',
        title: 't',
        totalAmount: Money.fromRupees(100),
        createdAt: DateTime(2026, 1, 1),
      );
      final map = txn.toMap();
      expect(map.containsKey('emiPlan'), isFalse);
      expect(map.containsKey('schedule'), isFalse);
      expect(MoneyTransaction.fromMap('x', map).emiPlan, isNull);
    });

    test('a payment can be tagged with an instalment number', () {
      final p = Payment(
        amount: Money.fromRupees(500),
        date: DateTime(2026, 2, 1),
        installment: 3,
      );
      expect(Payment.fromMap('x', p.toMap()).installment, 3);
      final plain = Payment(
        amount: Money.fromRupees(5),
        date: DateTime(2026, 2, 1),
      );
      expect(plain.toMap().containsKey('installment'), isFalse);
      expect(Payment.fromMap('y', plain.toMap()).installment, isNull);
    });
  });

  group('nextUnpaid and summaries helpers on the plan', () {
    test('nextUnpaid is the first row not fully paid', () {
      var plan = samplePlan();
      expect(plan.nextUnpaid!.number, 1);
      plan = plan.copyWithRow(
        plan.rows[0].copyWith(paidAmount: plan.rows[0].amount),
      );
      expect(plan.nextUnpaid!.number, 2);
      plan = plan.copyWithRow(
        plan.rows[1].copyWith(paidAmount: Money.fromRupees(1)),
      );
      expect(plan.nextUnpaid!.number, 2); // part paid still counts as unpaid
    });

    test('nextUnpaid is null when everything is paid', () {
      var plan = samplePlan();
      for (final r in [...plan.rows]) {
        plan = plan.copyWithRow(r.copyWith(paidAmount: r.amount));
      }
      expect(plan.nextUnpaid, isNull);
    });

    test('copyWithRow only changes the matching row', () {
      final plan = samplePlan();
      final changed = plan.copyWithRow(
        plan.rows[2].copyWith(paidAmount: Money.fromRupees(5)),
      );
      expect(changed.rows[2].paidAmount, Money.fromRupees(5));
      expect(changed.rows[1].paidAmount, Money.zero);
      expect(plan.rows[2].paidAmount, Money.zero); // original untouched
    });
  });
}
