import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/user_repository.dart';
import 'package:money_manager/core/models/app_settings.dart';
import 'package:money_manager/core/models/app_user.dart';
import 'package:money_manager/core/money/money.dart';

void main() {
  group('defaults', () {
    test('sensible out of the box', () {
      const s = AppSettings.defaults;
      expect(s.grouping, isNull);
      expect(s.dateStyle, DateStyle.dMonY);
      expect(s.theme, ThemeChoice.system);
      expect(s.autoAlarmMinutes, 9 * 60);
      expect(s.quietHours.enabled, isFalse);
      expect(s.quietHours.startMinutes, 22 * 60);
      expect(s.quietHours.endMinutes, 7 * 60);
      expect(s.summary.mode, SummaryMode.off);
      expect(s.summary.minutes, 8 * 60);
      expect(s.summary.weekday, DateTime.monday);
    });

    test('grouping follows the currency unless chosen', () {
      const s = AppSettings.defaults;
      expect(s.groupingFor('INR'), NumberGrouping.indian);
      expect(s.groupingFor('USD'), NumberGrouping.western);
      expect(s.groupingFor('AED'), NumberGrouping.western);
      final chosen = s.copyWith(grouping: NumberGrouping.western);
      expect(chosen.groupingFor('INR'), NumberGrouping.western);
      final indian = s.copyWith(grouping: NumberGrouping.indian);
      expect(indian.groupingFor('USD'), NumberGrouping.indian);
      expect(chosen.copyWith(clearGrouping: true).grouping, isNull);
    });

    test('currency symbols', () {
      expect(currencySymbol('INR'), '₹');
      expect(currencySymbol('USD'), r'$');
      expect(currencySymbol('EUR'), '€');
      expect(currencySymbol('GBP'), '£');
      expect(currencySymbol('AED'), 'AED ');
      expect(currencySymbol('JPY'), 'JPY ');
    });
  });

  group('storage', () {
    test('every field round-trips', () {
      const s = AppSettings(
        grouping: NumberGrouping.western,
        dateStyle: DateStyle.mdy,
        theme: ThemeChoice.dark,
        autoAlarmMinutes: 7 * 60 + 30,
        quietHours: QuietHours(
          enabled: true,
          startMinutes: 23 * 60,
          endMinutes: 6 * 60 + 15,
        ),
        summary: SummarySettings(
          mode: SummaryMode.weekly,
          minutes: 19 * 60,
          weekday: DateTime.friday,
        ),
      );
      expect(AppSettings.fromMap(s.toMap()), s);
    });

    test('missing, null and damaged data fall back to the defaults', () {
      expect(AppSettings.fromMap(null), AppSettings.defaults);
      expect(AppSettings.fromMap({}), AppSettings.defaults);
      final bad = AppSettings.fromMap({
        'grouping': 'lakh',
        'dateStyle': 'iso',
        'theme': 'neon',
        'autoAlarmMinutes': 99999,
        'quietHours': 'x',
        'summary': {'mode': 'hourly', 'minutes': -5, 'weekday': 9},
      });
      expect(bad, AppSettings.defaults);
    });

    test('an old profile document without settings loads with defaults', () {
      final u = AppUser.fromMap({'name': 'Asha', 'currency': 'USD'});
      expect(u.settings, AppSettings.defaults);
      expect(u.currency, 'USD');
    });

    test('settings nested in a profile document load', () {
      final u = AppUser.fromMap({
        'name': 'A',
        'settings': const AppSettings(theme: ThemeChoice.light).toMap(),
      });
      expect(u.settings.theme, ThemeChoice.light);
    });
  });

  group('UserRepository', () {
    late FakeFirebaseFirestore db;
    late UserRepository repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = UserRepository(db, 'u1');
    });

    test('saving settings does not touch name, currency or timezone', () async {
      await repo.save(
        const AppUser(name: 'Asha', currency: 'USD', timezone: 'UTC'),
      );
      await repo.saveSettings(const AppSettings(theme: ThemeChoice.dark));
      final u = (await repo.get())!;
      expect(u.name, 'Asha');
      expect(u.currency, 'USD');
      expect(u.timezone, 'UTC');
      expect(u.settings.theme, ThemeChoice.dark);
    });

    test('saving the profile does not reset the settings', () async {
      await repo.saveSettings(
        const AppSettings(theme: ThemeChoice.dark, autoAlarmMinutes: 8 * 60),
      );
      await repo.save(const AppUser(name: 'New Name', currency: 'EUR'));
      final u = (await repo.get())!;
      expect(u.name, 'New Name');
      expect(u.settings.theme, ThemeChoice.dark);
      expect(u.settings.autoAlarmMinutes, 8 * 60);
    });

    test('settings can be saved before the profile exists', () async {
      await repo.saveSettings(const AppSettings(theme: ThemeChoice.light));
      expect(
        ((await db.collection('users').doc('u1').get()).data()!['settings']
            as Map)['theme'],
        'light',
      );
    });

    test('the watch stream carries settings', () async {
      await repo.save(const AppUser(name: 'A'));
      await repo.saveSettings(const AppSettings(dateStyle: DateStyle.dmy));
      expect((await repo.watch().first)!.settings.dateStyle, DateStyle.dmy);
    });
  });
}
