import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/money/money.dart';
import '../core/theme/app_colors.dart';
import '../core/ui/initials_avatar.dart';
import '../people/people_providers.dart';
import '../settings/profile_screen.dart';
import '../transactions/add_entry_screen.dart';
import '../transactions/entries_screen.dart';
import '../transactions/entry_detail_screen.dart';
import '../transactions/entry_form_logic.dart';
import '../transactions/status_badge.dart';
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
      appBar: AppBar(
        title: Text(name.isEmpty ? 'Hello' : 'Hello, $name'),
        actions: [
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
          return ListView(
            padding: const EdgeInsets.all(16),
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
              if (totals.overdueCount > 0) ...[
                const SizedBox(height: 12),
                _OverdueStrip(
                  totals: totals,
                  onTap: () => _open(context, const EntriesScreen()),
                ),
              ],
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const Text('No entries yet'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _open(context, const AddEntryScreen()),
                        child: const Text('Add your first entry'),
                      ),
                    ],
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
          const Text('Net balance', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            '${net.isNegative ? '-' : ''}${Money(net.paise.abs()).format()}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(caption, style: const TextStyle(color: Colors.white70)),
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

class _OverdueStrip extends StatelessWidget {
  const _OverdueStrip({required this.totals, required this.onTap});

  final HomeTotals totals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.pay(context);
    final n = totals.overdueCount;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$n overdue ${n == 1 ? 'entry' : 'entries'} · '
                '${totals.overdueAmount.format()}',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }
}
