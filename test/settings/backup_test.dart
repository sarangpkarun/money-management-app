import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/reminder_repository.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/data/user_repository.dart';
import 'package:money_manager/core/models/app_settings.dart';
import 'package:money_manager/core/models/app_user.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/payment.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/models/reminder.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/settings/backup.dart';

void main() {
  late FakeFirebaseFirestore db;

  UserRepository users(String uid) => UserRepository(db, uid);
  PeopleRepository people(String uid) => PeopleRepository(db, uid);
  TransactionRepository txns(String uid) => TransactionRepository(db, uid);
  PaymentRepository pays(String uid) => PaymentRepository(db, uid);
  ReminderRepository rems(String uid) => ReminderRepository(db, uid);

  setUp(() => db = FakeFirebaseFirestore());

  Future<Map<String, dynamic>> collect(String uid) => collectBackup(
    users: users(uid),
    people: people(uid),
    transactions: txns(uid),
    payments: pays(uid),
    reminders: rems(uid),
    now: DateTime.utc(2026, 10, 10, 12),
  );

  Future<String> seedEntry(
    String uid,
    String personId,
    String name,
    int rupees,
  ) => txns(uid).add(
    MoneyTransaction(
      type: TransactionType.lent,
      personId: personId,
      personName: name,
      title: 'Loan',
      totalAmount: Money.fromRupees(rupees),
      dueDate: DateTime.utc(2026, 11, 1),
      createdAt: DateTime.utc(2026, 9, 1),
      date: DateTime.utc(2026, 9, 1),
      notes: 'for the bike',
    ),
  );

  test('an empty account still exports a valid file', () async {
    final b = await collect('u1');
    expect(b['version'], 1);
    expect(b['people'], isEmpty);
    expect(b['entries'], isEmpty);
    expect(b['reminders'], isEmpty);
    expect(b['profile'], isNull);
    expect(b['exportedAt'], '2026-10-10T12:00:00.000Z');
    expect(jsonDecode(backupJson(b)), isA<Map>());
  });

  test('people, entries, payments and reminders are all included', () async {
    await users('u1').save(const AppUser(name: 'Sarang', currency: 'USD'));
    await users('u1').saveSettings(const AppSettings(theme: ThemeChoice.dark));
    final pid = await people('u1').add(
      Person(
        name: 'Asha',
        phone: '98765 43210',
        notes: 'friend',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
    final eid = await seedEntry('u1', pid, 'Asha', 1000);
    await pays('u1').add(
      eid,
      Payment(
        amount: Money.fromRupees(300),
        date: DateTime.utc(2026, 9, 5),
        mode: PaymentMode.upi,
        note: 'part',
        createdAt: DateTime.utc(2026, 9, 5),
      ),
    );
    await rems('u1').add(
      Reminder(
        title: 'Call Asha',
        at: DateTime.utc(2026, 11, 1, 9),
        repeat: const RepeatRule.weekly({1, 3}),
        createdAt: DateTime.utc(2026, 9, 1),
      ),
    );
    final b = await collect('u1');

    expect((b['profile'] as Map)['name'], 'Sarang');
    expect((b['profile'] as Map)['currency'], 'USD');
    expect(((b['profile'] as Map)['settings'] as Map)['theme'], 'dark');

    final p = (b['people'] as List).single as Map;
    expect(p['id'], pid);
    expect(p['name'], 'Asha');
    expect(p['phone'], '98765 43210');
    expect(p['createdAt'], '2026-01-01T00:00:00.000Z');

    final e = (b['entries'] as List).single as Map;
    expect(e['id'], eid);
    expect(e['personId'], pid);
    expect(e['totalAmount'], 100000); // paise, an integer
    expect(e['paidTotal'], 30000);
    expect(e['notes'], 'for the bike');
    expect(e['dueDate'], '2026-11-01T00:00:00.000Z');
    final pay = (e['payments'] as List).single as Map;
    expect(pay['amount'], 30000);
    expect(pay['mode'], 'upi');
    expect(pay['note'], 'part');
    expect(pay['date'], '2026-09-05T00:00:00.000Z');

    final r = (b['reminders'] as List).single as Map;
    expect(r['title'], 'Call Asha');
    expect(r['repeat'], {
      'kind': 'weekly',
      'weekdays': [1, 3],
    });
  });

  test('it is plain JSON: no Firestore types survive', () async {
    final pid = await people(
      'u1',
    ).add(Person(name: 'A', createdAt: DateTime.utc(2026, 1, 1)));
    await seedEntry('u1', pid, 'A', 10);
    final text = backupJson(await collect('u1'));
    expect(text, isNot(contains('Timestamp')));
    expect(jsonDecode(text), isA<Map>()); // would throw on a non-JSON value
  });

  test('another user\'s data is never included', () async {
    final mine = await people(
      'u1',
    ).add(Person(name: 'Mine', createdAt: DateTime.utc(2026, 1, 1)));
    final theirs = await people(
      'u2',
    ).add(Person(name: 'Theirs', createdAt: DateTime.utc(2026, 1, 1)));
    await seedEntry('u1', mine, 'Mine', 100);
    await seedEntry('u2', theirs, 'Theirs', 200);
    await rems('u2').add(
      Reminder(
        title: 'secret',
        at: DateTime.utc(2030),
        createdAt: DateTime.utc(2026),
      ),
    );
    final text = backupJson(await collect('u1'));
    expect(text, contains('Mine'));
    expect(text, isNot(contains('Theirs')));
    expect(text, isNot(contains('secret')));
  });

  test('an EMI keeps its whole schedule', () async {
    final pid = await people(
      'u1',
    ).add(Person(name: 'Croma', createdAt: DateTime.utc(2026, 1, 1)));
    await txns('u1').addEmi(
      personId: pid,
      personName: 'Croma',
      title: 'Phone',
      price: Money.fromRupees(12000),
      annualRatePercent: 0,
      months: 4,
      startDate: DateTime.utc(2030, 1, 15),
    );
    final e = ((await collect('u1'))['entries'] as List).single as Map;
    expect((e['schedule'] as List).length, 4);
    expect(((e['schedule'] as List).first as Map)['amount'], 300000);
    expect(((e['emiPlan'] as Map)['months']), 4);
  });

  test('many entries and payments', () async {
    final pid = await people(
      'u1',
    ).add(Person(name: 'A', createdAt: DateTime.utc(2026, 1, 1)));
    for (var i = 0; i < 60; i++) {
      final id = await seedEntry('u1', pid, 'A', 100 + i);
      await pays('u1').add(
        id,
        Payment(
          amount: Money.fromRupees(10),
          date: DateTime.utc(2026, 9, 2),
          createdAt: DateTime.utc(2026, 9, 2),
        ),
      );
    }
    final entries = (await collect('u1'))['entries'] as List;
    expect(entries.length, 60);
    expect(
      entries.every((e) => ((e as Map)['payments'] as List).length == 1),
      isTrue,
    );
  });

  test('buildBackup alone: nothing is read from storage', () {
    final b = buildBackup(
      profile: null,
      people: [Person(id: 'p', name: 'X', createdAt: DateTime.utc(2026, 1, 1))],
      entries: const [],
      reminders: const [],
      exportedAt: DateTime.utc(2026, 10, 10),
    );
    expect(((b['people'] as List).single as Map)['id'], 'p');
  });

  test('file name', () {
    expect(
      backupFileName(DateTime(2026, 10, 9)),
      'money-manager-backup-2026-10-09.json',
    );
    expect(
      backupFileName(DateTime(2027, 1, 3)),
      'money-manager-backup-2027-01-03.json',
    );
  });
}
