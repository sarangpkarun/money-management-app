import '../core/interest/interest.dart';
import '../core/models/money_transaction.dart';
import '../core/money/money.dart';
import '../core/status/transaction_status.dart';

/// One payment that is due: an unpaid EMI or instalment row, or an entry's own
/// due date.
class DueItem {
  const DueItem({
    required this.entry,
    required this.rowNumber,
    required this.date,
    required this.amount,
  });

  final MoneyTransaction entry;

  /// The EMI or instalment row, null for a whole-entry due date.
  final int? rowNumber;

  /// The due day (date only).
  final DateTime date;

  /// What is still to pay (or collect) on this payment.
  final Money amount;

  /// True when this is money coming to you.
  bool get isReceivable => entry.isReceivable;

  /// "EMI #3 · Phone", "Payment #2 · Loan", or just the entry title.
  String get what => switch (entry.type) {
    TransactionType.emi => 'EMI #$rowNumber · ${entry.title}',
    TransactionType.instalment => 'Payment #$rowNumber · ${entry.title}',
    _ => entry.title,
  };
}

/// Items sharing a bucket, with what they add up to in each direction.
class DueGroup {
  const DueGroup(this.items);

  final List<DueItem> items;

  bool get isEmpty => items.isEmpty;
  int get count => items.length;

  Money get toReceive => items
      .where((i) => i.isReceivable)
      .fold(Money.zero, (sum, i) => sum + i.amount);

  Money get toPay => items
      .where((i) => !i.isReceivable)
      .fold(Money.zero, (sum, i) => sum + i.amount);
}

/// The four disjoint buckets of the dashboard, by calendar day: overdue (before
/// today), this week (today to Sunday), this month (after this week to month
/// end) and upcoming (later).
class DueGroups {
  const DueGroups({
    required this.overdue,
    required this.thisWeek,
    required this.thisMonth,
    required this.upcoming,
  });

  final DueGroup overdue;
  final DueGroup thisWeek;
  final DueGroup thisMonth;
  final DueGroup upcoming;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Every unpaid payment of [transactions] that has a due date, soonest first.
/// Paid entries, paid rows and entries without a due date give nothing. An
/// entry's own amount includes interest to [now].
List<DueItem> dueItems(List<MoneyTransaction> transactions, DateTime now) {
  final out = <DueItem>[];
  for (final t in transactions) {
    if (t.status == TransactionStatus.paid) continue;
    final plan = t.emiPlan;
    if (plan != null) {
      for (final r in plan.rows) {
        if (r.isPaid) continue;
        out.add(
          DueItem(
            entry: t,
            rowNumber: r.number,
            date: _day(r.dueDate),
            amount: r.remaining,
          ),
        );
      }
      continue;
    }
    final due = t.dueDate;
    if (due == null) continue;
    final owed = outstanding(t, now);
    if (owed.isZero) continue;
    out.add(DueItem(entry: t, rowNumber: null, date: _day(due), amount: owed));
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// Sorts [items] into the four buckets relative to [now].
DueGroups groupDueItems(List<DueItem> items, DateTime now) {
  final today = _day(now);
  // Sunday ends the week; on a Sunday the week is just today.
  final weekEnd = DateTime(
    today.year,
    today.month,
    today.day + (DateTime.sunday - today.weekday),
  );
  final monthEnd = DateTime(today.year, today.month + 1, 0);

  final overdue = <DueItem>[];
  final week = <DueItem>[];
  final month = <DueItem>[];
  final later = <DueItem>[];
  for (final i in items) {
    if (i.date.isBefore(today)) {
      overdue.add(i);
    } else if (!i.date.isAfter(weekEnd)) {
      week.add(i);
    } else if (!i.date.isAfter(monthEnd)) {
      month.add(i);
    } else {
      later.add(i);
    }
  }
  return DueGroups(
    overdue: DueGroup(overdue),
    thisWeek: DueGroup(week),
    thisMonth: DueGroup(month),
    upcoming: DueGroup(later),
  );
}

int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// "3 days late", "Due today", "Due tomorrow" or "Due 12 Jan 2030".
String dueLabel(DueItem item, DateTime now, String Function(DateTime) format) {
  final days = _daysBetween(now, item.date);
  if (days < 0) return days == -1 ? '1 day late' : '${-days} days late';
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'Due ${format(item.date)}';
}
