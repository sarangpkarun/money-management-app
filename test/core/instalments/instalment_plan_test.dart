import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/instalments/instalment_plan.dart';
import 'package:money_manager/core/models/emi_plan.dart';
import 'package:money_manager/core/money/money.dart';

Money rs(int r) => Money.fromRupees(r);

EmiPlan byMonths(int total, int months, {DateTime? start}) =>
    generateInstalmentPlan(
      total: rs(total),
      months: months,
      startDate: start ?? DateTime(2026, 1, 31),
    );

EmiPlan byMonthly(int total, int monthly, {DateTime? start}) =>
    generateInstalmentPlan(
      total: rs(total),
      monthlyAmount: rs(monthly),
      startDate: start ?? DateTime(2026, 1, 31),
    );

List<int> amounts(EmiPlan p) => p.rows.map((r) => r.amount.paise).toList();
List<int> rupees(EmiPlan p) =>
    p.rows.map((r) => r.amount.paise ~/ 100).toList();
List<DateTime> dates(EmiPlan p) => p.rows.map((r) => r.dueDate).toList();

Money sumAmounts(EmiPlan p) => p.rows.fold(Money.zero, (a, r) => a + r.amount);
Money sumPaid(EmiPlan p) => p.rows.fold(Money.zero, (a, r) => a + r.paidAmount);
Money sumRemaining(EmiPlan p) =>
    p.rows.fold(Money.zero, (a, r) => a + r.remaining);

EmiPlan pay(EmiPlan p, int number, int rupeesPaid) {
  final row = p.rowNumbered(number)!;
  return p.copyWithRow(
    row.copyWith(
      paidAmount: row.paidAmount + rs(rupeesPaid),
      paidOn: DateTime(2026, 6, 1),
    ),
  );
}

void expectError(void Function() f) =>
    expect(f, throwsA(isA<InstalmentError>()));

