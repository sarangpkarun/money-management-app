import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/reminder_repository.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/data/user_repository.dart';
import 'package:money_manager/core/models/app_settings.dart';
import 'package:money_manager/core/models/app_user.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/reminders/alarm_providers.dart';
import 'package:money_manager/settings/settings_extras_providers.dart';
import 'package:money_manager/settings/settings_screen.dart';

import '../support/fake_alarm_gateway.dart';
import '../support/fake_backup_sharer.dart';

void main() {
  late FakeFirebaseFirestore db;
  late UserRepository users;
  late FakeBackupSharer sharer;

  setUp(() async {
    db = FakeFirebaseFirestore();
    users = UserRepository(db, 'u1');
    sharer = FakeBackupSharer();
    await users.save(const AppUser(name: 'Sarang'));
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userRepositoryProvider.overrideWithValue(users),
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
          alarmGatewayProvider.overrideWithValue(FakeAlarmGateway()),
          backupSharerProvider.overrideWithValue(sharer),
          appVersionProvider.overrideWith((ref) async => '1.2.3 (45)'),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<AppUser> saved() async => (await users.get())!;

  Future<void> choose(WidgetTester tester, String tile, String option) async {
    await tester.tap(find.text(tile));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option));
    await tester.pumpAndSettle();
  }

  group('labels', () {
    test('minutesLabel', () {
      expect(minutesLabel(9 * 60), '9:00 am');
      expect(minutesLabel(0), '12:00 am');
      expect(minutesLabel(12 * 60), '12:00 pm');
      expect(minutesLabel(19 * 60 + 5), '7:05 pm');
    });

    test('summaryLabel', () {
      expect(summaryLabel(const SummarySettings()), 'Off');
      expect(
        summaryLabel(
          const SummarySettings(mode: SummaryMode.daily, minutes: 8 * 60),
        ),
        'Daily at 8:00 am',
      );
      expect(
        summaryLabel(
          const SummarySettings(
            mode: SummaryMode.weekly,
            minutes: 18 * 60 + 30,
            weekday: DateTime.sunday,
          ),
        ),
        'Weekly on Sunday at 6:30 pm',
      );
    });
  });

  group('Display', () {
    testWidgets('currency is saved without touching the name or settings', (
      tester,
    ) async {
      await users.saveSettings(const AppSettings(theme: ThemeChoice.dark));
      await pump(tester);
      expect(find.text('INR ₹'), findsOneWidget);
      await choose(tester, 'Currency', 'USD  \$');
      final u = await saved();
      expect(u.currency, 'USD');
      expect(u.name, 'Sarang');
      expect(u.settings.theme, ThemeChoice.dark);
      expect(find.text('USD \$'), findsOneWidget);
    });

    testWidgets('number format: Western, Indian, then Automatic', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Automatic (indian)'), findsOneWidget);
      await choose(tester, 'Number format', 'Western (1,234,567)');
      expect((await saved()).settings.grouping, NumberGrouping.western);
      await choose(tester, 'Number format', 'Indian (12,34,567)');
      expect((await saved()).settings.grouping, NumberGrouping.indian);
      await choose(tester, 'Number format', 'Automatic (by currency)');
      expect((await saved()).settings.grouping, isNull);
    });

    testWidgets('date format shows examples and saves the choice', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Date format'));
      await tester.pumpAndSettle();
      expect(find.text('9 Oct 2026'), findsOneWidget);
      expect(find.text('09/10/2026'), findsOneWidget);
      expect(find.text('10/09/2026'), findsOneWidget);
      await tester.tap(find.text('10/09/2026'));
      await tester.pumpAndSettle();
      expect((await saved()).settings.dateStyle, DateStyle.mdy);
    });

    testWidgets('theme', (tester) async {
      await pump(tester);
      expect(find.text('Same as the phone'), findsOneWidget);
      await choose(tester, 'Theme', 'Dark');
      expect((await saved()).settings.theme, ThemeChoice.dark);
      expect(find.text('Dark'), findsOneWidget);
      await choose(tester, 'Theme', 'Light');
      expect((await saved()).settings.theme, ThemeChoice.light);
    });

    testWidgets('cancelling a choice changes nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5)); // outside the dialog
      await tester.pumpAndSettle();
      expect((await saved()).settings.theme, ThemeChoice.system);
    });
  });

  group('Reminders', () {
    testWidgets('payment alarm time shows the setting and Cancel keeps it', (
      tester,
    ) async {
      await users.saveSettings(
        const AppSettings(autoAlarmMinutes: 7 * 60 + 30),
      );
      await pump(tester);
      expect(find.textContaining('7:30 am'), findsOneWidget);
      await tester.tap(find.text('Payment alarm time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await saved()).settings.autoAlarmMinutes, 7 * 60 + 30);
    });

    testWidgets('payment alarm time: OK saves the picked time', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Payment alarm time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect((await saved()).settings.autoAlarmMinutes, 9 * 60);
    });

    testWidgets('quiet hours: switch on shows From and Until, off hides them', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('From'), findsNothing);
      await tester.tap(find.text('Quiet hours'));
      await tester.pumpAndSettle();
      expect((await saved()).settings.quietHours.enabled, isTrue);
      expect(find.text('From'), findsOneWidget);
      expect(find.text('10:00 pm'), findsOneWidget);
      expect(find.text('7:00 am'), findsOneWidget);
      await tester.tap(find.text('Quiet hours'));
      await tester.pumpAndSettle();
      expect((await saved()).settings.quietHours.enabled, isFalse);
      expect(find.text('From'), findsNothing);
    });

    testWidgets('quiet hours explains that your own reminders still ring', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.textContaining('Reminders you set yourself still ring on time'),
        findsOneWidget,
      );
    });

    testWidgets('quiet hours times can be changed with OK', (tester) async {
      await users.saveSettings(
        const AppSettings(
          quietHours: QuietHours(
            enabled: true,
            startMinutes: 23 * 60,
            endMinutes: 6 * 60,
          ),
        ),
      );
      await pump(tester);
      await tester.tap(find.text('From'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect((await saved()).settings.quietHours.startMinutes, 23 * 60);
      expect((await saved()).settings.quietHours.endMinutes, 6 * 60);
    });

    testWidgets('summary: weekly on Friday is saved', (tester) async {
      await pump(tester);
      expect(find.text('Off'), findsOneWidget);
      await tester.tap(find.text('Daily or weekly summary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Fri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final s = (await saved()).settings.summary;
      expect(s.mode, SummaryMode.weekly);
      expect(s.weekday, DateTime.friday);
      expect(find.text('Weekly on Friday at 8:00 am'), findsOneWidget);
    });

    testWidgets('summary: daily, then off', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Daily or weekly summary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily'));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(3)); // no weekday chips
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((await saved()).settings.summary.mode, SummaryMode.daily);
      await tester.tap(find.text('Daily or weekly summary'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Off'));
      await tester.pumpAndSettle();
      expect(find.textContaining('little behind'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((await saved()).settings.summary.mode, SummaryMode.off);
    });

    testWidgets('summary: Cancel keeps the setting', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Daily or weekly summary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await saved()).settings.summary.mode, SummaryMode.off);
    });

    testWidgets('the summary dialog warns it can be a little behind', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Daily or weekly summary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily'));
      await tester.pumpAndSettle();
      expect(find.textContaining('little behind'), findsOneWidget);
    });
  });

  group('Export my data', () {
    Future<void> seed() async {
      final pid = await PeopleRepository(
        db,
        'u1',
      ).add(Person(name: 'Asha', createdAt: DateTime.utc(2026, 1, 1)));
      await TransactionRepository(db, 'u1').add(
        MoneyTransaction(
          type: TransactionType.lent,
          personId: pid,
          personName: 'Asha',
          title: 'Loan',
          totalAmount: Money.fromRupees(500),
          createdAt: DateTime.utc(2026, 9, 1),
          date: DateTime.utc(2026, 9, 1),
        ),
      );
    }

    testWidgets('warns first, and Cancel shares nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Export my data'));
      await tester.pumpAndSettle();
      expect(find.textContaining('private information'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(sharer.shared, isEmpty);
    });

    testWidgets('Export shares one JSON file with the account\'s data', (
      tester,
    ) async {
      await seed();
      await pump(tester);
      await tester.tap(find.text('Export my data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(sharer.shared.length, 1);
      final f = sharer.shared.single;
      expect(
        f.fileName,
        matches(RegExp(r'^money-manager-backup-\d{4}-\d{2}-\d{2}\.json$')),
      );
      final json = jsonDecode(f.json) as Map;
      expect(json['version'], 1);
      expect((json['people'] as List).single['name'], 'Asha');
      expect((json['entries'] as List).single['totalAmount'], 50000);
      expect((json['profile'] as Map)['name'], 'Sarang');
    });

    testWidgets('a failure is reported, not swallowed', (tester) async {
      sharer.failWith = Exception('no share sheet');
      await pump(tester);
      await tester.tap(find.text('Export my data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not export your data'), findsOneWidget);
    });
  });

  group('Help', () {
    testWidgets('Privacy explains what is stored', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      expect(find.text('What is stored'), findsOneWidget);
      expect(find.text('Contacts'), findsOneWidget);
      expect(find.textContaining('Export my data'), findsWidgets);
    });

    testWidgets('About shows the app version', (tester) async {
      await pump(tester);
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();
      expect(find.text('Money Manager'), findsOneWidget);
      expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
    });
  });

  testWidgets('saved settings are shown when the screen opens', (tester) async {
    await users.saveSettings(
      const AppSettings(
        grouping: NumberGrouping.western,
        dateStyle: DateStyle.dmy,
        theme: ThemeChoice.light,
        summary: SummarySettings(mode: SummaryMode.daily, minutes: 7 * 60),
      ),
    );
    await pump(tester);
    expect(find.text('Western (1,234,567)'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Daily at 7:00 am'), findsOneWidget);
  });
}
