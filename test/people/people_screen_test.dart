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
import 'package:money_manager/people/people_screen.dart';

void main() {
  late FakeFirebaseFirestore db;
  late PeopleRepository people;
  late TransactionRepository txns;
  // A fixed "now" far in the past of the real clock so the due date below is
  // overdue when the screen computes it with DateTime.now().
  final created = DateTime(2024, 1, 1);

  setUp(() {
    db = FakeFirebaseFirestore();
    people = PeopleRepository(db, 'u1');
    txns = TransactionRepository(db, 'u1', now: () => created);
  });

  Future<String> addPerson(String name, {String? phone}) =>
      people.add(Person(name: name, phone: phone, createdAt: created));

  Future<void> addTxn(
    String personId,
    TransactionType type,
    int rupees, {
    DateTime? due,
  }) async {
    await txns.add(
      MoneyTransaction(
        type: type,
        personId: personId,
        personName: '',
        title: 't',
        totalAmount: Money.fromRupees(rupees),
        dueDate: due,
        createdAt: created,
      ),
    );
  }

  Future<void> pumpPeople(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peopleRepositoryProvider.overrideWithValue(people),
          transactionRepositoryProvider.overrideWithValue(txns),
        ],
        child: const MaterialApp(home: PeopleScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> seed() async {
    final asha = await addPerson('Asha', phone: '98450');
    final ravi = await addPerson('Ravi');
    await addPerson('Meera');
    await addTxn(asha, TransactionType.lent, 1000);
    await addTxn(
      ravi,
      TransactionType.borrowed,
      300,
      due: DateTime(2024, 2, 1),
    );
  }

  testWidgets('empty state offers to add a person', (tester) async {
    await pumpPeople(tester);
    expect(find.text('No people yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add person'));
    await tester.pumpAndSettle();
    expect(find.text('Add person'), findsWidgets);
    expect(find.byType(TextFormField), findsNWidgets(4));
  });

  testWidgets('shows people with net amounts and overdue marker', (
    tester,
  ) async {
    await seed();
    await pumpPeople(tester);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('₹1,000'), findsOneWidget);
    expect(find.text('Owes you'), findsOneWidget);
    expect(find.text('₹300'), findsOneWidget);
    expect(find.text('You owe'), findsOneWidget);
    expect(find.text('Overdue'), findsWidgets);
    expect(
      find.text('Settled'),
      findsWidgets,
    ); // Meera row (and the filter chip)
  });

  testWidgets('search narrows the list by name or phone', (tester) async {
    await seed();
    await pumpPeople(tester);
    await tester.enterText(find.byType(TextField).first, 'rav');
    await tester.pumpAndSettle();
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Asha'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '9845');
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Ravi'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching people'), findsOneWidget);
  });

  testWidgets('filter chips work', (tester) async {
    await seed();
    await pumpPeople(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'They owe'));
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Ravi'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'I owe'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Asha'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Overdue'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi'), findsOneWidget);
  });

  testWidgets('adding a person saves it and shows it in the list', (
    tester,
  ) async {
    await pumpPeople(tester);
    await tester.tap(find.byTooltip('Add person'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    expect(find.text('Enter a name'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Kiran');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone (optional)'),
      '99999',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Kiran'), findsOneWidget);
    final docs = (await db.collection('users/u1/people').get()).docs;
    expect(docs.single.data()['phone'], '99999');
  });

  testWidgets('editing a person renames them', (tester) async {
    await addPerson('Meera');
    await pumpPeople(tester);
    await tester.tap(find.text('Meera'));
    await tester.pumpAndSettle();
    // A row opens the person's ledger; editing is behind the Edit icon.
    await tester.tap(find.byTooltip('Edit person'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Meera K',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    // Back on the ledger, which shows the new name in its title and header.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Meera K')),
      findsOneWidget,
    );
    expect(find.text('Meera'), findsNothing);
  });

  testWidgets('a person with no entries can be deleted after confirming', (
    tester,
  ) async {
    await addPerson('Meera');
    await pumpPeople(tester);
    await tester.tap(find.text('Meera'));
    await tester.pumpAndSettle();
    // A row opens the person's ledger; editing is behind the Edit icon.
    await tester.tap(find.byTooltip('Edit person'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete person'));
    await tester.tap(find.text('Delete person'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Meera?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Meera'), findsNothing);
    expect((await db.collection('users/u1/people').get()).docs, isEmpty);
  });

  testWidgets('a person with entries cannot be deleted', (tester) async {
    await seed();
    await pumpPeople(tester);
    await tester.tap(find.text('Asha'));
    await tester.pumpAndSettle();
    // A row opens the person's ledger; editing is behind the Edit icon.
    await tester.tap(find.byTooltip('Edit person'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete person'));
    await tester.tap(find.text('Delete person'));
    await tester.pumpAndSettle();
    expect(find.text("Can't delete yet"), findsOneWidget);
    expect(find.textContaining('has 1 entry'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect((await db.collection('users/u1/people').get()).docs.length, 3);
  });
}
