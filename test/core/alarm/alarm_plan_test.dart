import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/alarm/alarm_channels.dart';
import 'package:money_manager/core/alarm/alarm_plan.dart';
import 'package:money_manager/core/models/reminder.dart';

Reminder rem(
  String id,
  DateTime at, {
  RepeatRule repeat = const RepeatRule.none(),
  bool done = false,
  int snooze = 10,
  ReminderTone tone = ReminderTone.alarm,
  ReminderVibration vib = ReminderVibration.long,
  String? notes,
}) => Reminder(
  id: id,
  title: 'Title $id',
  notes: notes,
  at: at,
  repeat: repeat,
  done: done,
  snoozeMinutes: snooze,
  tone: tone,
  vibration: vib,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  final now = DateTime(2030, 1, 7, 12);

  group('payload', () {
    test('round-trips every field', () {
      final p = AlarmPayload(
        reminderId: 'abc',
        title: 'Pay "Ravi" ₹500',
        notes: 'line\nbreak',
        snoozeMinutes: 15,
        tone: ReminderTone.ringtone,
        vibration: ReminderVibration.short,
        at: DateTime(2030, 1, 8, 9, 30),
        snoozed: true,
        once: true,
      );
      final back = AlarmPayload.decode(p.encode())!;
      expect(back.reminderId, 'abc');
      expect(back.title, 'Pay "Ravi" ₹500');
      expect(back.notes, 'line\nbreak');
      expect(back.snoozeMinutes, 15);
      expect(back.tone, ReminderTone.ringtone);
      expect(back.vibration, ReminderVibration.short);
      expect(back.at, DateTime(2030, 1, 8, 9, 30));
      expect(back.snoozed, isTrue);
      expect(back.once, isTrue);
    });

    test('strangers and damage decode to null', () {
      expect(AlarmPayload.decode(null), isNull);
      expect(AlarmPayload.decode('alarm'), isNull);
      expect(AlarmPayload.decode('rem1:{not json'), isNull);
      expect(AlarmPayload.decode('rem1:[]'), isNull);
      expect(AlarmPayload.decode('rem1:{"rid":1}'), isNull);
    });

    test('odd values fall back to defaults', () {
      final p = AlarmPayload.decode(
        'rem1:{"rid":"a","t":"x","s":7,"tn":"horn","v":"zzz","at":1000}',
      )!;
      expect(p.snoozeMinutes, 10);
      expect(p.tone, ReminderTone.alarm);
      expect(p.vibration, ReminderVibration.long);
    });
  });

  group('alarm ids', () {
    test(
      'slot and key are recoverable and the id is a positive 31-bit int',
      () {
        for (final id in ['a', 'zzzzzzzz', 'KqL9x0Pq', '0']) {
          final key = reminderKey(id);
          for (var slot = 0; slot <= 31; slot++) {
            final a = alarmId(key, slot);
            expect(a > 0 || key == 0, isTrue);
            expect(a < (1 << 31), isTrue);
            expect(keyOfAlarmId(a), key);
            expect(slotOfAlarmId(a), slot);
          }
        }
      },
    );

    test('stable across calls', () {
      expect(reminderKey('abc'), reminderKey('abc'));
    });

    test('many reminders get distinct keys, even when hashes collide', () {
      final rs = [
        for (var i = 0; i < 500; i++)
          rem('id$i', now.add(Duration(days: i + 1))),
      ];
      final keys = reminderKeys(rs).values.toSet();
      expect(keys.length, 500);
      // Force every reminder onto the same hash.
      final forced = reminderKeys(rs, hash: (_) => 42).values.toSet();
      expect(forced.length, 500);
    });

    test('planned alarm ids never clash, even with forced collisions', () {
      final rs = [
        for (var i = 0; i < 20; i++)
          rem(
            'r$i',
            now.add(const Duration(hours: 1)),
            repeat: const RepeatRule.daily(),
          ),
      ];
      final plan = planAlarms(rs, now, hash: (_) => 7);
      expect(plan.map((a) => a.id).toSet().length, plan.length);
    });
  });

  group('planAlarms', () {
    test('a future one-off gets one alarm with its settings', () {
      final plan = planAlarms([
        rem(
          'a',
          DateTime(2030, 1, 8, 9),
          snooze: 15,
          tone: ReminderTone.notification,
          vib: ReminderVibration.off,
          notes: 'bring it',
        ),
      ], now);
      expect(plan.length, 1);
      final p = plan.single.payload;
      expect(plan.single.at, DateTime(2030, 1, 8, 9));
      expect(p.reminderId, 'a');
      expect(p.snoozeMinutes, 15);
      expect(p.tone, ReminderTone.notification);
      expect(p.vibration, ReminderVibration.off);
      expect(p.notes, 'bring it');
      expect(p.once, isTrue);
      expect(slotOfAlarmId(plan.single.id), 0);
    });

    test('passed one-offs and done reminders get none', () {
      expect(planAlarms([rem('a', DateTime(2030, 1, 1, 9))], now), isEmpty);
      expect(
        planAlarms([rem('a', DateTime(2030, 2, 1, 9), done: true)], now),
        isEmpty,
      );
      expect(planAlarms([rem('a', now)], now), isEmpty); // exactly now: no
    });

    test('a daily reminder gets its next 30 rings in order, slots 0..29', () {
      final plan = planAlarms([
        rem('d', DateTime(2030, 1, 1, 9), repeat: const RepeatRule.daily()),
      ], now);
      expect(plan.length, 30);
      expect(plan.first.at, DateTime(2030, 1, 8, 9));
      expect(plan.last.at, DateTime(2030, 2, 6, 9));
      expect(
        [for (final a in plan) slotOfAlarmId(a.id)],
        [for (var i = 0; i < 30; i++) i],
      );
      expect(plan.every((a) => !a.payload.once), isTrue);
    });

    test('only rings within 60 days count', () {
      final plan = planAlarms([
        rem('m', DateTime(2030, 1, 20, 9), repeat: const RepeatRule.monthly()),
      ], now);
      // 20 Jan, 20 Feb, 20 Mar (Mar 20 is 72 days out: dropped)
      expect(plan.map((a) => a.at), [
        DateTime(2030, 1, 20, 9),
        DateTime(2030, 2, 20, 9),
      ]);
    });

    test('the whole plan is the soonest 200 rings', () {
      final rs = [
        for (var i = 0; i < 10; i++)
          rem(
            'r$i',
            DateTime(2030, 1, 8, 9, i),
            repeat: const RepeatRule.daily(),
          ),
      ]; // 10 x 30 = 300 rings
      final plan = planAlarms(rs, now);
      expect(plan.length, 200);
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].at.isBefore(plan[i - 1].at), isFalse);
      }
    });

    test('weekly rings only on the chosen weekdays', () {
      final plan = planAlarms([
        rem(
          'w',
          DateTime(2030, 1, 7, 18),
          repeat: const RepeatRule.weekly({1, 3}),
        ),
      ], now);
      expect(plan.every((a) => {1, 3}.contains(a.at.weekday)), isTrue);
      expect(plan.first.at, DateTime(2030, 1, 7, 18));
    });

    test('daily keeps the wall-clock time across a daylight-saving change', () {
      final plan = planAlarms([
        rem('d', DateTime(2030, 3, 1, 9), repeat: const RepeatRule.daily()),
      ], DateTime(2030, 3, 8, 12));
      expect(plan.every((a) => a.at.hour == 9 && a.at.minute == 0), isTrue);
    });
  });

  group('snooze', () {
    final p = AlarmPayload(
      reminderId: 'abc',
      title: 't',
      snoozeMinutes: 15,
      tone: ReminderTone.ringtone,
      vibration: ReminderVibration.off,
      at: DateTime(2030, 1, 8, 9),
    );

    test('rings again after the reminder\'s own minutes, same tone', () {
      final s = snoozeAlarm(p, DateTime(2030, 1, 8, 9, 1));
      expect(s.at, DateTime(2030, 1, 8, 9, 16));
      expect(s.payload.tone, ReminderTone.ringtone);
      expect(s.payload.vibration, ReminderVibration.off);
      expect(s.payload.snoozed, isTrue);
      expect(slotOfAlarmId(s.id), snoozeSlot);
      expect(keyOfAlarmId(s.id), reminderKey('abc'));
    });

    test('5 and 10 minute snoozes', () {
      for (final m in [5, 10]) {
        final q = AlarmPayload(
          reminderId: 'x',
          title: 't',
          snoozeMinutes: m,
          tone: ReminderTone.alarm,
          vibration: ReminderVibration.long,
          at: DateTime(2030),
        );
        expect(
          snoozeAlarm(q, DateTime(2030, 1, 1, 8)).at,
          DateTime(2030, 1, 1, 8, m),
        );
      }
    });
  });

  group('channels', () {
    test('one distinct channel per tone and vibration', () {
      final all = allAlarmChannels();
      expect(all.length, 9);
      expect(all.map((c) => c.id).toSet().length, 9);
      expect(all.map((c) => c.name).toSet().length, 9);
    });

    test('mapping', () {
      final c = alarmChannelFor(ReminderTone.ringtone, ReminderVibration.off);
      expect(c.id, 'alarm_ringtone_off_v1');
      expect(c.soundUri, 'content://settings/system/ringtone');
      expect(c.vibrates, isFalse);
      final s = alarmChannelFor(ReminderTone.alarm, ReminderVibration.short);
      expect(s.soundUri, 'content://settings/system/alarm_alert');
      expect(s.vibrationPattern, [0, 300, 200, 300]);
      final l = alarmChannelFor(
        ReminderTone.notification,
        ReminderVibration.long,
      );
      expect(l.vibrationPattern!.length > s.vibrationPattern!.length, isTrue);
      expect(l.soundUri, 'content://settings/system/notification_sound');
    });
  });
}
