import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/alarm/alarm_plan.dart';
import 'package:money_manager/core/alarm/alarm_screen.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/reminder_repository.dart';
import 'package:money_manager/core/models/reminder.dart';
import 'package:money_manager/reminders/alarm_providers.dart';

import '../support/fake_alarm_gateway.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ReminderRepository repo;
  late FakeAlarmGateway gateway;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = ReminderRepository(db, 'u1');
    gateway = FakeAlarmGateway();
  });

  Future<bool> isDone(String id) async =>
      (await db.collection('users/u1/reminders').doc(id).get()).data()!['done']
          as bool;

  Future<(String, AlarmPayload)> seed({
    RepeatRule repeat = const RepeatRule.none(),
    int snooze = 15,
    String? notes,
  }) async {
    final r = Reminder(
      title: 'Pay Ravi',
      notes: notes,
      at: DateTime(2030, 1, 8, 9),
      repeat: repeat,
      snoozeMinutes: snooze,
      tone: ReminderTone.ringtone,
      vibration: ReminderVibration.short,
      createdAt: DateTime(2026, 1, 1),
    );
    final id = await repo.add(r);
    final payload = AlarmPayload(
      reminderId: id,
      title: r.title,
      notes: notes,
      snoozeMinutes: snooze,
      tone: r.tone,
      vibration: r.vibration,
      at: r.at,
      once: !repeat.repeats,
    );
    return (id, payload);
  }

  Future<void> pump(WidgetTester tester, AlarmPayload p, {int id = 77}) async {
    // Ringing for this id, as the system would have it.
    gateway.foreign[id] = p.encode();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alarmGatewayProvider.overrideWithValue(gateway),
          reminderRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AlarmScreen(id: id, payload: p),
                  ),
                ),
                child: const Text('ring'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ring'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the title, the note and the reminder\'s snooze time', (
    tester,
  ) async {
    final (_, p) = await seed(notes: 'bring cash');
    await pump(tester, p);
    expect(find.text('Pay Ravi'), findsOneWidget);
    expect(find.text('bring cash'), findsOneWidget);
    expect(find.text('Snooze 15 min'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
  });

  testWidgets('snooze rings again after the reminder\'s minutes', (
    tester,
  ) async {
    final (id, p) = await seed(snooze: 15);
    await pump(tester, p);
    final before = DateTime.now();
    await tester.tap(find.text('Snooze 15 min'));
    await tester.pumpAndSettle();
    expect(gateway.foreign.containsKey(77), isFalse); // this ring is stopped
    final s = gateway.scheduled.values.single;
    expect(slotOfAlarmId(s.id), snoozeSlot);
    expect(s.payload.reminderId, id);
    expect(s.payload.snoozed, isTrue);
    expect(s.payload.tone, ReminderTone.ringtone);
    final mins = s.at.difference(before).inSeconds / 60;
    expect(mins, closeTo(15, 0.2));
    expect(find.text('ring'), findsOneWidget); // screen closed
    // A snooze does not finish the reminder.
    expect((await isDone(id)), isFalse);
  });

  testWidgets('dismissing a one-off finishes it', (tester) async {
    final (id, p) = await seed();
    await pump(tester, p);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(gateway.foreign.containsKey(77), isFalse);
    expect((await isDone(id)), isTrue);
    expect(find.text('ring'), findsOneWidget);
  });

  testWidgets('dismissing a repeating reminder leaves it active', (
    tester,
  ) async {
    final (id, p) = await seed(repeat: const RepeatRule.daily());
    await pump(tester, p);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect((await isDone(id)), isFalse);
  });

  testWidgets('dismissing when the reminder is gone does not crash', (
    tester,
  ) async {
    final (id, p) = await seed();
    await repo.delete(id);
    await pump(tester, p);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ring'), findsOneWidget);
  });

  testWidgets('a snoozed ring says so', (tester) async {
    final (_, p) = await seed();
    await pump(tester, p.copyWith(snoozed: true));
    expect(find.text('Snoozed'), findsOneWidget);
  });
}
