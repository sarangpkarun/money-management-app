import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/payment.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/transactions/add_entry_screen.dart';
import 'package:money_manager/transactions/entries_screen.dart';
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

  Future<void> pumpApp(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peopleRepositoryProvider.overrideWithValue(people),
          transactionRepositoryProvider.overrideWithValue(txns),
          paymentRepositoryProvider.overrideWithValue(payments),
        ],
        // A launcher route so screens that pop have somewhere to return to.
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

  Future<String> seedEntry({
    TransactionType type = TransactionType.lent,
    int rupees = 1000,
  }) async {
    final personId = await people.add(
      Person(name: 'Asha', createdAt: DateTime(2026, 1, 1)),
    );
    return txns.add(
      MoneyTransaction(
        type: type,
        personId: personId,
        personName: 'Asha',
        title: 'Loan',
        totalAmount: Money.fromRupees(rupees),
        createdAt: DateTime(2026, 9, 1),
      ),
    );
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  group('Add entry', () {
    testWidgets('shows errors when required fields are missing', (
      tester,
    ) async {
      await pumpApp(tester, const AddEntryScreen());
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Choose or add a person'), findsOneWidget);
      expect(find.textContaining('Enter an amount above 0'), findsOneWidget);
      expect(
        (await db.collection('users/u1/transactions').get()).docs,
        isEmpty,
      );
    });

    testWidgets('creates a lent entry for a new person and opens its detail', (
      tester,
    ) async {
      await pumpApp(tester, const AddEntryScreen());
      await tester.enterText(field('Person'), 'Asha');
      await tester.pumpAndSettle();
      await tester.tap(find.text("Add 'Asha' as new person"));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount'), '1000');
      await tester.enterText(field('Reason or item (optional)'), 'Phone');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('₹1,000'), findsWidgets);
      expect(find.text('Receive Payment'), findsOneWidget);

      final doc = (await db.collection('users/u1/transactions').get())
          .docs
          .single
          .data();
      expect(doc['type'], 'lent');
      expect(doc['personName'], 'Asha');
      expect(doc['title'], 'Phone');
      expect(doc['totalAmount'], 100000);
      expect((await db.collection('users/u1/people').get()).docs.length, 1);
    });

    testWidgets('a borrowed entry shows Pay Now', (tester) async {
      await pumpApp(tester, const AddEntryScreen());
      await tester.tap(find.text('Borrowed'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Person'), 'Ravi');
      await tester.pumpAndSettle();
      await tester.tap(find.text("Add 'Ravi' as new person"));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount'), '20000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Pay Now'), findsOneWidget);
      final doc = (await db.collection('users/u1/transactions').get())
          .docs
          .single
          .data();
      expect(doc['type'], 'borrowed');
      expect(doc['title'], 'Money borrowed');
    });

    testWidgets('editing the name after choosing a person clears the choice', (
      tester,
    ) async {
      await people.add(Person(name: 'Asha', createdAt: DateTime(2026, 1, 1)));
      await pumpApp(tester, const AddEntryScreen());
      await tester.enterText(field('Person'), 'Asha');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asha').last);
      await tester.pumpAndSettle();
      await tester.enterText(field('Person'), 'Ashab');
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount'), '50');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Choose or add a person'), findsOneWidget);
    });
  });

  group('Entry detail and payments', () {
    testWidgets('shows totals, status and the receive button', (tester) async {
      final id = await seedEntry();
      await pumpApp(tester, EntryDetailScreen(transactionId: id));
      expect(find.text('₹1,000'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(
        find.text('Received ₹0 of ₹1,000 · Balance ₹1,000'),
        findsOneWidget,
      );
      expect(find.text('No payments yet'), findsOneWidget);
      expect(find.text('Receive Payment'), findsOneWidget);
    });

    testWidgets('a partial payment updates balance, status and the list', (
      tester,
    ) async {
      final id = await seedEntry();
      await pumpApp(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.text('Receive Payment'));
      await tester.pumpAndSettle();
      // Pre-filled with the whole balance.
      expect(
        tester.widget<TextField>(field('Amount')).controller!.text,
        '1000',
      );
      await tester.enterText(field('Amount'), '500');
      await tester.tap(find.text('UPI'));
      await tester.enterText(field('Note (optional)'), 'first half');
      await tester.tap(find.text('Save payment'));
      await tester.pumpAndSettle();

      expect(
        find.text('Received ₹500 of ₹1,000 · Balance ₹500'),
        findsOneWidget,
      );
      expect(find.text('Partially Paid'), findsOneWidget);
      expect(find.text('₹500'), findsOneWidget);
      expect(find.textContaining('UPI'), findsOneWidget);
      expect(find.textContaining('first half'), findsOneWidget);
    });

    testWidgets('overpayment is blocked with a clear message', (tester) async {
      final id = await seedEntry();
      await pumpApp(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.text('Receive Payment'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount'), '1500');
      await tester.tap(find.text('Save payment'));
      await tester.pumpAndSettle();
      expect(
        find.text('Cannot be more than the balance of ₹1,000'),
        findsOneWidget,
      );
      expect(
        (await db.collection('users/u1/transactions/$id/payments').get()).docs,
        isEmpty,
      );
    });

    testWidgets('zero and invalid amounts are rejected', (tester) async {
      final id = await seedEntry();
      await pumpApp(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.text('Receive Payment'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount'), '0');
      await tester.tap(find.text('Save payment'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount above 0'), findsOneWidget);
      await tester.enterText(field('Amount'), 'abc');
      await tester.tap(find.text('Save payment'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid amount'), findsOneWidget);
    });

    testWidgets('paying the full balance marks it Paid and hides the button', (
      tester,
    ) async {
      final id = await seedEntry();
      await pumpApp(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.text('Receive Payment'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Save payment'),
      ); // pre-filled with the balance
      await tester.pumpAndSettle();
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Receive Payment'), findsNothing);
      final doc = (await db.doc('users/u1/transactions/$id').get()).data()!;
      expect(doc['settledAt'], isNotNull);
    });

    testWidgets('editing a payment recalculates the balance', (tester) async {
      final id = await seedEntry();
      await payments.add(id, samplePayment());
      await pumpApp(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.text('₹500'));
      await tester.pumpAndSettle();
      expect(find.text('Edit payment'), findsOneWidget);
      await tester.enterText(field('Amount'), '300');
      await tester.tap(find.text('Save payment'));
      await tester.pumpAndSettle();
      expect(
        find.text('Received ₹300 of ₹1,000 · Balance ₹700'),
        findsOneWidget,
      );
    });

    testWidgets('deleting a payment reopens a settled entry', (tester) async {
      final id = await seedEntry();
      await payments.add(id, samplePayment(rupees: 1000));
      await pumpApp(tester, EntryDetailScreen(transactionId: id));
      expect(find.text('Paid'), findsOneWidget);
      await tester.tap(find.text('₹1,000').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('No payments yet'), findsOneWidget);
      expect(find.text('Receive Payment'), findsOneWidget);
    });

    testWidgets('borrowed entries use Pay wording', (tester) async {
      final id = await seedEntry(type: TransactionType.borrowed, rupees: 20000);
      await pumpApp(tester, EntryDetailScreen(transactionId: id));
      expect(find.text('Pay Now'), findsOneWidget);
      expect(find.text('Paid ₹0 of ₹20,000 · Balance ₹20,000'), findsOneWidget);
    });

    testWidgets('deleting the entry removes it and its payments', (
      tester,
    ) async {
      final id = await seedEntry();
      await payments.add(id, samplePayment());
      await pumpApp(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget); // back at the launcher
      expect(
        (await db.collection('users/u1/transactions').get()).docs,
        isEmpty,
      );
      expect(
        (await db.collection('users/u1/transactions/$id/payments').get()).docs,
        isEmpty,
      );
    });
  });

  group('Entries list', () {
    testWidgets('lists entries with status and opens the detail', (
      tester,
    ) async {
      await seedEntry();
      await pumpApp(tester, const EntriesScreen());
      expect(find.text('Asha · Loan'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      await tester.tap(find.text('Asha · Loan'));
      await tester.pumpAndSettle();
      expect(find.text('Receive Payment'), findsOneWidget);
    });

    testWidgets('empty state and add button', (tester) async {
      await pumpApp(tester, const EntriesScreen());
      expect(find.text('No entries yet'), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Add entry'), findsOneWidget);
    });
  });
}

// Small helper so the tests read clearly.
Payment samplePayment({int rupees = 500}) =>
    Payment(amount: Money.fromRupees(rupees), date: DateTime(2026, 9, 5));
