import '../emi/month_dates.dart';
import '../models/reminder.dart';

int _dayNumber(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1970)).inDays;

/// The ring on calendar day [date], at [base]'s time of day. Built from
/// calendar fields so a daylight-saving change never moves the wall-clock time.
DateTime _onDay(DateTime date, DateTime base) =>
    DateTime(date.year, date.month, date.day, base.hour, base.minute);

DateTime _addDays(DateTime base, int days) =>
    DateTime(base.year, base.month, base.day + days, base.hour, base.minute);

/// The first ring of [r] strictly after [after], or null when there is none
/// (a one-off that has passed, a done reminder, a weekly with no weekday).
///
/// Weekly rings only on the chosen weekdays, from the first ring's day on, so
/// the first ring itself counts only if its weekday is chosen. Monthly and
/// yearly measure from the first ring's day, so a 31st rings on 28 or 29 Feb and
/// is back on the 31st in March.
DateTime? nextOccurrence(Reminder r, DateTime after) {
  if (r.done) return null;
  final base = r.at;
  switch (r.repeat.kind) {
    case RepeatKind.none:
      return base.isAfter(after) ? base : null;
    case RepeatKind.daily:
      return _everyDays(base, 1, after);
    case RepeatKind.everyNDays:
      return _everyDays(
        base,
        r.repeat.interval < 1 ? 1 : r.repeat.interval,
        after,
      );
    case RepeatKind.weekly:
      return _weekly(base, r.repeat.weekdays, after);
    case RepeatKind.monthly:
      return _everyMonths(base, 1, after);
    case RepeatKind.yearly:
      return _everyMonths(base, 12, after);
  }
}

DateTime? _everyDays(DateTime base, int step, DateTime after) {
  if (base.isAfter(after)) return base;
  var k = (_dayNumber(after) - _dayNumber(base)) ~/ step;
  if (k > 0) k--; // start a step early, then walk forward
  for (; ; k++) {
    final c = _addDays(base, k * step);
    if (c.isAfter(after)) return c;
  }
}

DateTime? _weekly(DateTime base, Set<int> weekdays, DateTime after) {
  final days = weekdays.where((d) => d >= 1 && d <= 7).toSet();
  if (days.isEmpty) return null;
  var i = _dayNumber(after) - _dayNumber(base);
  if (i < 0) i = 0;
  if (i > 0) i--;
  for (var n = 0; n < 16; n++, i++) {
    final c = _addDays(base, i);
    if (days.contains(c.weekday) && c.isAfter(after)) return c;
  }
  return null;
}

DateTime? _everyMonths(DateTime base, int step, DateTime after) {
  if (base.isAfter(after)) return base;
  final months =
      (after.year * 12 + after.month) - (base.year * 12 + base.month);
  var k = months ~/ step;
  if (k > 0) k--;
  for (; ; k++) {
    final c = _onDay(addMonthsClamped(base, k * step), base);
    if (c.isAfter(after)) return c;
  }
}

/// Rings of [r] from [from] up to and including [to], at most [max] of them.
List<DateTime> occurrencesBetween(
  Reminder r,
  DateTime from,
  DateTime to, {
  int max = 200,
}) {
  final out = <DateTime>[];
  var next = nextOccurrence(r, from.subtract(const Duration(microseconds: 1)));
  while (next != null && !next.isAfter(to) && out.length < max) {
    out.add(next);
    next = nextOccurrence(r, next);
  }
  return out;
}
