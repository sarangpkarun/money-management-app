import 'package:flutter/material.dart';

import '../core/status/transaction_status.dart';
import '../core/theme/app_colors.dart';
import 'entry_form_logic.dart';

/// Pale pill tinted with the status colour, text in the same colour.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final TransactionStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TransactionStatus.pending => AppColors.pending(context),
      TransactionStatus.partiallyPaid => AppColors.partial(context),
      TransactionStatus.overdue => AppColors.pay(context),
      TransactionStatus.paid => AppColors.receive(context),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
