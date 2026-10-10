import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/alarm/alarm_plan.dart';
import 'package:money_manager/core/alarm/auto_alarms.dart';
import 'package:money_manager/core/emi/emi_schedule.dart';
import 'package:money_manager/core/instalments/instalment_plan.dart';
import 'package:money_manager/core/models/emi_plan.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/reminder.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';

MoneyTransaction loan(
  String id,
  TransactionType type,
  int rupees,
  DateTime? due, {
  String person = 'Asha',
  String title = 'Loan',
  bool auto = true,
  TransactionStatus status = TransactionStatus.pending,
  int paid = 0,
}) => MoneyTransaction(
  id: id,
  type: type,
  personId: 'p',
  personName: person,
  title: title,
  totalAmount: Money.fromRupees(rupees),
  paidTotal: Money.fromRupees(paid),
  status: status,
  dueDate: due,
  createdAt: DateTime(2026, 1, 1),
  autoReminders: auto,
);

MoneyTransaction emi(String id, {int paidRows = 0, bool auto = true}) {
  final s = generateEmiSchedule(
    price: Money.fromRupees(12000),
    annualRatePercent: 0,
    months: 4,
    startDate: DateTime(2030, 1, 15),
  );
  final plan0 = EmiPlan.fromSchedule(
    s,
    price: Money.fromRupees(12000),
    downPayment: Money.zero,
    annualRatePercent: 0,
    startDate: DateTime(2030, 1, 15),
  );
  final plan = plan0.copyWithRows([
    for (final r in plan0.rows)
      r.number <= paidRows ? r.copyWith(paidAmount: r.amount) : r,
  ]);
  return MoneyTransaction(
    id: id,
    type: TransactionType.emi,
    personId: 'p',
    personName: 'Croma',
    title: 'Phone',
    totalAmount: plan.totalPayable,
    dueDate: plan.nextUnpaid?.dueDate,
    createdAt: DateTime(2026, 1, 1),
    emiPlan: plan,
    autoReminders: auto,
  );
}

