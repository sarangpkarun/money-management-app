import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/emi/emi_schedule.dart';
import 'package:money_manager/core/emi/emi_summary.dart';
import 'package:money_manager/core/models/emi_plan.dart';
import 'package:money_manager/core/money/money.dart';

EmiPlan plan() {
  final s = generateEmiSchedule(
    price: Money.fromRupees(12000),
    annualRatePercent: 0,
    months: 4,
    startDate: DateTime(2026, 10, 15),
  );
  return EmiPlan.fromSchedule(
    s,
    price: Money.fromRupees(12000),
    downPayment: Money.zero,
    annualRatePercent: 0,
    startDate: DateTime(2026, 10, 15),
  );
}

EmiPlan paid(EmiPlan p, int count) {
  var out = p;
  for (final r in p.rows.take(count)) {
    out = out.copyWithRow(r.copyWith(paidAmount: r.amount, paidOn: r.dueDate));
  }
  return out;
}

void main() {
  final early = DateTime(2026, 9, 1); // before any due date

  test('a fresh plan: next is the first row, everything remains', () {
    final s = summarizePlan(plan(), early);
    expect(s.next!.number, 1);
    expect(s.next!.dueDate, DateTime(2026, 10, 15));
    expect(s.next!.amount, Money.fromRupees(3000));
    expect(s.remainingCount, 4);
    expect(s.remainingTotal, Money.fromRupees(12000));
    expect(s.paidCount, 0);
    expect(s.overdueCount, 0);
    expect(s.lastDueDate, DateTime(2027, 1, 15));
  });

  test('after paying two: next is the third, two remain', () {
    final s = summarizePlan(paid(plan(), 2), early);
    expect(s.next!.number, 3);
    expect(s.remainingCount, 2);
    expect(s.remainingTotal, Money.fromRupees(6000));
    expect(s.paidCount, 2);
  });

  test('a part-paid row still counts as remaining, by what is left', () {
    final p = plan();
    final part = p.copyWithRow(
      p.rows[0].copyWith(paidAmount: Money.fromRupees(1000)),
    );
    final s = summarizePlan(part, early);
    expect(s.next!.number, 1);
    expect(s.remainingCount, 4);
    expect(s.remainingTotal, Money.fromRupees(11000));
    expect(s.paidCount, 0);
  });

  test('overdue rows are counted from the date, with what they still owe', () {
    // 16 Nov: rows 1 (15 Oct) and 2 (15 Nov) are late; row 3 is 15 Dec.
    final s = summarizePlan(plan(), DateTime(2026, 11, 16));
    expect(s.overdueCount, 2);
    expect(s.overdueAmount, Money.fromRupees(6000));
    expect(s.next!.number, 1); // the oldest unpaid row is the one to pay
  });

  test('a paid row is never overdue', () {
    final s = summarizePlan(paid(plan(), 1), DateTime(2026, 11, 16));
    expect(s.overdueCount, 1); // only row 2
  });

  test('everything paid: no next row, nothing remaining', () {
    final s = summarizePlan(paid(plan(), 4), DateTime(2030, 1, 1));
    expect(s.next, isNull);
    expect(s.remainingCount, 0);
    expect(s.remainingTotal, Money.zero);
    expect(s.paidCount, 4);
    expect(s.overdueCount, 0);
    expect(s.isComplete, isTrue);
  });

  test('isComplete is false while anything remains', () {
    expect(summarizePlan(paid(plan(), 3), early).isComplete, isFalse);
  });

  test('a plan with no rows left is complete and does not crash', () {
    final empty = plan().copyWithRows(const []);
    final s = summarizePlan(empty, DateTime(2026, 1, 1));
    expect(s.next, isNull);
    expect(s.remainingCount, 0);
    expect(s.remainingTotal, Money.zero);
    expect(s.isComplete, isTrue);
    expect(s.lastDueDate, empty.startDate);
  });
}
