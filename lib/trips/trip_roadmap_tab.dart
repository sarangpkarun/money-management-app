import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/trip.dart';
import '../core/models/trip_stop.dart';
import '../core/money/money.dart';
import '../core/ui/empty_state.dart';
import '../core/ui/format.dart';
import '../core/data/providers.dart';
import '../core/models/trip_expense.dart';
import 'trip_expense_form_screen.dart';
import 'trip_expenses_tab.dart';
import 'trip_providers.dart';
import 'trip_stop_form_screen.dart';

IconData stopIcon(StopType t) => switch (t) {
  StopType.stay => Icons.hotel_outlined,
  StopType.travel => Icons.directions_bus_outlined,
  StopType.food => Icons.restaurant_outlined,
  StopType.activity => Icons.local_activity_outlined,
  StopType.other => Icons.place_outlined,
};

/// The trip's route as a timeline: where you stay, travel, eat and visit, with
/// what was spent at each stop.
class TripRoadmapTab extends ConsumerWidget {
  const TripRoadmapTab({super.key, required this.trip, required this.canEdit});

  final Trip trip;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = ref.watch(tripStopsProvider(trip.id));
    final expenses = ref.watch(tripExpensesProvider(trip.id)).value ?? const [];
    return stops.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load the roadmap: $e')),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.route_outlined,
            title: 'No stops yet',
            hint: canEdit
                ? 'Add the room, the travel, meals and activities in order.'
                : 'Nothing has been added to the roadmap yet.',
          );
        }
        final me = ref.watch(emailProvider);
        void push(Widget screen) => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => screen));
        final children = <Widget>[];
        for (var i = 0; i < list.length; i++) {
          final s = list[i];
          if (canEdit) {
            children.add(
              _InsertGap(
                first: i == 0,
                onAdd: () =>
                    push(TripStopFormScreen(trip: trip, insertIndex: i)),
              ),
            );
          }
          final mine = expenses.where((e) => e.stopId == s.id).toList();
          children.add(
            _StopRow(
              stop: s,
              spent: mine.fold(Money.zero, (a, e) => a + e.amount),
              first: i == 0 && !canEdit,
              last: i == list.length - 1 && !canEdit,
              onTap: () => _showStop(context, ref, s, mine, me),
            ),
          );
        }
        if (canEdit) {
          children.add(
            _InsertGap(
              last: true,
              onAdd: () => push(
                TripStopFormScreen(trip: trip, insertIndex: list.length),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          children: children,
        );
      },
    );
  }

  /// The stop with what was spent there, plus shortcuts to add or open an
  /// expense for it.
  void _showStop(
    BuildContext context,
    WidgetRef ref,
    TripStop s,
    List<TripExpense> mine,
    String me,
  ) {
    final text = Theme.of(context).textTheme;
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
              Text(s.title, style: text.titleLarge),
              Text(
                [
                  stopTypeLabel(s.type),
                  if (s.date != null) formatShortDate(s.date!),
                  ?s.place,
                ].join(' · '),
                style: text.bodySmall,
              ),
              if (s.notes != null) Text(s.notes!),
              const SizedBox(height: 12),
              Text('Expenses', style: text.titleMedium),
              if (mine.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Nothing spent here yet.'),
                ),
              for (final e in mine)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.title),
                  subtitle: Text(
                    [
                      ?e.category,
                      '${memberLabel(trip, e.paidBy, me)} paid',
                    ].join(' · '),
                  ),
                  trailing: Text(e.amount.format(), style: text.titleMedium),
                  onTap: () => showExpenseDetail(
                    context,
                    ref,
                    trip: trip,
                    canEdit: canEdit,
                    e: e,
                    me: me,
                    stopTitle: s.title,
                  ),
                ),
              if (canEdit) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(sheet).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  TripExpenseFormScreen(trip: trip, stop: s),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add expense'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheet).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  TripStopFormScreen(trip: trip, existing: s),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit stop'),
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

/// A small "+" on the timeline rail between two stops (or at either end).
class _InsertGap extends StatelessWidget {
  const _InsertGap({
    this.first = false,
    this.last = false,
    required this.onAdd,
  });

  final bool first;
  final bool last;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget line(bool visible) => Expanded(
      child: Container(
        width: 2,
        color: visible ? scheme.outlineVariant : Colors.transparent,
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 36,
        width: 40,
        child: Column(
          children: [
            line(!first),
            Tooltip(
              message: 'Add a stop here',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onAdd,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary),
                  ),
                  child: Icon(Icons.add, size: 16, color: scheme.primary),
                ),
              ),
            ),
            line(!last),
          ],
        ),
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.spent,
    required this.first,
    required this.last,
    this.onTap,
  });

  final TripStop stop;
  final Money spent;
  final bool first;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = [
      stopTypeLabel(stop.type),
      if (stop.date != null) formatShortDate(stop.date!),
      if (stop.place != null) stop.place!,
    ].join(' · ');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: first ? Colors.transparent : scheme.outlineVariant,
                  ),
                ),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    stopIcon(stop.type),
                    size: 18,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: last ? Colors.transparent : scheme.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(details, style: Theme.of(context).textTheme.bodySmall),
                    if (stop.notes != null) Text(stop.notes!),
                    if (!spent.isZero)
                      Text(
                        'Spent ${spent.format()}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
