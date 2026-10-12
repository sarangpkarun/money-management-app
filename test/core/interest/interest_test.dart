import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/interest/interest.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';

void main() {
  final start = DateTime(2025, 10, 9);
  final oneYear = DateTime(2026, 10, 9); // 365 days later

  group('interestAccrued', () {
    Money acc(
      InterestType type,
      double rate,
      DateTime to, {
      int rupees = 10000,
      DateTime? from,
    }) => interestAccrued(
      principal: Money.fromRupees(rupees),
      type: type,
      annualRatePercent: rate,
      from: from ?? start,
      to: to,
    );

    test('flat: a one-off percentage of the principal, whatever the time', () {
      expect(acc(InterestType.flat, 5, start), Money.fromRupees(500));
      expect(acc(InterestType.flat, 5, oneYear), Money.fromRupees(500));
    });

    test('simple per month: 2% a month for a year is 2,400', () {
      expect(
        interestAccrued(
          principal: Money.fromRupees(10000),
          type: InterestType.simple,
          annualRatePercent: 2,
          period: RatePeriod.month,
          from: start,
          to: oneYear,
        ),
        Money.fromRupees(2400),
      );
    });

    test('compound per month equals compound yearly at 12x the rate', () {
      expect(
        interestAccrued(
          principal: Money.fromRupees(10000),
          type: InterestType.compound,
          annualRatePercent: 1,
          period: RatePeriod.month,
          from: start,
          to: oneYear,
        ),
        acc(InterestType.compound, 12, oneYear),
      );
    });

    test('flat: a one-off percentage, whatever the duration', () {
      expect(acc(InterestType.flat, 5, start), Money.fromRupees(500));
      expect(acc(InterestType.flat, 5, oneYear), Money.fromRupees(500));
    });

    test('monthly rate: 2% a month simple is 2,400 over a year', () {
      expect(
        interestAccrued(
          principal: Money.fromRupees(10000),
          type: InterestType.simple,
          annualRatePercent: 2,
          period: RatePeriod.month,
          from: start,
          to: oneYear,
        ),
        Money.fromRupees(2400),
      );
    });

    test('monthly compound equals yearly compound at rate x 12', () {
      expect(
        interestAccrued(
          principal: Money.fromRupees(10000),
          type: InterestType.compound,
          annualRatePercent: 1,
          period: RatePeriod.month,
          from: start,
          to: oneYear,
        ),
        acc(InterestType.compound, 12, oneYear),
      );
    });

    test('simple: 10,000 at 12% for a year is exactly 1,200', () {
      expect(acc(InterestType.simple, 12, oneYear), Money.fromRupees(1200));
    });

    test('simple: half a year (182.5 days) rounds to the paise', () {
      // 10,000 * 12% * 183/365 = 601.64 (183 days, rounded).
      expect(
        acc(InterestType.simple, 12, start.add(const Duration(days: 183))),
        const Money(60164),
      );
    });

    test('compound monthly: 10,000 at 12% for a year is 1,268.25', () {
      // 10,000 * (1.01^12 - 1) = 1,268.2503... -> 1,268.25
      expect(acc(InterestType.compound, 12, oneYear), const Money(126825));
    });

    test('compound is always at least simple for the same period', () {
      final s = acc(InterestType.simple, 18, oneYear);
      final c = acc(InterestType.compound, 18, oneYear);
      expect(c > s, isTrue);
    });

    test('no interest for none, zero rate, or a non-positive period', () {
      expect(acc(InterestType.none, 12, oneYear), Money.zero);
      expect(acc(InterestType.simple, 0, oneYear), Money.zero);
      expect(acc(InterestType.simple, 12, start), Money.zero);
      expect(acc(InterestType.simple, 12, DateTime(2025, 1, 1)), Money.zero);
    });

    test(
      'whole days are counted correctly across a daylight-saving change',
      () {
        // 1 Mar -> 1 Apr is 31 days even where the clocks change in between
        // (run with TZ=America/New_York to exercise this).
        // 10,000 * 12% * 31/365 = 101.92
        expect(
          acc(
            InterestType.simple,
            12,
            DateTime(2026, 4, 1),
            from: DateTime(2026, 3, 1),
          ),
          const Money(10192),
        );
      },
    );

    test('time of day does not matter, only whole days', () {
      final a = acc(
        InterestType.simple,
        12,
        DateTime(2026, 10, 9, 23, 59),
        from: DateTime(2025, 10, 9, 8),
      );
      expect(a, Money.fromRupees(1200));
    });
  });

  MoneyTransaction txn({
    InterestType type = InterestType.simple,
    double? rate = 12,
    int paid = 0,
    TransactionStatus status = TransactionStatus.pending,
    DateTime? settledAt,
  }) => MoneyTransaction(
    type: TransactionType.borrowed,
    personId: 'p',
    personName: 'Ravi',
    title: 't',
    totalAmount: Money.fromRupees(10000),
    paidTotal: Money.fromRupees(paid),
    status: status,
    interestType: type,
    interestRate: rate,
    createdAt: start,
    date: start,
    settledAt: settledAt,
  );

  group('amount due and outstanding', () {
    test('due is principal plus interest to now', () {
      final t = txn();
      expect(interestFor(t, oneYear), Money.fromRupees(1200));
      expect(amountDue(t, oneYear), Money.fromRupees(11200));
    });

    test('outstanding subtracts payments', () {
      final t = txn(paid: 4000);
      expect(outstanding(t, oneYear), Money.fromRupees(7200));
    });

    test('an entry without interest is just the principal', () {
      final t = txn(type: InterestType.none, rate: null);
      expect(amountDue(t, oneYear), Money.fromRupees(10000));
    });

    test('interest stops accruing once the entry is settled', () {
      final settled = DateTime(2026, 4, 9); // 182 days in
      final t = txn(
        paid: 10599,
        status: TransactionStatus.paid,
        settledAt: settled,
      );
      final atSettle = interestFor(t, settled);
      // Much later, the interest is unchanged.
      expect(interestFor(t, DateTime(2030, 1, 1)), atSettle);
      expect(amountDue(t, DateTime(2030, 1, 1)), amountDue(t, settled));
      expect(outstanding(t, DateTime(2030, 1, 1)), outstanding(t, settled));
    });

    test('outstanding never goes below zero', () {
      final t = txn(paid: 99999);
      expect(outstanding(t, oneYear), Money.zero);
    });

    test('amountDueAt evaluates at any moment, ignoring settledAt', () {
      final t = txn(settledAt: DateTime(2026, 1, 1));
      expect(amountDueAt(t, oneYear), Money.fromRupees(11200));
    });
  });
}
