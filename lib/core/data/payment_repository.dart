import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../interest/interest.dart';
import '../models/money_transaction.dart';
import '../models/payment.dart';
import '../money/money.dart';
import '../status/transaction_status.dart';
import 'paths.dart';

class PaymentException implements Exception {
  const PaymentException(this.reason);

  final PaymentValidation reason;

  @override
  String toString() => 'PaymentException($reason)';
}

/// Every write changes the payment and the parent transaction's `paidTotal`,
/// `balance`, `status` and `settledAt` inside one Firestore transaction, so the
/// totals can never drift from the payments.
class PaymentRepository {
  PaymentRepository(
    FirebaseFirestore db,
    String uid, {
    DateTime Function()? now,
  }) : _paths = UserPaths(db, uid),
       _now = now ?? DateTime.now;

  final UserPaths _paths;
  final DateTime Function() _now;

  Stream<List<Payment>> watch(String txnId) => _paths
      .payments(txnId)
      .orderBy('date')
      .snapshots()
      .map((s) => s.docs.map((d) => Payment.fromMap(d.id, d.data())).toList());

  Future<String> add(String txnId, Payment payment) {
    final ref = _paths.payments(txnId).doc();
    return _apply(txnId, (txn, t) {
      _check(outstanding(t, _now()), payment.amount);
      txn.set(ref, {
        ...payment.toMap(),
        'createdAt': Timestamp.fromDate(_now()),
      });
      return payment.amount;
    }).then((_) => ref.id);
  }

  Future<void> edit(String txnId, Payment payment) {
    final ref = _paths.payments(txnId).doc(payment.id);
    return _apply(txnId, (txn, t) async {
      final old = Payment.fromMap(payment.id, (await txn.get(ref)).data()!);
      // The edited amount may use what is outstanding plus what this payment
      // already covered.
      _check(outstanding(t, _now()) + old.amount, payment.amount);
      txn.set(ref, {
        ...payment.toMap(),
        // Keep when it was first recorded; only the details change.
        if (old.createdAt != null)
          'createdAt': Timestamp.fromDate(old.createdAt!),
      });
      return payment.amount - old.amount;
    });
  }

  Future<void> delete(String txnId, String paymentId) {
    final ref = _paths.payments(txnId).doc(paymentId);
    return _apply(txnId, (txn, t) async {
      final old = Payment.fromMap(paymentId, (await txn.get(ref)).data()!);
      txn.delete(ref);
      return Money.zero - old.amount;
    });
  }

  /// "Mark as unpaid": removes the most recent payment (latest payment date,
  /// then the one recorded last) through [delete], so the totals, status,
  /// `settledAt` and interest are recomputed atomically. Returns what was
  /// removed.
  Future<Payment> reopenLastPayment(String txnId) async {
    final snap = await _paths.payments(txnId).get();
    if (snap.docs.isEmpty) {
      throw StateError('This entry has no payments to remove');
    }
    final last = latestPayment([
      for (final d in snap.docs) Payment.fromMap(d.id, d.data()),
    ])!;
    await delete(txnId, last.id);
    return last;
  }

  void _check(Money available, Money amount) {
    final result = validatePayment(balance: available, amount: amount);
    if (result != PaymentValidation.ok) throw PaymentException(result);
  }

  /// Runs [change] (which writes the payment and returns the change in paid
  /// total) then updates the parent transaction in the same Firestore transaction.
  ///
  /// Status is judged against what is due (principal plus interest). Once an
  /// entry is settled its interest is frozen at `settledAt`: it stays settled
  /// while payments still cover what was due then, and only reopens (interest
  /// resuming) if they no longer do.
  Future<void> _apply(
    String txnId,
    FutureOr<Money> Function(Transaction txn, MoneyTransaction t) change,
  ) {
    final txnRef = _paths.transactions.doc(txnId);
    return _paths.db.runTransaction((txn) async {
      final snap = await txn.get(txnRef);
      final t = MoneyTransaction.fromMap(txnId, snap.data()!);
      final delta = await change(txn, t);
      final paid = t.paidTotal + delta;
      final now = _now();

      final Money due;
      final TransactionStatus status;
      final DateTime? settledAt;
      final frozenAt = t.settledAt;
      if (frozenAt != null && paid >= amountDueAt(t, frozenAt)) {
        due = amountDueAt(t, frozenAt);
        status = TransactionStatus.paid;
        settledAt = frozenAt;
      } else {
        due = amountDueAt(t, now);
        status = computeStatus(
          total: due,
          paid: paid,
          dueDate: t.dueDate,
          now: now,
        );
        settledAt = status == TransactionStatus.paid ? now : null;
      }
      final left = due - paid;
      txn.update(txnRef, {
        'paidTotal': paid.paise,
        'balance': (left.isNegative ? Money.zero : left).paise,
        'status': status.name,
        'settledAt': settledAt == null ? null : Timestamp.fromDate(settledAt),
        'lastActivityAt': Timestamp.fromDate(now),
      });
    });
  }
}
