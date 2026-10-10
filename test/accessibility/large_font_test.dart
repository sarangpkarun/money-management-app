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
import 'package:money_manager/core/data/reminder_repository.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/data/user_repository.dart';
import 'package:money_manager/core/models/app_user.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/models/reminder.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/theme/app_theme.dart';
import 'package:money_manager/home/home_screen.dart';
import 'package:money_manager/people/people_screen.dart';
import 'package:money_manager/reminders/alarm_providers.dart';
import 'package:money_manager/reminders/reminder_form_screen.dart';
import 'package:money_manager/reminders/reminders_screen.dart';
import 'package:money_manager/settings/settings_screen.dart';
import 'package:money_manager/transactions/add_entry_screen.dart';
import 'package:money_manager/transactions/entries_screen.dart';
import 'package:money_manager/transactions/entry_detail_screen.dart';

import '../support/fake_alarm_gateway.dart';

void main() {
  late FakeFirebaseFirestore db;
  late String loanId;

  setUp(() async {
    db = FakeFirebaseFirestore();
    await UserRepository(db, 'u1').save(const AppUser(name: 'Sarang Kumar'));
    final people = PeopleRepository(db, 'u1');
    final txns = TransactionRepository(db, 'u1');
    final a = await people.add(
      Person(
        name: 'Ravichandran Venkataraghavan',
        phone: '9876543210',
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    loanId = await txns.add(
      MoneyTransaction(
        type: TransactionType.lent,
        personId: a,
        personName: 'Ravichandran Venkataraghavan',
        title: 'Bike repair and a long description of the loan',
        totalAmount: Money.fromRupees(123456),
        dueDate: DateTime.now().subtract(const Duration(days: 4)),
        createdAt: DateTime(2026, 9, 1),
      ),
    );
    await txns.add(
      MoneyTransaction(
        type: TransactionType.borrowed,
        personId: a,
        personName: 'Ravichandran Venkataraghavan',
        title: 'Rent',
        totalAmount: Money.fromRupees(5000),
        dueDate: DateTime.now().add(const Duration(days: 2)),
        createdAt: DateTime(2026, 9, 2),
      ),
    );
    await ReminderRepository(db, 'u1').add(
      Reminder(
        title: 'Call the landlord about the deposit and the agreement',
        at: DateTime.now().add(const Duration(days: 1)),
        repeat: const RepeatRule.daily(),
        createdAt: DateTime(2026, 1, 1),
      ),
    );
  });

  Future<void> pump(
    WidgetTester tester,
    Widget Function() screen, {
    required double scale,
    required ThemeMode mode,
  }) async {
    tester.view.physicalSize = const Size(360, 740); // a small phone
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'u1', email: 'a@b.com', displayName: 'Sarang'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peopleRepositoryProvider.overrideWithValue(
            PeopleRepository(db, 'u1'),
          ),
          transactionRepositoryProvider.overrideWithValue(
            TransactionRepository(db, 'u1'),
          ),
          paymentRepositoryProvider.overrideWithValue(
            PaymentRepository(db, 'u1'),
          ),
          reminderRepositoryProvider.overrideWithValue(
            ReminderRepository(db, 'u1'),
          ),
          userRepositoryProvider.overrideWithValue(UserRepository(db, 'u1')),
          authRepositoryProvider.overrideWithValue(AuthRepository(auth, db)),
          alarmGatewayProvider.overrideWithValue(FakeAlarmGateway()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: screen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final screens = <String, Widget Function(String loanId)>{
    'Home': (_) => const HomeScreen(),
    'People': (_) => const PeopleScreen(),
    'Entries': (_) => const EntriesScreen(),
    'Entry detail': (id) => EntryDetailScreen(transactionId: id),
    'Add entry': (_) => const AddEntryScreen(),
    'Reminders': (_) => const RemindersScreen(),
    'New reminder': (_) => const ReminderFormScreen(),
    'Settings': (_) => const SettingsScreen(),
  };

  for (final scale in [1.5, 2.0]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final e in screens.entries) {
        testWidgets('${e.key} at ${scale}x text, ${mode.name}: no overflow', (
          tester,
        ) async {
          await pump(tester, () => e.value(loanId), scale: scale, mode: mode);
          // A RenderFlex overflow or any other build error fails the test.
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} meets guidelines, ${mode.name}', (tester) async {
        final handle = tester.ensureSemantics();
        await pump(tester, () => e.value(loanId), scale: 1.0, mode: mode);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }
}
