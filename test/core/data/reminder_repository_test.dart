import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/reminder_repository.dart';
import 'package:money_manager/core/data/user_repository.dart';
import 'package:money_manager/core/models/reminder.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ReminderRepository repo;

  Reminder rem(String title, DateTime at, {RepeatRule? repeat}) => Reminder(
    title: title,
    at: at,
    repeat: repeat ?? const RepeatRule.none(),
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = ReminderRepository(db, 'u1');
  });

  test('add then read back, earliest ring first', () async {
    await repo.add(rem('later', DateTime(2030, 5, 1, 9)));
    await repo.add(rem('sooner', DateTime(2030, 1, 1, 9)));
    final list = await repo.watch().first;
    expect(list.map((r) => r.title), ['sooner', 'later']);
    expect(list.first.id, isNotEmpty);
  });

  test('stored under the user and nowhere else', () async {
    await repo.add(rem('x', DateTime(2030)));
    expect((await db.collection('users/u1/reminders').get()).docs.length, 1);
    expect((await db.collection('users/u2/reminders').get()).docs, isEmpty);
  });

  test('update changes the fields', () async {
    final id = await repo.add(rem('old', DateTime(2030, 1, 1, 9)));
    final r = (await repo.watch().first).single;
    await repo.update(
      r.copyWith(
        title: 'new',
        repeat: const RepeatRule.daily(),
        snoozeMinutes: 5,
        tone: ReminderTone.notification,
      ),
    );
    final back = (await repo.watchOne(id).first)!;
    expect(back.title, 'new');
    expect(back.repeat.kind, RepeatKind.daily);
    expect(back.snoozeMinutes, 5);
    expect(back.tone, ReminderTone.notification);
  });

  test('delete removes it; watchOne then gives null', () async {
    final id = await repo.add(rem('x', DateTime(2030)));
    await repo.delete(id);
    expect(await repo.watchOne(id).first, isNull);
    expect(await repo.watch().first, isEmpty);
  });

  test('markDone and reopen', () async {
    final id = await repo.add(rem('x', DateTime(2030)));
    await repo.markDone(id, at: DateTime(2030, 1, 2));
    var r = (await repo.watchOne(id).first)!;
    expect(r.done, isTrue);
    expect(r.doneAt, DateTime(2030, 1, 2));
    await repo.reopen(id);
    r = (await repo.watchOne(id).first)!;
    expect(r.done, isFalse);
    expect(r.doneAt, isNull);
  });

  test('deleting the account wipes reminders too', () async {
    await repo.add(rem('x', DateTime(2030)));
    await UserRepository(db, 'u1').deleteAllData();
    expect((await db.collection('users/u1/reminders').get()).docs, isEmpty);
  });

  test('the stored time is a Timestamp', () async {
    await repo.add(rem('x', DateTime(2030, 1, 7, 9, 30)));
    final doc = (await db.collection('users/u1/reminders').get()).docs.single;
    expect(doc.data()['at'], isA<Timestamp>());
  });
}
