import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/reminder.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';
import 'package:money_manager/reminders/reminder_lists.dart';

Reminder rem(
  String id,
  DateTime at, {
  RepeatRule repeat = const RepeatRule.none(),
  bool done = false,
  DateTime? doneAt,
}) => Reminder(
  id: id,
  title: id,
  at: at,
  repeat: repeat,
  done: done,
  doneAt: doneAt,
  createdAt: DateTime(2026, 1, 1),
);

MoneyTransaction entry(
  String id,
  DateTime? due, {
  bool auto = true,
  TransactionStatus status = TransactionStatus.pending,
}) => MoneyTransaction(
  id: id,
  type: TransactionType.lent,
  personId: 'p',
  personName: 'Asha',
  title: 'Loan',
  totalAmount: Money.fromRupees(100),
  status: status,
  dueDate: due,
  createdAt: DateTime(2026, 1, 1),
  autoReminders: auto,
);

void main() {
  final now = DateTime(2030, 1, 7, 12);

  group('upcoming', () {
    test('future one-offs, soonest first', () {
      final l = buildReminderLists(
        [rem('b', DateTime(2030, 1, 9, 9)), rem('a', DateTime(2030, 1, 8, 9))],
        const [],
        now,
      );
      expect(l.upcoming.map((u) => u.reminder!.id), ['a', 'b']);
      expect(l.upcoming.first.when, DateTime(2030, 1, 8, 9));
    });

    test('a repeating reminder shows its next ring, not its start', () {
      final l = buildReminderLists(
        [rem('d', DateTime(2020, 1, 1, 9), repeat: const RepeatRule.daily())],
        const [],
        now,
      );
      expect(l.upcoming.single.when, DateTime(2030, 1, 8, 9));
    });

    test('a ring exactly now is already past: missed, not upcoming', () {
      final l = buildReminderLists([rem('a', now)], const [], now);
      expect(l.upcoming, isEmpty);
      expect(l.missed.map((r) => r.id), ['a']);
    });

    test('automatic payment alarms within 14 days are merged in by time', () {
      final l = buildReminderLists(
        [rem('r', DateTime(2030, 1, 9, 8))],
        [entry('t', DateTime(2030, 1, 10))],
        now,
      );
      // 9 Jan 8:00 reminder, then auto 9 Jan 9:00, 10 Jan 9:00, 11 Jan 9:00.
      expect(l.upcoming.length, 4);
      expect(l.upcoming[0].reminder?.id, 'r');
      expect(l.upcoming.skip(1).every((u) => u.auto != null), isTrue);
      for (var i = 1; i < l.upcoming.length; i++) {
        expect(l.upcoming[i].when.isBefore(l.upcoming[i - 1].when), isFalse);
      }
    });

    test('automatic alarms beyond 14 days are not listed yet', () {
      final l = buildReminderLists(const [], [
        entry('t', DateTime(2030, 3, 1)),
      ], now);
      expect(l.upcoming, isEmpty);
    });

    test('the 14-day edge: 21 Jan 9:00 is inside, 22 Jan 9:00 is outside', () {
      // Now is 7 Jan 12:00, so the window ends 21 Jan 12:00.
      final inside = buildReminderLists(const [], [
        entry('t', DateTime(2030, 1, 22)), // rings 21, 22, 23 Jan
      ], now);
      expect(inside.upcoming.map((u) => u.when), [DateTime(2030, 1, 21, 9)]);
      final outside = buildReminderLists(const [], [
        entry('t', DateTime(2030, 1, 23)), // first ring 22 Jan
      ], now);
      expect(outside.upcoming, isEmpty);
    });

    test('paid, switched off and no-due-date entries add nothing', () {
      final l = buildReminderLists(const [], [
        entry('a', DateTime(2030, 1, 10), status: TransactionStatus.paid),
        entry('b', DateTime(2030, 1, 10), auto: false),
        entry('c', null),
      ], now);
      expect(l.upcoming, isEmpty);
    });
  });

  group('completed', () {
    test('done reminders, newest done first', () {
      final l = buildReminderLists(
        [
          rem(
            'old',
            DateTime(2030, 1, 1),
            done: true,
            doneAt: DateTime(2030, 1, 2),
          ),
          rem(
            'new',
            DateTime(2030, 1, 1),
            done: true,
            doneAt: DateTime(2030, 1, 5),
          ),
        ],
        const [],
        now,
      );
      expect(l.completed.map((r) => r.id), ['new', 'old']);
    });

    test('done wins: a done reminder is never upcoming or missed', () {
      final l = buildReminderLists(
        [
          rem('f', DateTime(2030, 2, 1), done: true),
          rem('p', DateTime(2020, 2, 1), done: true),
          rem(
            'r',
            DateTime(2030, 2, 1),
            repeat: const RepeatRule.daily(),
            done: true,
          ),
        ],
        const [],
        now,
      );
      expect(l.upcoming, isEmpty);
      expect(l.missed, isEmpty);
      expect(l.completed.length, 3);
    });
  });

  group('missed', () {
    test('passed one-offs that were not done, most recent first', () {
      final l = buildReminderLists(
        [rem('a', DateTime(2030, 1, 1, 9)), rem('b', DateTime(2030, 1, 6, 9))],
        const [],
        now,
      );
      expect(l.missed.map((r) => r.id), ['b', 'a']);
    });

    test('a repeating reminder is never missed', () {
      final l = buildReminderLists(
        [
          rem('d', DateTime(2020, 1, 1, 9), repeat: const RepeatRule.daily()),
          rem(
            'w',
            DateTime(2020, 1, 1, 9),
            repeat: const RepeatRule.weekly({1}),
          ),
          rem('m', DateTime(2020, 1, 1, 9), repeat: const RepeatRule.monthly()),
        ],
        const [],
        now,
      );
      expect(l.missed, isEmpty);
      expect(l.upcoming.length, 3);
    });

    test('a repeating reminder with no ring left is not called missed', () {
      // A weekly reminder with no weekday chosen never rings again.
      final l = buildReminderLists(
        [
          rem(
            'w',
            DateTime(2020, 1, 1, 9),
            repeat: const RepeatRule.weekly({}),
          ),
        ],
        const [],
        now,
      );
      expect(l.missed, isEmpty);
      expect(l.upcoming, isEmpty);
    });

    test('a one-off in the future is not missed', () {
      final l = buildReminderLists(
        [rem('a', DateTime(2030, 1, 8))],
        const [],
        now,
      );
      expect(l.missed, isEmpty);
    });
  });

  test('empty input', () {
    final l = buildReminderLists(const [], const [], now);
    expect(l.upcoming, isEmpty);
    expect(l.completed, isEmpty);
    expect(l.missed, isEmpty);
  });
}
