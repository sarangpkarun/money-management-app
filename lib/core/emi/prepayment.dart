import '../models/emi_plan.dart';
import '../money/money.dart';
import 'emi_schedule.dart';
import 'month_dates.dart';

const _maxMonths = 600;

Money _share(Money whole, Money part, Money of) => of.isZero
    ? Money.zero
    : Money((whole.paise * part.paise / of.paise).round());

/// The part of an unpaid row that is still principal: a part-paid row counts
/// its unpaid share. Rows paid in any order are handled.
Money _principalLeft(EmiRow r) => _share(r.principal, r.remaining, r.amount);

Money _interestLeft(EmiRow r) => _share(r.interest, r.remaining, r.amount);

/// The principal still owed across all unpaid rows.
Money outstandingPrincipal(EmiPlan plan) => plan.rows
    .where((r) => !r.isPaid)
    .fold(Money.zero, (sum, r) => sum + _principalLeft(r));

/// What closing the loan today would cost, as an estimate: the principal still
/// owed plus a foreclosure charge of [chargePercent] of it. Interest for the
/// part of the current month already run is not included, and a lender may
/// count things differently.
class ForeclosureEstimate {
  const ForeclosureEstimate({
    required this.principal,
    required this.charge,
    required this.saved,
  });

  final Money principal;
  final Money charge;

  /// Interest in the unpaid rows that is not paid by closing now.
  final Money saved;

  Money get total => principal + charge;
}

ForeclosureEstimate foreclosureEstimate(
  EmiPlan plan, {
  double chargePercent = 0,
}) {
  if (!chargePercent.isFinite || chargePercent < 0 || chargePercent > 100) {
    throw const EmiInputError('Charge must be between 0 and 100 percent');
  }
  final unpaid = plan.rows.where((r) => !r.isPaid);
  if (unpaid.isEmpty) throw const EmiInputError('Nothing left to pay');
  final principal = outstandingPrincipal(plan);
  return ForeclosureEstimate(
    principal: principal,
    charge: Money((principal.paise * chargePercent / 100).round()),
    saved: unpaid.fold(Money.zero, (sum, r) => sum + _interestLeft(r)),
  );
}

/// What a part-prepayment keeps the same.
enum PrepaymentKeep { emi, tenure }

/// The estimated effect of paying part of the principal now.
class PartPrepaymentResult {
  const PartPrepaymentResult({
    required this.newBalance,
    required this.monthsBefore,
    required this.monthsAfter,
    required this.emiAfter,
    required this.lastDueDate,
    required this.interestSaved,
  });

  /// Principal left after the prepayment.
  final Money newBalance;
  final int monthsBefore;
  final int monthsAfter;

  /// The regular monthly amount afterwards.
  final Money emiAfter;
  final DateTime lastDueDate;

  /// Interest that no longer has to be paid.
  final Money interestSaved;
}

PartPrepaymentResult partPrepayment(
  EmiPlan plan,
  Money amount, {
  required PrepaymentKeep keep,
}) {
  final unpaid = plan.rows.where((r) => !r.isPaid).toList();
  if (unpaid.isEmpty) throw const EmiInputError('Nothing left to pay');
  if (amount <= Money.zero) {
    throw const EmiInputError('Amount must be above 0');
  }
  final principal = outstandingPrincipal(plan);
  if (amount >= principal) {
    throw EmiInputError(
      'That clears the loan (${principal.format()} principal left): '
      'use foreclosure instead',
    );
  }

  final balance = principal - amount;
  final r = plan.annualRatePercent / 12 / 100;
  final monthsBefore = unpaid.length;
  final interestBefore = unpaid.fold(
    Money.zero,
    (sum, row) => sum + _interestLeft(row),
  );
  final firstDue = unpaid.first.dueDate;
  // The regular EMI of the plan; the unpaid rows' own amount if it is unset.
  final emi = plan.emi > Money.zero ? plan.emi : unpaid.first.amount;

  late final int months;
  late final Money emiAfter;
  late final Money interestAfter;

  if (keep == PrepaymentKeep.tenure) {
    final s = generateEmiSchedule(
      price: balance,
      annualRatePercent: plan.annualRatePercent,
      months: monthsBefore,
      startDate: firstDue,
    );
    months = monthsBefore;
    emiAfter = s.emi;
    interestAfter = s.totalInterest;
  } else {
    var opening = balance.paise;
    var interest = 0;
    var count = 0;
    while (opening > 0) {
      count++;
      if (count > _maxMonths) {
        throw const EmiInputError('That would take more than 600 months');
      }
      final monthly = (opening * r).round();
      final principalPart = emi.paise - monthly;
      if (principalPart <= 0) {
        throw const EmiInputError('The EMI does not cover the interest');
      }
      interest += monthly;
      opening -= principalPart < opening ? principalPart : opening;
    }
    months = count;
    emiAfter = emi;
    interestAfter = Money(interest);
  }

  return PartPrepaymentResult(
    newBalance: balance,
    monthsBefore: monthsBefore,
    monthsAfter: months,
    emiAfter: emiAfter,
    lastDueDate: addMonthsClamped(firstDue, months - 1),
    interestSaved: interestBefore - interestAfter,
  );
}
