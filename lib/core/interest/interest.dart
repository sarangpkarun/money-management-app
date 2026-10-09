import 'dart:math' as math;

import '../models/money_transaction.dart';
import '../money/money.dart';

/// The calendar date as a UTC midnight, so differences count whole days even
/// across daylight-saving changes (local midnights can be 23 or 25 hours apart).
DateTime _dayOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Interest earned on [principal] between [from] and [to] (whole days, a year
/// being 365 days), rounded to the nearest paisa.
///
/// Simple: P * R * T. Compound: monthly compounding, P * ((1 + R/12)^(12T) - 1)
/// (product doc 8.5). [annualRatePercent] is e.g. 12 for 12% a year.
Money interestAccrued({
  required Money principal,
  required InterestType type,
  required double annualRatePercent,
  required DateTime from,
  required DateTime to,
}) {
  if (type == InterestType.none || annualRatePercent <= 0) return Money.zero;
  final days = _dayOnly(to).difference(_dayOnly(from)).inDays;
  if (days <= 0) return Money.zero;
  final years = days / 365;
  final rate = annualRatePercent / 100;
  final paise = switch (type) {
    InterestType.simple => principal.paise * rate * years,
    InterestType.compound =>
      principal.paise * (math.pow(1 + rate / 12, 12 * years) - 1),
    InterestType.none => 0.0,
  };
  return Money(paise.round());
}

/// Principal plus the interest accrued from the entry date to [at], ignoring
/// whether the entry has been settled.
Money amountDueAt(MoneyTransaction t, DateTime at) =>
    t.totalAmount +
    interestAccrued(
      principal: t.totalAmount,
      type: t.interestType,
      annualRatePercent: t.interestRate ?? 0,
      from: t.entryDate,
      to: at,
    );

/// Where interest stops: now, or the moment the entry was settled.
DateTime accrualEnd(MoneyTransaction t, DateTime now) {
  final settled = t.settledAt;
  return (settled != null && settled.isBefore(now)) ? settled : now;
}

Money interestFor(MoneyTransaction t, DateTime now) =>
    amountDueAt(t, accrualEnd(t, now)) - t.totalAmount;

/// Principal plus interest to date (frozen once settled).
Money amountDue(MoneyTransaction t, DateTime now) =>
    amountDueAt(t, accrualEnd(t, now));

/// What is still to be paid, interest included. Never below zero.
Money outstanding(MoneyTransaction t, DateTime now) {
  final left = amountDue(t, now) - t.paidTotal;
  return left.isNegative ? Money.zero : left;
}
