import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/trip.dart';
import '../core/models/trip_stop.dart';
import '../core/money/money.dart';
import '../core/ui/empty_state.dart';
import '../core/ui/format.dart';
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
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final s = list[i];
            final spent = expenses
                .where((e) => e.stopId == s.id)
                .fold(Money.zero, (a, e) => a + e.amount);
            return _StopRow(
              stop: s,
              spent: spent,
              first: i == 0,
              last: i == list.length - 1,
              onTap: canEdit
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            TripStopFormScreen(trip: trip, existing: s),
                      ),
                    )
                  : null,
            );
          },
        );
      },
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
