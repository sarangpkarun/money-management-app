import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/person.dart';
import 'paths.dart';

class PeopleRepository {
  PeopleRepository(FirebaseFirestore db, String uid)
    : _paths = UserPaths(db, uid);

  final UserPaths _paths;

  Stream<List<Person>> watch() => _paths.people
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map((d) => Person.fromMap(d.id, d.data())).toList());

  /// Everyone, once (for exports).
  Future<List<Person>> getAll() async =>
      (await _paths.people.orderBy('name').get()).docs
          .map((d) => Person.fromMap(d.id, d.data()))
          .toList();

  Future<String> add(Person person) async =>
      (await _paths.people.add(person.toMap())).id;

  /// Saves the person and, so list screens never read the people collection,
  /// copies the (possibly new) name onto each of their transactions.
  Future<void> update(Person person) async {
    final batch = _paths.db.batch();
    batch.update(_paths.people.doc(person.id), person.toMap());
    final txns = await _paths.transactions
        .where('personId', isEqualTo: person.id)
        .get();
    for (final t in txns.docs) {
      batch.update(t.reference, {'personName': person.name});
    }
    await batch.commit();
  }

  Future<void> delete(String id) => _paths.people.doc(id).delete();

  /// Merges the people [removeIds] into [keepId]: all their entries move to the
  /// kept person (and carry its name), a missing phone or photo is filled in
  /// from the removed people, their notes are added to the kept person's, and
  /// the removed people are deleted. Returns how many entries moved.
  ///
  /// Entries are moved in batches and the people are deleted LAST, so an
  /// interrupted merge leaves every entry pointing at a person that exists and
  /// can simply be run again.
  Future<int> merge(String keepId, List<String> removeIds) async {
    final remove = removeIds.toSet();
    if (remove.isEmpty) throw const PeopleMergeException('Nothing to merge');
    if (remove.contains(keepId)) {
      throw const PeopleMergeException('A person cannot be merged into itself');
    }
    final keepSnap = await _paths.people.doc(keepId).get();
    if (!keepSnap.exists) {
      throw const PeopleMergeException('The person to keep no longer exists');
    }
    final keep = Person.fromMap(keepId, keepSnap.data()!);

    final removed = <Person>[];
    for (final id in remove) {
      final snap = await _paths.people.doc(id).get();
      // Already gone (an earlier, interrupted run): nothing left to fold in.
      if (snap.exists) removed.add(Person.fromMap(id, snap.data()!));
    }

    final moved = <DocumentReference<Map<String, dynamic>>>[];
    for (final id in remove) {
      final txns = await _paths.transactions
          .where('personId', isEqualTo: id)
          .get();
      moved.addAll(txns.docs.map((d) => d.reference));
    }
    for (var i = 0; i < moved.length; i += _batchSize) {
      final batch = _paths.db.batch();
      for (final ref in moved.skip(i).take(_batchSize)) {
        batch.update(ref, {'personId': keepId, 'personName': keep.name});
      }
      await batch.commit();
    }

    final notes = <String>[
      if (keep.notes != null && keep.notes!.trim().isNotEmpty)
        keep.notes!.trim(),
      for (final p in removed)
        if (p.notes != null &&
            p.notes!.trim().isNotEmpty &&
            !(keep.notes ?? '').contains(p.notes!.trim()))
          p.notes!.trim(),
    ];
    final phone = _firstNonBlank([keep.phone, ...removed.map((p) => p.phone)]);
    final email = _firstNonBlank([keep.email, ...removed.map((p) => p.email)]);
    final photo = _firstNonBlank([
      keep.photoUrl,
      ...removed.map((p) => p.photoUrl),
    ]);
    final finish = _paths.db.batch();
    finish.update(_paths.people.doc(keepId), {
      'phone': phone,
      'email': email,
      'notes': notes.isEmpty ? null : notes.join('\n'),
      'photoUrl': photo,
    });
    for (final p in removed) {
      finish.delete(_paths.people.doc(p.id));
    }
    await finish.commit();
    return moved.length;
  }

  static const _batchSize = 400;

  static String? _firstNonBlank(List<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v;
    }
    return null;
  }
}

/// A merge that cannot go ahead (bad ids, nothing to do).
class PeopleMergeException implements Exception {
  const PeopleMergeException(this.message);

  final String message;

  @override
  String toString() => 'PeopleMergeException: $message';
}
