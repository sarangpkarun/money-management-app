import '../models/emi_plan.dart';
import '../money/money.dart';
import 'emi_schedule.dart';

/// An estimated late fee on an EMI plan. Never added to what is owed.
class LateFeeEstimate {
  const LateFeeEstimate({required this.total, required this.count});

  final Money total;

  /// How many instalments are late enough to be charged.
  final int count;
}

int _days(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// The late fee to date: each unpaid instalment that is more than the rule's
/// grace days past its due date is charged once, a flat amount or a percentage
/// of what is still owed on it. Paid instalments and plans without a rule cost
/// nothing.
LateFeeEstimate lateFeeToDate(EmiPlan plan, DateTime now) {
  final rule = plan.lateFee;
  if (rule == null) return const LateFeeEstimate(total: Money.zero, count: 0);
  var total = Money.zero;
  var count = 0;
  for (final row in plan.rows) {
    if (row.isPaid) continue;
    if (_days(row.dueDate, now) <= rule.graceDays) continue;
    count++;
    total =
        total +
        (rule.flat ??
            Money((row.remaining.paise * rule.percent! / 100).round()));
  }
  return LateFeeEstimate(total: total, count: count);
}

/// For a no-cost EMI: the interest the seller absorbs, worked out at the
/// lender's yearly rate over the same months. Zero when it is not no-cost.
Money noCostSellerInterest(EmiPlan plan) {
  final rate = plan.noCostRate;
  if (rate == null || rate <= 0) return Money.zero;
  return generateEmiSchedule(
    price: plan.price,
    downPayment: plan.downPayment,
    annualRatePercent: rate,
    months: plan.months,
    startDate: plan.startDate,
  ).totalInterest;
}
