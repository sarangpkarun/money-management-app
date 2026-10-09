import '../core/interest/interest.dart';
import '../core/models/money_transaction.dart';
import '../core/models/payment.dart';
import '../core/money/money.dart';

/// A transaction together with its payments.
class TransactionWithPayments {
  const TransactionWithPayments(this.transaction, this.payments);

  final MoneyTransaction transaction;
  final List<Payment> payments;
}

enum LedgerKind { entry, interest, payment }

/// Cash direction for a row: green means money in, red money out; interest is
/// an accrual, not a cash movement.
enum LedgerFlow { moneyIn, moneyOut, none }

/// One row of a person's ledger. [delta] moves the running balance: positive
/// means they owe you more, negative means you owe them more (the same
/// convention as the People list's net amount).
class LedgerEvent {
  const LedgerEvent({
    required this.kind,
    required this.date,
    required this.label,
    this.detail,
    required this.delta,
    required this.transactionId,
    this.flow = LedgerFlow.none,
    this.balanceAfter = Money.zero,
  });

  final LedgerKind kind;
  final DateTime date;
  final String label;
  final String? detail;
  final Money delta;
  final String transactionId;
  final LedgerFlow flow;

  /// The running balance once this row is applied.
  final Money balanceAfter;

  LedgerEvent withBalance(Money balance) => LedgerEvent(
    kind: kind,
    date: date,
    label: label,
    detail: detail,
    delta: delta,
    transactionId: transactionId,
    flow: flow,
    balanceAfter: balance,
  );
}

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Builds the ledger, oldest first, with a running balance.
///
/// Every entry is a row (`Gave` for money lent, `Borrowed` otherwise), every
/// payment a row (`Received` / `Paid`), and entries with interest get an
/// `Interest` row dated where accrual currently stops: today while open, the
/// settled day once paid. That makes the last running balance equal the net
/// shown on the People list. On the same day the order is entry, interest, then
/// payments, so a loan settled today reads "owe X, owe X plus interest, paid,
/// zero".
List<LedgerEvent> buildLedger(
  List<TransactionWithPayments> items, {
  required DateTime now,
}) {
  final entries = <({LedgerEvent event, DateTime stamp, String tie})>[];

  for (final item in items) {
    final t = item.transaction;
    final sign = t.isReceivable ? 1 : -1;

    entries.add((
      event: LedgerEvent(
        kind: LedgerKind.entry,
        date: t.entryDate,
        label: switch (t.type) {
          TransactionType.emi => 'EMI purchase ${t.totalAmount.format()}',
          TransactionType.instalment =>
            'Instalment plan ${t.totalAmount.format()}',
          _ =>
            '${t.isReceivable ? 'Gave' : 'Borrowed'} ${t.totalAmount.format()}',
        },
        detail: t.title,
        delta: Money(sign * t.totalAmount.paise),
        transactionId: t.id,
        flow: t.isReceivable ? LedgerFlow.moneyOut : LedgerFlow.moneyIn,
      ),
      stamp: t.entryDate,
      tie: t.id,
    ));

    final interest = interestFor(t, now);
    if (!interest.isZero) {
      final at = accrualEnd(t, now);
      entries.add((
        event: LedgerEvent(
          kind: LedgerKind.interest,
          date: at,
          label: 'Interest ${interest.format()}',
          detail: t.title,
          delta: Money(sign * interest.paise),
          transactionId: t.id,
        ),
        stamp: at,
        tie: t.id,
      ));
    }

    for (final p in item.payments) {
      entries.add((
        event: LedgerEvent(
          kind: LedgerKind.payment,
          date: p.date,
          label: '${t.isReceivable ? 'Received' : 'Paid'} ${p.amount.format()}',
          detail: t.title,
          delta: Money(-sign * p.amount.paise),
          transactionId: t.id,
          flow: t.isReceivable ? LedgerFlow.moneyIn : LedgerFlow.moneyOut,
        ),
        stamp: p.createdAt ?? p.date,
        tie: '${t.id}/${p.id}',
      ));
    }
  }

  entries.sort((a, b) {
    final byDay = _day(a.event.date).compareTo(_day(b.event.date));
    if (byDay != 0) return byDay;
    final byKind = a.event.kind.index.compareTo(b.event.kind.index);
    if (byKind != 0) return byKind;
    final byStamp = a.stamp.compareTo(b.stamp);
    return byStamp != 0 ? byStamp : a.tie.compareTo(b.tie);
  });

  var balance = Money.zero;
  return [
    for (final e in entries)
      e.event.withBalance(balance = balance + e.event.delta),
  ];
}
