import '../core/models/emi_plan.dart';
import '../core/money/money.dart';

/// Whether paying [amount] on an entry that still has [available] to pay clears
/// it completely.
bool paymentSettles({required Money amount, required Money available}) =>
    available > Money.zero && amount >= available;

/// Whether paying [amount] on [row] of [plan] pays the last thing still owed:
/// the row is cleared and every other row is already paid.
bool rowPaymentSettles(EmiPlan plan, EmiRow row, Money amount) {
  if (amount < row.remaining || row.remaining.isZero) return false;
  return plan.rows.every((r) => r.number == row.number || r.isPaid);
}
