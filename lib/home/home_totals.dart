import '../core/interest/interest.dart';
import '../core/models/money_transaction.dart';
import '../core/money/money.dart';
import '../core/status/transaction_status.dart';
import '../transactions/entry_form_logic.dart';

/// The numbers on the Home screen.
class HomeTotals {
  const HomeTotals({
    required this.toReceive,
    required this.toPay,
    required this.overdueCount,
    required this.overdueAmount,
  });

  final Money toReceive;
  final Money toPay;

  /// Positive: you are owed more than you owe.
  Money get net => toReceive - toPay;

  final int overdueCount;

  /// What is still owed on the overdue entries (both directions added up).
  final Money overdueAmount;
}

/// Totals at [now], using what is still owed including interest. Settled
/// entries count nothing. Overdue comes from the due date, not the stored
/// status, which can be stale.
HomeTotals computeHomeTotals(
  List<MoneyTransaction> transactions, {
  required DateTime now,
}) {
  var toReceive = Money.zero;
  var toPay = Money.zero;
  var overdueCount = 0;
  var overdueAmount = Money.zero;

  for (final t in transactions) {
    final owed = outstanding(t, now);
    if (owed.isZero) continue;
    if (t.isReceivable) {
      toReceive = toReceive + owed;
    } else {
      toPay = toPay + owed;
    }
    if (effectiveStatus(t, now: now) == TransactionStatus.overdue) {
      overdueCount++;
      overdueAmount = overdueAmount + owed;
    }
  }
  return HomeTotals(
    toReceive: toReceive,
    toPay: toPay,
    overdueCount: overdueCount,
    overdueAmount: overdueAmount,
  );
}

/// The most recently active entries, newest first.
List<MoneyTransaction> recentEntries(
  List<MoneyTransaction> all, {
  int limit = 5,
}) {
  final sorted = [...all]
    ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  return sorted.take(limit).toList();
}
