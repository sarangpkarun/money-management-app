import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';
import 'package:money_manager/people/person_summary.dart';

void main() {
  final now = DateTime(2026, 10, 9);
  Person person(String id, String name, {String? phone}) =>
      Person(id: id, name: name, phone: phone, createdAt: DateTime(2026, 1, 1));

  MoneyTransaction txn(
    String personId,
    TransactionType type,
    int total, {
    int paid = 0,
    DateTime? due,
    DateTime? activity,
  }) {
    final paidMoney = Money.fromRupees(paid);
    final totalMoney = Money.fromRupees(total);
    return MoneyTransaction(
      type: type,
      personId: personId,
      personName: '',
      title: 't',
      totalAmount: totalMoney,
      paidTotal: paidMoney,
      status: computeStatus(
        total: totalMoney,
        paid: paidMoney,
        dueDate: due,
        now: now,
      ),
      dueDate: due,
      createdAt: DateTime(2026, 2, 1),
      lastActivityAt: activity,
    );
  }

  final asha = person('a', 'Asha', phone: '98450');
  final ravi = person('r', 'ravi', phone: '77001');
  final meera = person('m', 'Meera');

  group('summarize', () {
    test('net is receivables minus payables, using remaining balances', () {
      final s = summarize(
        [asha],
        [
          txn('a', TransactionType.lent, 1000, paid: 400), // +600
          txn('a', TransactionType.borrowed, 200), // -200
          txn('a', TransactionType.emi, 100, paid: 100), // settled, 0
        ],
        now: now,
      ).single;
      expect(s.net, Money.fromRupees(400));
    });

    test('ignores other people’s transactions', () {
      final s = summarize(
        [asha, ravi],
        [txn('r', TransactionType.lent, 500)],
        now: now,
      );
      expect(s.firstWhere((x) => x.person.id == 'a').net, Money.zero);
      expect(
        s.firstWhere((x) => x.person.id == 'r').net,
        Money.fromRupees(500),
      );
    });

    test('hasOverdue is computed from the due date, not a stale status', () {
      final stale = MoneyTransaction(
        type: TransactionType.lent,
        personId: 'a',
        personName: 'Asha',
        title: 't',
        totalAmount: Money.fromRupees(100),
        status: TransactionStatus.pending, // stored value is out of date
        dueDate: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 9, 1),
      );
      expect(summarize([asha], [stale], now: now).single.hasOverdue, isTrue);
    });

    test('paid-off entries are never overdue', () {
      final s = summarize(
        [asha],
        [
          txn(
            'a',
            TransactionType.lent,
            100,
            paid: 100,
            due: DateTime(2026, 1, 1),
          ),
        ],
        now: now,
      ).single;
      expect(s.hasOverdue, isFalse);
    });

    test(
      'lastActivity is the latest transaction activity, else person created',
      () {
        final s = summarize(
          [asha, meera],
          [
            txn('a', TransactionType.lent, 100, activity: DateTime(2026, 5, 1)),
            txn('a', TransactionType.lent, 100, activity: DateTime(2026, 8, 1)),
          ],
          now: now,
        );
        expect(
          s.firstWhere((x) => x.person.id == 'a').lastActivity,
          DateTime(2026, 8, 1),
        );
        expect(
          s.firstWhere((x) => x.person.id == 'm').lastActivity,
          meera.createdAt,
        );
      },
    );
  });

  group('applyFilters', () {
    final summaries = summarize(
      [asha, ravi, meera],
      [
        txn('a', TransactionType.lent, 1000), // asha: they owe me
        txn(
          'r',
          TransactionType.borrowed,
          300,
          due: DateTime(2026, 10, 1),
        ), // ravi: I owe, overdue
      ],
      now: now,
    );

    List<String> names(List<PersonSummary> l) =>
        l.map((s) => s.person.name).toList();

    test('filters', () {
      expect(
        names(applyFilters(summaries, filter: PeopleFilter.all)).length,
        3,
      );
      expect(names(applyFilters(summaries, filter: PeopleFilter.theyOwe)), [
        'Asha',
      ]);
      expect(names(applyFilters(summaries, filter: PeopleFilter.iOwe)), [
        'ravi',
      ]);
      expect(names(applyFilters(summaries, filter: PeopleFilter.settled)), [
        'Meera',
      ]);
      expect(names(applyFilters(summaries, filter: PeopleFilter.hasOverdue)), [
        'ravi',
      ]);
    });

    test('search matches name or phone, case-insensitively', () {
      expect(names(applyFilters(summaries, query: 'RAV')), ['ravi']);
      expect(names(applyFilters(summaries, query: '9845')), ['Asha']);
      expect(applyFilters(summaries, query: 'zzz'), isEmpty);
    });

    test('sort by name ignores case', () {
      expect(names(applyFilters(summaries, sort: PeopleSort.name)), [
        'Asha',
        'Meera',
        'ravi',
      ]);
    });

    test('sort by highest amount uses the absolute net', () {
      expect(names(applyFilters(summaries, sort: PeopleSort.highestAmount)), [
        'Asha',
        'ravi',
        'Meera',
      ]);
    });

    test('sort by latest activity puts the most recent first', () {
      final s = summarize(
        [asha, ravi],
        [
          txn('a', TransactionType.lent, 1, activity: DateTime(2026, 3, 1)),
          txn('r', TransactionType.lent, 1, activity: DateTime(2026, 9, 1)),
        ],
        now: now,
      );
      expect(names(applyFilters(s, sort: PeopleSort.latestActivity)), [
        'ravi',
        'Asha',
      ]);
    });
  });
}
