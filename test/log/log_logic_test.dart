import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/log_repository.dart';
import 'package:money_manager/core/models/log_entry.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/log/log_logic.dart';

LogEntry entry(
  String title,
  DateTime date, {
  LogKind kind = LogKind.expense,
  int? rupees,
  String? account,
  String? category,
  String? notes,
}) => LogEntry(
  title: title,
  date: date,
  kind: kind,
  amount: rupees == null ? null : Money.fromRupees(rupees),
  account: account,
  category: category,
  notes: notes,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  group('validateLog', () {
    test('needs a title', () {
      expect(
        validateLog(title: ' ', kind: LogKind.note, amountText: ''),
        isNotNull,
      );
    });
    test('expense and income need an amount, notes and tasks do not', () {
      expect(
        validateLog(title: 'x', kind: LogKind.expense, amountText: ''),
        isNotNull,
      );
      expect(
        validateLog(title: 'x', kind: LogKind.income, amountText: ''),
        isNotNull,
      );
      expect(
        validateLog(title: 'x', kind: LogKind.note, amountText: ''),
        isNull,
      );
      expect(
        validateLog(title: 'x', kind: LogKind.task, amountText: ''),
        isNull,
      );
    });
    test('rejects garbage and zero, accepts decimals', () {
      expect(
        validateLog(title: 'x', kind: LogKind.expense, amountText: 'abc'),
        isNotNull,
      );
      expect(
        validateLog(title: 'x', kind: LogKind.expense, amountText: '0'),
        isNotNull,
      );
      expect(
        validateLog(title: 'x', kind: LogKind.expense, amountText: '850.50'),
        isNull,
      );
    });
  });

  group('aggregation', () {
    final list = [
      entry(
        'Amazon',
        DateTime(2026, 10, 12, 18),
        rupees: 850,
        account: 'HDFC Credit Card',
        category: 'Shopping',
      ),
      entry(
        'Fuel',
        DateTime(2026, 10, 12),
        rupees: 500,
        account: 'hdfc credit card',
        category: 'Fuel',
      ),
      entry(
        'Salary',
        DateTime(2026, 10, 1),
        kind: LogKind.income,
        rupees: 50000,
      ),
      entry('Lunch', DateTime(2026, 10, 2), rupees: 200),
      entry('Call plumber', DateTime(2026, 10, 3), kind: LogKind.task),
    ];

    test('groups by day ignoring time', () {
      final g = groupByDay(list);
      expect(g[DateTime(2026, 10, 12)]!.length, 2);
      expect(g.length, 4);
    });

    test('totals count only expense and income', () {
      final t = totals(list);
      expect(t.spent, Money.fromRupees(1550));
      expect(t.income, Money.fromRupees(50000));
    });

    test('spent by account merges case and uses a fallback', () {
      final m = spentByAccount(list);
      expect(m['HDFC Credit Card'], Money.fromRupees(1350));
      expect(m['No account'], Money.fromRupees(200));
      expect(m.keys.first, 'HDFC Credit Card');
    });

    test('spent by category', () {
      final m = spentByCategory(list);
      expect(m['Shopping'], Money.fromRupees(850));
      expect(m['Uncategorised'], Money.fromRupees(200));
    });

    test('suggestions: most used first, case-insensitive merge', () {
      expect(suggestions(['Cash', 'UPI', 'cash', null, ' ', 'UPI', 'Cash']), [
        'Cash',
        'UPI',
      ]);
    });
  });

  group('LogFilter', () {
    final a = entry(
      'Amazon',
      DateTime(2026, 10, 12),
      rupees: 850,
      account: 'HDFC Credit Card',
      notes: 'headphones',
    );
    final b = entry(
      'Salary',
      DateTime(2026, 10, 1),
      kind: LogKind.income,
      rupees: 1,
    );

    test('inactive filter matches everything', () {
      expect(const LogFilter().isActive, isFalse);
      expect(const LogFilter().apply([a, b]), [a, b]);
    });
    test('by account, case-insensitive', () {
      expect(const LogFilter(account: 'hdfc credit card').apply([a, b]), [a]);
    });
    test('by kind and text search across fields', () {
      expect(const LogFilter(kind: LogKind.income).apply([a, b]), [b]);
      expect(const LogFilter(query: 'HEADPH').apply([a, b]), [a]);
    });
    test('date range is inclusive', () {
      final f = LogFilter(
        from: DateTime(2026, 10, 12),
        to: DateTime(2026, 10, 12),
      );
      expect(f.apply([a, b]), [a]);
    });
  });

  group('LogRepository', () {
    late FakeFirebaseFirestore db;
    late LogRepository repo;
    setUp(() {
      db = FakeFirebaseFirestore();
      repo = LogRepository(db, 'u1');
    });

    test('stored under the user and round-trips', () async {
      await repo.add(
        entry(
          'Amazon',
          DateTime(2026, 10, 12, 15),
          rupees: 850,
          account: 'HDFC',
        ),
      );
      expect((await db.collection('users/u1/logs').get()).docs.length, 1);
      expect((await db.collection('users/u2/logs').get()).docs, isEmpty);
      final e = (await repo.getAll()).single;
      expect(e.title, 'Amazon');
      expect(e.amount, Money.fromRupees(850));
      expect(e.account, 'HDFC');
      expect(e.date, DateTime(2026, 10, 12));
      expect(e.id, isNotEmpty);
    });

    test('watchMonth returns only that month', () async {
      await repo.add(entry('oct', DateTime(2026, 10, 31, 23), rupees: 1));
      await repo.add(entry('nov', DateTime(2026, 11, 1), rupees: 1));
      await repo.add(entry('sep', DateTime(2026, 9, 30), rupees: 1));
      final oct = await repo.watchMonth(DateTime(2026, 10, 15)).first;
      expect(oct.map((e) => e.title), ['oct']);
    });

    test('update, setDone and delete', () async {
      final id = await repo.add(
        entry('Call', DateTime(2026, 10, 3), kind: LogKind.task),
      );
      final e = (await repo.getAll()).single;
      await repo.update(
        LogEntry(
          id: id,
          date: e.date,
          title: 'Call plumber',
          kind: LogKind.task,
          createdAt: e.createdAt,
        ),
      );
      await repo.setDone(id, true);
      final after = (await repo.getAll()).single;
      expect(after.title, 'Call plumber');
      expect(after.done, isTrue);
      await repo.delete(id);
      expect(await repo.getAll(), isEmpty);
    });
  });
}
