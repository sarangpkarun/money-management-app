import '../core/interest/interest.dart';
import '../core/models/money_transaction.dart';
import '../core/money/money.dart';
import '../core/status/transaction_status.dart';

class EntryErrors {
  const EntryErrors({this.person, this.amount, this.dueDate, this.rate});

  final String? person;
  final String? amount;
  final String? dueDate;
  final String? rate;

  bool get hasAny =>
      person != null || amount != null || dueDate != null || rate != null;
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

EntryErrors validateEntry({
  required bool hasPerson,
  required String amountText,
  required DateTime date,
  DateTime? dueDate,
  InterestType interestType = InterestType.none,
  String rateText = '',
}) {
  final amount = Money.parse(amountText);
  String? rateError;
  if (interestType != InterestType.none) {
    final rate = double.tryParse(rateText.trim());
    if (rate == null || rate <= 0 || rate > 100) {
      rateError = 'Enter a rate above 0 and up to 100';
    }
  }
  return EntryErrors(
    person: hasPerson ? null : 'Choose or add a person',
    amount: (amount == null || amount <= Money.zero)
        ? 'Enter an amount above 0 (up to 2 decimals)'
        : null,
    dueDate: (dueDate != null && _dayOnly(dueDate).isBefore(_dayOnly(date)))
        ? 'Due date cannot be before the entry date'
        : null,
    rate: rateError,
  );
}

/// Fraction of what is due (principal plus interest to date) already paid,
/// between 0 and 1.
double paidFraction(MoneyTransaction t, {DateTime? now}) {
  final due = amountDue(t, now ?? DateTime.now());
  if (due <= Money.zero) return 0;
  return (t.paidTotal.paise / due.paise).clamp(0.0, 1.0);
}

/// e.g. "Received ₹500 of ₹1,000 · Balance ₹500", with the interest included
/// in the total when there is any: "... · incl. ₹1,200 interest".
String summaryLine(MoneyTransaction t, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final verb = t.isReceivable ? 'Received' : 'Paid';
  final interest = interestFor(t, at);
  final base =
      '$verb ${t.paidTotal.format()} of ${amountDue(t, at).format()} · '
      'Balance ${outstanding(t, at).format()}';
  return interest.isZero ? base : '$base · incl. ${interest.format()} interest';
}

String payActionLabel(MoneyTransaction t) =>
    t.isReceivable ? 'Receive Payment' : 'Pay Now';

String statusLabel(TransactionStatus s) => switch (s) {
  TransactionStatus.pending => 'Pending',
  TransactionStatus.partiallyPaid => 'Partially Paid',
  TransactionStatus.overdue => 'Overdue',
  TransactionStatus.paid => 'Paid',
};

/// 12.0 -> "12", 12.5 -> "12.5".
String formatRate(double rate) =>
    rate == rate.roundToDouble() ? rate.toInt().toString() : rate.toString();

String interestTypeLabel(InterestType t) => switch (t) {
  InterestType.none => 'No interest',
  InterestType.simple => 'Simple',
  InterestType.compound => 'Compound',
  InterestType.flat => 'Flat',
};

/// e.g. "Simple interest at 2% a month", "Flat interest of 5%".
String interestSummary(MoneyTransaction t) {
  final rate = formatRate(t.interestRate ?? 0);
  if (t.interestType == InterestType.flat) return 'Flat interest of $rate%';
  final per = t.ratePeriod == RatePeriod.month ? 'a month' : 'a year';
  return '${interestTypeLabel(t.interestType)} interest at $rate% $per';
}

String repaymentLabel(RepaymentType t) => switch (t) {
  RepaymentType.oneTime => 'One-time',
  RepaymentType.weekly => 'Weekly instalments',
  RepaymentType.monthly => 'Monthly instalments',
  RepaymentType.flexible => 'Flexible',
};

/// Status recomputed at [now] against principal plus interest; the stored
/// value can go stale as time passes. A settled entry stays Paid (its interest
/// is frozen when it settles).
TransactionStatus effectiveStatus(MoneyTransaction t, {required DateTime now}) {
  if (t.status == TransactionStatus.paid) return TransactionStatus.paid;
  return computeStatus(
    total: amountDue(t, now),
    paid: t.paidTotal,
    dueDate: t.dueDate,
    now: now,
  );
}
