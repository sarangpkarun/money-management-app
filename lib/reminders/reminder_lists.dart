import '../core/alarm/auto_alarms.dart';
import '../core/models/app_settings.dart';
import '../core/models/money_transaction.dart';
import '../core/models/reminder.dart';
import '../core/reminders/repeat.dart';

/// How far ahead automatic payment alarms are listed under Upcoming.
const upcomingAutoDays = 14;

/// One row of the Upcoming list: a manual reminder's next ring, or an automatic
/// payment alarm.
class UpcomingItem {
  const UpcomingItem.reminder(Reminder this.reminder, this.at) : auto = null;
  const UpcomingItem.auto(AutoRing this.auto) : reminder = null, at = null;

  final Reminder? reminder;
  final AutoRing? auto;
  final DateTime? at;

  DateTime get when => at ?? auto!.payload.at;
}

/// The three lists on the Reminders tab.
class ReminderLists {
  const ReminderLists({
    required this.upcoming,
    required this.completed,
    required this.missed,
  });

  /// Reminders still to ring and automatic payment alarms, soonest first.
  final List<UpcomingItem> upcoming;

  /// Reminders marked done, newest first.
  final List<Reminder> completed;

  /// One-off reminders whose time passed without being marked done, most recent
  /// first. A repeating reminder is never missed: its next ring is ahead.
  final List<Reminder> missed;
}

ReminderLists buildReminderLists(
  List<Reminder> reminders,
  List<MoneyTransaction> transactions,
  DateTime now, {
  AppSettings settings = AppSettings.defaults,
}) {
  final upcoming = <UpcomingItem>[];
  final completed = <Reminder>[];
  final missed = <Reminder>[];

  for (final r in reminders) {
    if (r.done) {
      completed.add(r);
      continue;
    }
    final next = nextOccurrence(r, now);
    if (next != null) {
      upcoming.add(UpcomingItem.reminder(r, next));
    } else if (!r.repeat.repeats) {
      missed.add(r);
    }
  }

  final horizon = now.add(const Duration(days: upcomingAutoDays));
  for (final a in autoRings(
    transactions,
    now,
    alarmMinutes: settings.autoAlarmMinutes,
    quietHours: settings.quietHours,
  )) {
    if (!a.payload.at.isAfter(horizon)) upcoming.add(UpcomingItem.auto(a));
  }

  upcoming.sort((a, b) => a.when.compareTo(b.when));
  completed.sort((a, b) => (b.doneAt ?? b.at).compareTo(a.doneAt ?? a.at));
  missed.sort((a, b) => b.at.compareTo(a.at));
  return ReminderLists(
    upcoming: upcoming,
    completed: completed,
    missed: missed,
  );
}
