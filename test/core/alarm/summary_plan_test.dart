import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/alarm/alarm_plan.dart';
import 'package:money_manager/core/alarm/auto_alarms.dart';
import 'package:money_manager/core/alarm/summary_plan.dart';
import 'package:money_manager/core/models/app_settings.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/reminder.dart';
import 'package:money_manager/core/money/money.dart';

MoneyTransaction lent(String id, DateTime due) => MoneyTransaction(
  id: id,
  type: TransactionType.lent,
  personId: 'p',
  personName: 'Asha',
  title: 'Loan',
  totalAmount: Money.fromRupees(100),
  dueDate: due,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  // Mon 7 Jan 2030, 10:00.
  final now = DateTime(2030, 1, 7, 10);
  const none = QuietHours();

  group('summaryRings', () {
    test('off means none', () {
      expect(
        summaryRings(const [], now, const SummarySettings(), none),
        isEmpty,
      );
    });

    test(
      'daily: the next 7 days at the chosen time, today only if still ahead',
      () {
        final r = summaryRings(
          const [],
          now,
          const SummarySettings(mode: SummaryMode.daily, minutes: 8 * 60),
          none,
        );
        expect(r.length, 7);
        // 8:00 today has passed (it is 10:00), so tomorrow is first.
        expect(r.first.payload.at, DateTime(2030, 1, 8, 8));
        expect(r.last.payload.at, DateTime(2030, 1, 14, 8));
        expect(r.every((x) => x.payload.at.hour == 8), isTrue);
      },
    );

    test('daily includes today when its time is still ahead', () {
      final r = summaryRings(
        const [],
        now,
        const SummarySettings(mode: SummaryMode.daily, minutes: 18 * 60),
        none,
      );
      expect(r.first.payload.at, DateTime(2030, 1, 7, 18));
    });

    test('weekly: the next 4 of the chosen weekday', () {
      final r = summaryRings(
        const [],
        now,
        const SummarySettings(
          mode: SummaryMode.weekly,
          minutes: 9 * 60,
          weekday: DateTime.friday,
        ),
        none,
      );
      expect(r.length, 4);
      expect(r.map((x) => x.payload.at), [
        DateTime(2030, 1, 11, 9),
        DateTime(2030, 1, 18, 9),
        DateTime(2030, 1, 25, 9),
        DateTime(2030, 2, 1, 9),
      ]);
      expect(r.every((x) => x.payload.at.weekday == DateTime.friday), isTrue);
    });

    test(
      'weekly on the same weekday as today waits for the next one if passed',
      () {
        final r = summaryRings(
          const [],
          now,
          const SummarySettings(
            mode: SummaryMode.weekly,
            minutes: 8 * 60,
            weekday: DateTime.monday,
          ),
          none,
        );
        expect(r.first.payload.at, DateTime(2030, 1, 14, 8));
      },
    );

    test('they are quiet summaries carrying the text', () {
      final r = summaryRings(
        [lent('a', DateTime(2030, 1, 9))],
        now,
        const SummarySettings(mode: SummaryMode.daily),
        none,
      );
      final p = r.first.payload;
      expect(p.kind, AlarmKind.summary);
      expect(p.title, 'Daily summary');
      expect(p.notes, contains('1 due this week'));
      expect(p.notes, contains('You are owed ₹100'));
      expect(p.vibration, ReminderVibration.off);
      expect(r.map((x) => x.id).toSet().length, r.length);
    });

    test('weekly title', () {
      final r = summaryRings(
        const [],
        now,
        const SummarySettings(mode: SummaryMode.weekly),
        none,
      );
      expect(r.first.payload.title, 'Weekly summary');
    });

    test('quiet hours delay a summary to the end of the window', () {
      final r = summaryRings(
        const [],
        now,
        const SummarySettings(mode: SummaryMode.daily, minutes: 6 * 60),
        const QuietHours(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 7 * 60,
        ),
      );
      expect(r.first.payload.at, DateTime(2030, 1, 8, 7));
      expect(r.length, 7);
      final times = r.map((x) => x.payload.at).toList();
      expect(times.toSet().length, times.length); // no two at the same moment
    });
  });

  group('planAllAlarms with settings', () {
    final settings = const AppSettings().copyWith(
      summary: const SummarySettings(mode: SummaryMode.daily, minutes: 8 * 60),
    );

    test('summaries are planned alongside alarms with unique ids', () {
      final plan = planAllAlarms(
        const [],
        [lent('a', DateTime(2030, 1, 9))],
        now,
        settings: settings,
      );
      expect(plan.where((a) => a.payload.kind == AlarmKind.summary).length, 7);
      expect(plan.where((a) => a.payload.kind == AlarmKind.alarm).length, 3);
      expect(plan.map((a) => a.id).toSet().length, plan.length);
    });

    test('summary off schedules none', () {
      final plan = planAllAlarms(const [], const [], now);
      expect(plan, isEmpty);
    });

    test('the summary kind survives encode and decode', () {
      final plan = planAllAlarms(const [], const [], now, settings: settings);
      final back = AlarmPayload.decode(plan.first.encodedPayload)!;
      expect(back.kind, AlarmKind.summary);
      expect(back.notes, plan.first.payload.notes);
    });

    test('ordinary alarms still decode as alarms', () {
      final plan = planAllAlarms(const [], [
        lent('a', DateTime(2030, 1, 9)),
      ], now);
      expect(
        AlarmPayload.decode(plan.first.encodedPayload)!.kind,
        AlarmKind.alarm,
      );
    });
  });

  group('configurable alarm time and quiet hours on automatic alarms', () {
    test('the time is configurable, including minutes', () {
      final r = autoRings(
        [lent('a', DateTime(2030, 1, 10))],
        now,
        alarmMinutes: 7 * 60 + 30,
      );
      expect(r.map((x) => x.payload.at), [
        DateTime(2030, 1, 9, 7, 30),
        DateTime(2030, 1, 10, 7, 30),
        DateTime(2030, 1, 11, 7, 30),
      ]);
    });

    test('default is still 9:00', () {
      final r = autoRings([lent('a', DateTime(2030, 1, 10))], now);
      expect(r.first.payload.at, DateTime(2030, 1, 9, 9));
    });

    test('quiet hours delay a ring that falls inside them', () {
      final r = autoRings(
        [lent('a', DateTime(2030, 1, 10))],
        now,
        alarmMinutes: 23 * 60,
        quietHours: const QuietHours(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 7 * 60,
        ),
      );
      expect(r.map((x) => x.payload.at), [
        DateTime(2030, 1, 10, 7),
        DateTime(2030, 1, 11, 7),
        DateTime(2030, 1, 12, 7),
      ]);
    });

    test('quiet hours leave rings outside them alone', () {
      final r = autoRings(
        [lent('a', DateTime(2030, 1, 10))],
        now,
        quietHours: const QuietHours(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 7 * 60,
        ),
      );
      expect(r.first.payload.at, DateTime(2030, 1, 9, 9));
    });

    test(
      'a ring whose raw time passed but whose delayed time is ahead still rings',
      () {
        // 23:00 ring on 6 Jan, delayed to 7:00 on 7 Jan; it is now 3:00 on 7 Jan.
        final r = autoRings(
          [
            lent('a', DateTime(2030, 1, 7)),
          ], // rings 6 Jan 23:00, 7 Jan 23:00, 8 Jan 23:00
          DateTime(2030, 1, 7, 3),
          alarmMinutes: 23 * 60,
          quietHours: const QuietHours(
            enabled: true,
            startMinutes: 22 * 60,
            endMinutes: 7 * 60,
          ),
        );
        expect(r.first.payload.at, DateTime(2030, 1, 7, 7));
      },
    );

    test('manual reminders are never delayed', () {
      final reminder = Reminder(
        id: 'r',
        title: 'Call',
        at: DateTime(2030, 1, 8, 23, 30),
        createdAt: DateTime(2026, 1, 1),
      );
      final plan = planAllAlarms(
        [reminder],
        const [],
        now,
        settings: const AppSettings(
          quietHours: QuietHours(
            enabled: true,
            startMinutes: 22 * 60,
            endMinutes: 7 * 60,
          ),
        ),
      );
      expect(plan.single.at, DateTime(2030, 1, 8, 23, 30));
    });

    test('quiet hours over a daylight-saving night keep the end at 7:00', () {
      final r = autoRings(
        [lent('a', DateTime(2030, 3, 11))],
        DateTime(2030, 3, 9, 12),
        alarmMinutes: 23 * 60,
        quietHours: const QuietHours(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 7 * 60,
        ),
      );
      expect(
        r.every((x) => x.payload.at.hour == 7 && x.payload.at.minute == 0),
        isTrue,
      );
    });
  });
}
