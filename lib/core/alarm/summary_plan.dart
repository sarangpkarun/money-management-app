import '../../home/summary_text.dart';
import '../models/app_settings.dart';
import '../models/money_transaction.dart';
import '../models/reminder.dart';
import 'alarm_plan.dart';
import 'auto_alarms.dart';
import 'quiet_hours.dart';

const _dailyAhead = 7;
const _weeklyAhead = 4;

/// The summary notifications to schedule: the next 7 days for a daily summary,
/// the next 4 weeks for a weekly one, none when it is off. All carry the text
/// worked out now (it says which day it is as of). Quiet hours delay a summary
/// to the end of the window.
List<AutoRing> summaryRings(
  List<MoneyTransaction> transactions,
  DateTime now,
  SummarySettings summary,
  QuietHours quietHours,
) {
  if (summary.mode == SummaryMode.off) return const [];
  final text = summaryText(transactions, now);
  final daily = summary.mode == SummaryMode.daily;
  final wanted = daily ? _dailyAhead : _weeklyAhead;
  final out = <AutoRing>[];
  for (var k = 0; k < 40 && out.length < wanted; k++) {
    final raw = DateTime(
      now.year,
      now.month,
      now.day + k,
      summary.minutes ~/ 60,
      summary.minutes % 60,
    );
    if (!daily && raw.weekday != summary.weekday) continue;
    final at = applyQuietHours(raw, quietHours);
    if (!at.isAfter(now)) continue;
    final id =
        'summary:${raw.year}${raw.month.toString().padLeft(2, '0')}'
        '${raw.day.toString().padLeft(2, '0')}';
    out.add(
      AutoRing(
        id: id,
        payload: AlarmPayload(
          reminderId: id,
          title: daily ? 'Daily summary' : 'Weekly summary',
          notes: text,
          snoozeMinutes: autoSnoozeMinutes,
          tone: ReminderTone.notification,
          vibration: ReminderVibration.off,
          at: at,
          kind: AlarmKind.summary,
        ),
      ),
    );
  }
  return out;
}
