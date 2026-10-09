import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

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
      _check(t.balance, payment.amount);
      txn.set(ref, payment.toMap());
      return payment.amount;
    }).then((_) => ref.id);
  }

  Future<void> edit(String txnId, Payment payment) {
    final ref = _paths.payments(txnId).doc(payment.id);
    return _apply(txnId, (txn, t) async {
      final old = Payment.fromMap(payment.id, (await txn.get(ref)).data()!);
      // The edited amount may use the balance plus what this payment already covered.
      _check(t.balance + old.amount, payment.amount);
      txn.set(ref, payment.toMap());
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

  void _check(Money available, Money amount) {
    final result = validatePayment(balance: available, amount: amount);
    if (result != PaymentValidation.ok) throw PaymentException(result);
  }

  /// Runs [change] (which writes the payment and returns the change in paid
  /// total) then updates the parent transaction in the same Firestore transaction.
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
      final status = computeStatus(
        total: t.totalAmount,
        paid: paid,
        dueDate: t.dueDate,
        now: now,
      );
      txn.update(txnRef, {
        'paidTotal': paid.paise,
        'balance': (t.totalAmount - paid).paise,
        'status': status.name,
        'settledAt': status == TransactionStatus.paid
            ? Timestamp.fromDate(now)
            : null,
        'lastActivityAt': Timestamp.fromDate(now),
      });
    });
  }
}
