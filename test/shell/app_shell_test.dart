import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/auth/auth_providers.dart';
import 'package:money_manager/auth/auth_repository.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/models/reminder.dart';
import 'package:money_manager/core/data/reminder_repository.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/data/user_repository.dart';
import 'package:money_manager/core/models/app_user.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/theme/app_theme.dart';
import 'package:money_manager/reminders/alarm_providers.dart';
import 'package:money_manager/shell/app_shell.dart';

import '../support/fake_alarm_gateway.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late PeopleRepository people;
  late TransactionRepository txns;
  late FakeAlarmGateway gateway;

  setUp(() async {
    gateway = FakeAlarmGateway();
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'u1', email: 'a@b.com', displayName: 'Sarang'),
    );
    people = PeopleRepository(db, 'u1');
    txns = TransactionRepository(db, 'u1');
    await UserRepository(db, 'u1').save(const AppUser(name: 'Sarang'));
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    ThemeData? theme,
    ThemeMode mode = ThemeMode.light,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peopleRepositoryProvider.overrideWithValue(people),
          alarmGatewayProvider.overrideWithValue(gateway),
          reminderRepositoryProvider.overrideWithValue(
            ReminderRepository(db, 'u1'),
          ),
          transactionRepositoryProvider.overrideWithValue(txns),
          paymentRepositoryProvider.overrideWithValue(
            PaymentRepository(db, 'u1'),
          ),
          userRepositoryProvider.overrideWithValue(UserRepository(db, 'u1')),
          authRepositoryProvider.overrideWithValue(AuthRepository(auth, db)),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String> entry(
    String name,
    TransactionType type,
    int rupees, {
    DateTime? due,
    String title = 'Loan',
  }) async {
    final personId = await people.add(
      Person(name: name, createdAt: DateTime(2026, 1, 1)),
    );
    return txns.add(
      MoneyTransaction(
        type: type,
        personId: personId,
        personName: name,
        title: title,
        totalAmount: Money.fromRupees(rupees),
        dueDate: due,
        createdAt: DateTime(2026, 9, 1),
        date: DateTime(2026, 9, 1),
      ),
    );
  }

  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  group('navigation', () {
    testWidgets('has the five destinations and starts on Home', (tester) async {
      await pumpShell(tester);
      for (final label in ['Home', 'People', 'Add', 'Reminders', 'Settings']) {
        expect(tab(label), findsOneWidget, reason: label);
      }
      expect(find.text('Hello, Sarang'), findsOneWidget);
    });

    testWidgets('switches between tabs', (tester) async {
      await pumpShell(tester);
      await tester.tap(tab('People'));
      await tester.pumpAndSettle();
      expect(find.text('No people yet'), findsOneWidget);

      await tester.tap(tab('Reminders'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing coming up'), findsOneWidget);

      await tester.tap(tab('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Log out'), findsOneWidget);

      await tester.tap(tab('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Hello, Sarang'), findsOneWidget);
    });

    testWidgets('tabs keep their state when you switch away and back', (
      tester,
    ) async {
      await entry('Asha', TransactionType.lent, 100);
      await entry('Ravi', TransactionType.lent, 100);
      await pumpShell(tester);
      await tester.tap(tab('People'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search name or phone'),
        'rav',
      );
      await tester.pumpAndSettle();
      expect(find.text('Asha'), findsNothing);

      await tester.tap(tab('Home'));
      await tester.pumpAndSettle();
      await tester.tap(tab('People'));
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.widgetWithText(TextField, 'Search name or phone'),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.controller.text, 'rav');
      expect(find.text('Asha'), findsNothing);
    });
  });

  group('the + button', () {
    testWidgets('opens the add sheet without leaving the current tab', (
      tester,
    ) async {
      await pumpShell(tester);
      await tester.tap(tab('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Add new entry'), findsOneWidget);
      expect(find.text('Money I gave'), findsOneWidget);
      expect(find.text('Money I borrowed'), findsOneWidget);
      // Home is still the tab underneath.
      expect(find.text('Hello, Sarang'), findsOneWidget);
    });

    testWidgets('"EMI purchase" opens the EMI form', (tester) async {
      await pumpShell(tester);
      await tester.tap(tab('Add'));
      await tester.pumpAndSettle();
      expect(find.text('EMI purchase'), findsOneWidget);
      await tester.tap(find.text('EMI purchase'));
      await tester.pumpAndSettle();
      expect(find.text('Monthly EMI'), findsNothing); // no preview yet
      expect(find.text('Total price'), findsOneWidget);
      expect(find.text('Store or bank'), findsOneWidget);
    });

    testWidgets('"Pay in instalments" opens the instalment form', (
      tester,
    ) async {
      await pumpShell(tester);
      await tester.tap(tab('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay in instalments'));
      await tester.pumpAndSettle();
      expect(find.text('Person you owe'), findsOneWidget);
    });

    testWidgets('"Reminder" opens the reminder form', (tester) async {
      await pumpShell(tester);
      await tester.tap(tab('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reminder').last);
      await tester.pumpAndSettle();
      expect(find.text('New reminder'), findsOneWidget);
    });

    testWidgets('"Money I gave" opens Add entry on Lent', (tester) async {
      await pumpShell(tester);
      await tester.tap(tab('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Money I gave'));
      await tester.pumpAndSettle();
      expect(find.text('Add entry'), findsOneWidget);
      expect(find.text('Interest'), findsNothing); // only for Borrowed
    });

    testWidgets('"Money I borrowed" opens Add entry on Borrowed', (
      tester,
    ) async {
      await pumpShell(tester);
      await tester.tap(tab('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Money I borrowed'));
      await tester.pumpAndSettle();
      expect(find.text('Add entry'), findsOneWidget);
      expect(find.text('Interest'), findsOneWidget);
    });
  });

  group('Home', () {
    testWidgets('shows to receive, to pay and the net', (tester) async {
      await entry('Asha', TransactionType.lent, 1000);
      await entry('Ravi', TransactionType.borrowed, 200);
      await pumpShell(tester);
      expect(find.text('₹1,000'), findsOneWidget); // to receive
      expect(find.text('₹200'), findsOneWidget); // to pay
      expect(find.text('₹800'), findsOneWidget); // net
      expect(find.text('You are owed overall'), findsOneWidget);
      expect(find.textContaining('overdue'), findsNothing);
    });

    testWidgets('a negative net is shown with a minus and "You owe"', (
      tester,
    ) async {
      await entry('Ravi', TransactionType.borrowed, 500);
      await pumpShell(tester);
      expect(find.text('-₹500'), findsOneWidget);
      expect(find.text('You owe overall'), findsOneWidget);
    });

    testWidgets('shows a red strip for overdue entries and opens Entries', (
      tester,
    ) async {
      await entry('Asha', TransactionType.lent, 300, due: DateTime(2026, 1, 1));
      await pumpShell(tester);
      expect(find.text('1 overdue entry · ₹300'), findsOneWidget);
      await tester.tap(find.text('1 overdue entry · ₹300'));
      await tester.pumpAndSettle();
      expect(find.text('Entries'), findsOneWidget);
    });

    testWidgets('lists recent entries and See all opens the full list', (
      tester,
    ) async {
      await entry('Asha', TransactionType.lent, 1000, title: 'Phone');
      await pumpShell(tester);
      expect(find.text('Asha · Phone'), findsOneWidget);
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.text('Entries'), findsOneWidget);
    });

    testWidgets('an empty Home invites the first entry', (tester) async {
      await pumpShell(tester);
      expect(find.text('No entries yet'), findsOneWidget);
      expect(find.text('See all'), findsNothing);
      await tester.tap(find.text('Add your first entry'));
      await tester.pumpAndSettle();
      expect(find.text('Add entry'), findsOneWidget);
    });

    testWidgets('the profile icon opens Profile', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Delete account'), findsOneWidget);
    });
  });

  group('Settings', () {
    Future<void> openSettings(WidgetTester tester) async {
      await pumpShell(tester);
      await tester.tap(tab('Settings'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists its rows', (tester) async {
      await openSettings(tester);
      for (final t in [
        'Profile',
        'History',
        'All entries',
        'Alarm and notification help',
        'Alarm test (developer)',
        'About',
        'Log out',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('Alarm and notification help opens', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Alarm and notification help'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('History and Profile open', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('History').first);
      await tester.pumpAndSettle();
      expect(find.text('No settled entries yet'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Delete account'), findsOneWidget);
    });

    testWidgets('Log out asks first, and cancelling keeps you signed in', (
      tester,
    ) async {
      await openSettings(tester);
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Log out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.currentUser, isNotNull);
    });

    testWidgets('logging out removes this account\'s alarms from the phone', (
      tester,
    ) async {
      await ReminderRepository(db, 'u1').add(
        Reminder(
          title: 'Rent',
          at: DateTime.now().add(const Duration(days: 1)),
          createdAt: DateTime.now(),
        ),
      );
      await openSettings(tester);
      expect(gateway.scheduled, isNotEmpty);
      gateway.foreign[9] = 'not ours';
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Log out'));
      await tester.pumpAndSettle();
      expect(gateway.scheduled, isEmpty);
      expect(gateway.foreign.keys, [9]);
    });

    testWidgets('confirming Log out signs you out', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Log out'));
      await tester.pumpAndSettle();
      expect(auth.currentUser, isNull);
    });
  });

  group('payment alarms', () {
    Future<String> dueEntry() async {
      final id = await people.add(
        Person(name: 'Asha', createdAt: DateTime(2026, 1, 1)),
      );
      return txns.add(
        MoneyTransaction(
          type: TransactionType.lent,
          personId: id,
          personName: 'Asha',
          title: 'Loan',
          totalAmount: Money.fromRupees(1000),
          dueDate: DateTime.now().add(const Duration(days: 10)),
          createdAt: DateTime.now(),
        ),
      );
    }

    testWidgets('an entry with a due date is scheduled, three alarms', (
      tester,
    ) async {
      await dueEntry();
      await pumpShell(tester);
      expect(gateway.scheduled.length, 3);
      expect(
        gateway.scheduled.values.every((a) => a.payload.entryId != null),
        isTrue,
      );
    });

    testWidgets('turning the switch off removes the alarms', (tester) async {
      final id = await dueEntry();
      await pumpShell(tester);
      expect(gateway.scheduled.length, 3);
      await txns.setAutoReminders(id, false);
      await tester.pumpAndSettle();
      expect(gateway.scheduled, isEmpty);
      await txns.setAutoReminders(id, true);
      await tester.pumpAndSettle();
      expect(gateway.scheduled.length, 3);
    });

    testWidgets('deleting the entry removes them', (tester) async {
      final id = await dueEntry();
      await pumpShell(tester);
      await txns.delete(id);
      await tester.pumpAndSettle();
      expect(gateway.scheduled, isEmpty);
    });
  });

  group('alarms', () {
    testWidgets('a reminder in the database is scheduled when the app opens', (
      tester,
    ) async {
      await ReminderRepository(db, 'u1').add(
        Reminder(
          title: 'Pay rent',
          at: DateTime.now().add(const Duration(days: 1)),
          createdAt: DateTime.now(),
        ),
      );
      await pumpShell(tester);
      expect(gateway.scheduled.length, 1);
      expect(gateway.scheduled.values.single.payload.title, 'Pay rent');
    });

    testWidgets('adding, editing and deleting reminders keeps alarms in step', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(gateway.scheduled, isEmpty);
      final repo = ReminderRepository(db, 'u1');
      final id = await repo.add(
        Reminder(
          title: 'One',
          at: DateTime.now().add(const Duration(days: 1)),
          createdAt: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway.scheduled.length, 1);
      await db.collection('users/u1/reminders').doc(id).update({
        'title': 'Renamed',
      });
      await tester.pumpAndSettle();
      expect(gateway.scheduled.values.single.payload.title, 'Renamed');
      await repo.delete(id);
      await tester.pumpAndSettle();
      expect(gateway.scheduled, isEmpty);
    });
  });

  testWidgets('renders in the dark theme', (tester) async {
    await entry('Asha', TransactionType.lent, 1000);
    await pumpShell(tester, theme: AppTheme.dark, mode: ThemeMode.dark);
    expect(find.text('Hello, Sarang'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(
      Theme.of(tester.element(find.byType(NavigationBar))).brightness,
      Brightness.dark,
    );
    expect(scaffold, isNotNull);
  });
}
