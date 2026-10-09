import 'dart:math' as math;

import '../money/money.dart';
import 'month_dates.dart';

/// Thrown when the loan details cannot make a schedule.
class EmiInputError implements Exception {
  const EmiInputError(this.message);

  final String message;

  @override
  String toString() => 'EmiInputError: $message';
}

/// One monthly instalment: what is due, and how it splits between paying off
/// the loan (principal) and the cost of borrowing (interest).
class EmiInstallment {
  const EmiInstallment({
    required this.number,
    required this.dueDate,
    required this.amount,
    required this.principal,
    required this.interest,
    required this.balanceAfter,
  });

  /// 1-based.
  final int number;
  final DateTime dueDate;
  final Money amount;
  final Money principal;
  final Money interest;

  /// What is still owed on the loan once this instalment is paid.
  final Money balanceAfter;
}

class EmiSchedule {
  const EmiSchedule({
    required this.financed,
    required this.emi,
    required this.installments,
  });

  /// Price minus down payment.
  final Money financed;

  /// The regular monthly amount. The last instalment can differ by a few paise
  /// because it absorbs the rounding.
  final Money emi;
  final List<EmiInstallment> installments;

  int get months => installments.length;
  EmiInstallment get lastInstallment => installments.last;

  Money get totalInterest =>
      installments.fold(Money.zero, (sum, i) => sum + i.interest);

  /// Everything paid in instalments (excludes the down payment).
  Money get totalPayable =>
      installments.fold(Money.zero, (sum, i) => sum + i.amount);
}

/// Builds the reducing-balance EMI schedule (product doc 8.3).
///
/// With monthly rate r = annual / 12 / 100, n months and financed amount P:
/// EMI = P r (1+r)^n / ((1+r)^n - 1), or P / n when the rate is 0. Each month
/// interest = opening balance * r, principal = EMI - interest. All amounts are
/// whole paise: the EMI and each month's interest are rounded to the nearest
/// paisa, and the last instalment simply clears what is left, so the leftover
/// rounding difference lands there. Due dates are the start date plus (k - 1)
/// months, clamped to month end (see [addMonthsClamped]).
EmiSchedule generateEmiSchedule({
  required Money price,
  Money downPayment = Money.zero,
  required double annualRatePercent,
  required int months,
  required DateTime startDate,
}) {
  if (price <= Money.zero) {
    throw const EmiInputError('Price must be above 0');
  }
  if (downPayment.isNegative || downPayment >= price) {
    throw const EmiInputError(
      'Down payment must be 0 or more and less than the price',
    );
  }
  if (!annualRatePercent.isFinite ||
      annualRatePercent < 0 ||
      annualRatePercent > 100) {
    throw const EmiInputError('Interest rate must be between 0 and 100');
  }
  if (months < 1 || months > 600) {
    throw const EmiInputError('Tenure must be between 1 and 600 months');
  }

  final financed = price - downPayment;
  final principalPaise = financed.paise;
  final r = annualRatePercent / 12 / 100;

  final double exactEmi;
  if (r == 0) {
    exactEmi = principalPaise / months;
  } else {
    final growth = math.pow(1 + r, months).toDouble();
    exactEmi = principalPaise * r * growth / (growth - 1);
  }
  final emiPaise = exactEmi.round();

  final installments = <EmiInstallment>[];
  var opening = principalPaise;
  for (var k = 1; k <= months; k++) {
    final interest = (opening * r).round();
    final int principal;
    if (k < months) {
      // Never negative and never more than what is left.
      principal = math.min(math.max(emiPaise - interest, 0), opening);
    } else {
      principal = opening; // the last instalment clears the loan exactly
    }
    opening -= principal;
    installments.add(
      EmiInstallment(
        number: k,
        dueDate: addMonthsClamped(startDate, k - 1),
        amount: Money(principal + interest),
        principal: Money(principal),
        interest: Money(interest),
        balanceAfter: Money(opening),
      ),
    );
  }

  return EmiSchedule(
    financed: financed,
    emi: Money(emiPaise),
    installments: installments,
  );
}
