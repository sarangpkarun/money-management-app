import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../instalments/instalment_plan.dart' as plans;
import '../interest/interest.dart';
import '../models/emi_plan.dart';
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

/// What a payment write changes on the parent: how much was paid, and for an
/// EMI purchase the schedule with its row updated.
class _Change {
  const _Change(this.delta, [this.plan]);

  final Money delta;
  final EmiPlan? plan;
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
      if (t.emiPlan != null) {
        throw StateError('This entry is paid through its schedule');
      }
      _check(outstanding(t, _now()), payment.amount);
      txn.set(ref, {
        ...payment.toMap(),
        'createdAt': Timestamp.fromDate(_now()),
      });
      return _Change(payment.amount);
    }).then((_) => ref.id);
  }

  Future<void> edit(String txnId, Payment payment) {
    final ref = _paths.payments(txnId).doc(payment.id);
    return _apply(txnId, (txn, t) async {
      final old = Payment.fromMap(payment.id, (await txn.get(ref)).data()!);
      if (old.extra && t.emiPlan != null) {
        _check(outstanding(t, _now()) + old.amount, payment.amount);
        txn.set(ref, {
          ...payment.toMap(),
          if (old.createdAt != null)
            'createdAt': Timestamp.fromDate(old.createdAt!),
          'extra': true,
        });
        // Undo the old extra payment, then apply the edited amount.
        final restored = plans.restoreExtraPayment(t.emiPlan!, old.amount);
        return _Change(
          payment.amount - old.amount,
          plans.applyExtraPayment(restored, payment.amount),
        );
      }
      final row = _rowOf(t, old);
      // The edited amount may use what is still open (on the instalment, or on
      // the entry) plus what this payment already covered.
      _check(
        row != null
            ? row.remaining + old.amount
            : outstanding(t, _now()) + old.amount,
        payment.amount,
      );
      txn.set(ref, {
        ...payment.toMap(),
        // Keep when it was first recorded; only the details change.
        if (old.createdAt != null)
          'createdAt': Timestamp.fromDate(old.createdAt!),
        // An instalment payment stays tied to its instalment.
        if (old.installment != null) 'installment': old.installment,
      });
      if (row != null) {
        final paid = row.paidAmount - old.amount + payment.amount;
        return _Change(
          payment.amount - old.amount,
          t.emiPlan!.copyWithRow(
            row.copyWith(paidAmount: paid, paidOn: payment.date),
          ),
        );
      }
      return _Change(payment.amount - old.amount);
    });
  }

  Future<void> delete(String txnId, String paymentId) {
    final ref = _paths.payments(txnId).doc(paymentId);
    return _apply(txnId, (txn, t) async {
      final old = Payment.fromMap(paymentId, (await txn.get(ref)).data()!);
      txn.delete(ref);
      if (old.extra && t.emiPlan != null) {
        return _Change(
          Money.zero - old.amount,
          plans.restoreExtraPayment(t.emiPlan!, old.amount),
        );
      }
      final row = _rowOf(t, old);
      if (row != null) {
        final left = row.paidAmount - old.amount;
        final paid = left.isNegative ? Money.zero : left;
        return _Change(
          Money.zero - old.amount,
          t.emiPlan!.copyWithRow(
            row.copyWith(paidAmount: paid, clearPaidOn: paid.isZero),
          ),
        );
      }
      return _Change(Money.zero - old.amount);
    });
  }

  /// Pays [amount] towards instalment [number] of an EMI purchase. The payment
  /// is tagged with the instalment, and that row, the entry's totals, status,
  /// `settledAt` and next due date change in the same Firestore transaction.
  /// The amount is at most what is left on that row.
  Future<String> payInstallment(
    String txnId,
    int number, {
    required Money amount,
    required DateTime date,
    required PaymentMode mode,
    String? note,
  }) {
    final ref = _paths.payments(txnId).doc();
    return _apply(txnId, (txn, t) {
      final plan = t.emiPlan;
      final row = plan?.rowNumbered(number);
      if (plan == null || row == null) {
        throw StateError('This entry has no instalment $number');
      }
      _check(row.remaining, amount);
      txn.set(
        ref,
        Payment(
          amount: amount,
          date: date,
          mode: mode,
          note: note,
          installment: number,
        ).toMap()..['createdAt'] = Timestamp.fromDate(_now()),
      );
      return _Change(
        amount,
        plan.copyWithRow(
          row.copyWith(paidAmount: row.paidAmount + amount, paidOn: date),
        ),
      );
    }).then((_) => ref.id);
  }

  /// Skips a month on an instalment plan (see `skipMonth` in the plan logic):
  /// the payment and all later unpaid ones move a month later.
  Future<void> skipMonth(String txnId, int number) => _apply(
    txnId,
    (txn, t) =>
        _Change(Money.zero, plans.skipMonth(_instalmentPlan(t), number)),
  );

  /// Changes one payment of an instalment plan; the rest is re-spread so the
  /// total still adds up.
  Future<void> changeInstalmentAmount(
    String txnId,
    int number,
    Money newAmount,
  ) => _apply(
    txnId,
    (txn, t) => _Change(
      Money.zero,
      plans.changeAmount(_instalmentPlan(t), number, newAmount),
    ),
  );

  /// An extra payment towards a whole instalment plan: it is recorded as a
  /// payment and shortens the schedule from the last payment backwards. At most
  /// what is still owed.
  Future<String> payExtra(
    String txnId, {
    required Money amount,
    required DateTime date,
    required PaymentMode mode,
    String? note,
  }) {
    final ref = _paths.payments(txnId).doc();
    return _apply(txnId, (txn, t) {
      final plan = _instalmentPlan(t);
      _check(outstanding(t, _now()), amount);
      txn.set(
        ref,
        Payment(
          amount: amount,
          date: date,
          mode: mode,
          note: note,
          extra: true,
        ).toMap()..['createdAt'] = Timestamp.fromDate(_now()),
      );
      return _Change(amount, plans.applyExtraPayment(plan, amount));
    }).then((_) => ref.id);
  }

  EmiPlan _instalmentPlan(MoneyTransaction t) {
    final plan = t.emiPlan;
    if (t.type != TransactionType.instalment || plan == null) {
      throw StateError('This is not an instalment plan');
    }
    return plan;
  }

  /// The instalment a payment was made towards, if it has one on this entry.
  EmiRow? _rowOf(MoneyTransaction t, Payment p) =>
      p.installment == null ? null : t.emiPlan?.rowNumbered(p.installment!);

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
    FutureOr<_Change> Function(Transaction txn, MoneyTransaction t) change,
  ) {
    final txnRef = _paths.transactions.doc(txnId);
    return _paths.db.runTransaction((txn) async {
      final snap = await txn.get(txnRef);
      final t = MoneyTransaction.fromMap(txnId, snap.data()!);
      final change0 = await change(txn, t);
      final plan = change0.plan;
      final paid = t.paidTotal + change0.delta;
      final now = _now();

      final Money due;
      final TransactionStatus status;
      final DateTime? settledAt;
      // For an EMI purchase the next unpaid instalment is what is due next.
      final dueDate = plan != null
          ? (plan.nextUnpaid?.dueDate ?? t.dueDate)
          : t.dueDate;
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
          dueDate: dueDate,
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
        if (plan != null) 'schedule': plan.scheduleToMaps(),
        if (plan != null)
          'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate),
      });
    });
  }
}
