import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/trip_repository.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/models/trip.dart';
import 'package:money_manager/core/models/trip_expense.dart';
import 'package:money_manager/trips/trip_detail_screen.dart';

void main() {
  late FakeFirebaseFirestore db;
  late String tripId;

  setUp(() async {
    db = FakeFirebaseFirestore();
    tripId = await TripRepository(db, 'alice', 'alice@x.com').create(
      name: 'Goa',
      ownerName: 'Alice',
      invited: const [
        TripMember(email: 'bob@x.com', name: 'Bob', role: TripRole.editor),
      ],
    );
    await TripRepository(db, 'bob', 'bob@x.com').claimInvites();
  });

  Future<List<TripExpense>> expenses(WidgetTester tester) async =>
      (await tester.runAsync(
        () =>
            TripRepository(db, 'bob', 'bob@x.com').watchExpenses(tripId).first,
      ))!;

  Future<void> pump(WidgetTester tester, String uid, String email) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(db),
          uidProvider.overrideWithValue(uid),
          emailProvider.overrideWithValue(email),
        ],
        child: MaterialApp(home: TripDetailScreen(tripId: tripId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an editor adds an expense split equally and sees balances', (
    tester,
  ) async {
    await pump(tester, 'bob', 'bob@x.com');
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'What'), 'Hotel');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '1000',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = (await expenses(tester)).single;
    expect(saved.paidBy, 'bob@x.com');
    expect(saved.shares, {'alice@x.com': 50000, 'bob@x.com': 50000});

    await tester.tap(find.text('Balances'));
    await tester.pumpAndSettle();
    expect(find.text('Alice pays You'), findsOneWidget);
    expect(find.text('₹500'), findsWidgets);
  });

  testWidgets('an exact split that does not add up cannot be saved', (
    tester,
  ) async {
    await pump(tester, 'bob', 'bob@x.com');
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'What'), 'Fuel');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '1000',
    );
    await tester.tap(find.text('Exact'));
    await tester.pumpAndSettle();
    expect(find.text('₹1,000 left to assign'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(await expenses(tester), isEmpty);
  });

  testWidgets('a viewer sees the trip but no add buttons', (tester) async {
    final alice = TripRepository(db, 'alice', 'alice@x.com');
    final current = (await tester.runAsync(
      () => alice.watchTrip(tripId).first,
    ))!;
    await tester.runAsync(
      () => alice.saveMembers(
        current.copyWith(
          members: [
            TripMember(
              email: 'alice@x.com',
              name: 'Alice',
              role: TripRole.owner,
              uid: 'alice',
            ),
            TripMember(
              email: 'bob@x.com',
              name: 'Bob',
              role: TripRole.viewer,
              uid: 'bob',
            ),
          ],
        ),
      ),
    );
    await pump(tester, 'bob', 'bob@x.com');
    expect(
      find.text('You can view this trip but not change it.'),
      findsOneWidget,
    );
    expect(find.text('Add stop'), findsNothing);
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    expect(find.text('Add expense'), findsNothing);
  });

  testWidgets('the owner can add only people who have an email', (
    tester,
  ) async {
    final people = PeopleRepository(db, 'alice');
    await tester.runAsync(() async {
      await people.add(
        Person(
          name: 'Dina',
          email: 'dina@x.com',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      await people.add(Person(name: 'Evan', createdAt: DateTime(2026, 1, 1)));
    });
    await pump(tester, 'alice', 'alice@x.com');
    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add people'));
    await tester.pumpAndSettle();

    expect(find.text('No email'), findsOneWidget);
    expect(find.text('Add email'), findsOneWidget);
    await tester.tap(find.text('Dina'));
    await tester.pumpAndSettle();

    final trip = (await tester.runAsync(
      () => TripRepository(db, 'alice', 'alice@x.com').watchTrip(tripId).first,
    ))!;
    final dina = trip.memberByEmail('dina@x.com')!;
    expect(dina.pending, isTrue);
    expect(dina.role, TripRole.editor);
    expect(trip.memberByEmail('evan@x.com'), isNull);
  });
}
