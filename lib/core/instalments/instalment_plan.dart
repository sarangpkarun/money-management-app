import '../emi/month_dates.dart';
import '../models/emi_plan.dart';
import '../money/money.dart';

/// Thrown when an instalment plan cannot be made or changed as asked.
class InstalmentError implements Exception {
  const InstalmentError(this.message);

  final String message;

  @override
  String toString() => 'InstalmentError: $message';
}

const _maxRows = 600;

/// A plan to pay [total] to a person in equal monthly payments (no interest),
/// given either the number of [months] or the [monthlyAmount].
///
/// By months, the monthly amount is the total divided by the months, to the
/// paisa, and the last payment takes whatever is left over. By monthly amount,
/// the months are the total divided by it rounded up, and the last payment is
/// the (smaller) remainder. Due dates are the start date plus 0, 1, 2... months,
/// clamped to month end.
EmiPlan generateInstalmentPlan({
  required Money total,
  int? months,
  Money? monthlyAmount,
  required DateTime startDate,
}) {
  if (total <= Money.zero) {
    throw const InstalmentError('Total must be above 0');
  }
  if ((months == null) == (monthlyAmount == null)) {
    throw const InstalmentError(
      'Enter either the number of months or the monthly amount',
    );
  }

  final amounts = <int>[];
  final int regular;
  if (months != null) {
    if (months < 1 || months > _maxRows) {
      throw const InstalmentError('Months must be between 1 and $_maxRows');
    }
    regular = (total.paise / months).round();
    if (regular < 1) {
      throw const InstalmentError(
        'The total is too small for that many months',
      );
    }
    final last = total.paise - regular * (months - 1);
    if (last < 1) {
      throw const InstalmentError(
        'The total is too small for that many months',
      );
    }
    amounts
      ..addAll(List.filled(months - 1, regular))
      ..add(last);
  } else {
    if (monthlyAmount! <= Money.zero) {
      throw const InstalmentError('Monthly amount must be above 0');
    }
    if (monthlyAmount >= total) {
      regular = total.paise;
      amounts.add(total.paise);
    } else {
      regular = monthlyAmount.paise;
      final count = (total.paise / regular).ceil();
      if (count > _maxRows) {
        throw const InstalmentError(
          'That monthly amount would take more than $_maxRows months',
        );
      }
      amounts
        ..addAll(List.filled(count - 1, regular))
        ..add(total.paise - regular * (count - 1));
    }
  }

  final rows = [
    for (var i = 0; i < amounts.length; i++)
      EmiRow(
        number: i + 1,
        dueDate: addMonthsClamped(startDate, i),
        amount: Money(amounts[i]),
        principal: Money(amounts[i]),
        interest: Money.zero,
      ),
  ];
  return _normalise(
    EmiPlan(
      price: total,
      downPayment: Money.zero,
      annualRatePercent: 0,
      months: rows.length,
      emi: Money(regular),
      startDate: startDate,
      rows: rows,
    ),
    rows,
  );
}

/// The same plan with rows tidied: principal equals the amount (there is no
/// interest) and the balance falls row by row. Paid amounts are untouched.
EmiPlan _normalise(EmiPlan plan, List<EmiRow> rows) {
  var left = rows.fold(Money.zero, (total, r) => total + r.amount);
  final tidy = <EmiRow>[];
  for (final r in rows) {
    left = left - r.amount;
    tidy.add(
      EmiRow(
        number: r.number,
        dueDate: r.dueDate,
        amount: r.amount,
        principal: r.amount,
        interest: Money.zero,
        balanceAfter: left,
        paidAmount: r.paidAmount,
        paidOn: r.paidOn,
      ),
    );
  }
  return plan.copyWithRows(tidy);
}

/// The due date one month after [date], keeping [anchorDay] where the month
/// has it (so 28 Feb followed by 31 Mar when the plan started on the 31st).
DateTime _monthAfter(DateTime date, int anchorDay) {
  final index = date.year * 12 + (date.month - 1) + 1;
  final year = index ~/ 12;
  final month = index % 12 + 1;
  final last = daysInMonth(year, month);
  return DateTime(year, month, anchorDay < last ? anchorDay : last);
}

EmiRow _row(EmiPlan plan, int number) {
  final row = plan.rowNumbered(number);
  if (row == null) throw InstalmentError('There is no payment #$number');
  return row;
}

Money _unpaid(Iterable<EmiRow> rows) =>
    rows.fold(Money.zero, (total, r) => total + r.remaining);

/// Skips a month: payment [number] and every later payment that has nothing
/// paid move one month later, so the end date moves too. Amounts and numbers
/// stay. A payment with anything paid on it cannot be skipped.
EmiPlan skipMonth(EmiPlan plan, int number) {
  final row = _row(plan, number);
  if (row.paidAmount > Money.zero) {
    throw const InstalmentError(
      'A payment that already has money paid on it cannot be skipped',
    );
  }
  final anchor = plan.startDate.day;
  return plan.copyWithRows([
    for (final r in plan.rows)
      if (r.number >= number && r.paidAmount.isZero)
        EmiRow(
          number: r.number,
          dueDate: _monthAfter(r.dueDate, anchor),
          amount: r.amount,
          principal: r.principal,
          interest: r.interest,
          balanceAfter: r.balanceAfter,
          paidAmount: r.paidAmount,
          paidOn: r.paidOn,
        )
      else
        r,
  ]);
}

