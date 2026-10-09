import 'package:flutter/material.dart';

import '../core/models/money_transaction.dart';
import '../transactions/add_entry_screen.dart';

/// The "+" in the bottom bar: choose what to record. Only lent and borrowed for
/// now; EMI, instalment plan and reminder join in Phase 2.
Future<void> showAddEntrySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add new entry',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          for (final (type, title, subtitle, icon) in [
            (
              TransactionType.lent,
              'Money I gave',
              'They owe you',
              Icons.north_east,
            ),
            (
              TransactionType.borrowed,
              'Money I borrowed',
              'You owe them',
              Icons.south_west,
            ),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(subtitle),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AddEntryScreen(initialType: type),
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );
}
