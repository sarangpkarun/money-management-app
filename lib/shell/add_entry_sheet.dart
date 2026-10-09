import 'package:flutter/material.dart';

import '../core/models/money_transaction.dart';
import '../transactions/add_emi_screen.dart';
import '../transactions/add_entry_screen.dart';
import '../transactions/add_instalment_screen.dart';

/// The "+" in the bottom bar: choose what to record. Lent, borrowed, EMI
/// purchase and instalment plan for now; reminder joins later in Phase 2.
Future<void> showAddEntrySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
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
            ListTile(
              leading: const Icon(Icons.phone_iphone),
              title: const Text('EMI purchase'),
              subtitle: const Text('Something bought on monthly instalments'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AddEmiScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_repeat),
              title: const Text('Pay in instalments'),
              subtitle: const Text('Money you owe a person, paid monthly'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AddInstalmentScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}
