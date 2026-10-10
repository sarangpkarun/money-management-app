import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/people/duplicates_screen.dart';
import 'package:money_manager/people/people_screen.dart';

void main() {
  late FakeFirebaseFirestore db;
  late PeopleRepository people;
  late TransactionRepository txns;

  setUp(() {
    db = FakeFirebaseFirestore();
    people = PeopleRepository(db, 'u1');
    txns = TransactionRepository(db, 'u1');
  });

  Future<void> pump(
    WidgetTester tester, {
    Widget screen = const DuplicatesScreen(),
  }) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peopleRepositoryProvider.overrideWithValue(people),
          transactionRepositoryProvider.overrideWithValue(txns),
          paymentRepositoryProvider.overrideWithValue(
            PaymentRepository(db, 'u1'),
          ),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String> addPerson(String name, {String? phone, int day = 1}) => people
      .add(Person(name: name, phone: phone, createdAt: DateTime(2026, 1, day)));

  Future<void> addEntries(
    String pid,
    String name,
    int count, {
    int rupees = 100,
  }) async {
    for (var i = 0; i < count; i++) {
      await txns.add(
        MoneyTransaction(
          type: TransactionType.lent,
          personId: pid,
          personName: name,
          title: 'Loan',
          totalAmount: Money.fromRupees(rupees),
          createdAt: DateTime(2026, 9, 1),
          date: DateTime(2026, 9, 1),
        ),
      );
    }
  }

  Future<int> peopleCount() async =>
      (await db.collection('users/u1/people').get()).docs.length;

  testWidgets('nothing to find', (tester) async {
    await addPerson('Asha');
    await addPerson('Ravi');
    await pump(tester);
    expect(find.text('No duplicates found'), findsOneWidget);
  });

  testWidgets('a group shows each person, number and entry count', (
    tester,
  ) async {
    final a = await addPerson('Ravi Kumar', phone: '+91 98765 43210');
    final b = await addPerson('R. Kumar', phone: '09876543210', day: 2);
    await addEntries(a, 'Ravi Kumar', 3);
    await addEntries(b, 'R. Kumar', 1);
    await addPerson('Someone Else', phone: '9000000001');
    await pump(tester);
    expect(find.text('2 people look the same'), findsOneWidget);
    expect(
      find.textContaining('Ravi Kumar · +91 98765 43210 · 3 entries'),
      findsOneWidget,
    );
    expect(
      find.textContaining('R. Kumar · 09876543210 · 1 entry'),
      findsOneWidget,
    );
    expect(find.textContaining('Someone Else'), findsNothing);
  });

  testWidgets('same name ignoring case is found without any phone', (
    tester,
  ) async {
    await addPerson('Ravi Kumar');
    await addPerson('ravi  kumar', day: 2);
    await pump(tester);
    expect(find.text('2 people look the same'), findsOneWidget);
  });

  testWidgets('the person with most entries is kept by default', (
    tester,
  ) async {
    final a = await addPerson('Old Name', phone: '9876543210');
    final b = await addPerson('New Name', phone: '9876543210', day: 5);
    await addEntries(a, 'Old Name', 1);
    await addEntries(b, 'New Name', 4);
    await pump(tester);
    await tester.tap(find.text('Merge…'));
    await tester.pumpAndSettle();
    final group = tester.widget<RadioGroup<Person>>(
      find.byType(RadioGroup<Person>),
    );
    expect(group.groupValue!.name, 'New Name');
    expect(
      find.textContaining("Merge 'Old Name' into 'New Name'? 1 entry moves."),
      findsOneWidget,
    );
    expect(find.textContaining('cannot be undone'), findsOneWidget);
  });

  testWidgets('with equal entries the oldest person is the default', (
    tester,
  ) async {
    final a = await addPerson('Older', phone: '9876543210', day: 1);
    final b = await addPerson('Newer', phone: '9876543210', day: 9);
    await addEntries(a, 'Older', 2);
    await addEntries(b, 'Newer', 2);
    await pump(tester);
    await tester.tap(find.text('Merge…'));
    await tester.pumpAndSettle();
    final group = tester.widget<RadioGroup<Person>>(
      find.byType(RadioGroup<Person>),
    );
    expect(group.groupValue!.name, 'Older');
  });

  testWidgets('choosing the other person changes who moves', (tester) async {
    final a = await addPerson('A', phone: '9876543210');
    final b = await addPerson('B', phone: '9876543210', day: 2);
    await addEntries(a, 'A', 3);
    await addEntries(b, 'B', 1);
    await pump(tester);
    await tester.tap(find.text('Merge…'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining("Merge 'B' into 'A'? 1 entry moves."),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(RadioListTile<Person>, 'B'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining("Merge 'A' into 'B'? 3 entries move."),
      findsOneWidget,
    );
  });

  testWidgets('Merge moves the entries, deletes the other, and says so', (
    tester,
  ) async {
    final a = await addPerson('Ravi Kumar', phone: '9876543210');
    final b = await addPerson('ravi k', phone: '+91 98765 43210', day: 2);
    await addEntries(a, 'Ravi Kumar', 2, rupees: 100);
    await addEntries(b, 'ravi k', 1, rupees: 300);
    await pump(tester);
    await tester.tap(find.text('Merge…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Merge'));
    await tester.pumpAndSettle();
    expect(await peopleCount(), 1);
    final all = (await db.collection('users/u1/transactions').get()).docs;
    expect(all.length, 3);
    expect(all.every((d) => d.data()['personId'] == a), isTrue);
    expect(all.every((d) => d.data()['personName'] == 'Ravi Kumar'), isTrue);
    expect(find.text('Merged into Ravi Kumar. 1 entry moved.'), findsOneWidget);
    expect(find.text('No duplicates found'), findsOneWidget); // refreshed
  });

  testWidgets('Cancel changes nothing', (tester) async {
    final a = await addPerson('A', phone: '9876543210');
    final b = await addPerson('B', phone: '9876543210', day: 2);
    await addEntries(b, 'B', 1);
    await pump(tester);
    await tester.tap(find.text('Merge…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await peopleCount(), 2);
    final e = (await db.collection('users/u1/transactions').get()).docs.single;
    expect(e.data()['personId'], b);
    expect(a, isNotEmpty);
    expect(find.text('2 people look the same'), findsOneWidget);
  });

  testWidgets('three people merge into one', (tester) async {
    final a = await addPerson('Sam', phone: '9876543210');
    final b = await addPerson('sam', day: 2);
    final c = await addPerson('Samuel', phone: '9876543210', day: 3);
    await addEntries(a, 'Sam', 1);
    await addEntries(b, 'sam', 1);
    await addEntries(c, 'Samuel', 1);
    await pump(tester);
    expect(find.text('3 people look the same'), findsOneWidget);
    await tester.tap(find.text('Merge…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Merge'));
    await tester.pumpAndSettle();
    expect(await peopleCount(), 1);
  });

  testWidgets('People tab menu opens Find duplicates', (tester) async {
    await addPerson('Ravi');
    await addPerson('ravi', day: 2);
    await pump(tester, screen: const PeopleScreen());
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find duplicates'));
    await tester.pumpAndSettle();
    expect(find.text('2 people look the same'), findsOneWidget);
  });
}
