import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/money_transaction.dart';
import '../money/money.dart';
import '../status/transaction_status.dart';
import 'paths.dart';

class TransactionRepository {
  TransactionRepository(
    FirebaseFirestore db,
    String uid, {
    DateTime Function()? now,
  }) : _paths = UserPaths(db, uid),
       _now = now ?? DateTime.now;

  final UserPaths _paths;
  final DateTime Function() _now;

  Stream<List<MoneyTransaction>> watch({
    TransactionStatus? status,
    TransactionType? type,
    String? personId,
  }) {
    Query<Map<String, dynamic>> q = _paths.transactions;
    if (status != null) q = q.where('status', isEqualTo: status.name);
    if (type != null) q = q.where('type', isEqualTo: type.name);
    if (personId != null) q = q.where('personId', isEqualTo: personId);
    return q.snapshots().map(
      (s) =>
          s.docs.map((d) => MoneyTransaction.fromMap(d.id, d.data())).toList(),
    );
  }

  Future<MoneyTransaction?> get(String id) async {
    final doc = await _paths.transactions.doc(id).get();
    final data = doc.data();
    return data == null ? null : MoneyTransaction.fromMap(doc.id, data);
  }

  /// Creates a transaction with nothing paid; status comes from the due date.
  Future<String> add(MoneyTransaction t) async {
    final fresh = MoneyTransaction(
      type: t.type,
      personId: t.personId,
      personName: t.personName,
      title: t.title,
      totalAmount: t.totalAmount,
      status: computeStatus(
        total: t.totalAmount,
        paid: Money.zero,
        dueDate: t.dueDate,
        now: _now(),
      ),
      dueDate: t.dueDate,
      interestType: t.interestType,
      interestRate: t.interestRate,
      createdAt: t.createdAt,
    );
    return (await _paths.transactions.add(fresh.toMap())).id;
  }

  /// Deletes the transaction and its payments.
  Future<void> delete(String id) async {
    final batch = _paths.db.batch();
    final payments = await _paths.payments(id).get();
    for (final p in payments.docs) {
      batch.delete(p.reference);
    }
    batch.delete(_paths.transactions.doc(id));
    await batch.commit();
  }
}
