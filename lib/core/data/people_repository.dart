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
}
