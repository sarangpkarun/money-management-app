import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/models/emi_plan.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/transactions/add_emi_screen.dart';
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

  Future<String> seedEmi({DateTime? start, LateFeeRule? lateFee}) async {
    final store = await people.add(
      Person(name: 'Croma', createdAt: DateTime(2026, 1, 1)),
    );
    return txns.addEmi(
      personId: store,
      personName: 'Croma',
      title: 'Phone',
      price: Money.fromRupees(12000),
      annualRatePercent: 0,
      months: 4,
      startDate: start ?? DateTime(2030, 1, 15),
      lateFee: lateFee,
    );
  }

  Future<Map<String, dynamic>> plan() async => Map<String, dynamic>.from(
    (await db.collection('users/u1/transactions').get()).docs.single
            .data()['emiPlan']
        as Map,
  );

  Future<void> fillBasics(WidgetTester tester) async {
    await tester.enterText(field('Product'), 'Phone');
    await tester.enterText(field('Store or bank'), 'Croma');
    await tester.pumpAndSettle();
    await tester.tap(find.text("Add 'Croma' as new person"));
    await tester.pumpAndSettle();
    await tester.enterText(field('Total price'), '12000');
    await tester.enterText(field('Months'), '4');
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  group('Add EMI: no-cost and late fee', () {
    testWidgets('a no-cost EMI shows what the seller absorbs and is saved', (
      tester,
    ) async {
      await pumpScreen(tester, const AddEmiScreen());
      await fillBasics(tester);
      await tapVisible(tester, find.text('No-cost EMI'));
      await tester.enterText(field("Lender's rate (% a year)"), '12');
      await tester.pumpAndSettle();
      expect(find.text('Seller absorbs (estimate)'), findsOneWidget);
      expect(find.text('₹3,000'), findsWidgets); // customer EMI at 0%
      await save(tester);
      final p = await plan();
      expect(p['noCostRate'], 12);
      expect(p['annualRatePercent'], 0);
    });

    testWidgets('a no-cost EMI needs the lender rate', (tester) async {
      await pumpScreen(tester, const AddEmiScreen());
      await fillBasics(tester);
      await tapVisible(tester, find.text('No-cost EMI'));
      await save(tester);
      expect(find.textContaining('Enter a rate above 0'), findsOneWidget);
      expect(
        (await db.collection('users/u1/transactions').get()).docs,
        isEmpty,
      );
    });

    testWidgets('a flat late fee with grace days is saved', (tester) async {
      await pumpScreen(tester, const AddEmiScreen());
      await fillBasics(tester);
      await tapVisible(tester, find.text('Flat ₹'));
      await tester.enterText(field('Fee per late EMI'), '150');
      await tester.enterText(field('Grace days'), '3');
      await save(tester);
      final fee = Map<String, dynamic>.from((await plan())['lateFee'] as Map);
      expect(fee['flat'], 15000);
      expect(fee['graceDays'], 3);
    });

    testWidgets('a percent late fee over 100 blocks saving', (tester) async {
      await pumpScreen(tester, const AddEmiScreen());
      await fillBasics(tester);
      await tapVisible(tester, find.text('Percent'));
      await tester.enterText(field('% of the EMI'), '150');
      await tester.pumpAndSettle();
      expect(find.textContaining('between 0 and 100'), findsOneWidget);
      await save(tester);
      expect(
        (await db.collection('users/u1/transactions').get()).docs,
        isEmpty,
      );
    });

    testWidgets('no late fee and no no-cost is the default', (tester) async {
      await pumpScreen(tester, const AddEmiScreen());
      await fillBasics(tester);
      await save(tester);
      final p = await plan();
      expect(p.containsKey('lateFee'), isFalse);
      expect(p.containsKey('noCostRate'), isFalse);
    });
  });

  group('Summary card', () {
    testWidgets('shows the late fee estimate only when something is late', (
      tester,
    ) async {
      final id = await seedEmi(
        start: DateTime(2020, 1, 15), // all four instalments are long overdue
        lateFee: LateFeeRule.flat(Money.fromRupees(100)),
      );
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      expect(find.text('Late fee to date (estimate)'), findsOneWidget);
      expect(find.text('₹400'), findsOneWidget);
    });

    testWidgets('no line while nothing is late', (tester) async {
      final id = await seedEmi(
        lateFee: LateFeeRule.flat(Money.fromRupees(100)),
      );
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      expect(find.textContaining('Late fee'), findsNothing);
    });
  });

  group('Prepay / foreclose', () {
    Future<void> openPrepay(WidgetTester tester) async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepay / foreclose'));
      await tester.pumpAndSettle();
    }

    testWidgets('foreclosure shows principal, charge and total', (
      tester,
    ) async {
      final id = await seedEmi();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await openPrepay(tester);
      expect(find.textContaining('Estimate only'), findsOneWidget);
      expect(find.text('₹12,000'), findsWidgets);
      await tester.enterText(field('Foreclosure charge (% of principal)'), '2');
      await tester.pumpAndSettle();
      expect(find.text('₹240'), findsOneWidget); // the charge
      expect(find.text('₹12,240'), findsOneWidget); // the total
    });

    testWidgets('part prepayment shows both choices', (tester) async {
      final id = await seedEmi();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await openPrepay(tester);
      await tester.tap(find.text('Part prepayment'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Part payment'), '3000');
      await tester.pumpAndSettle();
      expect(find.text('3 (was 4)'), findsOneWidget); // keep EMI
      await tester.tap(find.text('Keep months, lower EMI'));
      await tester.pumpAndSettle();
      expect(find.text('4 (was 4)'), findsOneWidget);
      expect(find.text('₹2,250'), findsOneWidget); // new EMI
    });

    testWidgets('an amount that clears the loan points to foreclosure', (
      tester,
    ) async {
      final id = await seedEmi();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await openPrepay(tester);
      await tester.tap(find.text('Part prepayment'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Part payment'), '12000');
      await tester.pumpAndSettle();
      expect(find.textContaining('use foreclosure instead'), findsOneWidget);
    });

    testWidgets('nothing is changed in the saved plan', (tester) async {
      final id = await seedEmi();
      final before = await plan();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await openPrepay(tester);
      await tester.tap(find.text('Part prepayment'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Part payment'), '3000');
      await tester.pumpAndSettle();
      expect(await plan(), before);
      expect(
        (await db.collection('users/u1/transactions/$id/payments').get()).docs,
        isEmpty,
      );
    });

    testWidgets('the menu entry is hidden for instalment plans', (
      tester,
    ) async {
      final p = await people.add(
        Person(name: 'Ravi', createdAt: DateTime(2026, 1, 1)),
      );
      final id = await txns.addInstalmentPlan(
        personId: p,
        personName: 'Ravi',
        title: 'Loan',
        total: Money.fromRupees(1000),
        months: 2,
        startDate: DateTime(2030, 1, 31),
      );
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Prepay / foreclose'), findsNothing);
      expect(find.text('Add extra payment'), findsOneWidget);
    });
  });
}
