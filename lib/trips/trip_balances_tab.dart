import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/trip.dart';
import '../core/money/money.dart';
import '../core/theme/app_colors.dart';
import '../core/ui/empty_state.dart';
import 'split_logic.dart';
import 'trip_expenses_tab.dart';
import 'trip_providers.dart';

/// Paid vs share for each person, and the fewest payments that settle it.
class TripBalancesTab extends ConsumerWidget {
  const TripBalancesTab({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(tripExpensesProvider(trip.id));
    final me = ref.watch(emailProvider);
    return expenses.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load balances: $e')),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.balance_outlined,
            title: 'Nothing to settle',
            hint: 'Balances appear once expenses are added.',
          );
        }
        final net = balances(list);
        final paid = <String, int>{};
        for (final e in list) {
          paid[e.paidBy] = (paid[e.paidBy] ?? 0) + e.amount.paise;
        }
        final transfers = settleUp(net);
        final keys = net.keys.toList()
          ..sort((a, b) => net[b]!.compareTo(net[a]!));
        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            const _Heading('Balances'),
            for (final k in keys)
              ListTile(
                title: Text(memberLabel(trip, k, me)),
                subtitle: Text('Paid ${Money(paid[k] ?? 0).format()}'),
                trailing: _NetText(net[k]!),
              ),
            const Divider(),
            const _Heading('Settle up'),
            if (transfers.isEmpty)
              const ListTile(title: Text('Everyone is settled.'))
            else
              for (final t in transfers)
                ListTile(
                  leading: const Icon(Icons.arrow_forward),
                  title: Text(
                    '${memberLabel(trip, t.from, me)} pays '
                    '${memberLabel(trip, t.to, me)}',
                  ),
                  trailing: Text(
                    Money(t.paise).format(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _NetText extends StatelessWidget {
  const _NetText(this.paise);

  final int paise;

  @override
  Widget build(BuildContext context) {
    if (paise == 0) return const Text('Settled');
    final owed = paise > 0;
    return Text(
      '${owed ? 'Gets back' : 'Owes'} ${Money(paise.abs()).format()}',
      style: TextStyle(
        color: owed ? AppColors.receive(context) : AppColors.pay(context),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
