import '../interest/interest.dart';
import '../models/app_settings.dart';
import '../models/money_transaction.dart';
import '../models/reminder.dart';
import '../money/money.dart';
import '../status/transaction_status.dart';
import 'alarm_plan.dart';
import 'quiet_hours.dart';

/// When automatic payment alarms ring unless the user changes it: 9:00 am.
const defaultAutoAlarmMinutes = 9 * 60;

/// How many minutes an automatic alarm snoozes for.
const autoSnoozeMinutes = 10;

enum _When { before, due, overdue }

const _suffix = {_When.before: 'b', _When.due: 'd', _When.overdue: 'o'};
const _phrase = {
  _When.before: 'due tomorrow',
  _When.due: 'due today',
  _When.overdue: 'overdue',
};

/// One payment that is due: [number] is the EMI or instalment row, 0 for a
/// whole-entry due date.
class _Due {
  const _Due(this.number, this.date, this.amount);

  final int number;
  final DateTime date;
  final Money amount;
}

/// The unpaid payments of [t] that have a due date.
List<_Due> _dues(MoneyTransaction t, DateTime now) {
  final plan = t.emiPlan;
  if (plan != null) {
    return [
      for (final r in plan.rows)
        if (!r.isPaid) _Due(r.number, r.dueDate, r.remaining),
    ];
  }
  final due = t.dueDate;
  return due == null ? const [] : [_Due(0, due, outstanding(t, now))];
}

bool _wanted(MoneyTransaction t) =>
    t.autoReminders && t.status != TransactionStatus.paid;

String _id(MoneyTransaction t, _Due d, _When w) =>
    'auto:${t.id}:${d.number}:${_suffix[w]}';

DateTime _ringAt(DateTime due, _When w, int minutes) {
  final offset = switch (w) {
    _When.before => -1,
    _When.due => 0,
    _When.overdue => 1,
  };
  return DateTime(
    due.year,
    due.month,
    due.day + offset,
    minutes ~/ 60,
    minutes % 60,
  );
}

String _what(MoneyTransaction t, _Due d) {
  final amount = d.amount.format();
  return switch (t.type) {
    TransactionType.lent => 'Collect $amount from ${t.personName}',
    TransactionType.borrowed => 'Pay ${t.personName} $amount',
    TransactionType.emi => 'EMI #${d.number} · ${t.title} $amount',
    TransactionType.instalment => 'Payment #${d.number} · ${t.title} $amount',
  };
}

/// An automatic alarm before it has a numeric id.
class AutoRing {
  const AutoRing({required this.id, required this.payload});

  /// A string id like `auto:<entry>:<row>:<b|d|o>`, unique per ring.
  final String id;
  final AlarmPayload payload;
}

/// The automatic alarms for [transactions] that are still to ring after [now]:
/// for each unpaid payment with a due date, 9:00 the day before ("due
/// tomorrow"), on the day ("due today") and the day after ("overdue"). Entries
/// that are paid or have automatic reminders switched off get none.
List<AutoRing> autoRings(
  List<MoneyTransaction> transactions,
  DateTime now, {
  int alarmMinutes = defaultAutoAlarmMinutes,
  QuietHours quietHours = const QuietHours(),
}) {
  final out = <AutoRing>[];
  for (final t in transactions) {
    if (!_wanted(t)) continue;
    for (final d in _dues(t, now)) {
      for (final w in _When.values) {
        // Quiet hours delay a ring to the end of the window; a ring whose time
        // has passed but whose delayed time is still ahead still rings then.
        final at = applyQuietHours(
          _ringAt(d.date, w, alarmMinutes),
          quietHours,
        );
        if (!at.isAfter(now)) continue;
        out.add(
          AutoRing(
            id: _id(t, d, w),
            payload: AlarmPayload(
              reminderId: _id(t, d, w),
              title: '${_what(t, d)} · ${_phrase[w]}',
              notes:
                  t.type == TransactionType.emi ||
                      t.type == TransactionType.instalment
                  ? t.personName
                  : t.title,
              snoozeMinutes: autoSnoozeMinutes,
              tone: ReminderTone.alarm,
              vibration: ReminderVibration.long,
              at: at,
              entryId: t.id,
            ),
          ),
        );
      }
    }
  }
  return out;
}

/// Every automatic-alarm id an open entry could have, past rings included. A
/// snoozed automatic alarm stays pending while its id is in this set.
Set<String> openAutoIds(List<MoneyTransaction> transactions, DateTime now) => {
  for (final t in transactions)
    if (_wanted(t))
      for (final d in _dues(t, now))
        for (final w in _When.values) _id(t, d, w),
};
