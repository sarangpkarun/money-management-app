import 'package:flutter/material.dart';

import '../core/emi/emi_summary.dart';
import '../core/models/emi_plan.dart';
import '../core/theme/app_colors.dart';
import '../core/ui/format.dart';

Color emiStatusColor(BuildContext context, EmiRowStatus status) =>
    switch (status) {
      EmiRowStatus.paid => AppColors.receive(context),
      EmiRowStatus.partial => AppColors.partial(context),
      EmiRowStatus.overdue => AppColors.pay(context),
      EmiRowStatus.upcoming => AppColors.pending(context),
    };

String emiStatusLabel(EmiRowStatus status) => switch (status) {
  EmiRowStatus.paid => 'Paid',
  EmiRowStatus.partial => 'Part paid',
  EmiRowStatus.overdue => 'Overdue',
  EmiRowStatus.upcoming => 'Upcoming',
};

/// The summary card and the instalment table for an EMI purchase. A coloured
/// dot shows each row's state: green paid, amber upcoming, red overdue, blue
/// part paid.
class EmiScheduleView extends StatelessWidget {
  const EmiScheduleView({
    super.key,
    required this.plan,
    required this.now,
    required this.onPayRow,
  });

  final EmiPlan plan;
  final DateTime now;

  /// Called when an unpaid row is tapped.
  final void Function(EmiRow row) onPayRow;

  @override
  Widget build(BuildContext context) {
    final summary = summarizePlan(plan, now);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('EMI summary', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _line(
                  context,
                  'Next EMI',
                  summary.next == null
                      ? 'All paid'
                      : '${summary.next!.remaining.format()} on '
                            '${formatShortDate(summary.next!.dueDate)}',
                ),
                _line(
                  context,
                  'Remaining EMIs',
                  '${summary.remainingCount} of ${plan.months}',
                ),
                _line(
                  context,
                  'Remaining total',
                  summary.remainingTotal.format(),
                ),
                _line(
                  context,
                  'Last EMI',
                  formatShortDate(summary.lastDueDate),
                ),
                if (summary.overdueCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${summary.overdueCount} overdue · '
                    '${summary.overdueAmount.format()}',
                    style: TextStyle(
                      color: AppColors.pay(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  [
                    'Price ${plan.price.format()}',
                    if (!plan.downPayment.isZero)
                      'Down payment ${plan.downPayment.format()}',
                    plan.annualRatePercent == 0
                        ? 'No-cost EMI'
                        : '${_rate(plan.annualRatePercent)}% a year',
                  ].join(' · '),
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Schedule', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final row in plan.rows)
          _RowTile(row: row, now: now, onTap: onPayRow),
      ],
    );
  }

  static String _rate(double r) =>
      r == r.roundToDouble() ? r.toInt().toString() : r.toString();

  Widget _line(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.now, required this.onTap});

  final EmiRow row;
  final DateTime now;
  final void Function(EmiRow) onTap;

  @override
  Widget build(BuildContext context) {
    final status = row.statusAt(now);
    final color = emiStatusColor(context, status);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        key: ValueKey('emi-dot-${row.number}'),
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text('#${row.number} · ${row.amount.format()}'),
      subtitle: Text(
        [
          'Due ${formatShortDate(row.dueDate)}',
          'Principal ${row.principal.format()}',
          'Interest ${row.interest.format()}',
          if (status == EmiRowStatus.partial)
            'Paid ${row.paidAmount.format()} of ${row.amount.format()}',
          if (row.paidOn != null && status == EmiRowStatus.paid)
            'Paid ${formatShortDate(row.paidOn!)}',
        ].join(' · '),
      ),
      trailing: Text(
        emiStatusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      onTap: row.isPaid ? null : () => onTap(row),
    );
  }
}
