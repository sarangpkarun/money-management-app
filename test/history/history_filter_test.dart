import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/money_transaction.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/status/transaction_status.dart';
import 'package:money_manager/history/history_filter.dart';

void main() {
  MoneyTransaction txn(
    String id, {
    TransactionType type = TransactionType.lent,
    String person = 'p1',
    String name = 'Asha',
    String title = 'Loan',
    int paid = 1000,
    TransactionStatus status = TransactionStatus.paid,
    DateTime? settled,
  }) => MoneyTransaction(
    id: id,
    type: type,
    personId: person,
    personName: name,
    title: title,
    totalAmount: Money.fromRupees(paid),
    paidTotal: Money.fromRupees(paid),
    status: status,
    createdAt: DateTime(2026, 1, 1),
    settledAt: status == TransactionStatus.paid
        ? (settled ?? DateTime(2026, 6, 1))
        : null,
  );

  List<String> ids(List<MoneyTransaction> l) => l.map((t) => t.id).toList();

  test('only settled (Paid) entries are in History', () {
    final all = [
      txn('paid'),
      txn('pending', status: TransactionStatus.pending),
      txn('partial', status: TransactionStatus.partiallyPaid),
      txn('overdue', status: TransactionStatus.overdue),
    ];
    expect(ids(applyHistoryFilter(all, const HistoryFilter())), ['paid']);
  });

  test('sorted by settled date, newest first', () {
    final all = [
      txn('a', settled: DateTime(2026, 3, 1)),
      txn('b', settled: DateTime(2026, 9, 1)),
      txn('c', settled: DateTime(2026, 6, 1)),
    ];
    expect(ids(applyHistoryFilter(all, const HistoryFilter())), [
      'b',
      'c',
      'a',
    ]);
  });

  test('filters by type', () {
    final all = [txn('lent'), txn('borrowed', type: TransactionType.borrowed)];
    expect(
      ids(
        applyHistoryFilter(
          all,
          const HistoryFilter(types: {TransactionType.borrowed}),
        ),
      ),
      ['borrowed'],
    );
    expect(
      ids(
        applyHistoryFilter(
          all,
          const HistoryFilter(
            types: {TransactionType.lent, TransactionType.borrowed},
          ),
        ),
      ).length,
      2,
    );
  });

  test('filters by person', () {
    final all = [txn('a', person: 'p1'), txn('b', person: 'p2')];
    expect(ids(applyHistoryFilter(all, const HistoryFilter(personId: 'p2'))), [
      'b',
    ]);
  });

  group('settled date range', () {
    final all = [
      txn('jan', settled: DateTime(2026, 1, 15, 23, 59)),
      txn('feb', settled: DateTime(2026, 2, 10)),
      txn('mar', settled: DateTime(2026, 3, 5, 8)),
    ];

    test('is inclusive of both days, whatever the time of day', () {
      final f = HistoryFilter(
        from: DateTime(2026, 1, 15),
        to: DateTime(2026, 3, 5),
      );
      expect(ids(applyHistoryFilter(all, f)), ['mar', 'feb', 'jan']);
    });

    test('from only, and to only', () {
      expect(
        ids(applyHistoryFilter(all, HistoryFilter(from: DateTime(2026, 2, 1)))),
        ['mar', 'feb'],
      );
      expect(
        ids(applyHistoryFilter(all, HistoryFilter(to: DateTime(2026, 2, 1)))),
        ['jan'],
      );
    });
  });

  test('filters by paid amount, inclusive', () {
    final all = [txn('s', paid: 100), txn('m', paid: 500), txn('l', paid: 900)];
    expect(
      ids(
        applyHistoryFilter(
          all,
          HistoryFilter(
            minAmount: Money.fromRupees(500),
            maxAmount: Money.fromRupees(900),
          ),
        ),
      ).toSet(),
      {'m', 'l'},
    );
    expect(
      ids(
        applyHistoryFilter(
          all,
          HistoryFilter(maxAmount: Money.fromRupees(100)),
        ),
      ),
      ['s'],
    );
  });

  test('search matches person name or title, case-insensitively', () {
    final all = [
      txn('a', name: 'Asha', title: 'Phone EMI'),
      txn('b', name: 'Ravi', title: 'Rent help'),
    ];
    expect(ids(applyHistoryFilter(all, const HistoryFilter(query: 'RAV'))), [
      'b',
    ]);
    expect(ids(applyHistoryFilter(all, const HistoryFilter(query: 'phone'))), [
      'a',
    ]);
    expect(applyHistoryFilter(all, const HistoryFilter(query: 'zzz')), isEmpty);
    expect(
      ids(applyHistoryFilter(all, const HistoryFilter(query: '  '))).length,
      2,
    );
  });

  test('filters combine', () {
    final all = [
      txn('a', type: TransactionType.borrowed, name: 'Asha', paid: 500),
      txn('b', type: TransactionType.lent, name: 'Asha', paid: 500),
      txn('c', type: TransactionType.borrowed, name: 'Ravi', paid: 500),
    ];
    final f = HistoryFilter(
      types: const {TransactionType.borrowed},
      query: 'asha',
      minAmount: Money.fromRupees(100),
    );
    expect(ids(applyHistoryFilter(all, f)), ['a']);
  });

  test('isActive and cleared', () {
    expect(const HistoryFilter().isActive, isFalse);
    final f = HistoryFilter(personId: 'p', query: 'x');
    expect(f.isActive, isTrue);
    expect(f.cleared().isActive, isFalse);
  });
}
