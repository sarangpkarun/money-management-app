import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/trip.dart';
import '../core/models/trip_expense.dart';
import '../core/models/trip_stop.dart';
import '../core/money/money.dart';
import '../core/ui/empty_state.dart';
import '../core/ui/format.dart';
import 'trip_expense_form_screen.dart';
import 'trip_providers.dart';
import 'trip_colors.dart';

/// A member's name for display: "You" for the signed-in person, the saved name
/// for a member, the bare email for someone who has since been removed.
String memberLabel(Trip trip, String email, String myEmail) {
  if (email == myEmail) return 'You';
  return trip.memberByEmail(email)?.name ?? email;
}

/// Expenses grouped under the roadmap point they were spent at, with a
/// per-category summary on top.
class TripExpensesTab extends ConsumerStatefulWidget {
  const TripExpensesTab({super.key, required this.trip, required this.canEdit});

  final Trip trip;
  final bool canEdit;

  @override
  ConsumerState<TripExpensesTab> createState() => _TripExpensesTabState();
}

class _TripExpensesTabState extends ConsumerState<TripExpensesTab> {
  bool _byStop = true;

  /// The category being filtered on; null shows everything.
  StopType? _filter;

  Trip get trip => widget.trip;

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(tripExpensesProvider(trip.id));
    final stops = ref.watch(tripStopsProvider(trip.id)).value ?? const [];
    final me = ref.watch(emailProvider);
    return expenses.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load expenses: $e')),
      data: (loaded) {
        var list = loaded;
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No expenses yet',
            hint: widget.canEdit
                ? 'Add what was spent at a roadmap point, who paid and how to '
                      'split it.'
                : 'Nothing has been spent yet.',
          );
        }
        final stopById = {for (final s in stops) s.id: s};
        final byCategory = <StopType, Money>{};
        for (final e in list) {
          final t = categoryType(e.category);
          byCategory[t] = (byCategory[t] ?? Money.zero) + e.amount;
        }
        // The filtered category may have just lost its last expense.
        final filter = byCategory.containsKey(_filter) ? _filter : null;
        final all = list;
        list = filter == null
            ? all
            : all.where((e) => categoryType(e.category) == filter).toList();
        final total = list.fold(Money.zero, (a, e) => a + e.amount);

        Widget tile(TripExpense e) => ListTile(
          leading: categoryAvatar(context, e.category),
          title: Text(e.title),
          subtitle: Text(
            [
              categoryLabel(e.category),
              '${memberLabel(trip, e.paidBy, me)} paid',
              formatShortDate(e.date),
              'split ${e.shares.length} ${e.shares.length == 1 ? 'way' : 'ways'}',
            ].join(' · '),
          ),
          trailing: Text(
            e.amount.format(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          onTap: () => showExpenseDetail(
            context,
            ref,
            trip: trip,
            canEdit: widget.canEdit,
            e: e,
            me: me,
            stopTitle: stopById[e.stopId]?.title,
          ),
        );

        final children = <Widget>[
          ListTile(
            title: Text(
              filter == null ? 'Total spent' : '${stopTypeLabel(filter)} total',
            ),
            trailing: Text(
              total.format(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                ),
                for (final t in StopType.values)
                  if (byCategory.containsKey(t))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: Icon(
                          stopIcon(t),
                          size: 18,
                          color: categoryForeground(context, stopTypeColor(t)),
                        ),
                        label: Text(
                          '${stopTypeLabel(t)} ${byCategory[t]!.format()}',
                        ),
                        selected: filter == t,
                        showCheckmark: false,
                        selectedColor: categoryBackground(stopTypeColor(t)),
                        onSelected: (_) =>
                            setState(() => _filter = filter == t ? null : t),
                      ),
                    ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('By stop')),
                ButtonSegment(value: false, label: Text('By date')),
              ],
              selected: {_byStop},
              onSelectionChanged: (s) => setState(() => _byStop = s.first),
            ),
          ),
          const Divider(height: 24),
        ];

        if (_byStop) {
          // Roadmap order first, then whatever isn't tied to a stop.
          for (final s in stops) {
            final mine = list.where((e) => e.stopId == s.id).toList();
            if (mine.isEmpty) continue;
            children.add(
              _header(
                context,
                s.title,
                mine,
                icon: stopIcon(s.type),
                color: categoryForeground(context, stopTypeColor(s.type)),
              ),
            );
            children.addAll(mine.map(tile));
          }
          final general = list
              .where((e) => !stopById.containsKey(e.stopId))
              .toList();
          if (general.isNotEmpty) {
            children.add(_header(context, 'General', general));
            children.addAll(general.map(tile));
          }
        } else {
          children.addAll(list.map(tile));
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: children,
        );
      },
    );
  }

  Widget _header(
    BuildContext context,
    String title,
    List<TripExpense> items, {
    IconData? icon,
    Color? color,
  }) {
    final sum = items.fold(Money.zero, (a, e) => a + e.amount);
    final style = Theme.of(context).textTheme.titleSmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Icon(icon ?? Icons.layers_outlined, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: style)),
          Text(sum.format(), style: style),
        ],
      ),
    );
  }
}

/// The expense in a bottom sheet: category, roadmap point, each person's share.
void showExpenseDetail(
  BuildContext context,
  WidgetRef ref, {
  required Trip trip,
  required bool canEdit,
  required TripExpense e,
  required String me,
  String? stopTitle,
}) {
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    avatar: Icon(
                      categoryIcon(e.category),
                      size: 16,
                      color: categoryForeground(
                        context,
                        categoryColor(e.category),
                      ),
                    ),
                    label: Text(categoryLabel(e.category)),
                    backgroundColor: categoryBackground(
                      categoryColor(e.category),
                    ),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
                  if (stopTitle != null)
                    Text(
                      'at $stopTitle',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
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
                            builder: (_) =>
                                TripExpenseFormScreen(trip: trip, existing: e),
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
