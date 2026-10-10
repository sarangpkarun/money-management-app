import '../core/models/money_transaction.dart';
import '../core/ui/format.dart';
import 'due_items.dart';
import 'home_totals.dart';

/// The text of the daily or weekly summary notification, from the entries as
/// they are at [now]: how many payments are overdue and due this week, and what
/// you owe and are owed. It ends with the day it was worked out, because the
/// phone shows it later without looking at the entries again.
String summaryText(List<MoneyTransaction> transactions, DateTime now) {
  final groups = groupDueItems(dueItems(transactions, now), now);
  final totals = computeHomeTotals(transactions, now: now);
  final parts = <String>[
    if (groups.overdue.count > 0) '${groups.overdue.count} overdue',
    if (groups.thisWeek.count > 0) '${groups.thisWeek.count} due this week',
    if (!totals.toPay.isZero) 'You owe ${totals.toPay.format()}',
    if (!totals.toReceive.isZero) 'You are owed ${totals.toReceive.format()}',
  ];
  final body = parts.isEmpty ? 'Nothing due this week' : parts.join(' · ');
  return '$body (as of ${formatShortDate(now)})';
}
