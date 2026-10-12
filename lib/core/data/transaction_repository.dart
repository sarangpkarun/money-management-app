import 'package:cloud_firestore/cloud_firestore.dart';

import '../emi/emi_schedule.dart';
import '../interest/interest.dart';
import '../instalments/instalment_plan.dart';
import '../models/emi_plan.dart';
import '../models/money_transaction.dart';
import '../money/money.dart';
import '../status/transaction_status.dart';
import 'paths.dart';

/// Thrown when an entry edit would leave it in an invalid state.
class EntryEditError implements Exception {
  const EntryEditError(this.message);
  final String message;
  @override
  String toString() => 'EntryEditError: $message';
}

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

  Stream<MoneyTransaction?> watchOne(String id) =>
      _paths.transactions.doc(id).snapshots().map((s) {
        final data = s.data();
        return data == null ? null : MoneyTransaction.fromMap(s.id, data);
      });

  /// Every entry, once (for exports).
  Future<List<MoneyTransaction>> getAll() async =>
      (await _paths.transactions.get()).docs
          .map((d) => MoneyTransaction.fromMap(d.id, d.data()))
          .toList();

  /// Edits an entry. Descriptive fields always apply; passing [totalAmount],
  /// [personId]/[personName], [interestType], [interestRate] or [repaymentType]
  /// changes those too, and the balance, status and settlement are recomputed.
  /// Throws [EntryEditError] if the new amount is below what is already paid.
  Future<void> update(
    String id, {
    required String title,
    String? notes,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? date,
    Money? totalAmount,
    String? personId,
    String? personName,
    InterestType? interestType,
    double? interestRate,
    RatePeriod? ratePeriod,
    RepaymentType? repaymentType,
  }) {
    final ref = _paths.transactions.doc(id);
    return _paths.db.runTransaction((txn) async {
      final current = MoneyTransaction.fromMap(
        id,
        (await txn.get(ref)).data()!,
      );
      final newTotal = totalAmount ?? current.totalAmount;
      if (newTotal < current.paidTotal) {
        throw const EntryEditError('Amount cannot be less than already paid');
      }
      final newDue = clearDueDate ? null : (dueDate ?? current.dueDate);
      final newDate = date ?? current.date;
      final newInterestType = interestType ?? current.interestType;
      final newRate = newInterestType == InterestType.none
          ? null
          : (interestRate ?? current.interestRate);
      final now = _now();
      final edited = MoneyTransaction(
        type: current.type,
        personId: personId ?? current.personId,
        personName: personName ?? current.personName,
        title: title,
        totalAmount: newTotal,
        paidTotal: current.paidTotal,
        dueDate: newDue,
        interestType: newInterestType,
        interestRate: newRate,
        ratePeriod: ratePeriod ?? current.ratePeriod,
        repaymentType: repaymentType ?? current.repaymentType,
        createdAt: current.createdAt,
        date: newDate,
      );
      // Interest terms may have changed, so settlement is re-evaluated from
      // scratch rather than keeping the old frozen date.
      final due = amountDueAt(edited, now);
      final status = computeStatus(
        total: due,
        paid: current.paidTotal,
        dueDate: newDue,
        now: now,
      );
      final left = due - current.paidTotal;
      txn.update(ref, {
        'title': title,
        'notes': notes,
        'dueDate': newDue == null ? null : Timestamp.fromDate(newDue),
        'date': newDate == null ? null : Timestamp.fromDate(newDate),
        'personId': edited.personId,
        'personName': edited.personName,
        'totalAmount': newTotal.paise,
        'interestType': newInterestType.name,
        'interestRate': newRate,
        'ratePeriod': edited.ratePeriod.name,
        'repaymentType': edited.repaymentType.name,
        'balance': (left.isNegative ? Money.zero : left).paise,
        'status': status.name,
        'settledAt': status == TransactionStatus.paid
            ? Timestamp.fromDate(current.settledAt ?? now)
            : null,
        'lastActivityAt': Timestamp.fromDate(now),
      });
    });
  }

  /// Turns the automatic due-date alarms for one entry on or off.
  Future<void> setAutoReminders(String id, bool on) =>
      _paths.transactions.doc(id).update({'autoReminders': on});

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
      ratePeriod: t.ratePeriod,
      repaymentType: t.repaymentType,
      createdAt: t.createdAt,
      lastActivityAt: _now(),
      date: t.date,
      notes: t.notes,
    );
    return (await _paths.transactions.add(fresh.toMap())).id;
  }

  /// Creates an EMI purchase: generates the schedule (throws [EmiInputError] for
  /// bad terms), and saves an `emi` entry whose total is everything due in
  /// instalments (the down payment is not owed). The interest is already inside
  /// the instalments, so the entry itself carries none.
  Future<String> addEmi({
    required String personId,
    required String personName,
    required String title,
    required Money price,
    Money downPayment = Money.zero,
    required double annualRatePercent,
    required int months,
    required DateTime startDate,
    LateFeeRule? lateFee,
    double? noCostRate,
    String? notes,
  }) async {
    final schedule = generateEmiSchedule(
      price: price,
      downPayment: downPayment,
      annualRatePercent: annualRatePercent,
      months: months,
      startDate: startDate,
    );
    final plan = EmiPlan.fromSchedule(
      schedule,
      price: price,
      downPayment: downPayment,
      annualRatePercent: annualRatePercent,
      startDate: startDate,
      lateFee: lateFee,
      noCostRate: noCostRate,
    );
    final now = _now();
    final firstDue = plan.rows.first.dueDate;
    final entry = MoneyTransaction(
      type: TransactionType.emi,
      personId: personId,
      personName: personName,
      title: title,
      totalAmount: plan.totalPayable,
      status: computeStatus(
        total: plan.totalPayable,
        paid: Money.zero,
        dueDate: firstDue,
        now: now,
      ),
      dueDate: firstDue,
      createdAt: now,
      lastActivityAt: now,
      date: now,
      notes: notes,
      emiPlan: plan,
    );
    return (await _paths.transactions.add(entry.toMap())).id;
  }

  /// Creates an instalment plan for money you owe a person: [total] paid in
  /// equal monthly payments, given either [months] or [monthlyAmount]. Throws
  /// [InstalmentError] for bad terms. The person you owe is the entry's person.
  Future<String> addInstalmentPlan({
    required String personId,
    required String personName,
    required String title,
    required Money total,
    int? months,
    Money? monthlyAmount,
    required DateTime startDate,
    String? notes,
  }) async {
    final plan = generateInstalmentPlan(
      total: total,
      months: months,
      monthlyAmount: monthlyAmount,
      startDate: startDate,
    );
    final now = _now();
    final firstDue = plan.rows.first.dueDate;
    final entry = MoneyTransaction(
      type: TransactionType.instalment,
      personId: personId,
      personName: personName,
      title: title,
      totalAmount: total,
      status: computeStatus(
        total: total,
        paid: Money.zero,
        dueDate: firstDue,
        now: now,
      ),
      dueDate: firstDue,
      createdAt: now,
      lastActivityAt: now,
      date: now,
      notes: notes,
      emiPlan: plan,
    );
    return (await _paths.transactions.add(entry.toMap())).id;
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
