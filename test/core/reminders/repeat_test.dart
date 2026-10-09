import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/reminder.dart';
import 'package:money_manager/core/reminders/repeat.dart';

Reminder rem(DateTime at, RepeatRule repeat, {bool done = false}) => Reminder(
  title: 't',
  at: at,
  repeat: repeat,
  done: done,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  group('once', () {
    final r = rem(DateTime(2030, 1, 7, 9), const RepeatRule.none());
    test('rings at its time', () {
      expect(nextOccurrence(r, DateTime(2030, 1, 1)), DateTime(2030, 1, 7, 9));
    });
    test('strictly after: at the ring time itself there is none', () {
      expect(nextOccurrence(r, DateTime(2030, 1, 7, 9)), isNull);
      expect(
        nextOccurrence(r, DateTime(2030, 1, 7, 8, 59)),
        DateTime(2030, 1, 7, 9),
      );
    });
    test('a done reminder has none', () {
      expect(
        nextOccurrence(
          rem(DateTime(2030, 1, 7, 9), const RepeatRule.daily(), done: true),
          DateTime(2030, 1, 1),
        ),
        isNull,
      );
    });
  });

  group('daily and every N days', () {
    test('daily keeps the time of day', () {
      final r = rem(DateTime(2030, 1, 7, 9, 30), const RepeatRule.daily());
      expect(
        nextOccurrence(r, DateTime(2030, 1, 10, 9, 30)),
        DateTime(2030, 1, 11, 9, 30),
      );
      expect(
        nextOccurrence(r, DateTime(2030, 1, 10, 9, 29)),
        DateTime(2030, 1, 10, 9, 30),
      );
      expect(
        nextOccurrence(r, DateTime(2031, 3, 1)),
        DateTime(2031, 3, 1, 9, 30),
      );
    });

    test('every 10 days steps from the first ring', () {
      final r = rem(DateTime(2030, 1, 1, 8), const RepeatRule.everyNDays(10));
      expect(
        nextOccurrence(r, DateTime(2030, 1, 1, 8)),
        DateTime(2030, 1, 11, 8),
      );
      expect(
        nextOccurrence(r, DateTime(2030, 1, 15)),
        DateTime(2030, 1, 21, 8),
      );
      expect(
        nextOccurrence(r, DateTime(2030, 1, 31, 8)),
        DateTime(2030, 2, 10, 8),
      );
    });

    test('every 1 day is daily', () {
      final r = rem(DateTime(2030, 1, 1, 8), const RepeatRule.everyNDays(1));
      expect(
        nextOccurrence(r, DateTime(2030, 1, 5, 9)),
        DateTime(2030, 1, 6, 8),
      );
    });

    test('the time of day survives a daylight-saving change', () {
      // In the US clocks change on 10 Mar 2030; wall-clock 9:00 must stay 9:00.
      final r = rem(DateTime(2030, 3, 1, 9), const RepeatRule.daily());
      final n = nextOccurrence(r, DateTime(2030, 3, 9, 9))!;
      expect([n.month, n.day, n.hour, n.minute], [3, 10, 9, 0]);
      final m = nextOccurrence(r, n)!;
      expect([m.month, m.day, m.hour, m.minute], [3, 11, 9, 0]);
    });
  });

  group('weekly', () {
    // 7 Jan 2030 is a Monday.
    final mwf = rem(
      DateTime(2030, 1, 7, 9),
      const RepeatRule.weekly({1, 3, 5}),
    );
    test('rings on the chosen weekdays only', () {
      expect(
        nextOccurrence(mwf, DateTime(2030, 1, 7, 9)),
        DateTime(2030, 1, 9, 9),
      );
      expect(
        nextOccurrence(mwf, DateTime(2030, 1, 9, 9)),
        DateTime(2030, 1, 11, 9),
      );
      expect(
        nextOccurrence(mwf, DateTime(2030, 1, 11, 9)),
        DateTime(2030, 1, 14, 9),
      );
    });
    test('the first ring counts when its weekday is chosen', () {
      expect(
        nextOccurrence(mwf, DateTime(2030, 1, 1)),
        DateTime(2030, 1, 7, 9),
      );
    });
    test('the first ring is skipped when its weekday is not chosen', () {
      final tue = rem(DateTime(2030, 1, 7, 9), const RepeatRule.weekly({2}));
      expect(
        nextOccurrence(tue, DateTime(2030, 1, 1)),
        DateTime(2030, 1, 8, 9),
      );
    });
    test('far in the future', () {
      final n = nextOccurrence(mwf, DateTime(2032, 6, 1))!;
      expect({1, 3, 5}.contains(n.weekday), isTrue);
      expect(n.isAfter(DateTime(2032, 6, 1)), isTrue);
      expect(n.difference(DateTime(2032, 6, 1)).inDays < 3, isTrue);
    });
    test('no weekday means no ring', () {
      expect(
        nextOccurrence(
          rem(DateTime(2030, 1, 7, 9), const RepeatRule.weekly({})),
          DateTime(2030, 1, 1),
        ),
        isNull,
      );
    });
  });

  group('monthly and yearly', () {
    test('a 31st rings on the last day of short months and recovers', () {
      final r = rem(DateTime(2030, 1, 31, 9), const RepeatRule.monthly());
      final rings = occurrencesBetween(
        r,
        DateTime(2030, 1, 1),
        DateTime(2030, 6, 30, 23),
      );
      expect(rings, [
        DateTime(2030, 1, 31, 9),
        DateTime(2030, 2, 28, 9),
        DateTime(2030, 3, 31, 9),
        DateTime(2030, 4, 30, 9),
        DateTime(2030, 5, 31, 9),
        DateTime(2030, 6, 30, 9),
      ]);
    });

    test('a leap-year February keeps the 29th', () {
      final r = rem(DateTime(2028, 1, 29, 9), const RepeatRule.monthly());
      expect(
        nextOccurrence(r, DateTime(2028, 1, 29, 9)),
        DateTime(2028, 2, 29, 9),
      );
    });

    test(
      'monthly after the ring time within the month moves to next month',
      () {
        final r = rem(DateTime(2030, 1, 15, 9), const RepeatRule.monthly());
        expect(
          nextOccurrence(r, DateTime(2030, 3, 15, 9)),
          DateTime(2030, 4, 15, 9),
        );
        expect(
          nextOccurrence(r, DateTime(2030, 3, 15, 8)),
          DateTime(2030, 3, 15, 9),
        );
      },
    );

    test('yearly keeps the date, 29 Feb falls back and returns', () {
      final r = rem(DateTime(2028, 2, 29, 9), const RepeatRule.yearly());
      expect(
        nextOccurrence(r, DateTime(2028, 2, 29, 9)),
        DateTime(2029, 2, 28, 9),
      );
      expect(nextOccurrence(r, DateTime(2031, 3, 1)), DateTime(2032, 2, 29, 9));
      final plain = rem(DateTime(2030, 7, 4, 9), const RepeatRule.yearly());
      expect(
        nextOccurrence(plain, DateTime(2030, 7, 4, 9)),
        DateTime(2031, 7, 4, 9),
      );
    });
  });

  group('occurrencesBetween', () {
    test('includes both ends and respects the limit', () {
      final r = rem(DateTime(2030, 1, 1, 9), const RepeatRule.daily());
      final all = occurrencesBetween(
        r,
        DateTime(2030, 1, 1, 9),
        DateTime(2030, 1, 5, 9),
      );
      expect(all.length, 5);
      expect(
        occurrencesBetween(
          r,
          DateTime(2030, 1, 1),
          DateTime(2031, 1, 1),
          max: 3,
        ).length,
        3,
      );
    });
    test('empty for a past one-off', () {
      final r = rem(DateTime(2030, 1, 1, 9), const RepeatRule.none());
      expect(
        occurrencesBetween(r, DateTime(2031, 1, 1), DateTime(2031, 2, 1)),
        isEmpty,
      );
    });
  });

  group('invariants', () {
    test('the next ring is always after, on time, and on a legal day', () {
      final rules = <RepeatRule>[
        const RepeatRule.daily(),
        const RepeatRule.everyNDays(3),
        const RepeatRule.everyNDays(45),
        const RepeatRule.weekly({1}),
        const RepeatRule.weekly({2, 6, 7}),
        const RepeatRule.monthly(),
        const RepeatRule.yearly(),
      ];
      final starts = [
        DateTime(2030, 1, 31, 23, 45),
        DateTime(2028, 2, 29, 0, 5),
        DateTime(2030, 3, 9, 2, 30), // a US daylight-saving night
      ];
      for (final rule in rules) {
        for (final start in starts) {
          final r = rem(start, rule);
          var after = DateTime(2029, 12, 1);
          for (var i = 0; i < 60; i++) {
            final next = nextOccurrence(r, after)!;
            final label = '${rule.kind} $start $after';
            expect(next.isAfter(after), isTrue, reason: label);
            if (rule.kind != RepeatKind.none && next.day != start.day) {
              // only month-end clamping may change the day-of-month
              expect(
                rule.kind == RepeatKind.monthly ||
                    rule.kind == RepeatKind.yearly ||
                    rule.kind == RepeatKind.daily ||
                    rule.kind == RepeatKind.everyNDays ||
                    rule.kind == RepeatKind.weekly,
                isTrue,
              );
            }
            if (rule.kind != RepeatKind.none) {
              expect(next.minute, start.minute, reason: label);
              // The first ring may sit in a missing daylight-saving hour; the
              // wall-clock hour must otherwise be the start's.
              if (!(start.month == 3 && start.day == 9)) {
                expect(next.hour, start.hour, reason: label);
              }
            }
            if (rule.kind == RepeatKind.weekly) {
              expect(
                rule.weekdays.contains(next.weekday),
                isTrue,
                reason: label,
              );
            }
            after = next;
          }
        }
      }
    });

    test('no ring is skipped between consecutive results', () {
      final r = rem(DateTime(2030, 1, 31, 9), const RepeatRule.monthly());
      final rings = occurrencesBetween(
        r,
        DateTime(2030, 1, 1),
        DateTime(2032, 12, 31, 23, 59),
      );
      expect(rings.length, 36);
      for (var i = 1; i < rings.length; i++) {
        expect(rings[i].isAfter(rings[i - 1]), isTrue);
      }
    });
  });
}
