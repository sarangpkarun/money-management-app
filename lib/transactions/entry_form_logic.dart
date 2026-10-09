import '../core/models/money_transaction.dart';
import '../core/money/money.dart';
import '../core/status/transaction_status.dart';

class EntryErrors {
  const EntryErrors({this.person, this.amount, this.dueDate});

  final String? person;
  final String? amount;
  final String? dueDate;

  bool get hasAny => person != null || amount != null || dueDate != null;
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

EntryErrors validateEntry({
  required bool hasPerson,
  required String amountText,
  required DateTime date,
  DateTime? dueDate,
}) {
  final amount = Money.parse(amountText);
  return EntryErrors(
    person: hasPerson ? null : 'Choose or add a person',
    amount: (amount == null || amount <= Money.zero)
        ? 'Enter an amount above 0 (up to 2 decimals)'
        : null,
    dueDate: (dueDate != null && _dayOnly(dueDate).isBefore(_dayOnly(date)))
        ? 'Due date cannot be before the entry date'
        : null,
  );
}

/// Fraction of the total already paid, between 0 and 1.
double paidFraction(MoneyTransaction t) {
  if (t.totalAmount <= Money.zero) return 0;
  return (t.paidTotal.paise / t.totalAmount.paise).clamp(0.0, 1.0);
}

/// e.g. "Received ₹500 of ₹1,000 · Balance ₹500".
String summaryLine(MoneyTransaction t) {
  final verb = t.isReceivable ? 'Received' : 'Paid';
  return '$verb ${t.paidTotal.format()} of ${t.totalAmount.format()} · '
      'Balance ${t.balance.format()}';
}

String payActionLabel(MoneyTransaction t) =>
    t.isReceivable ? 'Receive Payment' : 'Pay Now';

String statusLabel(TransactionStatus s) => switch (s) {
  TransactionStatus.pending => 'Pending',
  TransactionStatus.partiallyPaid => 'Partially Paid',
  TransactionStatus.overdue => 'Overdue',
  TransactionStatus.paid => 'Paid',
};

/// Status recomputed at [now]; the stored value can go stale as time passes.
TransactionStatus effectiveStatus(
  MoneyTransaction t, {
  required DateTime now,
}) => computeStatus(
  total: t.totalAmount,
  paid: t.paidTotal,
  dueDate: t.dueDate,
  now: now,
);
