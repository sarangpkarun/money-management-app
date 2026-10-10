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
import 'package:money_manager/core/models/reminder.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/reminders/alarm_providers.dart';
import 'package:money_manager/reminders/reminders_screen.dart';
import 'package:money_manager/transactions/entry_detail_screen.dart';

import '../support/fake_alarm_gateway.dart';

void main() {
  late FakeFirebaseFirestore db;
  late PeopleRepository people;
  late TransactionRepository txns;
  late PaymentRepository payments;
  late ReminderRepository reminders;
  final burst = find.byKey(const ValueKey('success-burst'));

  setUp(() {
    db = FakeFirebaseFirestore();
    people = PeopleRepository(db, 'u1');
    txns = TransactionRepository(db, 'u1');
    payments = PaymentRepository(db, 'u1');
    reminders = ReminderRepository(db, 'u1');
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peopleRepositoryProvider.overrideWithValue(people),
          transactionRepositoryProvider.overrideWithValue(txns),
          paymentRepositoryProvider.overrideWithValue(payments),
          reminderRepositoryProvider.overrideWithValue(reminders),
          alarmGatewayProvider.overrideWithValue(FakeAlarmGateway()),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String> seed({TransactionType type = TransactionType.lent}) async {
    final pid = await people.add(
      Person(name: 'Asha', createdAt: DateTime(2026, 1, 1)),
    );
    return txns.add(
      MoneyTransaction(
        type: type,
        personId: pid,
        personName: 'Asha',
        title: 'Loan',
        totalAmount: Money.fromRupees(1000),
        createdAt: DateTime(2026, 9, 1),
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('Receive Payment'));
    await tester.pumpAndSettle();
  }

  testWidgets('a part payment shows "Payment saved"', (tester) async {
    final id = await seed();
    await pump(tester, EntryDetailScreen(transactionId: id));
    await openSheet(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '400');
    await tester.tap(find.text('Save payment'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(burst, findsOneWidget);
    expect(find.text('Payment saved'), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.check_circle)).size, 64);
    await tester.pumpAndSettle();
    expect(burst, findsNothing);
  });

  testWidgets('paying the rest says "Settled" with the big burst', (
    tester,
  ) async {
    final id = await seed();
    await pump(tester, EntryDetailScreen(transactionId: id));
    await openSheet(tester); // the amount is prefilled with what is left
    await tester.tap(find.text('Save payment'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Settled'), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.check_circle)).size, 96);
    await tester.pumpAndSettle();
  });

  testWidgets('a refused payment shows no success', (tester) async {
    final id = await seed();
    await pump(tester, EntryDetailScreen(transactionId: id));
    await openSheet(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '5000');
    await tester.tap(find.text('Save payment'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(burst, findsNothing);
    expect(find.textContaining('Cannot be more than'), findsOneWidget);
  });

  testWidgets('with animations off the payment still saves, without a burst', (
    tester,
  ) async {
    final id = await seed();
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pump(tester, EntryDetailScreen(transactionId: id));
    await openSheet(tester);
    await tester.tap(find.text('Save payment'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(burst, findsNothing);
    final doc = (await db.collection('users/u1/transactions').doc(id).get())
        .data()!;
    expect(doc['paidTotal'], 100000);
  });

  group('EMI rows', () {
    Future<String> emi() async {
      final pid = await people.add(
        Person(name: 'Croma', createdAt: DateTime(2026, 1, 1)),
      );
      return txns.addEmi(
        personId: pid,
        personName: 'Croma',
        title: 'Phone',
        price: Money.fromRupees(6000),
        annualRatePercent: 0,
        months: 2,
        startDate: DateTime(2030, 1, 15),
      );
    }

    testWidgets('paying a row that is not the last says "EMI paid"', (
      tester,
    ) async {
      final id = await emi();
      await pump(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.text('Pay next EMI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark EMI paid'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('EMI paid'), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(Icons.check_circle)).size, 64);
      await tester.pumpAndSettle();
    });

    testWidgets('paying the last row says "Settled"', (tester) async {
      final id = await emi();
      await payments.payInstallment(
        id,
        1,
        amount: Money.fromRupees(3000),
        date: DateTime(2030, 1, 15),
        mode: PaymentMode.cash,
      );
      await pump(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.text('Pay next EMI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark EMI paid'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Settled'), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(Icons.check_circle)).size, 96);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('marking a missed reminder done shows "Marked done"', (
    tester,
  ) async {
    await reminders.add(
      Reminder(
        title: 'Old',
        at: DateTime(2020, 1, 1, 9),
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await pump(tester, const RemindersScreen());
    await tester.tap(find.text('Missed (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark done'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Marked done'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
