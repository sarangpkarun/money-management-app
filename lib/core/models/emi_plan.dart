import 'package:cloud_firestore/cloud_firestore.dart';

import '../emi/emi_schedule.dart';
import '../money/money.dart';

enum EmiRowStatus { paid, partial, overdue, upcoming }

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _date(Object? v) => (v as Timestamp).toDate();

/// One instalment of an EMI purchase, with how much of it has been paid.
class EmiRow {
  const EmiRow({
    required this.number,
    required this.dueDate,
    required this.amount,
    required this.principal,
    required this.interest,
    this.balanceAfter = Money.zero,
    this.paidAmount = Money.zero,
    this.paidOn,
  });

  /// 1-based.
  final int number;
  final DateTime dueDate;
  final Money amount;
  final Money principal;
  final Money interest;
  final Money balanceAfter;
  final Money paidAmount;

  /// The date of the latest payment towards this row.
  final DateTime? paidOn;

  /// What is still to pay on this row. Never below zero.
  Money get remaining {
    final left = amount - paidAmount;
    return left.isNegative ? Money.zero : left;
  }

  bool get isPaid => paidAmount >= amount;

  /// Paid is green, upcoming amber, overdue red, part-paid blue. Overdue is
  /// worked out from the date at read time (from the day after the due date)
  /// and wins over part-paid, as a late instalment is still late.
  EmiRowStatus statusAt(DateTime now) {
    if (isPaid) return EmiRowStatus.paid;
    if (_day(now).isAfter(_day(dueDate))) return EmiRowStatus.overdue;
    return paidAmount > Money.zero
        ? EmiRowStatus.partial
        : EmiRowStatus.upcoming;
  }

  EmiRow copyWith({
    Money? paidAmount,
    DateTime? paidOn,
    bool clearPaidOn = false,
  }) => EmiRow(
    number: number,
    dueDate: dueDate,
    amount: amount,
    principal: principal,
    interest: interest,
    balanceAfter: balanceAfter,
    paidAmount: paidAmount ?? this.paidAmount,
    paidOn: clearPaidOn ? null : (paidOn ?? this.paidOn),
  );

  Map<String, dynamic> toMap() => {
    'number': number,
    'dueDate': Timestamp.fromDate(dueDate),
    'amount': amount.paise,
    'principal': principal.paise,
    'interest': interest.paise,
    'balanceAfter': balanceAfter.paise,
    'paidAmount': paidAmount.paise,
    'paidOn': paidOn == null ? null : Timestamp.fromDate(paidOn!),
  };

  factory EmiRow.fromMap(Map<String, dynamic> m) => EmiRow(
    number: m['number'] as int,
    dueDate: _date(m['dueDate']),
    amount: Money(m['amount'] as int),
    principal: Money(m['principal'] as int),
    interest: Money(m['interest'] as int),
    balanceAfter: Money((m['balanceAfter'] as int?) ?? 0),
    paidAmount: Money((m['paidAmount'] as int?) ?? 0),
    paidOn: m['paidOn'] == null ? null : _date(m['paidOn']),
  );
}

/// The terms of an EMI purchase and its schedule with payment progress.
class EmiPlan {
  const EmiPlan({
    required this.price,
    required this.downPayment,
    required this.annualRatePercent,
    required this.months,
    required this.emi,
    required this.startDate,
    required this.rows,
  });

  /// Builds a plan with nothing paid from a generated [schedule].
  factory EmiPlan.fromSchedule(
    EmiSchedule schedule, {
    required Money price,
    required Money downPayment,
    required double annualRatePercent,
    required DateTime startDate,
  }) => EmiPlan(
    price: price,
    downPayment: downPayment,
    annualRatePercent: annualRatePercent,
    months: schedule.months,
    emi: schedule.emi,
    startDate: startDate,
    rows: [
      for (final i in schedule.installments)
        EmiRow(
          number: i.number,
          dueDate: i.dueDate,
          amount: i.amount,
          principal: i.principal,
          interest: i.interest,
          balanceAfter: i.balanceAfter,
        ),
    ],
  );

  final Money price;
  final Money downPayment;
  final double annualRatePercent;
  final int months;

  /// The regular monthly amount (the last row can differ by a few paise).
  final Money emi;
  final DateTime startDate;
  final List<EmiRow> rows;

  /// Everything due in instalments (excludes the down payment).
  Money get totalPayable =>
      rows.fold(Money.zero, (total, r) => total + r.amount);

  /// The first row not fully paid, or null once everything is paid.
  EmiRow? get nextUnpaid {
    for (final r in rows) {
      if (!r.isPaid) return r;
    }
    return null;
  }

  EmiRow? rowNumbered(int number) {
    for (final r in rows) {
      if (r.number == number) return r;
    }
    return null;
  }

  /// A copy with a different set of rows (the tenure follows the row count).
  EmiPlan copyWithRows(List<EmiRow> newRows) => EmiPlan(
    price: price,
    downPayment: downPayment,
    annualRatePercent: annualRatePercent,
    months: newRows.length,
    emi: emi,
    startDate: startDate,
    rows: newRows,
  );

  /// A copy with [row] replacing the row that has the same number.
  EmiPlan copyWithRow(EmiRow row) => EmiPlan(
    price: price,
    downPayment: downPayment,
    annualRatePercent: annualRatePercent,
    months: months,
    emi: emi,
    startDate: startDate,
    rows: [for (final r in rows) r.number == row.number ? row : r],
  );

  /// The terms, without the rows (those go in a separate `schedule` list so a
  /// payment can rewrite them in one transaction).
  Map<String, dynamic> toMap() => {
    'price': price.paise,
    'downPayment': downPayment.paise,
    'annualRatePercent': annualRatePercent,
    'months': months,
    'emi': emi.paise,
    'startDate': Timestamp.fromDate(startDate),
  };

  List<Map<String, dynamic>> scheduleToMaps() => [
    for (final r in rows) r.toMap(),
  ];

  factory EmiPlan.fromMaps(
    Map<String, dynamic> terms,
    List<dynamic> schedule,
  ) => EmiPlan(
    price: Money(terms['price'] as int),
    downPayment: Money(terms['downPayment'] as int),
    annualRatePercent: (terms['annualRatePercent'] as num).toDouble(),
    months: terms['months'] as int,
    emi: Money(terms['emi'] as int),
    startDate: _date(terms['startDate']),
    rows: [
      for (final r in schedule)
        EmiRow.fromMap(Map<String, dynamic>.from(r as Map)),
    ],
  );
}
