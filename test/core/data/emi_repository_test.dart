import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/emi/emi_schedule.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/payment.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';

void main() {
  // 12,000 at 0% over 4 months starting 15 Oct 2026: 4 x Rs 3,000 due
  // 15 Oct, 15 Nov, 15 Dec, 15 Jan.
  final now = DateTime(2026, 10, 1);
  late FakeFirebaseFirestore db;
  late TransactionRepository txns;
  late PaymentRepository pays;
  late PeopleRepository people;
  late String storeId;

  setUp(() async {
    db = FakeFirebaseFirestore();
    txns = TransactionRepository(db, 'u1', now: () => now);
    pays = PaymentRepository(db, 'u1', now: () => now);
    people = PeopleRepository(db, 'u1');
    storeId = await people.add(Person(name: 'Croma', createdAt: now));
  });

  Future<String> newEmi() => txns.addEmi(
    personId: storeId,
    personName: 'Croma',
    title: 'Phone',
    price: Money.fromRupees(12000),
    annualRatePercent: 0,
    months: 4,
    startDate: DateTime(2026, 10, 15),
  );

  Future<MoneyTransaction> load(String id) async => (await txns.get(id))!;

  Future<String> payRow(
    String id,
    int number,
    int rupees, {
    PaymentRepository? repo,
  }) => (repo ?? pays).payInstallment(
    id,
    number,
    amount: Money.fromRupees(rupees),
    date: DateTime(2026, 10, 10),
    mode: PaymentMode.upi,
    note: 'n$number',
  );

  group('addEmi', () {
    test(
      'creates an EMI entry with the schedule and the first due date',
      () async {
        final id = await newEmi();
        final t = await load(id);
        expect(t.type, TransactionType.emi);
        expect(t.title, 'Phone');
        expect(t.personId, storeId);
        expect(t.personName, 'Croma');
        expect(t.interestType, InterestType.none);
        expect(t.totalAmount, Money.fromRupees(12000)); // total payable
        expect(t.paidTotal, Money.zero);
        expect(t.status, TransactionStatus.pending);
        expect(t.dueDate, DateTime(2026, 10, 15));
        expect(t.emiPlan!.rows.length, 4);
        expect(t.emiPlan!.emi, Money.fromRupees(3000));
        expect(t.lastActivityAt, now);
      },
    );

    test('the down payment is not counted as owed', () async {
      final id = await txns.addEmi(
        personId: storeId,
        personName: 'Croma',
        title: 'TV',
        price: Money.fromRupees(40000),
        downPayment: Money.fromRupees(10000),
        annualRatePercent: 0,
        months: 3,
        startDate: DateTime(2026, 10, 15),
      );
      final t = await load(id);
      expect(t.totalAmount, Money.fromRupees(30000));
      expect(t.emiPlan!.downPayment, Money.fromRupees(10000));
      expect(t.emiPlan!.price, Money.fromRupees(40000));
    });

    test(
      'interest is inside the instalments, so it is not added twice',
      () async {
        final id = await txns.addEmi(
          personId: storeId,
          personName: 'Croma',
          title: 'Phone',
          price: Money.fromRupees(60000),
          annualRatePercent: 12,
          months: 12,
          startDate: DateTime(2026, 10, 15),
        );
        final t = await load(id);
        expect(
          t.totalAmount,
          const Money(6397113),
        ); // sum of the 12 instalments
        expect(t.interestType, InterestType.none);
      },
    );

    test('bad terms are rejected before anything is saved', () async {
      expect(
        () => txns.addEmi(
          personId: storeId,
          personName: 'Croma',
          title: 'x',
          price: Money.fromRupees(100),
          downPayment: Money.fromRupees(100),
          annualRatePercent: 12,
          months: 6,
          startDate: DateTime(2026, 10, 15),
        ),
        throwsA(isA<EmiInputError>()),
      );
      expect(
        (await db.collection('users/u1/transactions').get()).docs,
        isEmpty,
      );
    });
  });

  group('payInstallment', () {
    test(
      'paying a row in full marks it paid and moves the next due date',
      () async {
        final id = await newEmi();
        final pid = await payRow(id, 1, 3000);
        final t = await load(id);
        final row = t.emiPlan!.rows.first;
        expect(row.paidAmount, Money.fromRupees(3000));
        expect(row.paidOn, DateTime(2026, 10, 10));
        expect(row.isPaid, isTrue);
        expect(t.paidTotal, Money.fromRupees(3000));
        expect(t.dueDate, DateTime(2026, 11, 15));
        expect(t.status, TransactionStatus.partiallyPaid);
        expect(t.settledAt, isNull);

        final doc =
            (await db.doc('users/u1/transactions/$id/payments/$pid').get())
                .data()!;
        expect(doc['installment'], 1);
        expect(doc['amount'], 300000);
        expect(doc['mode'], 'upi');
        expect(doc['note'], 'n1');
      },
    );

    test(
      'a part payment leaves the row open and the due date unchanged',
      () async {
        final id = await newEmi();
        await payRow(id, 1, 1000);
        var t = await load(id);
        expect(t.emiPlan!.rows.first.paidAmount, Money.fromRupees(1000));
        expect(t.emiPlan!.rows.first.isPaid, isFalse);
        expect(t.dueDate, DateTime(2026, 10, 15));
        expect(t.paidTotal, Money.fromRupees(1000));

        await payRow(id, 1, 2000);
        t = await load(id);
        expect(t.emiPlan!.rows.first.isPaid, isTrue);
        expect(t.dueDate, DateTime(2026, 11, 15));
      },
    );

    test('paying more than what is left on the row is blocked', () async {
      final id = await newEmi();
      await payRow(id, 1, 1000);
      expect(
        () => payRow(id, 1, 2001),
        throwsA(
          isA<PaymentException>().having(
            (e) => e.reason,
            'reason',
            PaymentValidation.exceedsBalance,
          ),
        ),
      );
      final t = await load(id);
      expect(t.paidTotal, Money.fromRupees(1000));
      expect(t.emiPlan!.rows.first.paidAmount, Money.fromRupees(1000));
    });

    test('an already-paid row cannot take another payment', () async {
      final id = await newEmi();
      await payRow(id, 1, 3000);
      expect(() => payRow(id, 1, 1), throwsA(isA<PaymentException>()));
    });

    test('zero and negative amounts are blocked', () async {
      final id = await newEmi();
      for (final a in [0, -5]) {
        expect(
          () => pays.payInstallment(
            id,
            1,
            amount: Money.fromRupees(a),
            date: now,
            mode: PaymentMode.cash,
          ),
          throwsA(
            isA<PaymentException>().having(
              (e) => e.reason,
              'reason',
              PaymentValidation.notPositive,
            ),
          ),
        );
      }
    });

    test(
      'rows can be paid out of order; the next due stays the oldest unpaid',
      () async {
        final id = await newEmi();
        await payRow(id, 3, 3000);
        final t = await load(id);
        expect(t.emiPlan!.rows[2].isPaid, isTrue);
        expect(t.dueDate, DateTime(2026, 10, 15));
        expect(t.emiPlan!.nextUnpaid!.number, 1);
      },
    );

    test('an unknown instalment number is rejected', () async {
      final id = await newEmi();
      expect(() => payRow(id, 9, 1), throwsStateError);
    });

    test('paying the last row settles the entry', () async {
      final id = await newEmi();
      for (var n = 1; n <= 4; n++) {
        await payRow(id, n, 3000);
      }
      final t = await load(id);
      expect(t.status, TransactionStatus.paid);
      expect(t.settledAt, now);
      expect(t.paidTotal, Money.fromRupees(12000));
      expect(t.emiPlan!.nextUnpaid, isNull);
    });

    test('an overdue next instalment makes the entry overdue', () async {
      final id = await newEmi();
      final late = PaymentRepository(
        db,
        'u1',
        now: () => DateTime(2026, 12, 1),
      );
      await payRow(id, 1, 3000, repo: late);
      final t = await load(id);
      // Row 2 (15 Nov) is the next one and it is already past.
      expect(t.dueDate, DateTime(2026, 11, 15));
      expect(t.status, TransactionStatus.overdue);
    });

    test('free-form payments are not allowed on an EMI entry', () async {
      final id = await newEmi();
      expect(
        () => pays.add(id, Payment(amount: Money.fromRupees(100), date: now)),
        throwsStateError,
      );
    });

    test('lastActivityAt moves with each instalment payment', () async {
      final id = await newEmi();
      final later = PaymentRepository(
        db,
        'u1',
        now: () => DateTime(2026, 10, 20),
      );
      await payRow(id, 1, 3000, repo: later);
      expect((await load(id)).lastActivityAt, DateTime(2026, 10, 20));
    });
  });

  group('editing and deleting an instalment payment', () {
    test('deleting restores the row, the due date and the status', () async {
      final id = await newEmi();
      final pid = await payRow(id, 1, 3000);
      await pays.delete(id, pid);
      final t = await load(id);
      expect(t.emiPlan!.rows.first.paidAmount, Money.zero);
      expect(t.emiPlan!.rows.first.paidOn, isNull);
      expect(t.paidTotal, Money.zero);
      expect(t.dueDate, DateTime(2026, 10, 15));
      expect(t.status, TransactionStatus.pending);
    });

    test('deleting one of two part payments keeps the other', () async {
      final id = await newEmi();
      await payRow(id, 1, 1000);
      final second = await payRow(id, 1, 2000);
      await pays.delete(id, second);
      final t = await load(id);
      expect(t.emiPlan!.rows.first.paidAmount, Money.fromRupees(1000));
      expect(t.emiPlan!.rows.first.isPaid, isFalse);
      expect(t.dueDate, DateTime(2026, 10, 15));
    });

    test('deleting the final payment reopens a settled entry', () async {
      final id = await newEmi();
      String? last;
      for (var n = 1; n <= 4; n++) {
        last = await payRow(id, n, 3000);
      }
      await pays.delete(id, last!);
      final t = await load(id);
      expect(t.status, TransactionStatus.partiallyPaid);
      expect(t.settledAt, isNull);
      expect(t.emiPlan!.rows.last.paidAmount, Money.zero);
      expect(t.dueDate, DateTime(2027, 1, 15));
    });

    test('editing the amount adjusts the row and keeps the tag', () async {
      final id = await newEmi();
      final pid = await payRow(id, 1, 1000);
      await pays.edit(
        id,
        Payment(
          id: pid,
          amount: Money.fromRupees(2500),
          date: DateTime(2026, 10, 12),
          mode: PaymentMode.bank,
        ),
      );
      final t = await load(id);
      expect(t.emiPlan!.rows.first.paidAmount, Money.fromRupees(2500));
      expect(t.paidTotal, Money.fromRupees(2500));
      final doc =
          (await db.doc('users/u1/transactions/$id/payments/$pid').get())
              .data()!;
      expect(doc['installment'], 1);
      expect(doc['mode'], 'bank');
    });

    test('editing a payment past the row amount is blocked', () async {
      final id = await newEmi();
      final pid = await payRow(id, 1, 1000);
      expect(
        () => pays.edit(
          id,
          Payment(id: pid, amount: Money.fromRupees(3001), date: now),
        ),
        throwsA(isA<PaymentException>()),
      );
      expect(
        (await load(id)).emiPlan!.rows.first.paidAmount,
        Money.fromRupees(1000),
      );
    });

    test('Mark as unpaid removes the latest instalment payment', () async {
      final id = await newEmi();
      await pays.payInstallment(
        id,
        1,
        amount: Money.fromRupees(3000),
        date: DateTime(2026, 10, 10),
        mode: PaymentMode.cash,
      );
      await pays.payInstallment(
        id,
        2,
        amount: Money.fromRupees(3000),
        date: DateTime(2026, 11, 10),
        mode: PaymentMode.cash,
      );
      final removed = await pays.reopenLastPayment(id);
      expect(removed.installment, 2);
      final t = await load(id);
      expect(t.emiPlan!.rows[1].paidAmount, Money.zero);
      expect(t.emiPlan!.rows[0].isPaid, isTrue);
      expect(t.dueDate, DateTime(2026, 11, 15));
    });
  });

  test('the schedule survives a round trip through Firestore', () async {
    final id = await newEmi();
    await payRow(id, 2, 3000);
    final raw = (await db.doc('users/u1/transactions/$id').get()).data()!;
    expect((raw['schedule'] as List).length, 4);
    final t = MoneyTransaction.fromMap(id, raw);
    expect(t.emiPlan!.rows[1].isPaid, isTrue);
    expect(t.emiPlan!.rows[0].isPaid, isFalse);
    expect(raw['emiPlan'], isA<Map>());
    expect((raw['dueDate'] as Timestamp).toDate(), DateTime(2026, 10, 15));
  });
}
