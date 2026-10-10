import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/alarm/quiet_hours.dart';
import 'package:money_manager/core/models/app_settings.dart';

void main() {
  // 22:00 to 07:00 (crosses midnight).
  const night = QuietHours(
    enabled: true,
    startMinutes: 22 * 60,
    endMinutes: 7 * 60,
  );
  // 13:00 to 15:00 (same day).
  const nap = QuietHours(
    enabled: true,
    startMinutes: 13 * 60,
    endMinutes: 15 * 60,
  );

  DateTime d(int day, int h, [int m = 0]) => DateTime(2030, 1, day, h, m);

  group('a window that crosses midnight', () {
    test('before midnight moves to the next morning', () {
      expect(applyQuietHours(d(7, 23), night), d(8, 7));
      expect(applyQuietHours(d(7, 22, 30), night), d(8, 7));
    });

    test('after midnight moves to the same morning', () {
      expect(applyQuietHours(d(8, 0, 30), night), d(8, 7));
      expect(applyQuietHours(d(8, 6, 59), night), d(8, 7));
      expect(applyQuietHours(d(8, 0), night), d(8, 7));
    });

    test('the start is inside, the end is outside', () {
      expect(applyQuietHours(d(7, 22), night), d(8, 7));
      expect(applyQuietHours(d(8, 7), night), d(8, 7)); // already at the end
      expect(applyQuietHours(d(8, 7, 1), night), d(8, 7, 1));
      expect(applyQuietHours(d(7, 21, 59), night), d(7, 21, 59));
    });

    test('daytime is untouched', () {
      expect(applyQuietHours(d(7, 9), night), d(7, 9));
      expect(applyQuietHours(d(7, 12, 30), night), d(7, 12, 30));
    });

    test('month and year end', () {
      expect(
        applyQuietHours(DateTime(2030, 12, 31, 23), night),
        DateTime(2031, 1, 1, 7),
      );
      expect(
        applyQuietHours(DateTime(2030, 2, 28, 23, 30), night),
        DateTime(2030, 3, 1, 7),
      );
    });
  });

  group('a window within one day', () {
    test('inside moves to the end, never earlier', () {
      expect(applyQuietHours(d(7, 13), nap), d(7, 15));
      expect(applyQuietHours(d(7, 14, 59), nap), d(7, 15));
      expect(applyQuietHours(d(7, 15), nap), d(7, 15));
      expect(applyQuietHours(d(7, 12, 59), nap), d(7, 12, 59));
      expect(applyQuietHours(d(7, 15, 1), nap), d(7, 15, 1));
    });
  });

  group('off or degenerate', () {
    test('disabled changes nothing', () {
      expect(
        applyQuietHours(d(7, 23), night.copyWith(enabled: false)),
        d(7, 23),
      );
    });

    test('equal start and end is no window', () {
      expect(
        applyQuietHours(
          d(7, 23),
          const QuietHours(enabled: true, startMinutes: 600, endMinutes: 600),
        ),
        d(7, 23),
      );
    });
  });

  test('never moves a time earlier, for every minute of the day', () {
    for (final q in [night, nap]) {
      for (var m = 0; m < 24 * 60; m += 7) {
        final at = DateTime(2030, 3, 9, m ~/ 60, m % 60);
        final shifted = applyQuietHours(at, q);
        expect(shifted.isBefore(at), isFalse, reason: '$m');
        // A shifted time is exactly the window end.
        if (shifted != at) {
          expect(shifted.hour * 60 + shifted.minute, q.endMinutes);
        }
      }
    }
  });
}
