import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/people/person_autocomplete_field.dart';

void main() {
  late FakeFirebaseFirestore db;
  late PeopleRepository people;
  late TransactionRepository txns;
  Person? picked;
  final created = DateTime(2026, 1, 1);

  setUp(() {
    db = FakeFirebaseFirestore();
    people = PeopleRepository(db, 'u1');
    txns = TransactionRepository(db, 'u1', now: () => created);
    picked = null;
  });

  Future<void> pumpField(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peopleRepositoryProvider.overrideWithValue(people),
          transactionRepositoryProvider.overrideWithValue(txns),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: PersonAutocompleteField(onSelected: (p) => picked = p),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> seed() async {
    final asha = await people.add(
      Person(name: 'Asha', phone: '98450', createdAt: DateTime(2026, 1, 1)),
    );
    await people.add(Person(name: 'Ashok', createdAt: DateTime(2026, 1, 2)));
    await txns.add(
      MoneyTransaction(
        type: TransactionType.lent,
        personId: asha,
        personName: 'Asha',
        title: 'Loan',
        totalAmount: Money.fromRupees(500),
        createdAt: created,
      ),
    );
  }

  testWidgets('shows recent people with phone and balance when focused', (
    tester,
  ) async {
    await seed();
    await pumpField(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Ashok'), findsOneWidget);
    expect(find.text('98450'), findsOneWidget);
    expect(find.text('₹500'), findsOneWidget);
    expect(find.textContaining('as new person'), findsNothing);
  });

  testWidgets('typing filters suggestions and offers add-new', (tester) async {
    await seed();
    await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'Asho');
    await tester.pumpAndSettle();
    expect(find.text('Ashok'), findsOneWidget);
    expect(find.text('Asha'), findsNothing);
    expect(find.text("Add 'Asho' as new person"), findsOneWidget);
  });

  testWidgets('selecting a saved person reports it', (tester) async {
    await seed();
    await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'Asha');
    await tester.pumpAndSettle();
    expect(find.textContaining('as new person'), findsNothing); // exact match
    await tester.tap(find.text('Asha').last);
    await tester.pumpAndSettle();
    expect(picked!.name, 'Asha');
    expect(picked!.id, isNotEmpty);
  });

  testWidgets('"Add new" creates the person and reports it', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'Newbie');
    await tester.pumpAndSettle();
    await tester.tap(find.text("Add 'Newbie' as new person"));
    await tester.pumpAndSettle();
    expect(picked!.name, 'Newbie');
    expect(picked!.id, isNotEmpty);
    final docs = (await db.collection('users/u1/people').get()).docs;
    expect(docs.single.data()['name'], 'Newbie');
  });
}
