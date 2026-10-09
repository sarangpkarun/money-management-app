import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/payment_repository.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/payment.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';

void main() {
  final now = DateTime(2026, 10, 9, 12);
  late FakeFirebaseFirestore db;
  late PeopleRepository people;
  late TransactionRepository txns;
  late PaymentRepository payments;

  Future<String> newTxn({Money? total, DateTime? due}) async {
    final personId = await people.add(Person(name: 'Asha', createdAt: now));
    return txns.add(
      MoneyTransaction(
        type: TransactionType.lent,
        personId: personId,
        personName: 'Asha',
        title: 'Loan',
        totalAmount: total ?? Money.fromRupees(1000),
        dueDate: due,
        createdAt: now,
      ),
    );
  }

  Payment pay(int rupees, {String id = ''}) =>
      Payment(id: id, amount: Money.fromRupees(rupees), date: now);

  setUp(() {
    db = FakeFirebaseFirestore();
    people = PeopleRepository(db, 'u1');
    txns = TransactionRepository(db, 'u1', now: () => now);
    payments = PaymentRepository(db, 'u1', now: () => now);
  });

  group('models', () {
    test('transaction round-trips through a map', () async {
      final id = await newTxn(due: DateTime(2026, 11, 1));
      final t = (await txns.get(id))!;
      expect(t.totalAmount, Money.fromRupees(1000));
      expect(t.balance, Money.fromRupees(1000));
      expect(t.status, TransactionStatus.pending);
      expect(t.dueDate, DateTime(2026, 11, 1));
      final again = MoneyTransaction.fromMap(id, t.toMap());
      expect(again.title, 'Loan');
    });
  });

  group('payments', () {
    test('partial payment updates paidTotal, balance and status', () async {
      final id = await newTxn();
      await payments.add(id, pay(500));
      final t = (await txns.get(id))!;
      expect(t.paidTotal, Money.fromRupees(500));
      expect(t.balance, Money.fromRupees(500));
      expect(t.status, TransactionStatus.partiallyPaid);
      expect(t.settledAt, isNull);
    });

    test('full payment marks paid and sets settledAt', () async {
      final id = await newTxn();
      await payments.add(id, pay(1000));
      final t = (await txns.get(id))!;
      expect(t.status, TransactionStatus.paid);
      expect(t.balance, Money.zero);
      expect(t.settledAt, now);
    });

    test('overpayment is blocked and changes nothing', () async {
      final id = await newTxn();
      await payments.add(id, pay(600));
      expect(
        () => payments.add(id, pay(401)),
        throwsA(
          isA<PaymentException>().having(
            (e) => e.reason,
            'reason',
            PaymentValidation.exceedsBalance,
          ),
        ),
      );
      final t = (await txns.get(id))!;
      expect(t.paidTotal, Money.fromRupees(600));
      expect((await payments.watch(id).first).length, 1);
    });

    test('zero amount is rejected', () async {
      final id = await newTxn();
      expect(() => payments.add(id, pay(0)), throwsA(isA<PaymentException>()));
    });

    test('editing a payment recalculates the balance', () async {
      final id = await newTxn();
      final pid = await payments.add(id, pay(500));
      await payments.edit(id, pay(800, id: pid));
      final t = (await txns.get(id))!;
      expect(t.paidTotal, Money.fromRupees(800));
      expect(t.balance, Money.fromRupees(200));
    });

    test('editing cannot push the total past what is owed', () async {
      final id = await newTxn();
      final pid = await payments.add(id, pay(500));
      await payments.add(id, pay(300));
      expect(
        () => payments.edit(id, pay(800, id: pid)),
        throwsA(isA<PaymentException>()),
      );
      expect((await txns.get(id))!.paidTotal, Money.fromRupees(800));
    });

    test('deleting a payment reopens a settled entry', () async {
      final id = await newTxn();
      final pid = await payments.add(id, pay(1000));
      await payments.delete(id, pid);
      final t = (await txns.get(id))!;
      expect(t.status, TransactionStatus.pending);
      expect(t.paidTotal, Money.zero);
      expect(t.settledAt, isNull);
    });

    test('status becomes overdue when due date has passed', () async {
      final id = await newTxn(due: DateTime(2026, 10, 1));
      await payments.add(id, pay(100));
      expect((await txns.get(id))!.status, TransactionStatus.overdue);
    });
  });

  group('last activity', () {
    test('is set when a transaction is created', () async {
      final id = await newTxn();
      expect((await txns.get(id))!.lastActivityAt, now);
    });

    test('is updated by every payment write', () async {
      final id = await newTxn();
      final later = now.add(const Duration(days: 3));
      final laterRepo = PaymentRepository(db, 'u1', now: () => later);
      final pid = await laterRepo.add(id, pay(100));
      expect((await txns.get(id))!.lastActivityAt, later);

      final latest = later.add(const Duration(days: 1));
      await PaymentRepository(
        db,
        'u1',
        now: () => latest,
      ).edit(id, pay(200, id: pid));
      expect((await txns.get(id))!.lastActivityAt, latest);
    });

    test('falls back to createdAt for older documents', () {
      final t = MoneyTransaction(
        type: TransactionType.lent,
        personId: 'p',
        personName: 'A',
        title: 't',
        totalAmount: Money.fromRupees(1),
        createdAt: now,
      );
      expect(t.lastActivity, now);
    });
  });

  group('entry details', () {
    test('date and notes round-trip; date falls back to createdAt', () async {
      final personId = await people.add(Person(name: 'Asha', createdAt: now));
      final id = await txns.add(
        MoneyTransaction(
          type: TransactionType.borrowed,
          personId: personId,
          personName: 'Asha',
          title: 'Rent help',
          totalAmount: Money.fromRupees(500),
          date: DateTime(2026, 9, 1),
          notes: 'pay by Diwali',
          createdAt: now,
        ),
      );
      final t = (await txns.get(id))!;
      expect(t.date, DateTime(2026, 9, 1));
      expect(t.notes, 'pay by Diwali');
      expect(t.entryDate, DateTime(2026, 9, 1));

      final bare = MoneyTransaction(
        type: TransactionType.lent,
        personId: 'p',
        personName: 'A',
        title: 't',
        totalAmount: Money.fromRupees(1),
        createdAt: now,
      );
      expect(bare.entryDate, now);
    });

    test('watchOne emits the transaction and null once deleted', () async {
      final id = await newTxn();
      expect((await txns.watchOne(id).first)!.title, 'Loan');
      await txns.delete(id);
      expect(await txns.watchOne(id).first, isNull);
    });

    test('update changes editable fields and recomputes status', () async {
      final id = await newTxn(due: DateTime(2026, 12, 1));
      await payments.add(id, pay(300));
      final t = (await txns.get(id))!;
      expect(t.status, TransactionStatus.partiallyPaid);

      // Move the due date into the past: now overdue; amounts untouched.
      await txns.update(
        id,
        title: 'Loan (renamed)',
        notes: 'chase',
        dueDate: DateTime(2026, 10, 1),
        date: DateTime(2026, 9, 15),
      );
      final u = (await txns.get(id))!;
      expect(u.title, 'Loan (renamed)');
      expect(u.notes, 'chase');
      expect(u.date, DateTime(2026, 9, 15));
      expect(u.status, TransactionStatus.overdue);
      expect(u.paidTotal, Money.fromRupees(300));
    });

    test('update can clear the due date', () async {
      final id = await newTxn(due: DateTime(2026, 10, 1));
      await txns.update(id, title: 'Loan', clearDueDate: true);
      final u = (await txns.get(id))!;
      expect(u.dueDate, isNull);
      expect(u.status, TransactionStatus.pending);
    });
  });

  group('people', () {
    test(
      'renaming a person updates personName on their transactions',
      () async {
        final id = await newTxn();
        final t = (await txns.get(id))!;
        final person = (await people.watch().first).single;
        expect(person.id, t.personId);
        await people.update(person.copyWith(name: 'Asha K'));
        expect((await txns.get(id))!.personName, 'Asha K');
      },
    );

    test('deleting a transaction removes its payments', () async {
      final id = await newTxn();
      await payments.add(id, pay(100));
      await txns.delete(id);
      expect(await txns.get(id), isNull);
      expect(await payments.watch(id).first, isEmpty);
    });
  });

  group('transaction queries', () {
    test('watch filters by status', () async {
      final a = await newTxn();
      await newTxn();
      await payments.add(a, pay(1000));
      final paid = await txns.watch(status: TransactionStatus.paid).first;
      expect(paid.map((t) => t.id), [a]);
    });
  });
}
