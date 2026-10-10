import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/reminder_repository.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/data/user_repository.dart';
import 'package:money_manager/core/models/app_settings.dart';
import 'package:money_manager/core/models/app_user.dart';
import 'package:money_manager/core/ui/format.dart';
import 'package:money_manager/reminders/alarm_providers.dart';
import 'package:money_manager/reminders/reminder_form_screen.dart';
import 'package:money_manager/settings/settings_providers.dart';

import '../support/fake_alarm_gateway.dart';

void main() {
  test('theme choices map to Flutter theme modes', () {
    expect(themeModeFor(ThemeChoice.system), ThemeMode.system);
    expect(themeModeFor(ThemeChoice.light), ThemeMode.light);
    expect(themeModeFor(ThemeChoice.dark), ThemeMode.dark);
  });

  group('the settings provider', () {
    late FakeFirebaseFirestore db;
    late UserRepository users;

    setUp(() async {
      db = FakeFirebaseFirestore();
      users = UserRepository(db, 'u1');
    });

    test('defaults until the profile loads, then the saved settings', () async {
      await users.save(const AppUser(name: 'A', currency: 'EUR'));
      await users.saveSettings(const AppSettings(theme: ThemeChoice.dark));
      final c = ProviderContainer(
        overrides: [userRepositoryProvider.overrideWithValue(users)],
      );
      addTearDown(c.dispose);
      c.listen(appSettingsProvider, (_, _) {});
      // Nothing has arrived yet: the defaults.
      expect(c.read(appSettingsProvider), AppSettings.defaults);
      expect(c.read(appCurrencyProvider), 'INR');
      await c.read(currentProfileProvider.future);
      expect(c.read(appSettingsProvider).theme, ThemeChoice.dark);
      expect(c.read(appCurrencyProvider), 'EUR');
    });

    test('with no profile at all it stays on the defaults', () async {
      final c = ProviderContainer(
        overrides: [userRepositoryProvider.overrideWithValue(users)],
      );
      addTearDown(c.dispose);
      c.listen(appSettingsProvider, (_, _) {});
      await c.read(currentProfileProvider.future);
      expect(c.read(appSettingsProvider), AppSettings.defaults);
    });
  });

  group('new reminder default time', () {
    late FakeFirebaseFirestore db;
    late UserRepository users;

    setUp(() async {
      db = FakeFirebaseFirestore();
      users = UserRepository(db, 'u1');
      await users.save(const AppUser(name: 'A'));
    });

    Future<void> openForm(WidgetTester tester) async {
      // In the app the profile has long since loaded; do the same here.
      final container = ProviderContainer(
        overrides: [
          userRepositoryProvider.overrideWithValue(users),
          reminderRepositoryProvider.overrideWithValue(
            ReminderRepository(db, 'u1'),
          ),
          peopleRepositoryProvider.overrideWithValue(
            PeopleRepository(db, 'u1'),
          ),
          transactionRepositoryProvider.overrideWithValue(
            TransactionRepository(db, 'u1'),
          ),
          alarmGatewayProvider.overrideWithValue(FakeAlarmGateway()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(currentProfileProvider, (_, _) {});
      await tester.runAsync(
        () => container.read(currentProfileProvider.future),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ReminderFormScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('uses the configured time, today if ahead else tomorrow', (
      tester,
    ) async {
      await users.saveSettings(
        const AppSettings(autoAlarmMinutes: 7 * 60 + 30),
      );
      await openForm(tester);
      expect(find.widgetWithText(OutlinedButton, '7:30 am'), findsOneWidget);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 7, 30);
      final expected = today.isAfter(now)
          ? today
          : today.add(const Duration(days: 1));
      expect(
        find.widgetWithText(OutlinedButton, formatShortDate(expected)),
        findsOneWidget,
      );
    });

    testWidgets('a time that has already passed today means tomorrow', (
      tester,
    ) async {
      final now = DateTime.now();
      // One minute ago, so it can only be tomorrow.
      final past = now.subtract(const Duration(minutes: 1));
      await users.saveSettings(
        AppSettings(autoAlarmMinutes: past.hour * 60 + past.minute),
      );
      await openForm(tester);
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      expect(
        find.widgetWithText(OutlinedButton, formatShortDate(tomorrow)),
        findsOneWidget,
      );
    });
  });
}
