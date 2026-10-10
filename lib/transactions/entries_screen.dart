import '../core/ui/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ui/initials_avatar.dart';
import '../people/people_providers.dart';
import 'add_entry_screen.dart';
import 'entry_detail_screen.dart';
import 'pay_swipe.dart';
import 'entry_form_logic.dart';
import 'status_badge.dart';

/// Temporary list of every entry; replaced by Home and the person ledger.
class EntriesScreen extends ConsumerWidget {
  const EntriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(allTransactionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Entries')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add entry',
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const AddEntryScreen())),
        child: const Icon(Icons.add),
      ),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load entries: $e')),
        data: (all) {
          if (all.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No entries yet',
              hint: 'Entries you add show up here.',
            );
          }
          final sorted = [...all]
            ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
          final now = DateTime.now();
          return ListView.separated(
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final t = sorted[i];
              return withPaySwipe(
                context,
                t,
                ListTile(
                  leading: InitialsAvatar(name: t.personName),
                  title: Text('${t.personName} · ${t.title}'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(value: paidFraction(t)),
                        const SizedBox(height: 4),
                        Text(summaryLine(t)),
                      ],
                    ),
                  ),
                  trailing: StatusBadge(status: effectiveStatus(t, now: now)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EntryDetailScreen(transactionId: t.id),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
