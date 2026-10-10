import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/app_settings.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/ui/format.dart';

void main() {
  tearDown(() {
    MoneyFormat.reset();
    DateFormatHolder.style = DateStyle.dMonY;
  });

  group('Money.format follows the holders', () {
    test('defaults are rupees with Indian grouping', () {
      expect(Money.fromRupees(1234567).format(), '₹12,34,567');
    });

    test('dollars with western grouping', () {
      MoneyFormat.symbol = r'$';
      MoneyFormat.grouping = NumberGrouping.western;
      expect(const Money(123456750).format(), r'$1,234,567.50');
    });

    test('euro, pound and dirham', () {
      MoneyFormat.grouping = NumberGrouping.western;
      MoneyFormat.symbol = '€';
      expect(Money.fromRupees(1500).format(), '€1,500');
      MoneyFormat.symbol = '£';
      expect(Money.fromRupees(999).format(), '£999');
      MoneyFormat.symbol = 'AED ';
      expect(Money.fromRupees(100000).format(), 'AED 100,000');
    });

    test('Indian grouping can be kept for another currency', () {
      MoneyFormat.symbol = r'$';
      MoneyFormat.grouping = NumberGrouping.indian;
      expect(Money.fromRupees(100000).format(), r'$1,00,000');
    });

    test('negative amounts and paise', () {
      MoneyFormat.symbol = r'$';
      MoneyFormat.grouping = NumberGrouping.western;
      expect(const Money(-1234505).format(), r'-$12,345.05');
      expect(const Money(5).format(), r'$0.05');
    });

    test('explicit arguments still win', () {
      MoneyFormat.symbol = r'$';
      expect(
        Money.fromRupees(
          100000,
        ).format(symbol: '₹', grouping: NumberGrouping.indian),
        '₹1,00,000',
      );
    });

    test('typed amounts parse the same whatever the format', () {
      MoneyFormat.symbol = r'$';
      MoneyFormat.grouping = NumberGrouping.western;
      expect(Money.parse('1,234.50'), const Money(123450));
      expect(Money.parse('₹1,00,000'), Money.fromRupees(100000));
    });
  });

  group('formatShortDate', () {
    final d = DateTime(2026, 10, 9);
    final single = DateTime(2026, 1, 3);

    test('the three styles', () {
      expect(formatShortDate(d, style: DateStyle.dMonY), '9 Oct 2026');
      expect(formatShortDate(d, style: DateStyle.dmy), '09/10/2026');
      expect(formatShortDate(d, style: DateStyle.mdy), '10/09/2026');
    });

    test('numeric styles pad single digits', () {
      expect(formatShortDate(single, style: DateStyle.dmy), '03/01/2026');
      expect(formatShortDate(single, style: DateStyle.mdy), '01/03/2026');
    });

    test('the same date reads differently in dmy and mdy', () {
      expect(
        formatShortDate(d, style: DateStyle.dmy) ==
            formatShortDate(d, style: DateStyle.mdy),
        isFalse,
      );
    });

    test('follows the holder when no style is passed', () {
      expect(formatShortDate(d), '9 Oct 2026');
      DateFormatHolder.style = DateStyle.mdy;
      expect(formatShortDate(d), '10/09/2026');
    });
  });
}
