import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/trip.dart';
import '../core/models/trip_expense.dart';
import '../core/money/money.dart';
import '../core/ui/empty_state.dart';
import '../core/ui/format.dart';
import 'trip_expense_form_screen.dart';
import 'trip_providers.dart';

/// A member's name for display: "You" for the signed-in person, the saved name
/// for a member, the bare email for someone who has since been removed.
String memberLabel(Trip trip, String email, String myEmail) {
  if (email == myEmail) return 'You';
  return trip.memberByEmail(email)?.name ?? email;
}

class TripExpensesTab extends ConsumerWidget {
  const TripExpensesTab({super.key, required this.trip, required this.canEdit});

  final Trip trip;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(tripExpensesProvider(trip.id));
    final me = ref.watch(emailProvider);
    return expenses.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load expenses: $e')),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No expenses yet',
            hint: canEdit
                ? 'Add what was spent, who paid and how to split it.'
                : 'Nothing has been spent yet.',
          );
        }
        final total = list.fold(Money.zero, (a, e) => a + e.amount);
        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            ListTile(
              title: const Text('Total spent'),
              trailing: Text(
                total.format(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            for (final e in list)
              ListTile(
                title: Text(e.title),
                subtitle: Text(
                  '${memberLabel(trip, e.paidBy, me)} paid · '
                  '${formatShortDate(e.date)} · '
                  'split ${e.shares.length} ${e.shares.length == 1 ? 'way' : 'ways'}',
                ),
                trailing: Text(
                  e.amount.format(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                onTap: () => _showDetail(context, ref, e, me),
              ),
          ],
        );
      },
    );
  }

  void _showDetail(
    BuildContext context,
    WidgetRef ref,
    TripExpense e,
    String me,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.title, style: Theme.of(context).textTheme.titleLarge),
              Text(
                '${e.amount.format()} paid by ${memberLabel(trip, e.paidBy, me)}'
                ' · ${splitModeLabel(e.mode)}',
              ),
              const SizedBox(height: 12),
              for (final s in e.shares.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(memberLabel(trip, s.key, me))),
                      Text(Money(s.value).format()),
                    ],
                  ),
                ),
              if (canEdit) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheet).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TripExpenseFormScreen(
                                trip: trip,
                                existing: e,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () async {
                          Navigator.of(sheet).pop();
                          await ref
                              .read(tripRepositoryProvider)
                              .deleteExpense(trip.id, e.id);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