void main() {
  group('generate by number of months', () {
    test('an even split', () {
      final p = byMonths(30000, 6);
      expect(rupees(p), [5000, 5000, 5000, 5000, 5000, 5000]);
      expect(p.months, 6);
      expect(p.emi, rs(5000));
      expect(p.price, rs(30000));
      expect(p.downPayment, Money.zero);
      expect(p.annualRatePercent, 0);
    });

    test('an uneven split: the last row absorbs the remainder', () {
      final p = byMonths(10000, 3);
      expect(amounts(p), [333333, 333333, 333334]);
      expect(sumAmounts(p), rs(10000));
    });

    test('rounding up can make the last row smaller', () {
      final p = generateInstalmentPlan(
        total: const Money(200),
        months: 3,
        startDate: DateTime(2026, 1, 1),
      );
      expect(amounts(p), [67, 67, 66]);
    });

    test('rows carry the principal, no interest and a falling balance', () {
      final p = byMonths(30000, 3);
      expect(p.rows.every((r) => r.interest.isZero), isTrue);
      expect(p.rows.every((r) => r.principal == r.amount), isTrue);
      expect(p.rows.map((r) => r.balanceAfter.paise ~/ 100), [20000, 10000, 0]);
      expect(p.rows.every((r) => r.paidAmount.isZero), isTrue);
    });

    test('due dates follow the month-end rule from the start day', () {
      final p = byMonths(30000, 5, start: DateTime(2026, 1, 31));
      expect(dates(p), [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
        DateTime(2026, 5, 31),
      ]);
    });

    test('one month is the whole amount', () {
      expect(rupees(byMonths(777, 1)), [777]);
    });
  });

  group('generate by monthly amount', () {
    test('an exact multiple', () {
      final p = byMonthly(30000, 5000);
      expect(rupees(p), [5000, 5000, 5000, 5000, 5000, 5000]);
    });

    test('a remainder becomes a smaller last row', () {
      final p = byMonthly(32000, 5000);
      expect(rupees(p), [5000, 5000, 5000, 5000, 5000, 5000, 2000]);
      expect(p.months, 7);
      expect(p.emi, rs(5000));
    });

    test('a monthly amount above the total gives a single payment', () {
      final p = byMonthly(3000, 5000);
      expect(rupees(p), [3000]);
    });

    test('a monthly amount equal to the total gives a single payment', () {
      expect(rupees(byMonthly(5000, 5000)), [5000]);
    });
  });

  group('generate: validation', () {
    test('the total must be positive', () {
      expectError(() => byMonths(0, 6));
      expectError(
        () => generateInstalmentPlan(
          total: const Money(-5),
          months: 3,
          startDate: DateTime(2026, 1, 1),
        ),
      );
    });
    test('exactly one of months or monthly amount is needed', () {
      expectError(
        () => generateInstalmentPlan(
          total: rs(100),
          startDate: DateTime(2026, 1, 1),
        ),
      );
      expectError(
        () => generateInstalmentPlan(
          total: rs(100),
          months: 3,
          monthlyAmount: rs(10),
          startDate: DateTime(2026, 1, 1),
        ),
      );
    });
    test('months must be between 1 and 600', () {
      expectError(() => byMonths(100, 0));
      expectError(() => byMonths(100, 601));
    });
    test(
      'the monthly amount must be positive, and not produce over 600 rows',
      () {
        expectError(
          () => generateInstalmentPlan(
            total: rs(100),
            monthlyAmount: Money.zero,
            startDate: DateTime(2026, 1, 1),
          ),
        );
        expectError(
          () => generateInstalmentPlan(
            total: rs(1000000),
            monthlyAmount: const Money(100),
            startDate: DateTime(2026, 1, 1),
          ),
        );
      },
    );
    test('an amount too small to split that many ways is rejected', () {
      expectError(
        () => generateInstalmentPlan(
          total: const Money(2),
          months: 3,
          startDate: DateTime(2026, 1, 1),
        ),
      );
    });
    test('the error carries a message', () {
      try {
        byMonths(0, 6);
        fail('expected an InstalmentError');
      } on InstalmentError catch (e) {
        expect(e.message, isNotEmpty);
      }
    });
  });

  group('skipMonth', () {
    test('moves that row and every later row one month later', () {
      final p = byMonths(30000, 5, start: DateTime(2026, 1, 31));
      final skipped = skipMonth(p, 3);
      expect(dates(skipped), [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 4, 30), // was 31 Mar
        DateTime(2026, 5, 31), // was 30 Apr: back to the 31st
        DateTime(2026, 6, 30), // was 31 May
      ]);
      expect(rupees(skipped), rupees(p)); // amounts untouched
      expect(skipped.rows.map((r) => r.number), [1, 2, 3, 4, 5]);
    });

    test('the end date moves a month and the day never drifts', () {
      var p = byMonths(30000, 4, start: DateTime(2026, 1, 31));
      p = skipMonth(p, 1);
      p = skipMonth(p, 1);
      // 31 Jan -> 28 Feb -> 31 Mar for the first row.
      expect(p.rows.first.dueDate, DateTime(2026, 3, 31));
      expect(p.rows.last.dueDate, DateTime(2026, 6, 30)); // was 30 Apr + 2
    });

    test('rolls over the year', () {
      final p = byMonths(3000, 3, start: DateTime(2026, 11, 15));
      expect(dates(skipMonth(p, 2)), [
        DateTime(2026, 11, 15),
        DateTime(2027, 1, 15),
        DateTime(2027, 2, 15),
      ]);
    });

    test('paid rows keep their dates', () {
      var p = byMonths(30000, 5, start: DateTime(2026, 1, 15));
      p = pay(p, 1, 6000);
      final skipped = skipMonth(p, 2);
      expect(skipped.rows.first.dueDate, DateTime(2026, 1, 15));
      expect(skipped.rows[1].dueDate, DateTime(2026, 3, 15));
    });

    test('a row with something paid cannot be skipped', () {
      final p = pay(byMonths(30000, 5), 2, 1000);
      expectError(() => skipMonth(p, 2));
    });

    test('a fully paid row cannot be skipped', () {
      final p = pay(byMonths(30000, 5), 1, 6000);
      expectError(() => skipMonth(p, 1));
    });

    test('an unknown row is rejected', () {
      expectError(() => skipMonth(byMonths(30000, 5), 9));
    });

    test('later paid rows are left where they are', () {
      var p = byMonths(30000, 5, start: DateTime(2026, 1, 15));
      p = pay(p, 4, 6000);
      final skipped = skipMonth(p, 2);
      expect(skipped.rows[3].dueDate, DateTime(2026, 4, 15)); // paid: unchanged
      expect(skipped.rows[1].dueDate, DateTime(2026, 3, 15));
      expect(skipped.rows[2].dueDate, DateTime(2026, 4, 15));
    });
  });

  group('changeAmount', () {
    test('re-spreads the rest so the total still adds up', () {
      final p = byMonths(30000, 5); // 6,000 x 5
      final changed = changeAmount(p, 2, rs(10000));
      // 14,000 over three rows is 4,666.66 each, the last taking the paisa.
      expect(amounts(changed), [600000, 1000000, 466666, 466666, 466668]);
      expect(sumAmounts(changed), rs(30000));
    });

    test('the paisa remainder lands on the last row', () {
      final p = byMonths(10000, 4); // 2,500 x 4
      final changed = changeAmount(p, 1, rs(1));
      // 9,999 over 3 rows = 3,333 each.
      expect(rupees(changed), [1, 3333, 3333, 3333]);
      expect(sumAmounts(changed), rs(10000));
    });

    test('a smaller amount spreads more onto the later rows', () {
      final p = byMonths(30000, 5);
      final changed = changeAmount(p, 1, rs(2000));
      expect(rupees(changed), [2000, 7000, 7000, 7000, 7000]);
    });

    test('paid rows are untouched and not part of the spread', () {
      var p = byMonths(30000, 5);
      p = pay(p, 1, 6000);
      final changed = changeAmount(p, 2, rs(9000));
      expect(changed.rows.first.amount, rs(6000));
      expect(changed.rows.first.isPaid, isTrue);
      expect(rupees(changed), [6000, 9000, 5000, 5000, 5000]);
      expect(sumAmounts(changed), rs(30000));
    });

    test('part-paid later rows keep what is paid and share the rest', () {
      var p = byMonths(30000, 4); // 7,500 x 4
      p = pay(p, 3, 1000);
      final changed = changeAmount(p, 1, rs(10000));
      // Rows 2-4 hold 20,000 in total: 1,000 already paid on row 3, so 19,000
      // is spread over 3 rows (6,333.33... each) on top of what is paid.
      expect(sumAmounts(changed), rs(30000));
      expect(changed.rowNumbered(3)!.paidAmount, rs(1000));
      expect(changed.rowNumbered(3)!.amount >= rs(1000), isTrue);
      expect(sumRemaining(changed), rs(30000) - rs(1000));
    });

    test('an amount that covers everything removes the later rows', () {
      final p = byMonths(30000, 5);
      final changed = changeAmount(p, 2, rs(24000));
      expect(rupees(changed), [6000, 24000]);
      expect(sumAmounts(changed), rs(30000));
      expect(changed.months, 2);
    });

    test('a smaller last row means an extra row is added at the end', () {
      final p = byMonths(30000, 2); // 15,000 x 2
      final changed = changeAmount(p, 2, rs(5000));
      expect(rupees(changed), [15000, 5000, 10000]);
      expect(changed.rows.last.number, 3);
      expect(changed.rows.last.dueDate, DateTime(2026, 3, 31));
    });

    test('row numbers are never reused when rows are removed', () {
      final p = byMonths(30000, 5);
      final changed = changeAmount(p, 2, rs(24000));
      expect(changed.rows.map((r) => r.number), [1, 2]);
    });

    test('rejects zero, negative and too-large amounts', () {
      final p = byMonths(30000, 5);
      expectError(() => changeAmount(p, 2, Money.zero));
      expectError(() => changeAmount(p, 2, const Money(-1)));
      expectError(() => changeAmount(p, 2, rs(30001)));
    });

    test('a fully paid row cannot be changed', () {
      final p = pay(byMonths(30000, 5), 1, 6000);
      expectError(() => changeAmount(p, 1, rs(5000)));
    });

    test('an unknown row is rejected', () {
      expectError(() => changeAmount(byMonths(30000, 5), 9, rs(100)));
    });

    test(
      'the new amount cannot be less than what is already paid on the row',
      () {
        final p = pay(byMonths(30000, 5), 2, 4000);
        expectError(() => changeAmount(p, 2, rs(3000)));
      },
    );
  });

  group('extra payments', () {
    test('reduce the schedule from the last row', () {
      final p = byMonths(30000, 6); // 5,000 x 6
      final r = applyExtraPayment(p, rs(3000));
      expect(rupees(r), [5000, 5000, 5000, 5000, 5000, 2000]);
      expect(sumAmounts(r), rs(27000));
    });

    test('empty the last rows and remove them', () {
      final p = byMonths(30000, 6);
      final r = applyExtraPayment(p, rs(12000));
      // Last row 5,000 gone, next 5,000 gone, next reduced by 2,000.
      expect(rupees(r), [5000, 5000, 5000, 3000]);
      expect(r.months, 4);
      expect(sumAmounts(r), rs(18000));
    });

    test('an extra payment of exactly one row removes that row', () {
      final r = applyExtraPayment(byMonths(30000, 6), rs(5000));
      expect(rupees(r), [5000, 5000, 5000, 5000, 5000]);
    });

    test('paying everything leaves only the paid rows', () {
      var p = byMonths(30000, 3);
      p = pay(p, 1, 10000);
      final r = applyExtraPayment(p, rs(20000));
      expect(rupees(r), [10000]);
      expect(r.nextUnpaid, isNull);
    });

    test('part-paid rows only shrink to what is already paid', () {
      var p = byMonths(30000, 3); // 10,000 x 3
      p = pay(p, 3, 4000);
      final r = applyExtraPayment(p, rs(8000));
      // Row 3 can give up its unpaid 6,000; row 2 gives 2,000.
      expect(rupees(r), [10000, 8000, 4000]);
      expect(r.rowNumbered(3)!.isPaid, isTrue);
      expect(r.rowNumbered(3)!.paidAmount, rs(4000));
    });

    test('rows are renormalised: principal equals amount, balances fall', () {
      final r = applyExtraPayment(byMonths(30000, 6), rs(3000));
      expect(r.rows.every((x) => x.principal == x.amount), isTrue);
      expect(r.rows.last.balanceAfter, Money.zero);
    });

    test('rejects zero, negative and more than what is still to pay', () {
      final p = byMonths(30000, 3);
      expectError(() => applyExtraPayment(p, Money.zero));
      expectError(() => applyExtraPayment(p, const Money(-1)));
      expectError(() => applyExtraPayment(p, rs(30001)));
    });

    test('restoring adds the amount back to the last unpaid row', () {
      final p = byMonths(30000, 6);
      final reduced = applyExtraPayment(p, rs(3000));
      final back = restoreExtraPayment(reduced, rs(3000));
      expect(rupees(back), [5000, 5000, 5000, 5000, 5000, 5000]);
      expect(sumAmounts(back), rs(30000));
    });

    test('restoring refills to the regular payment, then adds rows, so undo '
        'gives back the original shape', () {
      final p = byMonths(30000, 6); // 5,000 x 6
      final reduced = applyExtraPayment(p, rs(12000));
      expect(rupees(reduced), [5000, 5000, 5000, 3000]);
      final back = restoreExtraPayment(reduced, rs(12000));
      expect(rupees(back), [5000, 5000, 5000, 5000, 5000, 5000]);
      expect(back.rows.map((r) => r.number), [1, 2, 3, 4, 5, 6]);
      expect(sumAmounts(back), rs(30000));
    });

    test('restoring a small amount only tops up the last row', () {
      final reduced = applyExtraPayment(byMonths(30000, 6), rs(3000));
      final back = restoreExtraPayment(reduced, rs(1000));
      expect(rupees(back), [5000, 5000, 5000, 5000, 5000, 3000]);
    });

    test('restoring after rows were removed appends a row a month later', () {
      final p = byMonths(30000, 3, start: DateTime(2026, 1, 31));
      final reduced = applyExtraPayment(p, rs(10000)); // last row gone
      expect(reduced.months, 2);
      var withPaidLast = reduced;
      withPaidLast = pay(withPaidLast, 2, 10000); // last row fully paid
      final back = restoreExtraPayment(withPaidLast, rs(10000));
      expect(rupees(back), [10000, 10000, 10000]);
      expect(back.rows.last.dueDate, DateTime(2026, 3, 31));
      expect(back.rows.last.number, 3);
    });
  });

  group('invariants over many operations', () {
    test('the total still to pay always matches', () {
      var plan = byMonths(120000, 12, start: DateTime(2026, 1, 31));
      var owed = rs(120000);
      void check(String step) {
        expect(sumRemaining(plan), owed, reason: step);
        expect(sumAmounts(plan) - sumPaid(plan), owed, reason: step);
        final numbers = plan.rows.map((r) => r.number).toList();
        expect(numbers.toSet().length, numbers.length, reason: '$step: unique');
        for (var i = 1; i < numbers.length; i++) {
          expect(numbers[i] > numbers[i - 1], isTrue, reason: '$step: ordered');
        }
      }

      check('start');
      plan = pay(plan, 1, 10000);
      owed = owed - rs(10000);
      check('pay 1');
      plan = skipMonth(plan, 2);
      check('skip 2');
      plan = changeAmount(plan, 2, rs(25000));
      check('change 2');
      plan = applyExtraPayment(plan, rs(15000));
      owed = owed - rs(15000);
      check('extra 15,000');
      plan = pay(plan, 2, 25000);
      owed = owed - rs(25000);
      check('pay 2');
      plan = changeAmount(plan, 3, rs(1));
      check('change 3');
      plan = applyExtraPayment(plan, rs(7000));
      owed = owed - rs(7000);
      check('extra 7,000');
      plan = restoreExtraPayment(plan, rs(7000));
      owed = owed + rs(7000);
      check('restore 7,000');
      plan = skipMonth(plan, 3);
      check('skip 3');
    });
  });
}
