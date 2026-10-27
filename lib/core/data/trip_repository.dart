import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/trip.dart';
import '../models/trip_expense.dart';
import '../models/trip_stop.dart';

/// Trips live in the top-level `trips` collection (not under `users/{uid}`) so
/// every member can read them. Who may do what is decided by the security
/// rules from `memberUids`, `memberEmails` and `editorUids`.
class TripRepository {
  TripRepository(this._db, this.uid, String email)
    : email = email.trim().toLowerCase();

  final FirebaseFirestore _db;
  final String uid;

  /// The signed-in person's lowercased email, used to find their invites.
  final String email;

  CollectionReference<Map<String, dynamic>> get _trips =>
      _db.collection('trips');
  CollectionReference<Map<String, dynamic>> _stops(String tripId) =>
      _trips.doc(tripId).collection('stops');
  CollectionReference<Map<String, dynamic>> _expenses(String tripId) =>
      _trips.doc(tripId).collection('expenses');

  /// Trips the signed-in person is on, invited or active, newest first.
  Stream<List<Trip>> watchMyTrips() =>
      _trips.where('memberEmails', arrayContains: email).snapshots().map((s) {
        final list = s.docs.map((d) => Trip.fromMap(d.id, d.data())).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  Stream<Trip?> watchTrip(String id) => _trips.doc(id).snapshots().map((s) {
    final data = s.data();
    return data == null ? null : Trip.fromMap(s.id, data);
  });

  /// Creates a trip with the signed-in person as its owner.
  Future<String> create({
    required String name,
    required String ownerName,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    List<TripMember> invited = const [],
  }) async {
    final trip = Trip(
      name: name,
      description: description,
      startDate: startDate,
      endDate: endDate,
      ownerUid: uid,
      members: [
        TripMember(
          email: email,
          name: ownerName,
          role: TripRole.owner,
          uid: uid,
        ),
        ...invited,
      ],
      createdAt: DateTime.now(),
    );
    return (await _trips.add(trip.toMap())).id;
  }

  /// Name, description and dates only; members are saved by [saveMembers].
  Future<void> updateDetails(Trip t) => _trips.doc(t.id).update({
    'name': t.name,
    'description': t.description,
    'startDate': t.startDate == null ? null : Timestamp.fromDate(t.startDate!),
    'endDate': t.endDate == null ? null : Timestamp.fromDate(t.endDate!),
  });

  /// Owner only: replaces the member list (invites, role changes, removals).
  Future<void> saveMembers(Trip t) async {
    final m = t.toMap();
    final keep = (m['members'] as Map<String, dynamic>);
    final current = (await _trips.doc(t.id).get()).data();
    final old = ((current?['members'] as Map?) ?? const {}).keys.cast<String>();
    // One field per member, so a removed member is deleted outright rather
    // than depending on how a whole-map write is merged.
    await _trips.doc(t.id).update({
      for (final e in keep.entries) 'members.${e.key}': e.value,
      for (final k in old)
        if (!keep.containsKey(k)) 'members.$k': FieldValue.delete(),
      'memberEmails': m['memberEmails'],
      'memberUids': m['memberUids'],
      'editorUids': m['editorUids'],
    });
  }

  /// Owner only: deletes the trip with its stops and expenses.
  Future<void> delete(String id) async {
    for (final c in [_stops(id), _expenses(id)]) {
      final snap = await c.get();
      for (final d in snap.docs) {
        await d.reference.delete();
      }
    }
    await _trips.doc(id).delete();
  }

  /// Turns invites addressed to this email into memberships: records the uid
  /// on the member entry. Safe to run on every login.
  Future<int> claimInvites() async {
    final snap = await _trips.where('memberEmails', arrayContains: email).get();
    var claimed = 0;
    for (final d in snap.docs) {
      final trip = Trip.fromMap(d.id, d.data());
      final me = trip.memberByEmail(email);
      if (me == null || me.uid != null) continue;
      await _db.runTransaction((tx) async {
        final fresh = await tx.get(d.reference);
        final data = fresh.data();
        if (data == null) return;
        final t = Trip.fromMap(fresh.id, data);
        final entry = t.memberByEmail(email);
        if (entry == null || entry.uid != null) return;
        final members = {
          for (final m in t.members)
            emailKey(m.email): (m == entry ? m.copyWith(uid: uid) : m).toMap(),
        };
        tx.update(d.reference, {
          'members': members,
          'memberUids': FieldValue.arrayUnion([uid]),
          if (entry.canEdit) 'editorUids': FieldValue.arrayUnion([uid]),
        });
        claimed++;
      });
    }
    return claimed;
  }

  // Roadmap

  Stream<List<TripStop>> watchStops(String tripId) =>
      _stops(tripId).snapshots().map((s) {
        final list = s.docs
            .map((d) => TripStop.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) {
          final ad = a.date, bd = b.date;
          if (ad != null && bd != null) {
            final c = ad.compareTo(bd);
            if (c != 0) return c;
          } else if (ad != null) {
            return -1;
          } else if (bd != null) {
            return 1;
          }
          return a.createdAt.compareTo(b.createdAt);
        });
        return list;
      });

  Future<void> addStop(String tripId, TripStop s) =>
      _stops(tripId).add(s.toMap());

  Future<void> updateStop(String tripId, TripStop s) =>
      _stops(tripId).doc(s.id).update(s.toMap());

  Future<void> deleteStop(String tripId, String id) =>
      _stops(tripId).doc(id).delete();

  // Expenses

  Stream<List<TripExpense>> watchExpenses(String tripId) =>
      _expenses(tripId).snapshots().map((s) {
        final list = s.docs
            .map((d) => TripExpense.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) {
          final c = b.date.compareTo(a.date);
          return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
        });
        return list;
      });

  Future<void> addExpense(String tripId, TripExpense e) =>
      _expenses(tripId).add(e.toMap());

  Future<void> updateExpense(String tripId, TripExpense e) =>
      _expenses(tripId).doc(e.id).update(e.toMap());

  Future<void> deleteExpense(String tripId, String id) =>
      _expenses(tripId).doc(id).delete();
}