/// Changes payment [number] to [newAmount] and re-spreads what is left evenly
/// over the later payments, so the total still adds up. If nothing is left,
/// the later unpaid payments are removed (the plan ends earlier); if later
/// payments do not exist but something is left, a new payment is added a month
/// after the last one. Numbers are never reused.
EmiPlan changeAmount(EmiPlan plan, int number, Money newAmount) {
  final row = _row(plan, number);
  if (row.isPaid) {
    throw const InstalmentError('That payment is already paid');
  }
  if (newAmount <= Money.zero) {
    throw const InstalmentError('Amount must be above 0');
  }
  if (newAmount < row.paidAmount) {
    throw const InstalmentError(
      'Amount cannot be less than what is already paid on it',
    );
  }

  final fromHere = plan.rows.where((r) => r.number >= number).toList();
  // What is still to pay from this payment onwards, before and after.
  final owedBefore = _unpaid(fromHere);
  final owedOnThis = newAmount - row.paidAmount;
  if (owedOnThis > owedBefore) {
    throw InstalmentError(
      'More than what is still to pay (${owedBefore.format()})',
    );
  }
  final rest = owedBefore - owedOnThis;

  final later = plan.rows
      .where((r) => r.number > number && !r.isPaid)
      .map((r) => r.number)
      .toSet();
  final share = later.isEmpty ? 0 : rest.paise ~/ later.length;
  final lastLater = later.isEmpty ? -1 : later.reduce((a, b) => a > b ? a : b);

  final rows = <EmiRow>[];
  for (final r in plan.rows) {
    if (r.number == number) {
      rows.add(
        EmiRow(
          number: r.number,
          dueDate: r.dueDate,
          amount: newAmount,
          principal: newAmount,
          interest: Money.zero,
          paidAmount: r.paidAmount,
          paidOn: r.paidOn,
        ),
      );
    } else if (later.contains(r.number)) {
      final mine = r.number == lastLater
          ? rest.paise - share * (later.length - 1)
          : share;
      final amount = r.paidAmount + Money(mine);
      // Nothing left for it and nothing paid: the payment goes away.
      if (amount.isZero) continue;
      rows.add(
        EmiRow(
          number: r.number,
          dueDate: r.dueDate,
          amount: amount,
          principal: amount,
          interest: Money.zero,
          paidAmount: r.paidAmount,
          paidOn: r.paidOn,
        ),
      );
    } else {
      rows.add(r);
    }
  }

  if (later.isEmpty && rest > Money.zero) {
    final last = rows.last;
    rows.add(
      EmiRow(
        number:
            plan.rows.map((r) => r.number).reduce((a, b) => a > b ? a : b) + 1,
        dueDate: _monthAfter(last.dueDate, plan.startDate.day),
        amount: rest,
        principal: rest,
        interest: Money.zero,
      ),
    );
  }
  return _normalise(plan, rows);
}

/// An extra payment of [amount] towards the whole plan: the schedule shrinks
/// from the LAST payment backwards. Emptied payments are removed; payments with
/// something already paid only shrink down to what is paid.
EmiPlan applyExtraPayment(EmiPlan plan, Money amount) {
  if (amount <= Money.zero) {
    throw const InstalmentError('Amount must be above 0');
  }
  final owed = _unpaid(plan.rows);
  if (amount > owed) {
    throw InstalmentError('More than what is still to pay (${owed.format()})');
  }
  var left = amount;
  final reversed = <EmiRow?>[];
  for (final r in plan.rows.reversed) {
    if (left.isZero || r.remaining.isZero) {
      reversed.add(r);
      continue;
    }
    final take = left < r.remaining ? left : r.remaining;
    left = left - take;
    final newAmount = r.amount - take;
    if (newAmount.isZero) {
      reversed.add(null); // emptied and nothing paid: removed
    } else {
      reversed.add(
        EmiRow(
          number: r.number,
          dueDate: r.dueDate,
          amount: newAmount,
          principal: newAmount,
          interest: Money.zero,
          paidAmount: r.paidAmount,
          paidOn: r.paidOn,
        ),
      );
    }
  }
  return _normalise(plan, [for (final r in reversed.reversed) ?r]);
}

/// Undoes [applyExtraPayment]: puts [amount] back at the end of the schedule.
/// The last payment, if it is still open, is first topped up to the regular
/// monthly amount; whatever is left becomes new payments of that size (the last
/// one smaller), each a month after the one before. So undoing an extra payment
/// gives back the original shape of the plan.
EmiPlan restoreExtraPayment(EmiPlan plan, Money amount) {
  if (amount <= Money.zero) {
    throw const InstalmentError('Amount must be above 0');
  }
  final regular = plan.emi > Money.zero ? plan.emi : amount;
  final rows = [...plan.rows];
  var left = amount;

  if (rows.isNotEmpty && !rows.last.isPaid && rows.last.amount < regular) {
    final last = rows.removeLast();
    final room = regular - last.amount;
    final top = left < room ? left : room;
    left = left - top;
    rows.add(
      EmiRow(
        number: last.number,
        dueDate: last.dueDate,
        amount: last.amount + top,
        principal: last.amount + top,
        interest: Money.zero,
        paidAmount: last.paidAmount,
        paidOn: last.paidOn,
      ),
    );
  }

  var number = rows.isEmpty
      ? 0
      : rows.map((r) => r.number).reduce((a, b) => a > b ? a : b);
  while (left > Money.zero) {
    final size = left < regular ? left : regular;
    number++;
    rows.add(
      EmiRow(
        number: number,
        dueDate: rows.isEmpty
            ? plan.startDate
            : _monthAfter(rows.last.dueDate, plan.startDate.day),
        amount: size,
        principal: size,
        interest: Money.zero,
      ),
    );
    left = left - size;
  }
  return _normalise(plan, rows);
}
