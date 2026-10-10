import 'package:flutter/material.dart';

import '../core/interest/interest.dart';
import '../core/models/money_transaction.dart';
import '../core/theme/app_colors.dart';
import '../core/ui/swipe_actions.dart';
import 'emi_payment_sheet.dart';
import 'entry_form_logic.dart';
import 'payment_sheet.dart';

/// The swipe-right action on an entry row: opens the same payment sheet as the
/// button on the entry's page. Null when nothing is left to pay.
SwipeAction? paySwipe(BuildContext context, MoneyTransaction t) {
  if (outstanding(t, DateTime.now()).isZero) return null;
  final plan = t.emiPlan;
  if (plan != null && plan.nextUnpaid == null) return null;
  return SwipeAction(
    label: plan != null ? 'Pay next' : payActionLabel(t),
    icon: Icons.payments_outlined,
    color: AppColors.receive(context),
    onTrigger: () async {
      if (plan != null) {
        await showEmiPaymentSheet(context, txn: t, row: plan.nextUnpaid!);
      } else {
        await showPaymentSheet(context, txn: t);
      }
    },
  );
}

/// Wraps [child] so it can be swiped right to pay [t]; unchanged when there is
/// nothing to pay.
Widget withPaySwipe(BuildContext context, MoneyTransaction t, Widget child) {
  final action = paySwipe(context, t);
  if (action == null) return child;
  return SwipeActions(
    key: ValueKey('pay-${t.id}'),
    right: action,
    child: child,
  );
}
