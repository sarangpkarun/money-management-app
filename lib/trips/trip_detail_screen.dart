import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/trip.dart';
import 'trip_balances_tab.dart';
import 'trip_expense_form_screen.dart';
import 'trip_expenses_tab.dart';
import 'trip_form_screen.dart';
import 'trip_members_tab.dart';
import 'trip_providers.dart';
import 'trip_roadmap_tab.dart';
import 'trip_stop_form_screen.dart';
import 'trips_screen.dart';

/// One trip: roadmap, expenses, people and who owes whom.
class TripDetailScreen extends ConsumerStatefulWidget {
  const TripDetailScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _delete(Trip trip) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${trip.name}?'),
        content: const Text(
          'This removes the trip, its roadmap and expenses for everyone. '
          'It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(tripRepositoryProvider).delete(trip.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tripProvider(widget.tripId));
    final uid = ref.watch(uidProvider);
    final email = ref.watch(emailProvider);
    final trip = async.value;
    if (trip == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: async.isLoading
              ? const CircularProgressIndicator()
              : Text(
                  async.hasError
                      ? 'Could not load this trip: ${async.error}'
                      : 'This trip is no longer available.',
                ),
        ),
      );
    }
    final access = tripAccess(trip, uid, email);
    final dates = tripDates(trip);

    Widget? fab;
    if (access.canEdit && _tabs.index == 0) {
      fab = FloatingActionButton.extended(
        heroTag: 'trip-stop',
        onPressed: () => _push(TripStopFormScreen(trip: trip)),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add stop'),
      );
    } else if (access.canEdit && _tabs.index == 1) {
      fab = FloatingActionButton.extended(
        heroTag: 'trip-expense',
        onPressed: () => _push(TripExpenseFormScreen(trip: trip)),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(trip.name),
            if (dates.isNotEmpty)
              Text(dates, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          if (access.canEdit)
            IconButton(
              tooltip: 'Edit trip',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _push(TripFormScreen(trip: trip)),
            ),
          if (access.isOwner)
            IconButton(
              tooltip: 'Delete trip',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(trip),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Roadmap'),
            Tab(text: 'Expenses'),
            Tab(text: 'People'),
            Tab(text: 'Balances'),
          ],
        ),
      ),
      floatingActionButton: fab,
      body: Column(
        children: [
          if (!access.canEdit)
            MaterialBanner(
              content: Text(
                access.member?.pending ?? false
                    ? 'Joining this trip...'
                    : 'You can view this trip but not change it.',
              ),
              actions: const [SizedBox.shrink()],
              dividerColor: Colors.transparent,
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                TripRoadmapTab(trip: trip, canEdit: access.canEdit),
                TripExpensesTab(trip: trip, canEdit: access.canEdit),
                TripMembersTab(trip: trip, isOwner: access.isOwner),
                TripBalancesTab(trip: trip),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
