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
import 'package:money_manager/history/history_screen.dart';
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

  Future<void> pumpHistory(
    WidgetTester tester, {
    Widget screen = const HistoryScreen(),
  }) async {
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

  Future<String> entry(
    String name,
    TransactionType type,
    int rupees, {
    String title = 'Loan',
    int paid = 0,
    List<int>? split,
  }) async {
    final personId = await people.add(
      Person(name: name, createdAt: DateTime(2026, 1, 1)),
    );
    final id = await txns.add(
      MoneyTransaction(
        type: type,
        personId: personId,
        personName: name,
        title: title,
        totalAmount: Money.fromRupees(rupees),
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    var day = 1;
    for (final part in split ?? [if (paid > 0) paid]) {
      await payments.add(
        id,
        Payment(amount: Money.fromRupees(part), date: DateTime(2026, 9, day++)),
      );
    }
    return id;
  }

  Future<void> seed() async {
    await entry('Asha', TransactionType.lent, 1000, title: 'Phone', paid: 1000);
    await entry(
      'Ravi',
      TransactionType.borrowed,
      500,
      title: 'Rent',
      paid: 500,
    );
    await entry(
      'Meera',
      TransactionType.lent,
      300,
      title: 'Open one',
      paid: 100,
    );
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('shows only settled entries', (tester) async {
    await seed();
    await pumpHistory(tester);
    expect(find.text('Asha · Phone'), findsOneWidget);
    expect(find.text('Ravi · Rent'), findsOneWidget);
    expect(find.text('Meera · Open one'), findsNothing);
    expect(find.text('Paid'), findsNWidgets(2));
  });

  testWidgets('empty state when nothing is settled yet', (tester) async {
    await entry('Meera', TransactionType.lent, 300, paid: 100);
    await pumpHistory(tester);
    expect(find.text('No settled entries yet'), findsOneWidget);
  });

  testWidgets('type chips filter and Clear resets', (tester) async {
    await seed();
    await pumpHistory(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Lent'));
    await tester.pumpAndSettle();
    expect(find.text('Asha · Phone'), findsOneWidget);
    expect(find.text('Ravi · Rent'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi · Rent'), findsOneWidget);
  });

  testWidgets('search matches person or reason', (tester) async {
    await seed();
    await pumpHistory(tester);
    await tester.enterText(field('Search person or reason').first, 'rent');
    await tester.pumpAndSettle();
    expect(find.text('Ravi · Rent'), findsOneWidget);
    expect(find.text('Asha · Phone'), findsNothing);

    await tester.enterText(field('Search person or reason').first, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching entries'), findsOneWidget);
  });

  testWidgets('the filter sheet narrows by amount and by person', (
    tester,
  ) async {
    await seed();
    await pumpHistory(tester);

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Min amount'), '600');
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('Asha · Phone'), findsOneWidget);
    expect(find.text('Ravi · Rent'), findsNothing);

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi · Rent'), findsOneWidget);

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anyone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ravi').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi · Rent'), findsOneWidget);
    expect(find.text('Asha · Phone'), findsNothing);
  });

  testWidgets('the filter sheet rejects bad amounts', (tester) async {
    await seed();
    await pumpHistory(tester);
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Min amount'), '900');
    await tester.enterText(field('Max amount'), '100');
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('Minimum is above the maximum'), findsOneWidget);
    await tester.enterText(field('Max amount'), 'abc');
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('Enter valid amounts'), findsOneWidget);
  });

  group('Mark as unpaid', () {
    testWidgets('settled entries offer it', (tester) async {
      await seed();
      await pumpHistory(tester);
      await tester.tap(find.text('Asha · Phone'));
      await tester.pumpAndSettle();
      expect(find.text('Mark as unpaid'), findsOneWidget);
      expect(find.text('Receive Payment'), findsNothing);
    });

    testWidgets('open entries do not offer it', (tester) async {
      final id = await entry('Meera', TransactionType.lent, 300, paid: 100);
      await pumpHistory(tester, screen: EntryDetailScreen(transactionId: id));
      expect(find.text('Receive Payment'), findsOneWidget);
      expect(find.text('Mark as unpaid'), findsNothing);
    });

    testWidgets('removes the last payment, reopens it and leaves History', (
      tester,
    ) async {
      // 600 then 400 on a later day: 400 is the last payment.
      final id = await entry(
        'Asha',
        TransactionType.lent,
        1000,
        title: 'Phone',
        split: [600, 400],
      );
      await pumpHistory(tester);
      await tester.tap(find.text('Asha · Phone'));
      await tester.pumpAndSettle();
      expect(find.text('Paid'), findsWidgets);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Mark as unpaid'));
      await tester.pumpAndSettle();
      expect(find.textContaining('last payment of ₹400'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Mark as unpaid'));
      await tester.pumpAndSettle();

      // The detail screen now shows an open entry with the payment gone.
      expect(find.text('Partially Paid'), findsOneWidget);
      expect(find.text('Receive Payment'), findsOneWidget);
      expect(find.text('Mark as unpaid'), findsNothing);
      expect(find.textContaining('Removed ₹400'), findsOneWidget);
      final doc = (await db.doc('users/u1/transactions/$id').get()).data()!;
      expect(doc['paidTotal'], 60000);
      expect(doc['settledAt'], isNull);

      // Back in History it is gone.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Asha · Phone'), findsNothing);
      expect(find.text('No settled entries yet'), findsOneWidget);
    });

    testWidgets('cancelling leaves it settled', (tester) async {
      await entry('Asha', TransactionType.lent, 1000, paid: 1000);
      await pumpHistory(tester);
      await tester.tap(find.textContaining('Asha'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Mark as unpaid'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Mark as unpaid'), findsOneWidget);
      expect(find.text('Receive Payment'), findsNothing);
    });
  });
}
