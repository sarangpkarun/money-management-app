import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/reminder.dart';

void main() {
  final created = DateTime(2026, 1, 1);

  test('defaults', () {
    final r = Reminder(
      title: 'x',
      at: DateTime(2030, 1, 7, 9),
      createdAt: created,
    );
    expect(r.snoozeMinutes, 10);
    expect(r.tone, ReminderTone.alarm);
    expect(r.vibration, ReminderVibration.long);
    expect(r.repeat.kind, RepeatKind.none);
    expect(r.done, isFalse);
  });

  test('every field round-trips', () {
    final r = Reminder(
      title: 'Pay rent',
      notes: 'to Ravi',
      at: DateTime(2030, 1, 7, 9, 30),
      repeat: const RepeatRule.weekly({5, 1, 3}),
      snoozeMinutes: 15,
      tone: ReminderTone.ringtone,
      vibration: ReminderVibration.short,
      transactionId: 't1',
      done: true,
      doneAt: DateTime(2030, 1, 8),
      createdAt: created,
    );
    final back = Reminder.fromMap('id1', r.toMap());
    expect(back.id, 'id1');
    expect(back.title, 'Pay rent');
    expect(back.notes, 'to Ravi');
    expect(back.at, DateTime(2030, 1, 7, 9, 30));
    expect(back.repeat, const RepeatRule.weekly({1, 3, 5}));
    expect(back.snoozeMinutes, 15);
    expect(back.tone, ReminderTone.ringtone);
    expect(back.vibration, ReminderVibration.short);
    expect(back.transactionId, 't1');
    expect(back.done, isTrue);
    expect(back.doneAt, DateTime(2030, 1, 8));
  });

  test('each repeat rule round-trips', () {
    for (final rule in const [
      RepeatRule.none(),
      RepeatRule.daily(),
      RepeatRule.monthly(),
      RepeatRule.yearly(),
      RepeatRule.weekly({2, 4}),
      RepeatRule.everyNDays(10),
    ]) {
      expect(RepeatRule.fromMap(rule.toMap()), rule, reason: '${rule.kind}');
    }
  });

  test('unknown or damaged data falls back safely', () {
    expect(RepeatRule.fromMap(null).kind, RepeatKind.none);
    expect(RepeatRule.fromMap({'kind': 'lunar'}).kind, RepeatKind.none);
    expect(
      RepeatRule.fromMap({'kind': 'everyNDays', 'interval': -4}).interval,
      1,
    );
    expect(
      RepeatRule.fromMap({
        'kind': 'weekly',
        'weekdays': [0, 3, 9, 'x'],
      }).weekdays,
      {3},
    );
    final m =
        Reminder(title: 'x', at: DateTime(2030), createdAt: created).toMap()
          ..['tone'] = 'trumpet'
          ..['snoozeMinutes'] = 7
          ..remove('repeat');
    final r = Reminder.fromMap('i', m);
    expect(r.tone, ReminderTone.alarm);
    expect(r.snoozeMinutes, 10);
    expect(r.repeat.kind, RepeatKind.none);
  });

  test('copyWith can clear the link and the done time', () {
    final r = Reminder(
      title: 'x',
      at: DateTime(2030),
      transactionId: 't',
      done: true,
      doneAt: DateTime(2030, 1, 2),
      createdAt: created,
    );
    final c = r.copyWith(
      clearTransaction: true,
      done: false,
      clearDoneAt: true,
    );
    expect(c.transactionId, isNull);
    expect(c.doneAt, isNull);
    expect(c.done, isFalse);
    expect(r.toMap()['at'], isA<Timestamp>());
  });

  test('an old document that still has a volume field loads fine', () {
    final m = Reminder(
      title: 'x',
      at: DateTime(2030),
      createdAt: created,
    ).toMap()..['volume'] = 'low';
    final r = Reminder.fromMap('i', m);
    expect(r.title, 'x');
    expect(r.toMap().containsKey('volume'), isFalse);
  });
}
