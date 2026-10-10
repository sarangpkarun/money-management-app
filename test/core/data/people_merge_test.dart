import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/interest/interest.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/payment.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/people/person_summary.dart';

void main() {
  late FakeFirebaseFirestore db;
  late PeopleRepository people;
  late TransactionRepository txns;

  setUp(() {
    db = FakeFirebaseFirestore();
    people = PeopleRepository(db, 'u1');
    txns = TransactionRepository(db, 'u1');
  });

  Future<String> addPerson(
    String name, {
    String? phone,
    String? notes,
    String? photo,
  }) => people.add(
    Person(
      name: name,
      phone: phone,
      notes: notes,
      photoUrl: photo,
      createdAt: DateTime(2026, 1, 1),
    ),
  );

  Future<String> addEntry(
    String personId,
    String name,
    int rupees, {
    TransactionType type = TransactionType.lent,
  }) => txns.add(
    MoneyTransaction(
      type: type,
      personId: personId,
      personName: name,
      title: 'Loan',
      totalAmount: Money.fromRupees(rupees),
      createdAt: DateTime(2026, 9, 1),
      date: DateTime(2026, 9, 1),
    ),
  );

  Future<Map<String, dynamic>?> personDoc(String id) async =>
      (await db.collection('users/u1/people').doc(id).get()).data();

  Future<List<Map<String, dynamic>>> entries() async => [
    for (final d in (await db.collection('users/u1/transactions').get()).docs)
      d.data(),
  ];

  test('entries move to the kept person and carry its name', () async {
    final keep = await addPerson('Ravi Kumar');
    final dup = await addPerson('ravi k');
    await addEntry(keep, 'Ravi Kumar', 100);
    await addEntry(dup, 'ravi k', 200);
    await addEntry(dup, 'ravi k', 300);
    final moved = await people.merge(keep, [dup]);
    expect(moved, 2);
    final all = await entries();
    expect(all.every((e) => e['personId'] == keep), isTrue);
    expect(all.every((e) => e['personName'] == 'Ravi Kumar'), isTrue);
    expect(await personDoc(dup), isNull);
    expect(await personDoc(keep), isNotNull);
  });

  test('a missing phone and photo are filled in, existing ones kept', () async {
    final keep = await addPerson('A');
    final dup = await addPerson('a', phone: '9876543210', photo: 'p.png');
    await people.merge(keep, [dup]);
    final d = (await personDoc(keep))!;
    expect(d['phone'], '9876543210');
    expect(d['photoUrl'], 'p.png');

    final keep2 = await addPerson('B', phone: '1111111111');
    final dup2 = await addPerson('b', phone: '2222222222');
    await people.merge(keep2, [dup2]);
    expect((await personDoc(keep2))!['phone'], '1111111111');
  });

  test('notes are combined, never lost, never duplicated', () async {
    final keep = await addPerson('A', notes: 'works at X');
    final d1 = await addPerson('a', notes: 'owes for rent');
    final d2 = await addPerson('A.', notes: 'works at X');
    await people.merge(keep, [d1, d2]);
    expect((await personDoc(keep))!['notes'], 'works at X\nowes for rent');
  });

  test('no notes anywhere stays null', () async {
    final keep = await addPerson('A');
    final dup = await addPerson('a');
    await people.merge(keep, [dup]);
    expect((await personDoc(keep))!['notes'], isNull);
  });

  test('several people can be merged at once', () async {
    final keep = await addPerson('A');
    final d1 = await addPerson('a');
    final d2 = await addPerson('A ');
    await addEntry(d1, 'a', 10);
    await addEntry(d2, 'A ', 20);
    expect(await people.merge(keep, [d1, d2]), 2);
    expect((await db.collection('users/u1/people').get()).docs.length, 1);
  });

  test('other people and their entries are untouched', () async {
    final keep = await addPerson('A');
    final dup = await addPerson('a');
    final other = await addPerson('Zed');
    await addEntry(other, 'Zed', 500);
    await people.merge(keep, [dup]);
    expect(await personDoc(other), isNotNull);
    final z = (await entries()).single;
    expect(z['personId'], other);
    expect(z['personName'], 'Zed');
  });

  test('payments and totals follow the entries', () async {
    final keep = await addPerson('A');
    final dup = await addPerson('a');
    final e1 = await addEntry(keep, 'A', 1000);
    final e2 = await addEntry(dup, 'a', 500);
    final payments = PaymentRepository(db, 'u1');
    await payments.add(
      e2,
      Payment(
        amount: Money.fromRupees(200),
        date: DateTime(2026, 9, 2),
        createdAt: DateTime(2026, 9, 2),
      ),
    );
    final before = await txns.watch().first;
    final netBefore = before.fold(Money.zero, (sum, t) {
      return sum + outstanding(t, DateTime(2026, 10, 1));
    });
    await people.merge(keep, [dup]);
    expect(
      (await db.collection('users/u1/transactions/$e2/payments').get())
          .docs
          .length,
      1,
    );
    expect(e1, isNotEmpty);
    final after = await txns.watch().first;
    final summary = summarize(
      await people.watch().first,
      after,
      now: DateTime(2026, 10, 1),
    );
    expect(summary.length, 1);
    expect(summary.single.net, netBefore);
    expect(summary.single.net, Money.fromRupees(1300));
  });

  test('more than 400 entries are moved in several batches', () async {
    final keep = await addPerson('A');
    final dup = await addPerson('a');
    for (var i = 0; i < 450; i++) {
      await addEntry(dup, 'a', 1);
    }
    expect(await people.merge(keep, [dup]), 450);
    final all = await entries();
    expect(all.length, 450);
    expect(all.every((e) => e['personId'] == keep), isTrue);
  });

  test(
    'merging into itself, nothing, or a missing person is an error',
    () async {
      final a = await addPerson('A');
      final b = await addPerson('B');
      expect(() => people.merge(a, [a]), throwsA(isA<PeopleMergeException>()));
      expect(() => people.merge(a, []), throwsA(isA<PeopleMergeException>()));
      expect(
        () => people.merge('nope', [b]),
        throwsA(isA<PeopleMergeException>()),
      );
      expect(await personDoc(b), isNotNull); // nothing was changed
    },
  );

  test('running it again after an interruption is harmless', () async {
    final keep = await addPerson('A');
    final dup = await addPerson('a');
    await addEntry(dup, 'a', 10);
    await people.merge(keep, [dup]);
    // The removed person is already gone: a repeat does not fail or change data.
    expect(await people.merge(keep, [dup]), 0);
    expect((await entries()).single['personId'], keep);
  });

  test(
    'an interrupted merge leaves no entry pointing at a deleted person',
    () async {
      // Simulate: entries moved but people not yet deleted.
      final keep = await addPerson('A');
      final dup = await addPerson('a');
      await addEntry(dup, 'a', 10);
      final entry =
          (await db.collection('users/u1/transactions').get()).docs.single;
      await entry.reference.update({'personId': keep, 'personName': 'A'});
      // Both people still exist; finishing the merge removes the duplicate.
      expect(await people.merge(keep, [dup]), 0);
      expect(await personDoc(dup), isNull);
      expect((await entries()).single['personId'], keep);
    },
  );
}
