import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/instalments/instalment_plan.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/payment.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';

Money rs(int r) => Money.fromRupees(r);

void main() {
  // Owe Ravi Rs 30,000 as 5 x Rs 6,000 from 31 Jan 2026.
  final now = DateTime(2026, 1, 10);
  late FakeFirebaseFirestore db;
  late TransactionRepository txns;
  late PaymentRepository pays;
  late String ravi;

  setUp(() async {
    db = FakeFirebaseFirestore();
    txns = TransactionRepository(db, 'u1', now: () => now);
    pays = PaymentRepository(db, 'u1', now: () => now);
    ravi = await PeopleRepository(
      db,
      'u1',
    ).add(Person(name: 'Ravi', createdAt: now));
  });

  Future<String> newPlan({int? months = 5, Money? monthly}) =>
      txns.addInstalmentPlan(
        personId: ravi,
        personName: 'Ravi',
        title: 'Loan from Ravi',
        total: rs(30000),
        months: monthly == null ? months : null,
        monthlyAmount: monthly,
        startDate: DateTime(2026, 1, 31),
      );

  Future<MoneyTransaction> load(String id) async => (await txns.get(id))!;

  List<int> rupees(MoneyTransaction t) =>
      t.emiPlan!.rows.map((r) => r.amount.paise ~/ 100).toList();

  /// What is left to pay must always match the entry's own totals.
  void expectConsistent(MoneyTransaction t) {
    final remaining = t.emiPlan!.rows.fold(
      Money.zero,
      (a, r) => a + r.remaining,
    );
    expect(remaining, t.totalAmount - t.paidTotal);
  }

  group('addInstalmentPlan', () {
    test('by months creates an instalment entry with the schedule', () async {
      final t = await load(await newPlan());
      expect(t.type, TransactionType.instalment);
      expect(t.title, 'Loan from Ravi');
      expect(t.personId, ravi);
      expect(t.totalAmount, rs(30000));
      expect(t.interestType, InterestType.none);
      expect(rupees(t), [6000, 6000, 6000, 6000, 6000]);
      expect(t.dueDate, DateTime(2026, 1, 31));
      expect(t.status, TransactionStatus.pending);
      expect(t.lastActivityAt, now);
      expectConsistent(t);
    });

    test('by monthly amount works out the months', () async {
      final t = await load(await newPlan(monthly: rs(7000)));
      expect(rupees(t), [7000, 7000, 7000, 7000, 2000]);
    });

    test('bad terms save nothing', () async {
      expect(
        () => txns.addInstalmentPlan(
          personId: ravi,
          personName: 'Ravi',
          title: 'x',
          total: rs(100),
          startDate: DateTime(2026, 1, 31),
        ),
        throwsA(isA<InstalmentError>()),
      );
      expect(
        (await db.collection('users/u1/transactions').get()).docs,
        isEmpty,
      );
    });
  });

  group('skipMonth', () {
    test('moves the dates and the next due date', () async {
      final id = await newPlan();
      await pays.skipMonth(id, 1);
      final t = await load(id);
      expect(t.dueDate, DateTime(2026, 2, 28));
      expect(t.emiPlan!.rows.last.dueDate, DateTime(2026, 6, 30));
      expect(rupees(t), [6000, 6000, 6000, 6000, 6000]);
      expect(t.paidTotal, Money.zero);
      expectConsistent(t);
    });

    test(
      'a skipped payment is no longer overdue until its new date passes',
      () async {
        final id = await newPlan();
        final march = PaymentRepository(
          db,
          'u1',
          now: () => DateTime(2026, 3, 5),
        );
        await march.skipMonth(id, 1); // 31 Jan -> 28 Feb, still before 5 Mar
        expect((await load(id)).status, TransactionStatus.overdue);
        await march.skipMonth(id, 1); // 28 Feb -> 31 Mar
        final t = await load(id);
        expect(t.dueDate, DateTime(2026, 3, 31));
        expect(t.status, TransactionStatus.pending);
      },
    );

    test('a payment with money on it cannot be skipped', () async {
      final id = await newPlan();
      await pays.payInstallment(
        id,
        1,
        amount: rs(1000),
        date: now,
        mode: PaymentMode.cash,
      );
      expect(() => pays.skipMonth(id, 1), throwsA(isA<InstalmentError>()));
      expect((await load(id)).dueDate, DateTime(2026, 1, 31));
    });

    test('works after the first payment', () async {
      final id = await newPlan();
      await pays.payInstallment(
        id,
        1,
        amount: rs(6000),
        date: now,
        mode: PaymentMode.cash,
      );
      await pays.skipMonth(id, 2);
      final t = await load(id);
      expect(t.emiPlan!.rows[0].dueDate, DateTime(2026, 1, 31)); // paid: kept
      expect(t.dueDate, DateTime(2026, 3, 31)); // row 2 was 28 Feb
      expectConsistent(t);
    });

    test('only instalment plans can be changed this way', () async {
      final plain = await txns.add(
        MoneyTransaction(
          type: TransactionType.lent,
          personId: ravi,
          personName: 'Ravi',
          title: 't',
          totalAmount: rs(100),
          createdAt: now,
        ),
      );
      expect(() => pays.skipMonth(plain, 1), throwsStateError);
    });
  });

  group('changeInstalmentAmount', () {
    test('re-spreads the rest and keeps the totals', () async {
      final id = await newPlan();
      await pays.changeInstalmentAmount(id, 2, rs(10000));
      final t = await load(id);
      expect(t.emiPlan!.rows.map((r) => r.amount.paise), [
        600000,
        1000000,
        466666,
        466666,
        466668,
      ]);
      expect(t.totalAmount, rs(30000));
      expect(t.paidTotal, Money.zero);
      expectConsistent(t);
    });

    test(
      'a big amount shortens the plan and moves the next due date on',
      () async {
        final id = await newPlan();
        await pays.payInstallment(
          id,
          1,
          amount: rs(6000),
          date: now,
          mode: PaymentMode.cash,
        );
        await pays.changeInstalmentAmount(id, 2, rs(24000));
        final t = await load(id);
        expect(rupees(t), [6000, 24000]);
        expect(t.dueDate, DateTime(2026, 2, 28));
        expectConsistent(t);
      },
    );

    test('invalid changes are rejected and nothing is written', () async {
      final id = await newPlan();
      expect(
        () => pays.changeInstalmentAmount(id, 2, rs(0)),
        throwsA(isA<InstalmentError>()),
      );
      expect(
        () => pays.changeInstalmentAmount(id, 2, rs(99999)),
        throwsA(isA<InstalmentError>()),
      );
      expect(rupees(await load(id)), [6000, 6000, 6000, 6000, 6000]);
    });

    test('paying the changed amount settles the plan in the end', () async {
      final id = await newPlan(months: 2); // 15,000 x 2
      await pays.changeInstalmentAmount(id, 1, rs(20000));
      var t = await load(id);
      expect(rupees(t), [20000, 10000]);
      await pays.payInstallment(
        id,
        1,
        amount: rs(20000),
        date: now,
        mode: PaymentMode.cash,
      );
      await pays.payInstallment(
        id,
        2,
        amount: rs(10000),
        date: now,
        mode: PaymentMode.cash,
      );
      t = await load(id);
      expect(t.status, TransactionStatus.paid);
      expect(t.settledAt, now);
    });
  });

  group('extra payments', () {
    test(
      'reduce the schedule from the last payment and count as paid',
      () async {
        final id = await newPlan();
        final pid = await pays.payExtra(
          id,
          amount: rs(7000),
          date: now,
          mode: PaymentMode.upi,
          note: 'bonus',
        );
        final t = await load(id);
        expect(rupees(t), [6000, 6000, 6000, 5000]);
        expect(t.paidTotal, rs(7000));
        expect(t.status, TransactionStatus.partiallyPaid);
        expect(t.dueDate, DateTime(2026, 1, 31));
        expectConsistent(t);

        final doc =
            (await db.doc('users/u1/transactions/$id/payments/$pid').get())
                .data()!;
        expect(doc['extra'], true);
        expect(doc.containsKey('installment'), isFalse);
        expect(doc['note'], 'bonus');
      },
    );

    test('more than what is left is blocked', () async {
      final id = await newPlan();
      expect(
        () => pays.payExtra(
          id,
          amount: rs(30001),
          date: now,
          mode: PaymentMode.cash,
        ),
        throwsA(
          isA<PaymentException>().having(
            (e) => e.reason,
            'reason',
            PaymentValidation.exceedsBalance,
          ),
        ),
      );
      final t = await load(id);
      expect(t.paidTotal, Money.zero);
      expect(rupees(t), [6000, 6000, 6000, 6000, 6000]);
    });

    test('zero is blocked', () async {
      final id = await newPlan();
      expect(
        () => pays.payExtra(
          id,
          amount: Money.zero,
          date: now,
          mode: PaymentMode.cash,
        ),
        throwsA(isA<PaymentException>()),
      );
    });

    test('paying everything as an extra settles the entry', () async {
      final id = await newPlan();
      await pays.payExtra(
        id,
        amount: rs(30000),
        date: now,
        mode: PaymentMode.cash,
      );
      final t = await load(id);
      expect(t.status, TransactionStatus.paid);
      expect(t.settledAt, now);
      expect(t.emiPlan!.rows, isEmpty);
      expect(t.paidTotal, rs(30000));
    });

    test('deleting the extra payment puts the schedule back', () async {
      final id = await newPlan();
      final pid = await pays.payExtra(
        id,
        amount: rs(7000),
        date: now,
        mode: PaymentMode.cash,
      );
      await pays.delete(id, pid);
      final t = await load(id);
      expect(t.paidTotal, Money.zero);
      expect(t.status, TransactionStatus.pending);
      expect(
        t.emiPlan!.rows.fold(Money.zero, (a, r) => a + r.amount),
        rs(30000),
      );
      expectConsistent(t);
    });

    test(
      'deleting an extra payment that emptied the plan restores the rows',
      () async {
        final id = await newPlan();
        final pid = await pays.payExtra(
          id,
          amount: rs(30000),
          date: now,
          mode: PaymentMode.cash,
        );
        await pays.delete(id, pid);
        final t = await load(id);
        expect(t.status, TransactionStatus.pending);
        expect(t.settledAt, isNull);
        // Back to the original five payments of Rs 6,000.
        expect(rupees(t), [6000, 6000, 6000, 6000, 6000]);
        expect(t.emiPlan!.rows.first.dueDate, DateTime(2026, 1, 31));
        expectConsistent(t);
      },
    );

    test('editing the amount re-applies it', () async {
      final id = await newPlan();
      final pid = await pays.payExtra(
        id,
        amount: rs(7000),
        date: now,
        mode: PaymentMode.cash,
      );
      await pays.edit(
        id,
        Payment(id: pid, amount: rs(2000), date: now, mode: PaymentMode.bank),
      );
      final t = await load(id);
      expect(t.paidTotal, rs(2000));
      expect(rupees(t), [6000, 6000, 6000, 6000, 4000]);
      expectConsistent(t);
      final doc =
          (await db.doc('users/u1/transactions/$id/payments/$pid').get())
              .data()!;
      expect(doc['extra'], true);
    });

    test('editing past what is owed is blocked', () async {
      final id = await newPlan();
      final pid = await pays.payExtra(
        id,
        amount: rs(7000),
        date: now,
        mode: PaymentMode.cash,
      );
      expect(
        () => pays.edit(id, Payment(id: pid, amount: rs(40000), date: now)),
        throwsA(isA<PaymentException>()),
      );
      expect((await load(id)).paidTotal, rs(7000));
    });

    test('Mark as unpaid removes a final extra payment', () async {
      final id = await newPlan();
      await pays.payExtra(
        id,
        amount: rs(30000),
        date: now,
        mode: PaymentMode.cash,
      );
      final removed = await pays.reopenLastPayment(id);
      expect(removed.extra, isTrue);
      expect((await load(id)).status, TransactionStatus.pending);
    });
  });

  test('free-form payments are not allowed on an instalment plan', () async {
    final id = await newPlan();
    expect(
      () => pays.add(id, Payment(amount: rs(100), date: now)),
      throwsStateError,
    );
  });

  test(
    'skip, change, extra and pay together keep every total consistent',
    () async {
      final id = await newPlan();
      await pays.payInstallment(
        id,
        1,
        amount: rs(6000),
        date: now,
        mode: PaymentMode.cash,
      );
      await pays.skipMonth(id, 2);
      await pays.changeInstalmentAmount(id, 2, rs(9000));
      final extra = await pays.payExtra(
        id,
        amount: rs(5000),
        date: now,
        mode: PaymentMode.cash,
      );
      await pays.payInstallment(
        id,
        2,
        amount: rs(9000),
        date: now,
        mode: PaymentMode.cash,
      );
      var t = await load(id);
      expectConsistent(t);
      expect(t.paidTotal, rs(20000));
      await pays.delete(id, extra);
      t = await load(id);
      expectConsistent(t);
      expect(t.paidTotal, rs(15000));
    },
  );
}
