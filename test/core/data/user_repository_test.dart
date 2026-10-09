import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/user_repository.dart';
import 'package:money_manager/core/models/app_user.dart';

void main() {
  late FakeFirebaseFirestore db;
  late UserRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = UserRepository(db, 'u1');
  });

  test('save then get round-trips the profile', () async {
    await repo.save(
      const AppUser(name: 'Sarang', currency: 'USD', timezone: 'UTC'),
    );
    final user = (await repo.get())!;
    expect(user.name, 'Sarang');
    expect(user.currency, 'USD');
    expect(user.timezone, 'UTC');
  });

  test(
    'ensureProfile creates a default profile once and never overwrites',
    () async {
      await repo.ensureProfile('Sarang');
      expect((await repo.get())!.name, 'Sarang');
      expect((await repo.get())!.currency, 'INR');

      await repo.save(const AppUser(name: 'Changed', currency: 'USD'));
      await repo.ensureProfile('Sarang');
      expect((await repo.get())!.name, 'Changed');
      expect((await repo.get())!.currency, 'USD');
    },
  );

  test('watch emits profile updates', () async {
    await repo.save(const AppUser(name: 'A'));
    final first = await repo.watch().first;
    expect(first!.name, 'A');
  });

  test(
    'deleteAllData removes everything under the user, not other users',
    () async {
      final u1 = db.collection('users').doc('u1');
      await u1.set({'name': 'A'});
      await u1.collection('people').doc('p1').set({'name': 'Asha'});
      final t = await u1.collection('transactions').add({'title': 'Loan'});
      await t.collection('payments').add({'amount': 100});
      await t.collection('payments').add({'amount': 200});
      await u1.collection('reminders').add({'title': 'Pay'});

      final u2 = db.collection('users').doc('u2');
      await u2.set({'name': 'B'});
      await u2.collection('people').doc('p9').set({'name': 'Other'});

      await repo.deleteAllData();

      expect((await u1.get()).exists, isFalse);
      expect((await u1.collection('people').get()).docs, isEmpty);
      expect((await u1.collection('transactions').get()).docs, isEmpty);
      expect((await t.collection('payments').get()).docs, isEmpty);
      expect((await u1.collection('reminders').get()).docs, isEmpty);
      expect((await u2.get()).exists, isTrue);
      expect((await u2.collection('people').get()).docs, hasLength(1));
    },
  );

  test('deleteAllData handles more than one batch of documents', () async {
    final people = db.collection('users').doc('u1').collection('people');
    for (var i = 0; i < 450; i++) {
      await people.add({'name': 'P$i'});
    }
    await repo.deleteAllData();
    expect((await people.get()).docs, isEmpty);
  });
}
