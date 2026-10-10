import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/data/user_repository.dart';
import 'package:money_manager/core/models/app_user.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/payment.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/theme/app_theme.dart';
import 'package:money_manager/home/home_screen.dart';

void main() {
  late FakeFirebaseFirestore db;
  late PeopleRepository people;
  late TransactionRepository txns;
  late PaymentRepository payments;

  setUp(() async {
    db = FakeFirebaseFirestore();
    people = PeopleRepository(db, 'u1');
    txns = TransactionRepository(db, 'u1');
    payments = PaymentRepository(db, 'u1');
    await UserRepository(db, 'u1').save(const AppUser(name: 'Sarang'));
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peopleRepositoryProvider.overrideWithValue(people),
          transactionRepositoryProvider.overrideWithValue(txns),
          paymentRepositoryProvider.overrideWithValue(payments),
          userRepositoryProvider.overrideWithValue(UserRepository(db, 'u1')),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  DateTime daysFromToday(int n) {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day + n);
  }

  Future<String> entry(
    String name,
    int rupees,
    DateTime? due, {
    TransactionType type = TransactionType.lent,
    String title = 'Loan',
  }) async {
    final pid = await people.add(
      Person(name: name, createdAt: DateTime(2026, 1, 1)),
    );
    return txns.add(
      MoneyTransaction(
        type: type,
        personId: pid,
        personName: name,
        title: title,
        totalAmount: Money.fromRupees(rupees),
        dueDate: due,
        createdAt: DateTime(2026, 9, 1),
        date: DateTime(2026, 9, 1),
      ),
    );
  }

  testWidgets('shows overdue, this week and upcoming, hides empty ones', (
    tester,
  ) async {
    await entry('Asha', 300, daysFromToday(-3));
    await entry('Ravi', 500, daysFromToday(0), type: TransactionType.borrowed);
    await entry('Meena', 700, daysFromToday(100));
    await pump(tester);
    expect(find.text('Overdue · 1'), findsOneWidget);
    expect(find.text('This week · 1'), findsOneWidget);
    expect(find.text('Upcoming · 1'), findsOneWidget);
    expect(find.textContaining('This month'), findsNothing);
    expect(find.text('3 days late'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
    expect(find.text('Receive ₹300'), findsOneWidget);
    expect(find.text('Pay ₹500'), findsOneWidget);
  });

  testWidgets('amounts are green when owed to you and red when you pay', (
    tester,
  ) async {
    await entry('Asha', 300, daysFromToday(1));
    await entry('Ravi', 500, daysFromToday(0), type: TransactionType.borrowed);
    await pump(tester);
    // The Home cards also show these totals, so look inside the due rows.
    Color amountIn(String dueLabel, String amount) => tester
        .widget<Text>(
          find.descendant(
            of: find.widgetWithText(ListTile, dueLabel),
            matching: find.text(amount),
          ),
        )
        .style!
        .color!;
    expect(amountIn('Due tomorrow', '₹300'), const Color(0xFF16A34A));
    expect(amountIn('Due today', '₹500'), const Color(0xFFDC2626));
  });

  testWidgets('an entry with no due date appears in no section', (
    tester,
  ) async {
    await entry('Asha', 300, null);
    await pump(tester);
    expect(find.textContaining('Overdue'), findsNothing);
    expect(find.textContaining('This week'), findsNothing);
    expect(find.textContaining('Upcoming'), findsNothing);
    expect(find.text('Asha · Loan'), findsOneWidget); // still in Recent
  });

  testWidgets('more than five: first five shown, See all shows them all', (
    tester,
  ) async {
    for (var i = 1; i <= 7; i++) {
      await entry('P$i', 100 * i, daysFromToday(-i), title: 'T$i');
    }
    await pump(tester);
    expect(find.text('Overdue · 7'), findsOneWidget);
    // Oldest first: 7 days late down to 3 days late are the five shown.
    expect(find.text('7 days late'), findsOneWidget);
    expect(find.text('3 days late'), findsOneWidget);
    expect(find.text('2 days late'), findsNothing);
    expect(find.text('1 day late'), findsNothing);
    final seeAll = find.widgetWithText(TextButton, 'See all').first;
    await tester.tap(seeAll);
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsOneWidget); // the list screen title
    expect(find.text('1 day late'), findsOneWidget);
    expect(find.text('7 days late'), findsOneWidget);
  });

  testWidgets('tapping a row opens the entry', (tester) async {
    await entry('Asha', 300, daysFromToday(-2), title: 'Bike');
    await pump(tester);
    await tester.tap(find.text('2 days late'));
    await tester.pumpAndSettle();
    expect(find.text('Bike'), findsWidgets);
    expect(find.text('Receive Payment'), findsOneWidget);
  });

  testWidgets('an EMI shows each unpaid row on its own', (tester) async {
    final pid = await people.add(
      Person(name: 'Croma', createdAt: DateTime(2026, 1, 1)),
    );
    final t = DateTime.now();
    await txns.addEmi(
      personId: pid,
      personName: 'Croma',
      title: 'Phone',
      price: Money.fromRupees(12000),
      annualRatePercent: 0,
      months: 4,
      startDate: DateTime(t.year, t.month, t.day - 70),
    );
    await pump(tester);
    // Rows were due 70 days ago, 40 ago, 10 ago (all overdue) and in 20 days.
    expect(find.text('Overdue · 3'), findsOneWidget);
    expect(find.text('Croma · EMI #1 · Phone'), findsOneWidget);
    expect(find.text('Pay ₹9,000'), findsOneWidget);
  });

  testWidgets('paying an entry removes it from the sections live', (
    tester,
  ) async {
    final id = await entry('Asha', 300, daysFromToday(-1));
    await pump(tester);
    expect(find.text('Overdue · 1'), findsOneWidget);
    await payments.add(
      id,
      Payment(
        amount: Money.fromRupees(300),
        date: DateTime.now(),
        createdAt: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Overdue'), findsNothing);
  });

  testWidgets('the Add button opens the sheet with every entry type', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
    await tester.pumpAndSettle();
    for (final t in [
      'Money I gave',
      'Money I borrowed',
      'EMI purchase',
      'Pay in instalments',
      'Reminder',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('an empty Home has no sections and invites the first entry', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('No entries yet'), findsOneWidget);
    expect(find.text('Add your first entry'), findsOneWidget);
    expect(find.textContaining('Overdue'), findsNothing);
  });
}
