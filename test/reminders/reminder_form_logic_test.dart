import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/reminder.dart';
import 'package:money_manager/reminders/reminder_form_logic.dart';

void main() {
  final now = DateTime(2030, 1, 7, 12);

  String? check({
    String title = 'Pay',
    DateTime? at,
    RepeatRule repeat = const RepeatRule.none(),
    int snooze = 10,
    bool isNew = true,
  }) => validateReminder(
    title: title,
    at: at ?? now.add(const Duration(hours: 1)),
    repeat: repeat,
    snoozeMinutes: snooze,
    now: now,
    isNew: isNew,
  );

  group('validateReminder', () {
    test('a good one passes', () => expect(check(), isNull));
    test('title is required', () {
      expect(check(title: '  '), 'Enter a title');
    });
    test('a new one-off must be in the future', () {
      expect(check(at: now), 'Pick a time in the future');
      expect(check(at: now.subtract(const Duration(days: 1))), isNotNull);
    });
    test('an old one-off can be edited', () {
      expect(
        check(at: now.subtract(const Duration(days: 1)), isNew: false),
        isNull,
      );
    });
    test('a repeating one may start in the past', () {
      expect(
        check(
          at: now.subtract(const Duration(days: 1)),
          repeat: const RepeatRule.daily(),
        ),
        isNull,
      );
    });
    test('weekly needs a weekday', () {
      expect(
        check(repeat: const RepeatRule.weekly({})),
        'Pick at least one weekday',
      );
      expect(check(repeat: const RepeatRule.weekly({1})), isNull);
    });
    test('every N days is 1 to 365', () {
      expect(check(repeat: const RepeatRule.everyNDays(0)), isNotNull);
      expect(check(repeat: const RepeatRule.everyNDays(366)), isNotNull);
      expect(check(repeat: const RepeatRule.everyNDays(365)), isNull);
      expect(check(repeat: const RepeatRule.everyNDays(1)), isNull);
    });
    test('snooze is 5, 10 or 15', () {
      for (final s in [5, 10, 15]) {
        expect(check(snooze: s), isNull);
      }
      expect(check(snooze: 7), isNotNull);
    });
  });

  group('repeatSummary', () {
    final at = DateTime(2030, 1, 31, 9);
    test('each kind', () {
      expect(repeatSummary(const RepeatRule.none(), at), 'Once');
      expect(repeatSummary(const RepeatRule.daily(), at), 'Every day');
      expect(
        repeatSummary(const RepeatRule.weekly({5, 1, 3}), at),
        'Every Mon, Wed, Fri',
      );
      expect(
        repeatSummary(const RepeatRule.monthly(), at),
        'Monthly on the 31st',
      );
      expect(
        repeatSummary(const RepeatRule.yearly(), at),
        'Every year on 31 Jan',
      );
      expect(
        repeatSummary(const RepeatRule.everyNDays(10), at),
        'Every 10 days',
      );
      expect(repeatSummary(const RepeatRule.everyNDays(1), at), 'Every day');
    });
    test('ordinals', () {
      String m(int d) =>
          repeatSummary(const RepeatRule.monthly(), DateTime(2030, 1, d));
      expect(m(1), 'Monthly on the 1st');
      expect(m(2), 'Monthly on the 2nd');
      expect(m(3), 'Monthly on the 3rd');
      expect(m(11), 'Monthly on the 11th');
      expect(m(12), 'Monthly on the 12th');
      expect(m(13), 'Monthly on the 13th');
      expect(m(21), 'Monthly on the 21st');
      expect(m(22), 'Monthly on the 22nd');
    });
  });
}
