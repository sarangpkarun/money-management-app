import '../core/ui/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/money/money.dart';
import '../core/theme/app_colors.dart';
import '../core/ui/initials_avatar.dart';
import '../log/calendar_screen.dart';
import '../people/people_providers.dart';
import '../settings/profile_screen.dart';
import '../transactions/add_entry_screen.dart';
import '../transactions/entries_screen.dart';
import '../transactions/entry_detail_screen.dart';
import '../transactions/entry_form_logic.dart';
import '../transactions/status_badge.dart';
import '../shell/add_entry_sheet.dart';
import 'due_items.dart';
import 'due_list_screen.dart';
import 'due_row.dart';
import 'home_totals.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(currentProfileProvider).value?.name ?? '';
    final entries = ref.watch(allTransactionsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'home-add',
        onPressed: () => showAddEntrySheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      appBar: AppBar(
        title: Text(name.isEmpty ? 'Hello' : 'Hello, $name'),
        actions: [
          IconButton(
            tooltip: 'Calendar log',
            icon: const Icon(Icons.calendar_month),
            onPressed: () => _open(context, const CalendarScreen()),
          ),
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => _open(context, const ProfileScreen()),
          ),
        ],
      ),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load entries: $e')),
        data: (all) {
          final now = DateTime.now();
          final totals = computeHomeTotals(all, now: now);
          final recent = recentEntries(all);
          final groups = groupDueItems(dueItems(all, now), now);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              _NetCard(totals: totals),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _AmountCard(
                      label: 'To receive',
                      amount: totals.toReceive,
                      color: AppColors.receive(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AmountCard(
                      label: 'To pay',
                      amount: totals.toPay,
                      color: AppColors.pay(context),
                    ),
                  ),
                ],
              ),
              _DueSection(
                title: 'Overdue',
                group: groups.overdue,
                now: now,
                overdue: true,
              ),
              _DueSection(title: 'This week', group: groups.thisWeek, now: now),
              _DueSection(
                title: 'This month',
                group: groups.thisMonth,
                now: now,
              ),
              _DueSection(title: 'Upcoming', group: groups.upcoming, now: now),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    'Recent entries',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  if (all.isNotEmpty)
                    TextButton(
                      onPressed: () => _open(context, const EntriesScreen()),
                      child: const Text('See all'),
                    ),
                ],
              ),
              if (recent.isEmpty)
                SizedBox(
                  height: 320,
                  child: EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'No entries yet',
                    hint:
                        'Record money you lend or borrow, an EMI or an '
                        'instalment plan, and it shows up here.',
                    actionLabel: 'Add your first entry',
                    onAction: () => _open(context, const AddEntryScreen()),
                  ),
                )
              else
                for (final t in recent)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: InitialsAvatar(name: t.personName),
                    title: Text('${t.personName} · ${t.title}'),
                    subtitle: Text(summaryLine(t, now: now)),
                    trailing: StatusBadge(status: effectiveStatus(t, now: now)),
                    onTap: () =>
                        _open(context, EntryDetailScreen(transactionId: t.id)),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// Secondary text on the net card's indigo gradient: white at 90% keeps it above
/// 4.5:1 on both ends of the gradient.
final _onCardMuted = Colors.white.withValues(alpha: 0.9);

class _NetCard extends StatelessWidget {
  const _NetCard({required this.totals});

  final HomeTotals totals;

  @override
  Widget build(BuildContext context) {
    final net = totals.net;
    final caption = net.isZero
        ? 'All settled'
        : (net.isNegative ? 'You owe overall' : 'You are owed overall');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF3F51B5), Color(0xFF283593)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Net balance', style: TextStyle(color: _onCardMuted)),
          const SizedBox(height: 4),
          Text(
            '${net.isNegative ? '-' : ''}${Money(net.paise.abs()).format()}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(caption, style: TextStyle(color: _onCardMuted)),
        ],
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final Money amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              amount.format(),
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One dashboard group: a header with the count and what it adds up to, the
/// first few payments, and "See all" when there are more. Hidden when empty.
class _DueSection extends StatelessWidget {
  const _DueSection({
    required this.title,
    required this.group,
    required this.now,
    this.overdue = false,
  });

  static const _shown = 5;

  final String title;
  final DueGroup group;
  final DateTime now;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    if (group.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = overdue ? AppColors.pay(context) : null;
    final totals = [
      if (!group.toReceive.isZero) 'Receive ${group.toReceive.format()}',
      if (!group.toPay.isZero) 'Pay ${group.toPay.format()}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                '$title · ${group.count}',
                style: theme.textTheme.titleMedium?.copyWith(color: color),
              ),
            ),
            if (group.count > _shown)
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        DueListScreen(title: title, items: group.items),
                  ),
                ),
                child: const Text('See all'),
              ),
          ],
        ),
        Text(
          totals,
          style: TextStyle(color: color ?? theme.colorScheme.onSurfaceVariant),
        ),
        for (final i in group.items.take(_shown)) DueRow(item: i, now: now),
      ],
    );
  }
}
