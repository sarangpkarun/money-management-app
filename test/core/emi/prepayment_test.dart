import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/emi/emi_estimates.dart';
import 'package:money_manager/core/emi/emi_schedule.dart';
import 'package:money_manager/core/emi/prepayment.dart';
import 'package:money_manager/core/models/emi_plan.dart';
import 'package:money_manager/core/money/money.dart';

/// Rs 60,000 at 12% for 12 months from 15 Jan 2030, with the first [paid] EMIs
/// paid in full.
EmiPlan loan({int paid = 0, double rate = 12, int rupees = 60000, int n = 12}) {
  final price = Money.fromRupees(rupees);
  final s = generateEmiSchedule(
    price: price,
    annualRatePercent: rate,
    months: n,
    startDate: DateTime(2030, 1, 15),
  );
  final plan = EmiPlan.fromSchedule(
    s,
    price: price,
    downPayment: Money.zero,
    annualRatePercent: rate,
    startDate: DateTime(2030, 1, 15),
  );
  return plan.copyWithRows([
    for (final r in plan.rows)
      r.number <= paid ? r.copyWith(paidAmount: r.amount) : r,
  ]);
}

void main() {
  // Reference values from an independent decimal calculation (Python), with
  // the same rounding rules as the schedule engine.
  group('foreclosure', () {
    test('principal left after 3 EMIs, plus a 2% charge', () {
      final f = foreclosureEstimate(loan(paid: 3), chargePercent: 2);
      expect(f.principal, const Money(4566481));
      expect(f.charge, const Money(91330));
      expect(f.total, const Money(4657811));
      expect(f.saved, const Money(231353)); // interest in the 9 unpaid rows
    });

    test('with no charge the total is just the principal', () {
      final f = foreclosureEstimate(loan(paid: 3));
      expect(f.total, f.principal);
    });

    test('nothing paid: the whole financed amount', () {
      expect(outstandingPrincipal(loan()), const Money(6000000));
    });

    test('a part-paid row counts only its unpaid share of principal', () {
      final plan = loan(paid: 2);
      final row = plan.rowNumbered(3)!;
      final half = Money(row.amount.paise ~/ 2);
      final part = plan.copyWithRow(row.copyWith(paidAmount: half));
      final full = outstandingPrincipal(plan);
      final partial = outstandingPrincipal(part);
      expect(partial < full, isTrue);
      expect(
        (full - partial).paise,
        closeTo((row.principal.paise * half.paise / row.amount.paise), 1),
      );
    });

    test('rows paid out of order are not counted', () {
      final plan = loan();
      final last = plan.rows.last;
      final out = plan.copyWithRow(last.copyWith(paidAmount: last.amount));
      expect(outstandingPrincipal(out), const Money(6000000) - last.principal);
    });

    test('a fully paid plan and a bad charge are rejected', () {
      expect(
        () => foreclosureEstimate(loan(paid: 12)),
        throwsA(isA<EmiInputError>()),
      );
      expect(
        () => foreclosureEstimate(loan(), chargePercent: -1),
        throwsA(isA<EmiInputError>()),
      );
      expect(
        () => foreclosureEstimate(loan(), chargePercent: 101),
        throwsA(isA<EmiInputError>()),
      );
    });
  });

  group('part prepayment of Rs 10,000 after 3 EMIs', () {
    final amount = Money.fromRupees(10000);

    test('keeping the EMI shortens the loan', () {
      final r = partPrepayment(loan(paid: 3), amount, keep: PrepaymentKeep.emi);
      expect(r.newBalance, const Money(3566481));
      expect(r.monthsBefore, 9);
      expect(r.monthsAfter, 7);
      expect(r.emiAfter, const Money(533093));
      expect(r.interestSaved, const Money(87917));
      expect(r.lastDueDate, DateTime(2030, 10, 15)); // 7 payments from 15 Apr
    });

    test('keeping the tenure lowers the EMI', () {
      final r = partPrepayment(
        loan(paid: 3),
        amount,
        keep: PrepaymentKeep.tenure,
      );
      expect(r.monthsAfter, 9);
      expect(r.emiAfter, const Money(416352));
      expect(r.interestSaved, const Money(50663));
      expect(r.lastDueDate, DateTime(2030, 12, 15));
    });

    test('shortening the loan saves more interest than lowering the EMI', () {
      final a = partPrepayment(loan(paid: 3), amount, keep: PrepaymentKeep.emi);
      final b = partPrepayment(
        loan(paid: 3),
        amount,
        keep: PrepaymentKeep.tenure,
      );
      expect(a.interestSaved > b.interestSaved, isTrue);
    });

    test('0% (no-cost): nothing saved, months or EMI just follow', () {
      final plan = loan(paid: 2, rate: 0, rupees: 12000, n: 4);
      final a = partPrepayment(
        plan,
        Money.fromRupees(3000),
        keep: PrepaymentKeep.emi,
      );
      expect(a.monthsAfter, 1);
      expect(a.interestSaved, Money.zero);
      final b = partPrepayment(
        plan,
        Money.fromRupees(3000),
        keep: PrepaymentKeep.tenure,
      );
      expect(b.emiAfter, Money.fromRupees(1500));
      expect(b.monthsAfter, 2);
    });

    test('the amount must be above 0 and below the principal left', () {
      void bad(Money m) => expect(
        () => partPrepayment(loan(paid: 3), m, keep: PrepaymentKeep.emi),
        throwsA(isA<EmiInputError>()),
      );
      bad(Money.zero);
      bad(const Money(-1));
      bad(const Money(4566481)); // that is a foreclosure
      bad(const Money(9999999));
    });

    test('a fully paid plan is rejected', () {
      expect(
        () => partPrepayment(loan(paid: 12), amount, keep: PrepaymentKeep.emi),
        throwsA(isA<EmiInputError>()),
      );
    });
  });

  group('invariants over many loans', () {
    test('prepaying never lengthens or dearens the loan', () {
      for (final rate in [0.0, 8.5, 12.0, 24.0]) {
        for (final n in [6, 12, 36, 84]) {
          for (final paid in [0, 1, n ~/ 2]) {
            final plan = loan(paid: paid, rate: rate, n: n, rupees: 250000);
            final p = outstandingPrincipal(plan);
            for (final fraction in [0.01, 0.2, 0.5, 0.99]) {
              final amt = Money((p.paise * fraction).round());
              if (amt <= Money.zero || amt >= p) continue;
              final label = 'rate=$rate n=$n paid=$paid f=$fraction';
              final a = partPrepayment(plan, amt, keep: PrepaymentKeep.emi);
              final b = partPrepayment(plan, amt, keep: PrepaymentKeep.tenure);
              expect(a.newBalance, p - amt, reason: label);
              expect(a.monthsAfter <= a.monthsBefore, isTrue, reason: label);
              expect(b.monthsAfter, b.monthsBefore, reason: label);
              expect(b.emiAfter <= plan.emi, isTrue, reason: label);
              expect(a.interestSaved.isNegative, isFalse, reason: label);
              expect(b.interestSaved.isNegative, isFalse, reason: label);
              if (rate > 0) {
                expect(a.interestSaved > Money.zero, isTrue, reason: label);
              }
            }
          }
        }
      }
    });
  });

  group('late fee', () {
    EmiPlan withRule(LateFeeRule? rule, {int paid = 0}) {
      final p = loan(paid: paid, rate: 0, rupees: 12000, n: 4);
      return EmiPlan(
        price: p.price,
        downPayment: p.downPayment,
        annualRatePercent: p.annualRatePercent,
        months: p.months,
        emi: p.emi,
        startDate: p.startDate,
        rows: p.rows,
        lateFee: rule,
      );
    }

    // Rows are due 15 Jan, 15 Feb, 15 Mar, 15 Apr 2030, Rs 3,000 each.
    test('no rule means no fee', () {
      final e = lateFeeToDate(withRule(null), DateTime(2031, 1, 1));
      expect(e.total, Money.zero);
      expect(e.count, 0);
    });

    test('a flat fee is charged once per late instalment', () {
      final e = lateFeeToDate(
        withRule(LateFeeRule.flat(Money.fromRupees(100))),
        DateTime(2030, 3, 20), // rows 1, 2, 3 are late
      );
      expect(e.count, 3);
      expect(e.total, Money.fromRupees(300));
    });

    test('it is once per instalment, not per day', () {
      final rule = withRule(LateFeeRule.flat(Money.fromRupees(100)));
      expect(
        lateFeeToDate(rule, DateTime(2030, 1, 16)).total,
        Money.fromRupees(100),
      );
      expect(
        lateFeeToDate(rule, DateTime(2030, 1, 30)).total,
        Money.fromRupees(100),
      );
    });

    test('a percentage fee uses what is still owed on the instalment', () {
      final plan = withRule(const LateFeeRule.percent(2));
      final row = plan.rows.first;
      final part = plan.copyWithRow(
        row.copyWith(paidAmount: Money.fromRupees(1000)),
      );
      final e = lateFeeToDate(part, DateTime(2030, 1, 16));
      expect(e.total, Money.fromRupees(40)); // 2% of 2,000
    });

    test('grace days: not charged until they have passed', () {
      final plan = withRule(
        LateFeeRule.flat(Money.fromRupees(100), graceDays: 5),
      );
      // Due 15 Jan: 20 Jan is exactly 5 days late, 21 Jan is 6.
      expect(lateFeeToDate(plan, DateTime(2030, 1, 15)).count, 0);
      expect(lateFeeToDate(plan, DateTime(2030, 1, 20)).count, 0);
      expect(lateFeeToDate(plan, DateTime(2030, 1, 21)).count, 1);
    });

    test('with no grace it starts the day after the due date', () {
      final plan = withRule(LateFeeRule.flat(Money.fromRupees(100)));
      expect(lateFeeToDate(plan, DateTime(2030, 1, 15)).count, 0);
      expect(lateFeeToDate(plan, DateTime(2030, 1, 16)).count, 1);
    });

    test('paid instalments are not charged', () {
      final plan = withRule(LateFeeRule.flat(Money.fromRupees(100)), paid: 2);
      expect(lateFeeToDate(plan, DateTime(2030, 3, 20)).count, 1);
    });

    test('the rule round-trips through the stored map', () {
      final plan = withRule(
        LateFeeRule.flat(Money.fromRupees(100), graceDays: 3),
      );
      final back = EmiPlan.fromMaps(plan.toMap(), plan.scheduleToMaps());
      expect(back.lateFee!.flat, Money.fromRupees(100));
      expect(back.lateFee!.graceDays, 3);
      final pct = withRule(const LateFeeRule.percent(1.5));
      final back2 = EmiPlan.fromMaps(pct.toMap(), pct.scheduleToMaps());
      expect(back2.lateFee!.percent, 1.5);
      expect(back2.lateFee!.flat, isNull);
    });
  });

  group('no-cost EMI', () {
    EmiPlan noCost(double? lender) {
      final p = loan(rate: 0, rupees: 60000);
      return EmiPlan(
        price: p.price,
        downPayment: p.downPayment,
        annualRatePercent: 0,
        months: p.months,
        emi: p.emi,
        startDate: p.startDate,
        rows: p.rows,
        noCostRate: lender,
      );
    }

    test('the seller absorbs the interest at the lender rate', () {
      // Rs 60,000 at 12% over 12 months: 3,971.13 interest (see EMI tests).
      expect(noCostSellerInterest(noCost(12)), const Money(397113));
    });

    test('not no-cost means zero', () {
      expect(noCostSellerInterest(noCost(null)), Money.zero);
      expect(noCostSellerInterest(noCost(0)), Money.zero);
    });

    test('the rate round-trips and old plans still load', () {
      final plan = noCost(14.5);
      final back = EmiPlan.fromMaps(plan.toMap(), plan.scheduleToMaps());
      expect(back.noCostRate, 14.5);
      expect(noCost(null).toMap().containsKey('noCostRate'), isFalse);
      expect(
        EmiPlan.fromMaps(noCost(null).toMap(), const []).noCostRate,
        isNull,
      );
    });
  });
}
