import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/payment.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';
import 'package:money_manager/people/ledger.dart';
import 'package:money_manager/people/person_summary.dart';

void main() {
  final now = DateTime(2026, 10, 9);

  MoneyTransaction txn(
    String id,
    TransactionType type,
    int rupees, {
    DateTime? date,
    String title = 'Loan',
    InterestType interest = InterestType.none,
    double? rate,
    Money? total,
    TransactionStatus status = TransactionStatus.pending,
    DateTime? settledAt,
    Money? paid,
  }) => MoneyTransaction(
    id: id,
    type: type,
    personId: 'p',
    personName: 'Asha',
    title: title,
    totalAmount: total ?? Money.fromRupees(rupees),
    paidTotal: paid ?? Money.zero,
    status: status,
    interestType: interest,
    interestRate: rate,
    createdAt: date ?? DateTime(2026, 9, 1),
    date: date ?? DateTime(2026, 9, 1),
    settledAt: settledAt,
  );

  Payment pay(int rupees, DateTime date, {DateTime? created, String id = ''}) =>
      Payment(
        id: id,
        amount: Money.fromRupees(rupees),
        date: date,
        createdAt: created,
      );

  List<int> balances(List<LedgerEvent> e) =>
      e.map((x) => x.balanceAfter.paise ~/ 100).toList();

  test('no transactions gives an empty ledger', () {
    expect(buildLedger([], now: now), isEmpty);
  });

  test('lent entry then received payment: running balance falls', () {
    final events = buildLedger([
      TransactionWithPayments(txn('a', TransactionType.lent, 1000), [
        pay(500, DateTime(2026, 9, 10)),
      ]),
    ], now: now);
    expect(events.map((e) => e.kind), [LedgerKind.entry, LedgerKind.payment]);
    expect(events.map((e) => e.delta.paise ~/ 100), [1000, -500]);
    expect(balances(events), [1000, 500]);
    expect(events[0].label, 'Gave ₹1,000');
    expect(events[1].label, 'Received ₹500');
  });

  test(
    'borrowed entry then payment: balance is negative and returns to zero',
    () {
      final events = buildLedger([
        TransactionWithPayments(txn('b', TransactionType.borrowed, 200), [
          pay(200, DateTime(2026, 9, 5)),
        ]),
      ], now: now);
      expect(events.map((e) => e.delta.paise ~/ 100), [-200, 200]);
      expect(balances(events), [-200, 0]);
      expect(events[0].label, 'Borrowed ₹200');
      expect(events[1].label, 'Paid ₹200');
    },
  );

  test('several entries interleave by date with one running balance', () {
    final events = buildLedger([
      TransactionWithPayments(
        txn('a', TransactionType.lent, 1000, date: DateTime(2026, 9, 1)),
        [pay(500, DateTime(2026, 9, 10))],
      ),
      TransactionWithPayments(
        txn('b', TransactionType.borrowed, 200, date: DateTime(2026, 9, 5)),
        const [],
      ),
    ], now: now);
    expect(events.map((e) => e.transactionId), ['a', 'b', 'a']);
    expect(balances(events), [1000, 800, 300]);
  });

  test('same day: entry first, then its payments in the order recorded', () {
    final day = DateTime(2026, 9, 1);
    final events = buildLedger([
      TransactionWithPayments(
        txn(
          'a',
          TransactionType.lent,
          1000,
          date: day.add(const Duration(hours: 20)),
        ),
        [
          pay(
            100,
            day.add(const Duration(hours: 9)),
            created: DateTime(2026, 9, 1, 9),
            id: 'p1',
          ),
          pay(
            200,
            day.add(const Duration(hours: 9)),
            created: DateTime(2026, 9, 1, 12),
            id: 'p2',
          ),
        ],
      ),
    ], now: now);
    expect(events.map((e) => e.kind), [
      LedgerKind.entry,
      LedgerKind.payment,
      LedgerKind.payment,
    ]);
    expect(events.map((e) => e.delta.paise ~/ 100), [1000, -100, -200]);
  });

  test('each row says whether money came in or went out', () {
    final events = buildLedger([
      TransactionWithPayments(txn('a', TransactionType.lent, 1000), [
        pay(500, DateTime(2026, 9, 10)),
      ]),
      TransactionWithPayments(
        txn('b', TransactionType.borrowed, 200, date: DateTime(2026, 9, 5)),
        [pay(50, DateTime(2026, 9, 12))],
      ),
    ], now: now);
    // gave 1000 (out), borrowed 200 (in), received 500 (in), paid 50 (out)
    expect(events.map((e) => e.flow), [
      LedgerFlow.moneyOut,
      LedgerFlow.moneyIn,
      LedgerFlow.moneyIn,
      LedgerFlow.moneyOut,
    ]);
  });

  test('interest is not a cash movement', () {
    final loan = txn(
      'l',
      TransactionType.borrowed,
      10000,
      date: DateTime(2025, 10, 9),
      interest: InterestType.simple,
      rate: 12,
    );
    final events = buildLedger([
      TransactionWithPayments(loan, const []),
    ], now: now);
    expect(events.last.flow, LedgerFlow.none);
  });

  group('interest', () {
    test('an open loan with interest ends at principal plus interest', () {
      final loan = txn(
        'l',
        TransactionType.borrowed,
        10000,
        date: DateTime(2025, 10, 9),
        interest: InterestType.simple,
        rate: 12,
      );
      final events = buildLedger([
        TransactionWithPayments(loan, const []),
      ], now: now);
      expect(events.map((e) => e.kind), [
        LedgerKind.entry,
        LedgerKind.interest,
      ]);
      expect(events.last.delta, Money.fromRupees(-1200));
      expect(events.last.date, now);
      expect(events.last.balanceAfter, Money.fromRupees(-11200));
    });

    test('a settled loan: interest is frozen at the settled date and the '
        'ledger ends at zero', () {
      final settled = DateTime(2026, 4, 9); // 182 days in: interest 598.36
      final loan = txn(
        'l',
        TransactionType.borrowed,
        10000,
        date: DateTime(2025, 10, 9),
        interest: InterestType.simple,
        rate: 12,
        status: TransactionStatus.paid,
        settledAt: settled,
        paid: const Money(1059836),
      );
      final events = buildLedger([
        TransactionWithPayments(loan, [
          Payment(amount: const Money(1059836), date: settled),
        ]),
      ], now: DateTime(2030, 1, 1));
      expect(events.map((e) => e.kind), [
        LedgerKind.entry,
        LedgerKind.interest,
        LedgerKind.payment,
      ]);
      expect(events[1].date, settled);
      expect(events[1].delta, const Money(-59836));
      expect(events.last.balanceAfter, Money.zero);
    });

    test('no interest row when there is none to show', () {
      final events = buildLedger([
        TransactionWithPayments(txn('a', TransactionType.lent, 100), const []),
      ], now: now);
      expect(events.map((e) => e.kind), [LedgerKind.entry]);
    });
  });

  test('the last running balance equals the net used by the People list', () {
    final asha = Person(id: 'p', name: 'Asha', createdAt: DateTime(2026, 1, 1));
    final loan = txn(
      'l',
      TransactionType.borrowed,
      10000,
      date: DateTime(2025, 10, 9),
      interest: InterestType.compound,
      rate: 12,
      paid: Money.fromRupees(3000),
    );
    final lent = txn('a', TransactionType.lent, 5000);
    final withPayments = [
      TransactionWithPayments(loan, [pay(3000, DateTime(2026, 2, 1))]),
      TransactionWithPayments(lent, [pay(1000, DateTime(2026, 9, 20))]),
    ];
    // Mirror the paid totals the repositories would have written.
    final lentPaid = txn(
      'a',
      TransactionType.lent,
      5000,
      paid: Money.fromRupees(1000),
    );
    final net = summarize([asha], [loan, lentPaid], now: now).single.net;
    final events = buildLedger([
      withPayments[0],
      TransactionWithPayments(lentPaid, withPayments[1].payments),
    ], now: now);
    expect(events.last.balanceAfter, net);
  });
}
