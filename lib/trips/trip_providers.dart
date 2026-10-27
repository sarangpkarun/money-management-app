import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/trip.dart';
import '../core/models/trip_expense.dart';
import '../core/models/trip_stop.dart';

final myTripsProvider = StreamProvider.autoDispose<List<Trip>>(
  (ref) => ref.watch(tripRepositoryProvider).watchMyTrips(),
);

final tripProvider = StreamProvider.autoDispose.family<Trip?, String>(
  (ref, id) => ref.watch(tripRepositoryProvider).watchTrip(id),
);

final tripStopsProvider = StreamProvider.autoDispose
    .family<List<TripStop>, String>(
      (ref, id) => ref.watch(tripRepositoryProvider).watchStops(id),
    );

final tripExpensesProvider = StreamProvider.autoDispose
    .family<List<TripExpense>, String>(
      (ref, id) => ref.watch(tripRepositoryProvider).watchExpenses(id),
    );

/// Accepts invites addressed to the signed-in email. Watched behind the auth
/// gate so a new member's trips appear as soon as they log in.
final claimInvitesProvider = FutureProvider<void>((ref) async {
  await ref.watch(tripRepositoryProvider).claimInvites();
});

/// What the signed-in person may do on [trip].
class TripAccess {
  const TripAccess(this.member);

  final TripMember? member;

  /// Pending invitees (no uid yet) are read-only until their invite is claimed.
  bool get canEdit => member != null && !member!.pending && member!.canEdit;
  bool get isOwner => member?.role == TripRole.owner;
}

TripAccess tripAccess(Trip trip, String uid, String email) =>
    TripAccess(trip.memberByUid(uid) ?? trip.memberByEmail(email));

/// The latest value of [tripProvider] without the loading wrapper.
final tripProvider2 = Provider.autoDispose.family<Trip?, String>(
  (ref, id) => ref.watch(tripProvider(id)).value,
);
