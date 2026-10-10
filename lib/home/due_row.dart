import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/ui/format.dart';
import '../core/ui/initials_avatar.dart';
import '../transactions/entry_detail_screen.dart';
import '../transactions/pay_swipe.dart';
import 'due_items.dart';

/// One payment on the dashboard: who, what, when, and how much (green when it
/// is money coming to you, red when you pay).
class DueRow extends StatelessWidget {
  const DueRow({super.key, required this.item, required this.now});

  final DueItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final late = item.date.isBefore(DateTime(now.year, now.month, now.day));
    final color = item.isReceivable
        ? AppColors.receive(context)
        : AppColors.pay(context);
    return withPaySwipe(
      context,
      item.entry,
      ListTile(
        leading: InitialsAvatar(name: item.entry.personName),
        title: Text('${item.entry.personName} · ${item.what}'),
        subtitle: Text(
          dueLabel(item, now, formatShortDate),
          style: late ? TextStyle(color: AppColors.pay(context)) : null,
        ),
        trailing: Text(
          item.amount.format(),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EntryDetailScreen(transactionId: item.entry.id),
          ),
        ),
      ),
    );
  }
}
