import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/reminder.dart';
import 'paths.dart';

class ReminderRepository {
  ReminderRepository(FirebaseFirestore db, String uid)
    : _paths = UserPaths(db, uid);

  final UserPaths _paths;

  /// Every reminder, earliest first ring first.
  Stream<List<Reminder>> watch() => _paths.reminders
      .orderBy('at')
      .snapshots()
      .map((s) => s.docs.map((d) => Reminder.fromMap(d.id, d.data())).toList());

  /// Every reminder, once (for exports).
  Future<List<Reminder>> getAll() async =>
      (await _paths.reminders.orderBy('at').get()).docs
          .map((d) => Reminder.fromMap(d.id, d.data()))
          .toList();

  Stream<Reminder?> watchOne(String id) => _paths.reminders
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Reminder.fromMap(d.id, d.data()!) : null);

  Future<String> add(Reminder reminder) async =>
      (await _paths.reminders.add(reminder.toMap())).id;

  Future<void> update(Reminder reminder) =>
      _paths.reminders.doc(reminder.id).update(reminder.toMap());

  Future<void> delete(String id) => _paths.reminders.doc(id).delete();

  /// Puts a deleted reminder back exactly as it was, under its old id (Undo).
  Future<void> restore(Reminder reminder) =>
      _paths.reminders.doc(reminder.id).set(reminder.toMap());

  Future<void> markDone(String id, {DateTime? at}) =>
      _paths.reminders.doc(id).update({
        'done': true,
        'doneAt': Timestamp.fromDate(at ?? DateTime.now()),
      });

  Future<void> reopen(String id) =>
      _paths.reminders.doc(id).update({'done': false, 'doneAt': null});
}
