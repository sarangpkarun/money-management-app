import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/trip_repository.dart';
import 'package:money_manager/core/models/trip.dart';
import 'package:money_manager/core/models/trip_expense.dart';
import 'package:money_manager/core/models/trip_stop.dart';
import 'package:money_manager/core/money/money.dart';

void main() {
  late FakeFirebaseFirestore db;
  late TripRepository alice;

  setUp(() {
    db = FakeFirebaseFirestore();
    alice = TripRepository(db, 'alice', 'Alice@X.com');
  });

  Future<String> makeTrip() => alice.create(
    name: 'Goa',
    ownerName: 'Alice',
    invited: const [
      TripMember(email: 'bob@x.com', name: 'Bob', role: TripRole.editor),
      TripMember(email: 'carol@x.com', name: 'Carol', role: TripRole.viewer),
    ],
  );

  test('create makes the signed-in person the owner and lists invitees', () async {
    final id = await makeTrip();
    final trip = (await alice.watchTrip(id).first)!;
    expect(trip.ownerUid, 'alice');
    expect(trip.members.map((m) => m.email), contains('alice@x.com'));
    expect(trip.memberByEmail('bob@x.com')!.pending, isTrue);
    expect(trip.memberByUid('alice')!.role, TripRole.owner);
    final raw = (await db.collection('trips').doc(id).get()).data()!;
    expect(raw['memberUids'], ['alice']);
    expect(raw['editorUids'], ['alice']);
    expect(raw['memberEmails'], hasLength(3));
  });

  test('an invited person sees the trip and claiming records their uid', () async {
    final id = await makeTrip();
    final bob = TripRepository(db, 'bob', 'bob@x.com');
    final seen = await bob.watchMyTrips().first;
    expect(seen.single.id, id);

    expect(await bob.claimInvites(), 1);
    expect(await bob.claimInvites(), 0);

    final raw = (await db.collection('trips').doc(id).get()).data()!;
    expect(raw['memberUids'], containsAll(['alice', 'bob']));
    expect(raw['editorUids'], containsAll(['alice', 'bob']));
    final trip = Trip.fromMap(id, raw);
    expect(trip.memberByUid('bob')!.role, TripRole.editor);
  });

  test('a viewer who accepts is not added to editorUids', () async {
    final id = await makeTrip();
    await TripRepository(db, 'carol', 'carol@x.com').claimInvites();
    final raw = (await db.collection('trips').doc(id).get()).data()!;
    expect(raw['memberUids'], contains('carol'));
    expect(raw['editorUids'], isNot(contains('carol')));
  });

  test('strangers do not see the trip', () async {
    await makeTrip();
    final erin = TripRepository(db, 'erin', 'erin@x.com');
    expect(await erin.watchMyTrips().first, isEmpty);
  });

  test('owner can change a role and remove someone', () async {
    final id = await makeTrip();
    var trip = (await alice.watchTrip(id).first)!;
    await alice.saveMembers(
      trip.copyWith(
        members: [
          for (final m in trip.members)
            if (m.email != 'carol@x.com')
              m.email == 'bob@x.com'
                  ? TripMember(email: m.email, name: m.name, role: TripRole.viewer)
                  : m,
        ],
      ),
    );
    trip = (await alice.watchTrip(id).first)!;
    expect(trip.memberByEmail('carol@x.com'), isNull);
    expect(trip.memberByEmail('bob@x.com')!.role, TripRole.viewer);
    expect(await TripRepository(db, 'carol', 'carol@x.com').watchMyTrips().first, isEmpty);
  });

  test('stops and expenses round-trip and an expense split can be edited', () async {
    final id = await makeTrip();
    await alice.addStop(
      id,
      TripStop(title: 'Hotel', type: StopType.stay, createdAt: DateTime(2026, 1, 1)),
    );
    expect((await alice.watchStops(id).first).single.type, StopType.stay);

    await alice.addExpense(
      id,
      TripExpense(
        title: 'Dinner',
        amount: Money.fromRupees(300),
        paidBy: 'alice@x.com',
        date: DateTime(2026, 10, 2),
        shares: const {'alice@x.com': 15000, 'bob@x.com': 15000},
        createdAt: DateTime(2026, 10, 2),
      ),
    );
    final saved = (await alice.watchExpenses(id).first).single;
    expect(saved.mode, SplitMode.equal);

    await alice.updateExpense(
      id,
      TripExpense(
        id: saved.id,
        title: 'Dinner',
        amount: saved.amount,
        paidBy: saved.paidBy,
        date: saved.date,
        mode: SplitMode.percent,
        shares: const {'alice@x.com': 9000, 'bob@x.com': 21000},
        percentBp: const {'alice@x.com': 3000, 'bob@x.com': 7000},
        createdAt: saved.createdAt,
      ),
    );
    final edited = (await alice.watchExpenses(id).first).single;
    expect(edited.mode, SplitMode.percent);
    expect(edited.shares['bob@x.com'], 21000);
    expect(edited.percentBp!['alice@x.com'], 3000);
  });

  test('deleting a trip removes its stops and expenses', () async {
    final id = await makeTrip();
    await alice.addStop(id, TripStop(title: 'A', createdAt: DateTime(2026, 1, 1)));
    await alice.delete(id);
    expect((await db.collection('trips').get()).docs, isEmpty);
    expect((await db.collection('trips/$id/stops').get()).docs, isEmpty);
  });
}
