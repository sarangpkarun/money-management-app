import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/log_entry.dart';
import 'paths.dart';

class LogRepository {
  LogRepository(FirebaseFirestore db, String uid) : _paths = UserPaths(db, uid);

  final UserPaths _paths;

  /// Entries dated within the month of [month], oldest day first.
  Stream<List<LogEntry>> watchMonth(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return _paths.logs
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map(_sorted);
  }

  /// Every entry, newest day first (for the list, search and exports).
  Stream<List<LogEntry>> watchAll() =>
      _paths.logs.snapshots().map((s) => _sorted(s).reversed.toList());

  Future<List<LogEntry>> getAll() async =>
      _sorted(await _paths.logs.get()).reversed.toList();

  Future<String> add(LogEntry e) async => (await _paths.logs.add(e.toMap())).id;

  /// Replaces the fields of an existing entry, keeping its creation time.
  Future<void> update(LogEntry e) => _paths.logs.doc(e.id).update(e.toMap());

  Future<void> setDone(String id, bool done) =>
      _paths.logs.doc(id).update({'done': done});

  Future<void> delete(String id) => _paths.logs.doc(id).delete();

  List<LogEntry> _sorted(QuerySnapshot<Map<String, dynamic>> s) {
    final list = s.docs.map((d) => LogEntry.fromMap(d.id, d.data())).toList();
    list.sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      return byDay != 0 ? byDay : a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }
}
