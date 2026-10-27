import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/trip.dart';
import '../core/ui/empty_state.dart';
import '../core/ui/format.dart';
import 'trip_detail_screen.dart';
import 'trip_form_screen.dart';
import 'trip_providers.dart';

String tripDates(Trip t) {
  final s = t.startDate, e = t.endDate;
  if (s == null && e == null) return '';
  if (s != null && e != null) {
    return '${formatShortDate(s)} - ${formatShortDate(e)}';
  }
  return formatShortDate((s ?? e)!);
}

/// Every trip the signed-in person is on, including ones they were invited to.
class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(myTripsProvider);
    final uid = ref.watch(uidProvider);
    final email = ref.watch(emailProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'trips-add',
        onPressed: () => _open(context, const TripFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('New trip'),
      ),
      body: trips.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load trips: $e')),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.luggage_outlined,
              title: 'No trips yet',
              hint:
                  'Plan a trip or any group event, track what everyone spends '
                  'and split it. Trips shared with your email show up here.',
              actionLabel: 'New trip',
              onAction: () => _open(context, const TripFormScreen()),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = list[i];
              final access = tripAccess(t, uid, email);
              final role = access.member?.role;
              final dates = tripDates(t);
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.luggage)),
                title: Text(t.name),
                subtitle: Text(
                  [
                    if (dates.isNotEmpty) dates,
                    '${t.members.length} ${t.members.length == 1 ? 'person' : 'people'}',
                  ].join(' · '),
                ),
                trailing: role == null
                    ? null
                    : Chip(
                        label: Text(tripRoleLabel(role)),
                        visualDensity: VisualDensity.compact,
                      ),
                onTap: () => _open(context, TripDetailScreen(tripId: t.id)),
              );
            },
          );
        },
      ),
    );
  }
}
