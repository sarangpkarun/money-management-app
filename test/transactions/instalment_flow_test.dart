import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/transactions/add_instalment_screen.dart';
import 'package:money_manager/transactions/entry_detail_screen.dart';

void main() {
  late FakeFirebaseFirestore db;
  late PeopleRepository people;
  late TransactionRepository txns;
  late PaymentRepository payments;

  setUp(() {
    db = FakeFirebaseFirestore();
    people = PeopleRepository(db, 'u1');
    txns = TransactionRepository(db, 'u1');
    payments = PaymentRepository(db, 'u1');
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peopleRepositoryProvider.overrideWithValue(people),
          transactionRepositoryProvider.overrideWithValue(txns),
          paymentRepositoryProvider.overrideWithValue(payments),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => screen)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  /// Rs 12,000 over 4 months from 31 Jan 2030: 4 x Rs 3,000, all upcoming.
  Future<String> seed() async {
    final p = await people.add(
      Person(name: 'Ravi', createdAt: DateTime(2026, 1, 1)),
    );
    return txns.addInstalmentPlan(
      personId: p,
      personName: 'Ravi',
      title: 'Loan',
      total: Money.fromRupees(12000),
      months: 4,
      startDate: DateTime(2030, 1, 31),
    );
  }

  Future<List<Map<String, dynamic>>> rows() async {
    final doc = (await db.collection('users/u1/transactions').get()).docs.single
        .data();
    return [
      for (final r in doc['schedule'] as List)
        Map<String, dynamic>.from(r as Map),
    ];
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  group('Add instalment plan', () {
    testWidgets('previews by months, then by monthly amount', (tester) async {
      await pumpScreen(tester, const AddInstalmentScreen());
      expect(find.textContaining('Enter the total'), findsOneWidget);

      await tester.enterText(field('Total you owe'), '30000');
      await tester.enterText(field('Months'), '6');
      await tester.pumpAndSettle();
      expect(find.text('₹5,000'), findsOneWidget);
      expect(find.text('6 payments'), findsOneWidget);

      await tester.tap(find.text('Monthly amount'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount each month'), '7000');
      await tester.pumpAndSettle();
      expect(find.text('5 payments'), findsOneWidget);
      expect(find.text('The last one is ₹2,000'), findsOneWidget);
    });

    testWidgets('bad terms show the reason', (tester) async {
      await pumpScreen(tester, const AddInstalmentScreen());
      await tester.enterText(field('Total you owe'), '1000');
      await tester.enterText(field('Months'), '700');
      await tester.pumpAndSettle();
      expect(find.textContaining('between 1 and 600'), findsOneWidget);
    });

    testWidgets('saving needs a person and a purpose', (tester) async {
      await pumpScreen(tester, const AddInstalmentScreen());
      await tester.enterText(field('Total you owe'), '12000');
      await tester.enterText(field('Months'), '4');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter what this is for'), findsOneWidget);
      expect(find.text('Choose or add the person'), findsOneWidget);
      expect(
        (await db.collection('users/u1/transactions').get()).docs,
        isEmpty,
      );
    });

    testWidgets('saves and opens the plan', (tester) async {
      await pumpScreen(tester, const AddInstalmentScreen());
      await tester.enterText(field('Person you owe'), 'Ravi');
      await tester.pumpAndSettle();
      await tester.tap(find.text("Add 'Ravi' as new person"));
      await tester.pumpAndSettle();
      await tester.enterText(field('What is it for'), 'Loan');
      await tester.enterText(field('Total you owe'), '12000');
      await tester.enterText(field('Months'), '4');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Instalment summary'), findsOneWidget);
      expect(find.text('Pay next instalment'), findsOneWidget);
      final doc = (await db.collection('users/u1/transactions').get())
          .docs
          .single
          .data();
      expect(doc['type'], 'instalment');
      expect(doc['totalAmount'], 1200000);
      expect((doc['schedule'] as List).length, 4);
    });
  });

  group('Instalment detail', () {
    testWidgets('uses payment wording and no principal or interest', (
      tester,
    ) async {
      final id = await seed();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      expect(find.text('Instalment summary'), findsOneWidget);
      expect(find.text('Next payment'), findsOneWidget);
      expect(find.text('Remaining payments'), findsOneWidget);
      expect(find.textContaining('Principal'), findsNothing);
      expect(find.textContaining('Interest'), findsNothing);
      expect(find.text('Pay next EMI'), findsNothing);
    });

    testWidgets('Pay next instalment marks the first payment paid', (
      tester,
    ) async {
      final id = await seed();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.text('Pay next instalment'));
      await tester.pumpAndSettle();
      expect(find.text('Pay instalment #1'), findsOneWidget);
      await tester.tap(find.text('Mark paid'));
      await tester.pumpAndSettle();
      final r = await rows();
      expect(r.first['paidAmount'], 300000);
      expect(r[1]['paidAmount'] ?? 0, 0);
    });

    testWidgets('skipping a month moves it and the later payments', (
      tester,
    ) async {
      final id = await seed();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tapVisible(tester, find.textContaining('#2 · '));
      await tester.tap(find.text('Skip this month'));
      await tester.pumpAndSettle();
      expect(find.text('Skip this month?'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      final dates = [
        for (final r in await rows()) (r['dueDate'] as Timestamp).toDate(),
      ];
      expect(dates, [
        DateTime(2030, 1, 31),
        DateTime(2030, 3, 31),
        DateTime(2030, 4, 30),
        DateTime(2030, 5, 31),
      ]);
    });

    testWidgets('cancelling the skip changes nothing', (tester) async {
      final id = await seed();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tapVisible(tester, find.textContaining('#2 · '));
      await tester.tap(find.text('Skip this month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final dates = [
        for (final r in await rows()) (r['dueDate'] as Timestamp).toDate(),
      ];
      expect(dates[1], DateTime(2030, 2, 28));
    });

    testWidgets('changing an amount re-spreads the rest', (tester) async {
      final id = await seed();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tapVisible(tester, find.textContaining('#1 · '));
      await tester.tap(find.text('Change amount'));
      await tester.pumpAndSettle();
      await tester.enterText(field('New amount'), '6000');
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(
        [for (final r in await rows()) r['amount']],
        [600000, 200000, 200000, 200000],
      );
    });

    testWidgets('a too-large amount is refused with a message', (tester) async {
      final id = await seed();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tapVisible(tester, find.textContaining('#1 · '));
      await tester.tap(find.text('Change amount'));
      await tester.pumpAndSettle();
      await tester.enterText(field('New amount'), '13000');
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('More than what is still to pay'),
        findsOneWidget,
      );
      expect((await rows()).first['amount'], 300000);
    });

    testWidgets('an extra payment shortens the plan from the end', (
      tester,
    ) async {
      final id = await seed();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add extra payment'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount'), '5000');
      await tester.tap(find.widgetWithText(FilledButton, 'Add extra payment'));
      await tester.pumpAndSettle();
      expect(
        [for (final r in await rows()) r['amount']],
        [300000, 300000, 100000],
      );
    });

    testWidgets('an extra payment above what is left is refused', (
      tester,
    ) async {
      final id = await seed();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add extra payment'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount'), '12001');
      await tester.tap(find.widgetWithText(FilledButton, 'Add extra payment'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cannot be more than'), findsOneWidget);
      expect((await rows()).length, 4);
    });
  });
}
