import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_settings.dart';
import '../models/app_user.dart';
import 'paths.dart';

class UserRepository {
  UserRepository(FirebaseFirestore db, String uid)
    : _paths = UserPaths(db, uid);

  final UserPaths _paths;

  Future<AppUser?> get() async {
    final data = (await _paths.user.get()).data();
    return data == null ? null : AppUser.fromMap(data);
  }

  Stream<AppUser?> watch() => _paths.user.snapshots().map((s) {
    final data = s.data();
    return data == null ? null : AppUser.fromMap(data);
  });

  /// Saves name, currency and timezone. Settings are left as they are.
  Future<void> save(AppUser user) =>
      _paths.user.set(user.toMap(), SetOptions(merge: true));

  /// Saves the display and reminder settings only.
  Future<void> saveSettings(AppSettings settings) =>
      _paths.user.set({'settings': settings.toMap()}, SetOptions(merge: true));

  /// Creates a default profile if none exists yet; never overwrites one.
  Future<void> ensureProfile(String fallbackName) async {
    if ((await _paths.user.get()).exists) return;
    await save(AppUser(name: fallbackName));
  }

  /// Permanently erases everything stored under `users/{uid}`: payments, then
  /// transactions, people, reminders and finally the profile document.
  Future<void> deleteAllData() async {
    final txns = await _paths.transactions.get();
    for (final t in txns.docs) {
      await _deleteCollection(t.reference.collection('payments'));
    }
    await _deleteCollection(_paths.transactions);
    await _deleteCollection(_paths.people);
    await _deleteCollection(_paths.reminders);
    await _paths.user.delete();
  }

  /// Deletes in batches, as Firestore limits a batch to 500 writes.
  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> c,
  ) async {
    while (true) {
      final snap = await c.limit(400).get();
      if (snap.docs.isEmpty) return;
      final batch = _paths.db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }
}
