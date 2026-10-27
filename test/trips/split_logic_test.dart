import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/trip_expense.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/trips/split_logic.dart';

TripExpense expense(String paidBy, int paise, Map<String, int> shares) =>
    TripExpense(
      title: 'x',
      amount: Money(paise),
      paidBy: paidBy,
      date: DateTime(2026, 10, 1),
      shares: shares,
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  group('equalSplit', () {
    test('divides exactly', () {
      expect(equalSplit(9000, ['a', 'b', 'c']), {
        'a': 3000,
        'b': 3000,
        'c': 3000,
      });
    });

    test('gives leftover paise to the first people and keeps the total', () {
      final s = equalSplit(1000, ['a', 'b', 'c']);
      expect(s, {'a': 334, 'b': 333, 'c': 333});
      expect(s.values.reduce((a, b) => a + b), 1000);
    });

    test(
      'nobody selected gives nothing',
      () => expect(equalSplit(100, []), isEmpty),
    );
  });

  group('percentSplit', () {
    test('splits by percent', () {
      expect(percentSplit(20000, {'a': 5000, 'b': 2500, 'c': 2500}), {
        'a': 10000,
        'b': 5000,
        'c': 5000,
      });
    });

    test('rounding leftovers still add up to the total', () {
      final s = percentSplit(100, {'a': 3333, 'b': 3333, 'c': 3334})!;
      expect(s.values.reduce((a, b) => a + b), 100);
    });

    test('rejects percentages that do not total 100', () {
      expect(percentSplit(1000, {'a': 5000, 'b': 4000}), isNull);
    });
  });

  test('exactSplitValid needs shares that add up to the total', () {
    expect(exactSplitValid(1000, {'a': 400, 'b': 600}), isTrue);
    expect(exactSplitValid(1000, {'a': 400, 'b': 500}), isFalse);
    expect(exactSplitValid(1000, {}), isFalse);
  });

  group('balances and settleUp', () {
    test('payer is owed what others share', () {
      final net = balances([
        expense('a', 9000, {'a': 3000, 'b': 3000, 'c': 3000}),
      ]);
      expect(net, {'a': 6000, 'b': -3000, 'c': -3000});
    });

    test('settles with the fewest payments', () {
      final net = balances([
        expense('a', 9000, {'a': 3000, 'b': 3000, 'c': 3000}),
        expense('b', 3000, {'a': 1000, 'b': 1000, 'c': 1000}),
      ]);
      // a: +6000-1000 = 5000, b: -3000+2000 = -1000... c: -4000
      final transfers = settleUp(net);
      final byPerson = <String, int>{};
      for (final t in transfers) {
        byPerson[t.from] = (byPerson[t.from] ?? 0) + t.paise;
        byPerson[t.to] = (byPerson[t.to] ?? 0) - t.paise;
      }
      // Applying the payments cancels every balance.
      for (final e in net.entries) {
        expect(e.value + (byPerson[e.key] ?? 0), 0);
      }
      expect(transfers.length, lessThanOrEqualTo(2));
    });

    test('nothing to settle when everyone is even', () {
      expect(settleUp({'a': 0, 'b': 0}), isEmpty);
    });
  });
}
