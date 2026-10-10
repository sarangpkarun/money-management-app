import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/reminder_repository.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/payment.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/home/home_screen.dart';
import 'package:money_manager/reminders/alarm_providers.dart';
import 'package:money_manager/transactions/entries_screen.dart';

import '../support/fake_alarm_gateway.dart';

void main() {
  late FakeFirebaseFirestore db;
  late TransactionRepository txns;
  late PaymentRepository payments;
  late String pid;

  setUp(() async {
    db = FakeFirebaseFirestore();
    final people = PeopleRepository(db, 'u1');
    txns = TransactionRepository(db, 'u1');
    payments = PaymentRepository(db, 'u1');
    pid = await people.add(
      Person(name: 'Asha', createdAt: DateTime(2026, 1, 1)),
    );
  });

  Future<String> add(String title, {DateTime? due}) => txns.add(
    MoneyTransaction(
      type: TransactionType.lent,
      personId: pid,
      personName: 'Asha',
      title: title,
      totalAmount: Money.fromRupees(1000),
      dueDate: due,
      createdAt: DateTime(2026, 9, 1),
    ),
  );

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peopleRepositoryProvider.overrideWithValue(
            PeopleRepository(db, 'u1'),
          ),
          transactionRepositoryProvider.overrideWithValue(txns),
          paymentRepositoryProvider.overrideWithValue(payments),
          reminderRepositoryProvider.overrideWithValue(
            ReminderRepository(db, 'u1'),
          ),
          alarmGatewayProvider.overrideWithValue(FakeAlarmGateway()),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Entries: swipe right opens the payment sheet, row stays', (
    tester,
  ) async {
    await add('Loan');
    await pump(tester, const EntriesScreen());
    await tester.drag(find.textContaining('Loan'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Receive Payment'), findsWidgets);
    expect(find.byType(BottomSheet), findsOneWidget);
    // Nothing was recorded and the entry is still listed.
    expect((await db.collection('users/u1/transactions').get()).docs.length, 1);
  });

  testWidgets('Entries: swiping left does nothing (no destructive swipe)', (
    tester,
  ) async {
    await add('Loan');
    await pump(tester, const EntriesScreen());
    await tester.drag(find.textContaining('Loan'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.textContaining('Loan'), findsOneWidget);
    expect((await db.collection('users/u1/transactions').get()).docs.length, 1);
  });

  testWidgets('Entries: a settled entry cannot be swiped to pay', (
    tester,
  ) async {
    final id = await add('Loan');
    await payments.add(
      id,
      Payment(
        amount: Money.fromRupees(1000),
        date: DateTime(2026, 9, 2),
        mode: PaymentMode.cash,
        createdAt: DateTime(2026, 9, 2),
      ),
    );
    await pump(tester, const EntriesScreen());
    await tester.drag(find.textContaining('Loan'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('Home: swiping a due row right opens the payment sheet', (
    tester,
  ) async {
    await add('Loan', due: DateTime.now().subtract(const Duration(days: 3)));
    await pump(tester, const HomeScreen());
    await tester.drag(
      find.textContaining('Asha ·').first,
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  });
}
