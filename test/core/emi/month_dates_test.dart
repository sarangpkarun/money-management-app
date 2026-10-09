import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/emi/month_dates.dart';

void main() {
  group('daysInMonth', () {
    test('month lengths', () {
      expect(daysInMonth(2026, 1), 31);
      expect(daysInMonth(2026, 4), 30);
      expect(daysInMonth(2026, 12), 31);
    });
    test('February in leap and non-leap years', () {
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(1900, 2), 28); // divisible by 100, not 400
      expect(daysInMonth(2000, 2), 29); // divisible by 400
    });
  });

  group('addMonthsClamped', () {
    test('zero months returns the same calendar date', () {
      expect(addMonthsClamped(DateTime(2026, 1, 31), 0), DateTime(2026, 1, 31));
    });

    test('an ordinary day just moves forward', () {
      expect(addMonthsClamped(DateTime(2026, 1, 15), 1), DateTime(2026, 2, 15));
      expect(addMonthsClamped(DateTime(2026, 1, 15), 5), DateTime(2026, 6, 15));
    });

    test('31 Jan gives the last day of February', () {
      expect(addMonthsClamped(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonthsClamped(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
    });

    test('30 and 29 Jan clamp in February too', () {
      expect(addMonthsClamped(DateTime(2026, 1, 30), 1), DateTime(2026, 2, 28));
      expect(addMonthsClamped(DateTime(2028, 1, 30), 1), DateTime(2028, 2, 29));
      expect(addMonthsClamped(DateTime(2026, 1, 29), 1), DateTime(2026, 2, 28));
      expect(addMonthsClamped(DateTime(2028, 1, 29), 1), DateTime(2028, 2, 29));
    });

    test('31st clamps to 30 in 30-day months', () {
      expect(addMonthsClamped(DateTime(2026, 3, 31), 1), DateTime(2026, 4, 30));
      expect(addMonthsClamped(DateTime(2026, 5, 31), 1), DateTime(2026, 6, 30));
      expect(addMonthsClamped(DateTime(2026, 8, 31), 1), DateTime(2026, 9, 30));
    });

    test('the original day is restored later: it never drifts', () {
      // 31 Jan, 28 Feb, 31 Mar, 30 Apr, 31 May (not 28 forever).
      final start = DateTime(2026, 1, 31);
      final days = [for (var k = 0; k < 5; k++) addMonthsClamped(start, k).day];
      expect(days, [31, 28, 31, 30, 31]);
    });

    test('rolls over the year and handles long tenures', () {
      expect(
        addMonthsClamped(DateTime(2026, 11, 10), 2),
        DateTime(2027, 1, 10),
      );
      expect(
        addMonthsClamped(DateTime(2026, 12, 31), 1),
        DateTime(2027, 1, 31),
      );
      expect(
        addMonthsClamped(DateTime(2026, 1, 31), 120),
        DateTime(2036, 1, 31),
      );
      expect(
        addMonthsClamped(DateTime(2026, 1, 31), 25),
        DateTime(2028, 2, 29),
      );
    });

    test('every start day lands on a real date for the next 48 months', () {
      for (var day = 1; day <= 31; day++) {
        for (var month = 1; month <= 12; month++) {
          if (day > daysInMonth(2027, month)) continue;
          final start = DateTime(2027, month, day);
          for (var k = 0; k <= 48; k++) {
            final d = addMonthsClamped(start, k);
            expect(d.day, lessThanOrEqualTo(daysInMonth(d.year, d.month)));
            expect(d.day, lessThanOrEqualTo(day));
            // Matches the original day whenever that day exists.
            if (day <= daysInMonth(d.year, d.month)) expect(d.day, day);
          }
        }
      }
    });

    test('the time of day is dropped', () {
      expect(
        addMonthsClamped(DateTime(2026, 1, 31, 15, 45), 1),
        DateTime(2026, 2, 28),
      );
    });
  });
}
