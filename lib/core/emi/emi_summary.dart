import '../models/emi_plan.dart';
import '../money/money.dart';

/// The numbers on an EMI entry's summary card.
class EmiSummary {
  const EmiSummary({
    required this.next,
    required this.remainingCount,
    required this.remainingTotal,
    required this.lastDueDate,
    required this.paidCount,
    required this.overdueCount,
    required this.overdueAmount,
  });

  /// The oldest instalment not fully paid; null once everything is paid.
  final EmiRow? next;
  final int remainingCount;

  /// What is still to pay across all rows (part payments taken off).
  final Money remainingTotal;
  final DateTime lastDueDate;
  final int paidCount;
  final int overdueCount;

  /// What the overdue rows still owe.
  final Money overdueAmount;

  bool get isComplete => remainingCount == 0;
}

EmiSummary summarizePlan(EmiPlan plan, DateTime now) {
  var remainingCount = 0;
  var paidCount = 0;
  var overdueCount = 0;
  var remainingTotal = Money.zero;
  var overdueAmount = Money.zero;

  for (final row in plan.rows) {
    if (row.isPaid) {
      paidCount++;
      continue;
    }
    remainingCount++;
    remainingTotal = remainingTotal + row.remaining;
    if (row.statusAt(now) == EmiRowStatus.overdue) {
      overdueCount++;
      overdueAmount = overdueAmount + row.remaining;
    }
  }
  return EmiSummary(
    next: plan.nextUnpaid,
    remainingCount: remainingCount,
    remainingTotal: remainingTotal,
    lastDueDate: plan.rows.isEmpty ? plan.startDate : plan.rows.last.dueDate,
    paidCount: paidCount,
    overdueCount: overdueCount,
    overdueAmount: overdueAmount,
  );
}
