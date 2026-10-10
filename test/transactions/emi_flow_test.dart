import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/models/payment.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/theme/app_colors.dart';
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

  /// 12,000 at 0% over 4 months: 4 x Rs 3,000.
  Future<String> seedEmi({DateTime? start}) async {
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
      startDate: start ?? DateTime(2030, 1, 15), // in the future: all upcoming
    );
  }

  Color dotColor(WidgetTester tester, int row) {
    final c = tester.widget<Container>(find.byKey(ValueKey('emi-dot-$row')));
    return (c.decoration! as BoxDecoration).color!;
  }

  final amber = AppColors.pendingFor(Brightness.light);
  final green = AppColors.receiveFor(Brightness.light);
  final red = AppColors.payFor(Brightness.light);
  final blue = AppColors.partialFor(Brightness.light);

  group('Add EMI purchase', () {
    testWidgets('asks for the terms before showing a preview', (tester) async {
      await pumpScreen(tester, const AddEmiScreen());
      expect(
        find.text('Enter the price, interest and months to see the EMI'),
        findsOneWidget,
      );
      expect(field('Interest (% a year)'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('Interest (% a year)')).controller!.text,
        '0',
      );
    });

    testWidgets('the preview shows the EMI, interest and total as you type', (
      tester,
    ) async {
      await pumpScreen(tester, const AddEmiScreen());
      await tester.enterText(field('Total price'), '60000');
      await tester.enterText(field('Interest (% a year)'), '12');
      await tester.enterText(field('Months'), '12');
      await tester.pumpAndSettle();
      expect(find.text('Monthly EMI'), findsOneWidget);
      expect(find.text('₹5,330.93'), findsOneWidget);
      expect(find.text('₹3,971.13'), findsOneWidget); // total interest
      expect(find.text('₹63,971.13'), findsOneWidget); // total payable
    });

    testWidgets('a down payment lowers the EMI', (tester) async {
      await pumpScreen(tester, const AddEmiScreen());
      await tester.enterText(field('Total price'), '12000');
      await tester.enterText(field('Months'), '4');
      await tester.pumpAndSettle();
      expect(find.text('₹3,000'), findsWidgets); // 12,000 / 4 at 0%
      await tester.enterText(field('Down payment (optional)'), '6000');
      await tester.pumpAndSettle();
      expect(find.text('₹1,500'), findsWidgets); // 6,000 / 4
    });

    testWidgets('bad terms show a clear message instead of a preview', (
      tester,
    ) async {
      await pumpScreen(tester, const AddEmiScreen());
      await tester.enterText(field('Total price'), '1000');
      await tester.enterText(field('Down payment (optional)'), '1000');
      await tester.enterText(field('Months'), '6');
      await tester.pumpAndSettle();
      expect(
        find.text('Down payment must be 0 or more and less than the price'),
        findsOneWidget,
      );
      expect(find.text('Monthly EMI'), findsNothing);
    });

    testWidgets('saving needs a product and a store or bank', (tester) async {
      await pumpScreen(tester, const AddEmiScreen());
      await tester.enterText(field('Total price'), '12000');
      await tester.enterText(field('Months'), '4');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter what you bought'), findsOneWidget);
      expect(find.text('Choose or add the store or bank'), findsOneWidget);
      expect(
        (await db.collection('users/u1/transactions').get()).docs,
        isEmpty,
      );
    });

    testWidgets('saves the purchase and opens its schedule', (tester) async {
      await pumpScreen(tester, const AddEmiScreen());
      await tester.enterText(field('Product'), 'Phone');
      await tester.enterText(field('Store or bank'), 'Croma');
      await tester.pumpAndSettle();
      await tester.tap(find.text("Add 'Croma' as new person"));
      await tester.pumpAndSettle();
      await tester.enterText(field('Total price'), '12000');
      await tester.enterText(field('Months'), '4');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('EMI summary'), findsOneWidget);
      expect(find.text('Pay next EMI'), findsOneWidget);
      final doc = (await db.collection('users/u1/transactions').get())
          .docs
          .single
          .data();
      expect(doc['type'], 'emi');
      expect(doc['title'], 'Phone');
      expect(doc['personName'], 'Croma');
      expect(doc['totalAmount'], 1200000);
      expect((doc['schedule'] as List).length, 4);
      expect((await db.collection('users/u1/people').get()).docs.length, 1);
    });
  });

  group('Schedule screen', () {
    testWidgets('shows the summary card and every instalment as upcoming', (
      tester,
    ) async {
      final id = await seedEmi();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      expect(find.text('EMI summary'), findsOneWidget);
      expect(find.text('₹3,000 on 15 Jan 2030'), findsOneWidget); // next EMI
      expect(find.text('4 of 4'), findsOneWidget); // remaining EMIs
      expect(find.text('₹12,000'), findsWidgets); // remaining total
      expect(find.text('15 Apr 2030'), findsWidgets); // last EMI
      expect(find.textContaining('No-cost EMI'), findsOneWidget);
      for (var n = 1; n <= 4; n++) {
        expect(dotColor(tester, n), amber, reason: 'row $n');
      }
      expect(find.text('Upcoming'), findsNWidgets(4));
    });

    testWidgets('instalments past their date are red and counted as overdue', (
      tester,
    ) async {
      final id = await seedEmi(start: DateTime(2024, 1, 15));
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      for (var n = 1; n <= 4; n++) {
        expect(dotColor(tester, n), red, reason: 'row $n');
      }
      expect(find.text('4 overdue · ₹12,000'), findsOneWidget);
    });

    testWidgets('paying the next EMI turns its dot green and moves on', (
      tester,
    ) async {
      final id = await seedEmi();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.text('Pay next EMI'));
      await tester.pumpAndSettle();
      expect(find.text('Pay EMI #1'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('Amount')).controller!.text,
        '3000', // what is left on the row
      );
      await tester.tap(find.text('UPI'));
      await tester.enterText(field('Note (optional)'), 'first');
      await tester.tap(find.text('Mark EMI paid'));
      await tester.pumpAndSettle();

      expect(dotColor(tester, 1), green);
      expect(dotColor(tester, 2), amber);
      expect(find.text('₹3,000 on 15 Feb 2030'), findsOneWidget); // next EMI
      expect(find.text('3 of 4'), findsOneWidget);
      expect(find.text('Partially Paid'), findsOneWidget);
      final pay =
          (await db.collection('users/u1/transactions/$id/payments').get())
              .docs
              .single
              .data();
      expect(pay['installment'], 1);
      expect(pay['mode'], 'upi');
      expect(pay['note'], 'first');
    });

    testWidgets('a part payment shows blue and keeps the row open', (
      tester,
    ) async {
      final id = await seedEmi();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.text('Pay next EMI'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount'), '1000');
      await tester.tap(find.text('Mark EMI paid'));
      await tester.pumpAndSettle();
      expect(dotColor(tester, 1), blue);
      expect(find.text('Part paid'), findsOneWidget);
      expect(find.textContaining('Paid ₹1,000 of ₹3,000'), findsOneWidget);
      expect(find.text('4 of 4'), findsOneWidget); // still remaining
      expect(find.text('₹11,000'), findsWidgets); // remaining total
    });

    testWidgets('paying more than is left on the EMI is blocked', (
      tester,
    ) async {
      final id = await seedEmi();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.text('Pay next EMI'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount'), '3500');
      await tester.tap(find.text('Mark EMI paid'));
      await tester.pumpAndSettle();
      expect(
        find.text('Cannot be more than what is left on this EMI (₹3,000)'),
        findsOneWidget,
      );
      expect(
        (await db.collection('users/u1/transactions/$id/payments').get()).docs,
        isEmpty,
      );
    });

    testWidgets('tapping an unpaid row pays that instalment', (tester) async {
      final id = await seedEmi();
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tester.ensureVisible(find.textContaining('#3 ·'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('#3 ·'));
      await tester.pumpAndSettle();
      expect(find.text('Pay EMI #3'), findsOneWidget);
      await tester.tap(find.text('Mark EMI paid'));
      await tester.pumpAndSettle();
      expect(dotColor(tester, 3), green);
      expect(dotColor(tester, 1), amber);
      expect(find.text('₹3,000 on 15 Jan 2030'), findsOneWidget); // still row 1
    });

    testWidgets('a paid row cannot be paid again', (tester) async {
      final id = await seedEmi();
      await payments.payInstallment(
        id,
        1,
        amount: Money.fromRupees(3000),
        date: DateTime(2026, 10, 1),
        mode: PaymentMode.cash,
      );
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      await tester.tap(find.textContaining('#1 ·'));
      await tester.pumpAndSettle();
      expect(find.text('Pay EMI #1'), findsNothing);
    });

    testWidgets('deleting the payment from the list restores the instalment', (
      tester,
    ) async {
      final id = await seedEmi();
      await payments.payInstallment(
        id,
        1,
        amount: Money.fromRupees(3000),
        date: DateTime(2026, 10, 1),
        mode: PaymentMode.cash,
      );
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      expect(dotColor(tester, 1), green);
      await tester.scrollUntilVisible(
        find.byIcon(Icons.edit),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(dotColor(tester, 1), amber);
      expect(find.text('4 of 4'), findsOneWidget);
    });

    testWidgets('paying every EMI settles it and offers Mark as unpaid', (
      tester,
    ) async {
      final id = await seedEmi();
      for (var n = 1; n <= 4; n++) {
        await payments.payInstallment(
          id,
          n,
          amount: Money.fromRupees(3000),
          date: DateTime(2026, 10, n),
          mode: PaymentMode.cash,
        );
      }
      await pumpScreen(tester, EntryDetailScreen(transactionId: id));
      expect(find.text('All paid'), findsOneWidget);
      expect(find.text('0 of 4'), findsOneWidget);
      expect(find.text('Paid'), findsWidgets);
      expect(find.text('Pay next EMI'), findsNothing);
      expect(find.text('Mark as unpaid'), findsOneWidget);
    });
  });
}
