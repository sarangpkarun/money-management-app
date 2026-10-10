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
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/models/reminder.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/reminders/alarm_providers.dart';
import 'package:money_manager/reminders/reminders_screen.dart';

import '../support/fake_alarm_gateway.dart';
import '../support/fake_settings_opener.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ReminderRepository repo;
  late TransactionRepository txns;
  late FakeAlarmGateway gateway;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = ReminderRepository(db, 'u1');
    txns = TransactionRepository(db, 'u1');
    gateway = FakeAlarmGateway();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alarmGatewayProvider.overrideWithValue(gateway),
          settingsOpenerProvider.overrideWithValue(FakeSettingsOpener()),
          reminderRepositoryProvider.overrideWithValue(repo),
          peopleRepositoryProvider.overrideWithValue(
            PeopleRepository(db, 'u1'),
          ),
          transactionRepositoryProvider.overrideWithValue(txns),
          paymentRepositoryProvider.overrideWithValue(
            PaymentRepository(db, 'u1'),
          ),
        ],
        child: const MaterialApp(home: RemindersScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Reminder rem(String t, DateTime at, {bool done = false}) => Reminder(
    title: t,
    at: at,
    done: done,
    doneAt: done ? DateTime(2030, 1, 2) : null,
    createdAt: DateTime(2026, 1, 1),
  );

  Future<bool> isDone(String title) async {
    final d = (await db.collection('users/u1/reminders').get()).docs.firstWhere(
      (x) => x.data()['title'] == title,
    );
    return d.data()['done'] as bool;
  }

  Future<void> goTo(WidgetTester tester, String tab) async {
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
  }

  group('Missed', () {
    testWidgets('Mark done moves it to Completed', (tester) async {
      await repo.add(rem('Old', DateTime(2020, 1, 1, 9)));
      await pump(tester);
      await goTo(tester, 'Missed (1)');
      await tester.tap(find.text('Mark done'));
      await tester.pumpAndSettle();
      expect(await isDone('Old'), isTrue);
      expect(find.text('Old'), findsNothing);
      expect(find.text('Missed'), findsOneWidget); // count gone
      await goTo(tester, 'Completed');
      expect(find.text('Old'), findsOneWidget);
    });

    testWidgets('tapping a missed reminder opens it to reschedule', (
      tester,
    ) async {
      await repo.add(rem('Old', DateTime(2020, 1, 1, 9)));
      await pump(tester);
      await goTo(tester, 'Missed (1)');
      await tester.tap(find.text('Old'));
      await tester.pumpAndSettle();
      expect(find.text('Edit reminder'), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      await pump(tester);
      await goTo(tester, 'Missed');
      expect(find.text('No missed reminders'), findsOneWidget);
    });

    testWidgets('a repeating reminder is never missed', (tester) async {
      await repo.add(
        Reminder(
          title: 'Daily',
          at: DateTime(2020, 1, 1, 9),
          repeat: const RepeatRule.daily(),
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      await pump(tester);
      expect(find.text('Missed'), findsOneWidget);
      expect(find.text('Daily'), findsOneWidget); // Upcoming
    });
  });

  group('Completed', () {
    testWidgets('Reopen brings it back to Upcoming', (tester) async {
      await repo.add(rem('Task', DateTime(2099, 1, 1, 9), done: true));
      await pump(tester);
      await goTo(tester, 'Completed');
      await tester.tap(find.text('Reopen'));
      await tester.pumpAndSettle();
      expect(await isDone('Task'), isFalse);
      expect(find.text('Task'), findsNothing);
      await goTo(tester, 'Upcoming');
      expect(find.text('Task'), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      await pump(tester);
      await goTo(tester, 'Completed');
      expect(find.text('Finished reminders appear here'), findsOneWidget);
    });
  });

  group('Upcoming automatic payment alarms', () {
    Future<String> dueEntry() async {
      final pid = await PeopleRepository(
        db,
        'u1',
      ).add(Person(name: 'Asha', createdAt: DateTime(2026, 1, 1)));
      return txns.add(
        MoneyTransaction(
          type: TransactionType.lent,
          personId: pid,
          personName: 'Asha',
          title: 'Loan',
          totalAmount: Money.fromRupees(500),
          dueDate: DateTime.now().add(const Duration(days: 5)),
          createdAt: DateTime.now(),
        ),
      );
    }

    testWidgets('are listed, labelled automatic, and open their entry', (
      tester,
    ) async {
      await dueEntry();
      await pump(tester);
      expect(find.textContaining('Collect ₹500 from Asha'), findsWidgets);
      expect(find.textContaining('Automatic payment alarm'), findsWidgets);
      await tester.tap(find.textContaining('Collect ₹500 from Asha').first);
      await tester.pumpAndSettle();
      expect(find.text('Asha'), findsWidgets);
      expect(find.text('Remind me about due dates'), findsOneWidget);
    });

    testWidgets('switching them off removes them from the list', (
      tester,
    ) async {
      final id = await dueEntry();
      await pump(tester);
      expect(find.textContaining('Automatic payment alarm'), findsWidgets);
      await txns.setAutoReminders(id, false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Automatic payment alarm'), findsNothing);
    });

    testWidgets('they appear alongside manual reminders in time order', (
      tester,
    ) async {
      await dueEntry();
      await repo.add(rem('Soon', DateTime.now().add(const Duration(hours: 5))));
      await pump(tester);
      final soon = tester.getTopLeft(find.text('Soon')).dy;
      final auto = tester
          .getTopLeft(find.textContaining('Collect ₹500 from Asha').first)
          .dy;
      expect(soon < auto, isTrue);
    });
  });

  group('permission banner', () {
    testWidgets('How to fix opens the help screen', (tester) async {
      gateway.allowed = false;
      await pump(tester);
      expect(find.textContaining('Alarms are off'), findsOneWidget);
      await tester.tap(find.text('How to fix'));
      await tester.pumpAndSettle();
      expect(find.text('Alarm and notification help'), findsOneWidget);
    });

    testWidgets('the help icon opens it even when alarms work', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Alarm and notification help'));
      await tester.pumpAndSettle();
      expect(find.text('Alarm and notification help'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
    });
  });
}
