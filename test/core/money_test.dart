import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/money/money.dart';

void main() {
  group('construction and arithmetic', () {
    test('fromRupees converts to paise', () {
      expect(Money.fromRupees(1000).paise, 100000);
    });

    test('add, subtract and compare', () {
      const a = Money(100000);
      const b = Money(50000);
      expect((a + b).paise, 150000);
      expect((a - b).paise, 50000);
      expect(a > b, isTrue);
      expect(b < a, isTrue);
      expect(a == const Money(100000), isTrue);
    });

    test('isZero and isNegative', () {
      expect(Money.zero.isZero, isTrue);
      expect(const Money(-1).isNegative, isTrue);
    });
  });

  group('parse', () {
    test('whole rupees', () => expect(Money.parse('1000')!.paise, 100000));
    test(
      'rupees and paise',
      () => expect(Money.parse('5331.45')!.paise, 533145),
    );
    test(
      'single decimal digit',
      () => expect(Money.parse('10.5')!.paise, 1050),
    );
    test(
      'strips symbol, commas and spaces',
      () => expect(Money.parse(' ₹1,00,000.00 ')!.paise, 10000000),
    );
    test(
      'rejects more than two decimals',
      () => expect(Money.parse('1.234'), isNull),
    );
    test('rejects garbage and empty', () {
      expect(Money.parse('abc'), isNull);
      expect(Money.parse(''), isNull);
      expect(Money.parse('1.2.3'), isNull);
    });
  });

  group('format', () {
    test('Indian grouping', () {
      expect(const Money(10000000).format(), '₹1,00,000');
      expect(Money.fromRupees(1234567).format(), '₹12,34,567');
      expect(Money.fromRupees(999).format(), '₹999');
    });

    test('western grouping', () {
      expect(
        Money.fromRupees(100000).format(grouping: NumberGrouping.western),
        '₹100,000',
      );
    });

    test('shows paise only when non-zero', () {
      expect(const Money(533145).format(), '₹5,331.45');
      expect(const Money(533150).format(), '₹5,331.50');
    });

    test('negative amounts and custom symbol', () {
      expect(const Money(-50000).format(), '-₹500');
      expect(Money.fromRupees(500).format(symbol: '\$'), '\$500');
    });

    test('zero', () => expect(Money.zero.format(), '₹0'));
  });
}
