import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/emi/emi_schedule.dart';
import 'package:money_manager/core/money/money.dart';

/// Checks the engine against EMI figures that finance sites publish, retrieved
/// on 2026-10-09. They are third-party calculator tables, not a bank's own
/// calculator, so they validate the formula and rounding but cannot speak for
/// one lender's fees or conventions.
///
/// Sources:
///  - Scripbox, "5 Lakh Home Loan EMI":
///    https://scripbox.com/plan/emi-calculator/5-lakh-home-loan-emi/
///  - NoBroker, "5 Lakh Home Loan EMI":
///    https://www.nobroker.in/home-loan/5-lakh-home-loan-emi/
///  - StockCalc, 5 lakh and 10 lakh home loan EMI pages:
///    https://stockcalc.in/home-loan-emi/5-lakh-loan
///    https://stockcalc.in/home-loan-emi/10-lakh-loan
///
/// The sites print the EMI to the whole rupee and the totals to the rupee with
/// their own rounding, so the EMI must match exactly and the total interest
/// within a few rupees.
void main() {
  EmiSchedule loan(int rupees, double rate, int years) => generateEmiSchedule(
    price: Money.fromRupees(rupees),
    annualRatePercent: rate,
    months: years * 12,
    startDate: DateTime(2026, 1, 1),
  );

  const totalInterestToleranceRupees = 5;

  void expectMatches(
    EmiSchedule s, {
    required int publishedEmi,
    int? publishedTotalInterest,
    String? reason,
  }) {
    // The sites print whole rupees; ours is exact to the paisa, so it must be
    // within half a rupee of what they print (not re-rounded, which would
    // round 3,992.4968 -> 3,992.50 -> 3,993 and disagree with their 3,992).
    expect(
      (s.emi.paise - publishedEmi * 100).abs(),
      lessThanOrEqualTo(50),
      reason: '$reason: EMI ${s.emi.paise / 100} vs published $publishedEmi',
    );
    if (publishedTotalInterest != null) {
      final diff = (s.totalInterest.paise / 100 - publishedTotalInterest).abs();
      expect(
        diff,
        lessThanOrEqualTo(totalInterestToleranceRupees),
        reason:
            '$reason: total interest ${s.totalInterest.paise / 100} vs '
            'published $publishedTotalInterest',
      );
    }
  }

  group('Scripbox: Rs 5,00,000 at 8.40%', () {
    const published = {
      5: 10234,
      10: 6173,
      15: 4894,
      20: 4308,
      25: 3992,
      30: 3809,
    };
    for (final e in published.entries) {
      test('${e.key} years -> Rs ${e.value}', () {
        expectMatches(
          loan(500000, 8.4, e.key),
          publishedEmi: e.value,
          reason: '${e.key} years',
        );
      });
    }
  });

  group('NoBroker: Rs 5,00,000 at 8.45%', () {
    const published = {
      5: (10246, 114773),
      10: (6186, 242311),
      15: (4909, 383630),
      20: (4323, 537594),
      25: (4009, 702791),
      30: (3827, 877671),
    };
    for (final e in published.entries) {
      test('${e.key} years -> Rs ${e.value.$1}, interest ${e.value.$2}', () {
        expectMatches(
          loan(500000, 8.45, e.key),
          publishedEmi: e.value.$1,
          publishedTotalInterest: e.value.$2,
          reason: '${e.key} years',
        );
      });
    }
  });

  group('StockCalc at 8.5% for 20 years', () {
    test('Rs 5,00,000 -> Rs 4,339, interest 5,41,388', () {
      expectMatches(
        loan(500000, 8.5, 20),
        publishedEmi: 4339,
        publishedTotalInterest: 541388,
      );
    });
    test('Rs 10,00,000 -> Rs 8,678, interest 10,82,776', () {
      expectMatches(
        loan(1000000, 8.5, 20),
        publishedEmi: 8678,
        publishedTotalInterest: 1082776,
      );
    });
  });

  group('0% (no-cost EMI)', () {
    // Not a published calculator: a no-cost EMI is just the price over the
    // months, so this checks the plain arithmetic a shop would quote.
    test('Rs 30,000 over 6 months is Rs 5,000 a month, no interest', () {
      final s = generateEmiSchedule(
        price: Money.fromRupees(30000),
        annualRatePercent: 0,
        months: 6,
        startDate: DateTime(2026, 1, 1),
      );
      expect(s.emi, Money.fromRupees(5000));
      expect(s.totalInterest, Money.zero);
      expect(s.totalPayable, Money.fromRupees(30000));
    });
  });
}
