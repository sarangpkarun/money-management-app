import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/emi/emi_schedule.dart';
import 'package:money_manager/core/emi/month_dates.dart';
import 'package:money_manager/core/money/money.dart';

EmiSchedule gen(
  int priceRupees,
  double rate,
  int months, {
  int downRupees = 0,
  DateTime? start,
}) => generateEmiSchedule(
  price: Money.fromRupees(priceRupees),
  downPayment: Money.fromRupees(downRupees),
  annualRatePercent: rate,
  months: months,
  startDate: start ?? DateTime(2026, 1, 31),
);

/// Row as (amount, principal, interest, balanceAfter) in paise.
(int, int, int, int) row(EmiInstallment i) =>
    (i.amount.paise, i.principal.paise, i.interest.paise, i.balanceAfter.paise);

void main() {
  // The reference values below were computed independently with exact decimal
  // arithmetic (Python `decimal`, 60 digits), using the same rounding rules:
  // EMI and each month's interest rounded half-up to the paisa, last
  // installment closing the balance.
  group('matches an independent decimal calculation', () {
    test('Rs 60,000 at 12% for 12 months (the product-doc example)', () {
      final s = gen(60000, 12, 12);
      expect(s.financed, const Money(6000000));
      expect(s.emi, const Money(533093)); // Rs 5,330.93, "about 5,331"
      expect(s.totalInterest, const Money(397113));
      expect(s.totalPayable, const Money(6397113));
      expect(row(s.installments.first), (533093, 473093, 60000, 5526907));
      expect(row(s.installments[1]), (533093, 477824, 55269, 5049083));
      expect(row(s.installments.last), (533090, 527812, 5278, 0));
    });

    test('Rs 10,00,000 at 10% for 120 months', () {
      final s = gen(1000000, 10, 120);
      expect(s.emi, const Money(1321507)); // Rs 13,215.07
      expect(s.totalInterest, const Money(58580912));
      expect(s.totalPayable, const Money(158580912));
      expect(row(s.installments.first), (1321507, 488174, 833333, 99511826));
      expect(row(s.installments.last), (1321579, 1310657, 10922, 0));
    });

    test('Rs 5,00,000 at 8.5% for 60 months', () {
      final s = gen(500000, 8.5, 60);
      expect(s.emi, const Money(1025827)); // Rs 10,258.27
      expect(s.totalInterest, const Money(11549589));
      expect(row(s.installments.first), (1025827, 671660, 354167, 49328340));
      expect(row(s.installments.last), (1025796, 1018581, 7215, 0));
    });

    test('Rs 25,00,000 with Rs 5,00,000 down at 9.25% for 240 months', () {
      final s = gen(2500000, 9.25, 240, downRupees: 500000);
      expect(s.financed, const Money(200000000));
      expect(s.emi, const Money(1831734)); // Rs 18,317.34
      expect(s.totalInterest, const Money(239615936));
      expect(row(s.installments.first), (1831734, 290067, 1541667, 199709933));
      expect(row(s.installments.last), (1831510, 1817500, 14010, 0));
    });
  });

  group('0% (no-cost EMI)', () {
    test('divides evenly: Rs 12,000 over 12 months is Rs 1,000 each', () {
      final s = gen(12000, 0, 12);
      expect(s.emi, const Money(100000));
      expect(s.totalInterest, Money.zero);
      expect(s.installments.every((i) => i.interest.isZero), isTrue);
      expect(
        s.installments.every((i) => i.amount == const Money(100000)),
        isTrue,
      );
      expect(s.installments.last.balanceAfter, Money.zero);
    });

    test('uneven: Rs 10,000 over 3 months, the last EMI absorbs the paisa', () {
      final s = gen(10000, 0, 3);
      expect(s.emi, const Money(333333));
      expect(s.installments.map((i) => i.amount.paise), [
        333333,
        333333,
        333334,
      ]);
      expect(s.totalPayable, const Money(1000000));
    });

    test('rounding up can make the last EMI smaller instead', () {
      // 200 paise over 3: 66.67 rounds to 67; 67 + 67 + 66.
      final s = generateEmiSchedule(
        price: const Money(200),
        annualRatePercent: 0,
        months: 3,
        startDate: DateTime(2026, 1, 1),
      );
      expect(s.installments.map((i) => i.amount.paise), [67, 67, 66]);
    });
  });

  group('shape of a schedule', () {
    test('a one-month loan is principal plus one month of interest', () {
      final s = gen(1000, 12, 1);
      expect(s.installments.length, 1);
      expect(row(s.installments.single), (101000, 100000, 1000, 0));
      expect(s.emi, const Money(101000));
    });

    test('installments are numbered from 1 and keep the summary in sync', () {
      final s = gen(60000, 12, 12);
      expect(s.installments.map((i) => i.number), [
        for (var k = 1; k <= 12; k++) k,
      ]);
      expect(s.lastInstallment, s.installments.last);
      expect(s.months, 12);
    });

    test('due dates follow the month-end rule from the original start day', () {
      final s = gen(60000, 12, 6, start: DateTime(2026, 1, 31));
      expect(s.installments.map((i) => i.dueDate), [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
        DateTime(2026, 5, 31),
        DateTime(2026, 6, 30),
      ]);
    });

    test('a leap-year February keeps the 29th', () {
      final s = gen(12000, 0, 3, start: DateTime(2028, 1, 30));
      expect(s.installments[1].dueDate, DateTime(2028, 2, 29));
      expect(s.installments[2].dueDate, DateTime(2028, 3, 30));
    });
  });

  group('input validation', () {
    void expectInvalid(void Function() f) =>
        expect(f, throwsA(isA<EmiInputError>()));

    test('price must be positive', () => expectInvalid(() => gen(0, 12, 12)));
    test('down payment cannot be negative', () {
      expectInvalid(
        () => generateEmiSchedule(
          price: Money.fromRupees(1000),
          downPayment: const Money(-1),
          annualRatePercent: 12,
          months: 12,
          startDate: DateTime(2026, 1, 1),
        ),
      );
    });
    test('down payment must be less than the price', () {
      expectInvalid(() => gen(1000, 12, 12, downRupees: 1000));
      expectInvalid(() => gen(1000, 12, 12, downRupees: 2000));
    });
    test('rate cannot be negative or above 100', () {
      expectInvalid(() => gen(1000, -1, 12));
      expectInvalid(() => gen(1000, 101, 12));
      expectInvalid(() => gen(1000, double.nan, 12));
    });
    test('months must be at least 1 and at most 600', () {
      expectInvalid(() => gen(1000, 12, 0));
      expectInvalid(() => gen(1000, 12, -3));
      expectInvalid(() => gen(1000, 12, 601));
    });
    test('the error carries a readable message', () {
      try {
        gen(0, 12, 12);
        fail('expected an EmiInputError');
      } on EmiInputError catch (e) {
        expect(e.message, isNotEmpty);
      }
    });
  });

  group('invariants hold for many loans', () {
    final prices = [1000, 7777, 25000, 99999, 123456, 1000000];
    final rates = <double>[0, 1, 6.5, 12, 18, 24, 36];
    final tenures = [1, 2, 3, 6, 7, 12, 18, 24, 36, 60, 84];
    final starts = [
      DateTime(2026, 1, 31),
      DateTime(2027, 2, 28),
      DateTime(2028, 2, 29),
      DateTime(2026, 8, 15),
    ];

    test('principal, balance, amounts and dates are consistent', () {
      var checked = 0;
      for (final price in prices) {
        for (final rate in rates) {
          for (final n in tenures) {
            final start = starts[checked % starts.length];
            checked++;
            final s = gen(price, rate, n, start: start);
            final label = 'price=$price rate=$rate n=$n';

            final principal = s.installments.fold<int>(
              0,
              (a, i) => a + i.principal.paise,
            );
            expect(principal, s.financed.paise, reason: label);
            expect(s.installments.last.balanceAfter, Money.zero, reason: label);

            // Every installment but the last is the regular EMI.
            for (final i in s.installments.take(n - 1)) {
              expect(i.amount, s.emi, reason: '$label #${i.number}');
            }
            // The last differs only by accumulated rounding. Each month's
            // half-paisa error compounds, so the bound grows with the rate and
            // tenure: about ((1+r)^n - 1) / r paise (just n at 0%).
            final r = rate / 1200;
            final bound = r == 0
                ? n
                : ((math.pow(1 + r, n) - 1) / r).ceil() + 1;
            expect(
              (s.installments.last.amount - s.emi).paise.abs(),
              lessThanOrEqualTo(bound),
              reason: label,
            );

            var balance = s.financed;
            DateTime? previous;
            for (final i in s.installments) {
              expect(i.interest.isNegative, isFalse, reason: label);
              expect(i.principal > Money.zero, isTrue, reason: label);
              expect(i.amount, i.principal + i.interest, reason: label);
              expect(i.balanceAfter, balance - i.principal, reason: label);
              balance = i.balanceAfter;
              expect(
                i.dueDate,
                addMonthsClamped(start, i.number - 1),
                reason: label,
              );
              if (previous != null) {
                expect(i.dueDate.isAfter(previous), isTrue, reason: label);
              }
              previous = i.dueDate;
            }

            final paid = s.installments.fold<int>(
              0,
              (a, i) => a + i.amount.paise,
            );
            expect(s.totalPayable.paise, paid, reason: label);
            expect(s.totalPayable, s.financed + s.totalInterest, reason: label);
            if (rate == 0) expect(s.totalInterest, Money.zero, reason: label);
          }
        }
      }
      expect(checked, prices.length * rates.length * tenures.length);
    });

    test('a higher rate always costs more in total interest', () {
      for (final n in [12, 36, 60]) {
        var last = Money.zero;
        for (final rate in [1.0, 6.5, 12.0, 24.0]) {
          final interest = gen(100000, rate, n).totalInterest;
          expect(interest > last, isTrue, reason: 'n=$n rate=$rate');
          last = interest;
        }
      }
    });

    test('a longer tenure always costs more in total interest', () {
      var last = Money.zero;
      for (final n in [6, 12, 24, 48]) {
        final interest = gen(100000, 12, n).totalInterest;
        expect(interest > last, isTrue, reason: 'n=$n');
        last = interest;
      }
    });

    test('a down payment lowers both the EMI and the interest', () {
      final without = gen(100000, 12, 24);
      final withDown = gen(100000, 12, 24, downRupees: 25000);
      expect(withDown.emi < without.emi, isTrue);
      expect(withDown.totalInterest < without.totalInterest, isTrue);
    });
  });
}
