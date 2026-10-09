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
import 'package:money_manager/people/person_ledger_screen.dart';

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

  Future<String> person(String name, {String? phone}) => people.add(
    Person(name: name, phone: phone, createdAt: DateTime(2026, 1, 1)),
  );

  Future<String> entry(
    String personId,
    String name,
    TransactionType type,
    int rupees, {
    DateTime? date,
    String title = 'Loan',
    InterestType interest = InterestType.none,
    double? rate,
  }) => txns.add(
    MoneyTransaction(
      type: type,
      personId: personId,
      personName: name,
      title: title,
      totalAmount: Money.fromRupees(rupees),
      interestType: interest,
      interestRate: rate,
      createdAt: date ?? DateTime(2026, 9, 1),
      date: date ?? DateTime(2026, 9, 1),
    ),
  );

  Future<void> pay(String txnId, int rupees, DateTime date) => payments.add(
    txnId,
    Payment(amount: Money.fromRupees(rupees), date: date),
  );

  Future<void> pumpLedger(WidgetTester tester, String personId) async {
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
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PersonLedgerScreen(personId: personId),
                    ),
                  ),
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

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('shows the net in the header and the timeline newest first', (
    tester,
  ) async {
    final id = await person('Asha', phone: '98450');
    final a = await entry(id, 'Asha', TransactionType.lent, 1000);
    await pay(a, 500, DateTime(2026, 9, 10));
    await entry(
      id,
      'Asha',
      TransactionType.borrowed,
      200,
      date: DateTime(2026, 9, 15),
      title: 'Rent',
    );
    await pumpLedger(tester, id);

    expect(find.text('98450'), findsOneWidget);
    expect(find.text('Owes you'), findsOneWidget); // header
    expect(find.text('₹300'), findsWidgets); // header and the newest row

    final borrowed = top(tester, 'Borrowed ₹200');
    final received = top(tester, 'Received ₹500');
    final gave = top(tester, 'Gave ₹1,000');
    expect(
      borrowed < received && received < gave,
      isTrue,
      reason: 'newest first',
    );

    // Running balances: 300 after borrowing, 500 after receiving, 1,000 first.
    expect(find.text('₹500'), findsOneWidget);
    expect(find.text('₹1,000'), findsOneWidget);
    expect(find.text('owes you'), findsNWidgets(3));
  });

  testWidgets('the header says You owe when the balance is negative', (
    tester,
  ) async {
    final id = await person('Ravi');
    await entry(id, 'Ravi', TransactionType.borrowed, 500, title: 'Rent');
    await pumpLedger(tester, id);
    expect(find.text('You owe'), findsOneWidget);
    expect(find.text('Borrowed ₹500'), findsOneWidget);
    expect(find.text('you owe'), findsOneWidget); // the row's balance caption
  });

  testWidgets('a settled person reads Settled and Receive / Pay is disabled', (
    tester,
  ) async {
    final id = await person('Asha');
    final a = await entry(id, 'Asha', TransactionType.lent, 300);
    await pay(a, 300, DateTime(2026, 9, 5));
    await pumpLedger(tester, id);
    expect(find.text('Settled'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Receive / Pay'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('an empty ledger says so', (tester) async {
    final id = await person('Meera');
    await pumpLedger(tester, id);
    expect(find.text('Nothing with Meera yet'), findsOneWidget);
  });

  testWidgets('a row opens the entry detail', (tester) async {
    final id = await person('Asha');
    await entry(id, 'Asha', TransactionType.lent, 1000, title: 'Phone');
    await pumpLedger(tester, id);
    await tester.tap(find.text('Gave ₹1,000'));
    await tester.pumpAndSettle();
    expect(find.text('Receive Payment'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
  });

  testWidgets('Give / Add opens Add entry with the person already chosen', (
    tester,
  ) async {
    final id = await person('Asha');
    await pumpLedger(tester, id);
    await tester.tap(find.text('Give / Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add entry'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Person'))
          .controller!
          .text,
      'Asha',
    );
  });

  group('Receive / Pay', () {
    testWidgets('with one open entry it goes straight to the payment sheet', (
      tester,
    ) async {
      final id = await person('Asha');
      await entry(id, 'Asha', TransactionType.lent, 1000);
      await pumpLedger(tester, id);
      await tester.tap(find.text('Receive / Pay'));
      await tester.pumpAndSettle();
      expect(find.text('Receive payment'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '400');
      await tester.tap(find.text('Save payment'));
      await tester.pumpAndSettle();
      // The ledger gains a Received row and the header net drops.
      expect(find.text('Received ₹400'), findsOneWidget);
      expect(find.text('₹600'), findsWidgets);
    });

    testWidgets('with several open entries you choose one first', (
      tester,
    ) async {
      final id = await person('Asha');
      await entry(id, 'Asha', TransactionType.lent, 1000, title: 'Phone');
      await entry(
        id,
        'Asha',
        TransactionType.lent,
        300,
        title: 'Lunch',
        date: DateTime(2026, 9, 2),
      );
      await pumpLedger(tester, id);
      await tester.tap(find.text('Receive / Pay'));
      await tester.pumpAndSettle();
      expect(find.text('Which entry?'), findsOneWidget);
      await tester.tap(find.text('Gave ₹300 · Lunch'));
      await tester.pumpAndSettle();
      expect(find.text('Receive payment'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Amount'))
            .controller!
            .text,
        '300', // the chosen entry's balance
      );
    });
  });

  testWidgets('interest shows as its own row and the header includes it', (
    tester,
  ) async {
    final id = await person('Ravi');
    await entry(
      id,
      'Ravi',
      TransactionType.borrowed,
      10000,
      date: DateTime.now().subtract(const Duration(days: 365)),
      interest: InterestType.simple,
      rate: 12,
    );
    await pumpLedger(tester, id);
    expect(find.text('Interest ₹1,200'), findsOneWidget);
    expect(find.text('₹11,200'), findsWidgets); // header and the last row
    expect(find.text('You owe'), findsOneWidget);
  });

  testWidgets('Edit person opens the form', (tester) async {
    final id = await person('Asha');
    await pumpLedger(tester, id);
    await tester.tap(find.byTooltip('Edit person'));
    await tester.pumpAndSettle();
    expect(find.text('Edit person'), findsWidgets);
    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
  });
}