void main() {
  final now = DateTime(2030, 1, 7, 12);

  group('autoRings', () {
    test('a due date gives three rings at 9:00: before, on, after', () {
      final r = autoRings([
        loan('a', TransactionType.lent, 2000, DateTime(2030, 1, 10)),
      ], now);
      expect(r.map((x) => x.payload.at), [
        DateTime(2030, 1, 9, 9),
        DateTime(2030, 1, 10, 9),
        DateTime(2030, 1, 11, 9),
      ]);
      expect(r.map((x) => x.payload.title), [
        'Collect ₹2,000 from Asha · due tomorrow',
        'Collect ₹2,000 from Asha · due today',
        'Collect ₹2,000 from Asha · overdue',
      ]);
      expect(r.map((x) => x.id).toSet().length, 3);
    });

    test('overdue is the day AFTER the due date, never on it', () {
      final r = autoRings([
        loan('a', TransactionType.lent, 100, DateTime(2030, 1, 10, 18)),
      ], now);
      final overdue = r.firstWhere((x) => x.payload.title.endsWith('overdue'));
      expect(overdue.payload.at, DateTime(2030, 1, 11, 9));
    });

    test('past rings are skipped, later ones kept', () {
      // Due today at 9:00 has passed (it is 12:00); "after" is tomorrow.
      final r = autoRings([
        loan('a', TransactionType.borrowed, 500, DateTime(2030, 1, 7)),
      ], now);
      expect(r.map((x) => x.payload.at), [DateTime(2030, 1, 8, 9)]);
      expect(r.single.payload.title, 'Pay Asha ₹500 · overdue');
    });

    test('a ring exactly at now is not scheduled', () {
      final r = autoRings([
        loan('a', TransactionType.lent, 100, DateTime(2030, 1, 8)),
      ], DateTime(2030, 1, 7, 9));
      expect(r.map((x) => x.payload.at.day), [8, 9]); // 7 Jan 9:00 is "now"
    });

    test('paid, switched off, and no-due-date entries get none', () {
      expect(
        autoRings([
          loan(
            'a',
            TransactionType.lent,
            100,
            DateTime(2030, 1, 10),
            status: TransactionStatus.paid,
            paid: 100,
          ),
        ], now),
        isEmpty,
      );
      expect(
        autoRings([
          loan(
            'a',
            TransactionType.lent,
            100,
            DateTime(2030, 1, 10),
            auto: false,
          ),
        ], now),
        isEmpty,
      );
      expect(
        autoRings([loan('a', TransactionType.lent, 100, null)], now),
        isEmpty,
      );
    });

    test('wording per type', () {
      String first(MoneyTransaction t) =>
          autoRings([t], now).first.payload.title;
      expect(
        first(
          loan(
            'a',
            TransactionType.borrowed,
            5000,
            DateTime(2030, 1, 10),
            person: 'Ravi',
          ),
        ),
        'Pay Ravi ₹5,000 · due tomorrow',
      );
      expect(first(emi('e')), 'EMI #1 · Phone ₹3,000 · due tomorrow');
    });

    test('a loan entry shows its title as the note, a plan its person', () {
      final l = autoRings([
        loan(
          'a',
          TransactionType.lent,
          100,
          DateTime(2030, 1, 10),
          title: 'Bike',
        ),
      ], now).first;
      expect(l.payload.notes, 'Bike');
      expect(autoRings([emi('e')], now).first.payload.notes, 'Croma');
    });

    test('EMI: every unpaid row rings, paid rows do not', () {
      final r = autoRings([emi('e', paidRows: 1)], now);
      // Rows due 15 Feb, 15 Mar, 15 Apr 2030: 3 rows x 3 rings, none for row 1.
      expect(r.length, 9);
      expect(r.any((x) => x.id.contains(':1:')), isFalse);
      expect(r.first.id, startsWith('auto:e:2:'));
      expect(r.first.payload.at, DateTime(2030, 2, 14, 9));
    });

    test('a part-paid EMI row rings with what is left on it', () {
      final t = emi('e');
      final row = t.emiPlan!.rows.first;
      final part = MoneyTransaction(
        id: 'e',
        type: t.type,
        personId: 'p',
        personName: 'Croma',
        title: 'Phone',
        totalAmount: t.totalAmount,
        createdAt: t.createdAt,
        emiPlan: t.emiPlan!.copyWithRow(
          row.copyWith(paidAmount: Money.fromRupees(1000)),
        ),
      );
      expect(
        autoRings([part], now).first.payload.title,
        'EMI #1 · Phone ₹2,000 · due tomorrow',
      );
    });

    test('instalment rows use payment wording', () {
      final plan = generateInstalmentPlan(
        total: Money.fromRupees(1000),
        months: 2,
        startDate: DateTime(2030, 1, 20),
      );
      final t = MoneyTransaction(
        id: 'i',
        type: TransactionType.instalment,
        personId: 'p',
        personName: 'Ravi',
        title: 'Loan',
        totalAmount: Money.fromRupees(1000),
        createdAt: DateTime(2026, 1, 1),
        emiPlan: plan,
      );
      expect(
        autoRings([t], now).first.payload.title,
        'Payment #1 · Loan ₹500 · due tomorrow',
      );
    });

    test('automatic alarms use the defaults and link the entry', () {
      final p = autoRings([
        loan('abc', TransactionType.lent, 100, DateTime(2030, 1, 10)),
      ], now).first.payload;
      expect(p.entryId, 'abc');
      expect(p.once, isFalse);
      expect(p.snoozeMinutes, autoSnoozeMinutes);
      expect(p.tone, ReminderTone.alarm);
      expect(p.vibration, ReminderVibration.long);
    });

    test('month-end due dates ring on the right days', () {
      final r = autoRings([
        loan('a', TransactionType.lent, 100, DateTime(2030, 2, 28)),
      ], now);
      expect(r.map((x) => x.payload.at), [
        DateTime(2030, 2, 27, 9),
        DateTime(2030, 2, 28, 9),
        DateTime(2030, 3, 1, 9),
      ]);
    });

    test('9:00 holds across a daylight-saving change', () {
      final r = autoRings([
        loan('a', TransactionType.lent, 100, DateTime(2030, 3, 10)),
      ], DateTime(2030, 3, 1));
      expect(r.every((x) => x.payload.at.hour == 9), isTrue);
    });
  });

  group('openAutoIds', () {
    test('includes past rings of open entries, none for paid or off', () {
      final ids = openAutoIds([
        loan('a', TransactionType.lent, 100, DateTime(2020, 1, 10)),
        loan(
          'b',
          TransactionType.lent,
          100,
          DateTime(2030, 1, 10),
          status: TransactionStatus.paid,
          paid: 100,
        ),
        loan(
          'c',
          TransactionType.lent,
          100,
          DateTime(2030, 1, 10),
          auto: false,
        ),
      ], now);
      expect(ids.length, 3);
      expect(ids.every((i) => i.startsWith('auto:a:')), isTrue);
    });
  });

  group('planAllAlarms', () {
    Reminder rem(String id, DateTime at) => Reminder(
      id: id,
      title: 'R$id',
      at: at,
      createdAt: DateTime(2026, 1, 1),
    );

    test('manual reminders and automatic alarms share one plan', () {
      final plan = planAllAlarms(
        [rem('r1', DateTime(2030, 1, 8, 8))],
        [loan('a', TransactionType.lent, 100, DateTime(2030, 1, 10))],
        now,
      );
      expect(plan.length, 4);
      expect(plan.first.payload.reminderId, 'r1');
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].at.isBefore(plan[i - 1].at), isFalse);
      }
    });

    test('ids never clash between manual and automatic alarms', () {
      final txns = [
        for (var i = 0; i < 20; i++)
          loan('t$i', TransactionType.lent, 100, DateTime(2030, 1, 10 + i % 5)),
      ];
      final rs = [
        for (var i = 0; i < 20; i++) rem('r$i', DateTime(2030, 1, 8, 8, i)),
      ];
      for (final hash in [reminderKey, (String _) => 5]) {
        final plan = planAllAlarms(rs, txns, now, hash: hash);
        expect(plan.map((a) => a.id).toSet().length, plan.length);
      }
    });

    test('entries further than 60 days out are left for later', () {
      final plan = planAllAlarms(const [], [
        loan('a', TransactionType.lent, 100, DateTime(2030, 6, 10)),
      ], now);
      expect(plan, isEmpty);
    });

    test('the 200 cap is shared', () {
      final txns = [
        for (var i = 0; i < 100; i++)
          loan('t$i', TransactionType.lent, 100, DateTime(2030, 1, 10)),
      ]; // 300 automatic rings
      expect(planAllAlarms(const [], txns, now).length, 200);
    });

    test('payload round-trips the entry id', () {
      final p = autoRings([
        loan('abc', TransactionType.lent, 100, DateTime(2030, 1, 10)),
      ], now).first.payload;
      expect(AlarmPayload.decode(p.encode())!.entryId, 'abc');
    });
  });

  group('MoneyTransaction.autoReminders', () {
    test('defaults to on, is only stored when off, old docs load', () {
      final on = loan('a', TransactionType.lent, 100, DateTime(2030, 1, 10));
      expect(on.autoReminders, isTrue);
      expect(on.toMap().containsKey('autoReminders'), isFalse);
      final off = loan(
        'a',
        TransactionType.lent,
        100,
        DateTime(2030, 1, 10),
        auto: false,
      );
      expect(off.toMap()['autoReminders'], false);
      expect(MoneyTransaction.fromMap('a', off.toMap()).autoReminders, isFalse);
      expect(MoneyTransaction.fromMap('a', on.toMap()).autoReminders, isTrue);
    });
  });
}
