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
import 'package:money_manager/transactions/entry_detail_screen.dart';

void main() {
  late FakeFirebaseFirestore db;
  late TransactionRepository txns;

  setUp(() {
    db = FakeFirebaseFirestore();
    txns = TransactionRepository(db, 'u1');
  });

  Future<void> pump(WidgetTester tester, String id) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peopleRepositoryProvider.overrideWithValue(
            PeopleRepository(db, 'u1'),
          ),
          transactionRepositoryProvider.overrideWithValue(txns),
          paymentRepositoryProvider.overrideWithValue(
            PaymentRepository(db, 'u1'),
          ),
        ],
        child: MaterialApp(home: EntryDetailScreen(transactionId: id)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String> seed({DateTime? due}) async {
    final p = await PeopleRepository(
      db,
      'u1',
    ).add(Person(name: 'Asha', createdAt: DateTime(2026, 1, 1)));
    return txns.add(
      MoneyTransaction(
        type: TransactionType.lent,
        personId: p,
        personName: 'Asha',
        title: 'Loan',
        totalAmount: Money.fromRupees(1000),
        dueDate: due,
        createdAt: DateTime(2026, 1, 1),
      ),
    );
  }

  Future<bool?> stored(String id) async =>
      (await db.collection('users/u1/transactions').doc(id).get())
              .data()!['autoReminders']
          as bool?;

  testWidgets('the switch is on by default and turning it off saves it', (
    tester,
  ) async {
    final id = await seed(due: DateTime(2030, 1, 10));
    await pump(tester, id);
    final tile = find.widgetWithText(
      SwitchListTile,
      'Remind me about due dates',
    );
    await tester.ensureVisible(tile);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(await stored(id), false);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(await stored(id), true);
  });

  testWidgets('no switch when there is no due date', (tester) async {
    final id = await seed();
    await pump(tester, id);
    expect(find.text('Remind me about due dates'), findsNothing);
  });

  testWidgets('no switch once the entry is paid', (tester) async {
    final id = await seed(due: DateTime(2030, 1, 10));
    await PaymentRepository(db, 'u1').add(
      id,
      Payment(
        amount: Money.fromRupees(1000),
        date: DateTime(2030, 1, 1),
        mode: PaymentMode.cash,
        createdAt: DateTime(2030, 1, 1),
      ),
    );
    await pump(tester, id);
    expect(find.text('Remind me about due dates'), findsNothing);
  });
}
