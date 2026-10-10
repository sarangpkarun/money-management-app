import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/emi/emi_schedule.dart';
import 'package:money_manager/core/instalments/instalment_plan.dart';
import 'package:money_manager/core/models/emi_plan.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';
import 'package:money_manager/home/due_items.dart';

MoneyTransaction entry(
  String id,
  DateTime? due, {
  TransactionType type = TransactionType.lent,
  int rupees = 100,
  int paid = 0,
  TransactionStatus status = TransactionStatus.pending,
  String person = 'Asha',
  String title = 'Loan',
  InterestType interest = InterestType.none,
  double? rate,
  DateTime? date,
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
  interestType: interest,
  interestRate: rate,
  createdAt: DateTime(2026, 1, 1),
  date: date,
);

DueGroups groups(List<MoneyTransaction> t, DateTime now) =>
    groupDueItems(dueItems(t, now), now);

List<String> ids(DueGroup g) => [for (final i in g.items) i.entry.id];

void main() {
  // Mon 7 Jan 2030: the week ends Sun 13 Jan, the month ends Thu 31 Jan.
  final monday = DateTime(2030, 1, 7, 12);

  group('buckets', () {
    test('every boundary lands in exactly one bucket', () {
      final g = groups([
        entry('yesterday', DateTime(2030, 1, 6)),
        entry('today', DateTime(2030, 1, 7)),
        entry('sunday', DateTime(2030, 1, 13)),
        entry('nextMon', DateTime(2030, 1, 14)),
        entry('monthEnd', DateTime(2030, 1, 31)),
        entry('nextMonth', DateTime(2030, 2, 1)),
      ], monday);
      expect(ids(g.overdue), ['yesterday']);
      expect(ids(g.thisWeek), ['today', 'sunday']);
      expect(ids(g.thisMonth), ['nextMon', 'monthEnd']);
      expect(ids(g.upcoming), ['nextMonth']);
    });

    test('nothing is counted twice or lost', () {
      final all = [
        for (var d = 1; d <= 60; d++)
          entry('e$d', DateTime(2029, 12, 20).add(Duration(days: d))),
      ];
      final g = groups(all, monday);
      final total =
          g.overdue.count +
          g.thisWeek.count +
          g.thisMonth.count +
          g.upcoming.count;
      expect(total, 60);
    });

    test('due today is not overdue (overdue starts the day after)', () {
      final g = groups([
        entry('a', DateTime(2030, 1, 7, 0, 5)),
      ], DateTime(2030, 1, 7, 23, 59));
      expect(g.overdue.isEmpty, isTrue);
      expect(ids(g.thisWeek), ['a']);
    });

    test('on a Sunday the week is just today', () {
      final sunday = DateTime(2030, 1, 13, 9);
      final g = groups([
        entry('today', DateTime(2030, 1, 13)),
        entry('tomorrow', DateTime(2030, 1, 14)),
      ], sunday);
      expect(ids(g.thisWeek), ['today']);
      expect(ids(g.thisMonth), ['tomorrow']);
    });

    test('when the week runs into next month, this month is empty', () {
      // Thu 31 Jan: the week ends Sun 3 Feb.
      final thu = DateTime(2030, 1, 31, 8);
      final g = groups([
        entry('fri', DateTime(2030, 2, 1)),
        entry('sun', DateTime(2030, 2, 3)),
        entry('mon', DateTime(2030, 2, 4)),
      ], thu);
      expect(ids(g.thisWeek), ['fri', 'sun']);
      expect(g.thisMonth.isEmpty, isTrue);
      expect(ids(g.upcoming), ['mon']);
    });

    test('year rollover: Dec 30 is a Monday, the week reaches 5 Jan', () {
      final now = DateTime(2030, 12, 30, 10);
      final g = groups([
        entry('a', DateTime(2030, 12, 31)),
        entry('b', DateTime(2031, 1, 5)),
        entry('c', DateTime(2031, 1, 6)),
      ], now);
      expect(ids(g.thisWeek), ['a', 'b']);
      expect(ids(g.upcoming), ['c']);
    });

    test('the time of day on the due date does not matter', () {
      final g = groups([
        entry('a', DateTime(2030, 1, 6, 23, 59)),
        entry('b', DateTime(2030, 1, 7, 0, 0)),
      ], monday);
      expect(ids(g.overdue), ['a']);
      expect(ids(g.thisWeek), ['b']);
    });

    test('same buckets under any timezone (calendar days, not instants)', () {
      final g = groups([
        entry('a', DateTime(2030, 3, 10)),
      ], DateTime(2030, 3, 10, 1));
      expect(ids(g.thisWeek), ['a']);
    });
  });

  group('what counts', () {
    test('paid entries, no due date and zero owed give nothing', () {
      final items = dueItems([
        entry(
          'paid',
          DateTime(2030, 1, 10),
          status: TransactionStatus.paid,
          paid: 100,
        ),
        entry('none', null),
        entry('cleared', DateTime(2030, 1, 10), paid: 100),
      ], monday);
      expect(items, isEmpty);
    });

    test('amount is what is left, partial payments taken off', () {
      final items = dueItems([
        entry('a', DateTime(2030, 1, 10), rupees: 1000, paid: 400),
      ], monday);
      expect(items.single.amount, Money.fromRupees(600));
    });

    test('an entry with interest uses what is owed including interest', () {
      // Borrowed Rs 10,000 at 12% simple, a year ago: about Rs 11,200 owed.
      final items = dueItems([
        entry(
          'loan',
          DateTime(2030, 1, 20),
          type: TransactionType.borrowed,
          rupees: 10000,
          interest: InterestType.simple,
          rate: 12,
          date: DateTime(2029, 1, 7),
        ),
      ], monday);
      expect(items.single.amount, Money.fromRupees(11200));
    });

    test('receive and pay totals are kept apart', () {
      final g = groups([
        entry('a', DateTime(2030, 1, 8), rupees: 300),
        entry(
          'b',
          DateTime(2030, 1, 9),
          rupees: 200,
          type: TransactionType.borrowed,
        ),
        entry(
          'c',
          DateTime(2030, 1, 10),
          rupees: 50,
          type: TransactionType.lent,
        ),
        entry(
          'd',
          DateTime(2030, 1, 10),
          rupees: 70,
          type: TransactionType.borrowed,
        ),
      ], monday);
      expect(g.thisWeek.toReceive, Money.fromRupees(350));
      expect(g.thisWeek.toPay, Money.fromRupees(270));
      expect(g.thisWeek.count, 4);
    });

    test('soonest first, overdue oldest first', () {
      final g = groups([
        entry('b', DateTime(2030, 1, 5)),
        entry('a', DateTime(2030, 1, 1)),
        entry('d', DateTime(2030, 1, 12)),
        entry('c', DateTime(2030, 1, 8)),
      ], monday);
      expect(ids(g.overdue), ['a', 'b']);
      expect(ids(g.thisWeek), ['c', 'd']);
    });
  });

  group('plans', () {
    MoneyTransaction emi({int paidRows = 0}) {
      final s = generateEmiSchedule(
        price: Money.fromRupees(12000),
        annualRatePercent: 0,
        months: 4,
        startDate: DateTime(2030, 1, 8),
      );
      final p = EmiPlan.fromSchedule(
        s,
        price: Money.fromRupees(12000),
        downPayment: Money.zero,
        annualRatePercent: 0,
        startDate: DateTime(2030, 1, 8),
      );
      return MoneyTransaction(
        id: 'e',
        type: TransactionType.emi,
        personId: 'p',
        personName: 'Croma',
        title: 'Phone',
        totalAmount: p.totalPayable,
        createdAt: DateTime(2026, 1, 1),
        emiPlan: p.copyWithRows([
          for (final r in p.rows)
            r.number <= paidRows ? r.copyWith(paidAmount: r.amount) : r,
        ]),
      );
    }

    test('every unpaid row is its own item, labelled', () {
      final items = dueItems([emi()], monday);
      expect(items.length, 4);
      expect(items.first.what, 'EMI #1 · Phone');
      expect(items.first.rowNumber, 1);
      expect(items.first.amount, Money.fromRupees(3000));
      expect(items.first.isReceivable, isFalse);
    });

    test('paid rows are skipped and rows spread over the buckets', () {
      final g = groups([emi(paidRows: 1)], monday);
      // Rows due 8 Feb, 8 Mar, 8 Apr 2030 (row 1, 8 Jan, is paid).
      expect(g.thisWeek.isEmpty, isTrue);
      expect(g.upcoming.count, 3);
    });

    test('rows split across overdue and later as time passes', () {
      // Sat 9 Feb 2030: rows 8 Jan and 8 Feb are past; 8 Mar and 8 Apr are later.
      final g = groups([emi()], DateTime(2030, 2, 9, 9));
      expect(g.overdue.count, 2);
      expect(g.thisWeek.isEmpty, isTrue);
      expect(g.thisMonth.isEmpty, isTrue);
      expect(g.upcoming.count, 2);
    });

    test('a part-paid row shows what is left on it', () {
      final t = emi();
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
      expect(dueItems([part], monday).first.amount, Money.fromRupees(2000));
    });

    test('instalment rows say Payment and a skipped month moves the date', () {
      final plan = generateInstalmentPlan(
        total: Money.fromRupees(1000),
        months: 2,
        startDate: DateTime(2030, 1, 8),
      );
      final skipped = skipMonth(plan, 1);
      MoneyTransaction t(EmiPlan p) => MoneyTransaction(
        id: 'i',
        type: TransactionType.instalment,
        personId: 'p',
        personName: 'Ravi',
        title: 'Loan',
        totalAmount: Money.fromRupees(1000),
        createdAt: DateTime(2026, 1, 1),
        emiPlan: p,
      );
      expect(dueItems([t(plan)], monday).first.what, 'Payment #1 · Loan');
      expect(dueItems([t(plan)], monday).first.date, DateTime(2030, 1, 8));
      expect(dueItems([t(skipped)], monday).first.date, DateTime(2030, 2, 8));
    });
  });

  group('dueLabel', () {
    String label(DateTime due, DateTime now) => dueLabel(
      dueItems([entry('a', due)], now).single,
      now,
      (d) => '${d.day}/${d.month}/${d.year}',
    );
    final now = DateTime(2030, 1, 7, 15);
    test('late, today, tomorrow and later', () {
      expect(label(DateTime(2030, 1, 6), now), '1 day late');
      expect(label(DateTime(2030, 1, 1), now), '6 days late');
      expect(label(DateTime(2030, 1, 7), now), 'Due today');
      expect(label(DateTime(2030, 1, 8), now), 'Due tomorrow');
      expect(label(DateTime(2030, 1, 20), now), 'Due 20/1/2030');
    });
    test('counts calendar days across a month end', () {
      expect(
        label(DateTime(2030, 2, 28), DateTime(2030, 3, 2, 8)),
        '2 days late',
      );
    });
  });
}
