import '../money/money.dart';

enum TransactionStatus { pending, partiallyPaid, overdue, paid }

enum PaymentValidation { ok, notPositive, exceedsBalance }

/// Derives a transaction's status from its totals and due date.
///
/// Rules (product doc 8.2): a zero balance is Paid; otherwise a passed due date
/// is Overdue (it beats Pending and Partially Paid); otherwise any payment makes
/// it Partially Paid; else Pending. An entry is overdue from the day *after* its
/// due date, regardless of the time of day.
TransactionStatus computeStatus({
  required Money total,
  required Money paid,
  required DateTime? dueDate,
  required DateTime now,
}) {
  if (total - paid <= Money.zero) return TransactionStatus.paid;
  if (dueDate != null) {
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    if (today.isAfter(due)) return TransactionStatus.overdue;
  }
  if (paid > Money.zero) return TransactionStatus.partiallyPaid;
  return TransactionStatus.pending;
}

/// Overpayment is blocked: a payment must be positive and not exceed the
/// current balance.
PaymentValidation validatePayment({
  required Money balance,
  required Money amount,
}) {
  if (amount <= Money.zero) return PaymentValidation.notPositive;
  if (amount > balance) return PaymentValidation.exceedsBalance;
  return PaymentValidation.ok;
}
