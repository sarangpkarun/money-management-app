enum NumberGrouping { indian, western }

/// An amount of money stored as an integer number of paise, so arithmetic is
/// exact and never touches floating point.
class Money implements Comparable<Money> {
  const Money(this.paise);

  factory Money.fromRupees(int rupees) => Money(rupees * 100);

  static const zero = Money(0);

  final int paise;

  /// Parses user input such as `1000`, `5331.45` or `₹1,00,000.00`.
  /// Returns null when the text is not a valid amount (more than two
  /// decimals, letters, empty).
  static Money? parse(String input) {
    final text = input.replaceAll(RegExp(r'[₹,\s]'), '');
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
    if (match == null) return null;
    final rupees = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return Money(rupees * 100 + int.parse(fraction.isEmpty ? '0' : fraction));
  }

  bool get isZero => paise == 0;
  bool get isNegative => paise < 0;

  Money operator +(Money other) => Money(paise + other.paise);
  Money operator -(Money other) => Money(paise - other.paise);
  bool operator >(Money other) => paise > other.paise;
  bool operator <(Money other) => paise < other.paise;
  bool operator >=(Money other) => paise >= other.paise;
  bool operator <=(Money other) => paise <= other.paise;

  @override
  int compareTo(Money other) => paise.compareTo(other.paise);

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;

  @override
  int get hashCode => paise.hashCode;

  @override
  String toString() => 'Money($paise paise)';

  /// Formats as e.g. `₹1,00,000` (Indian) or `₹100,000` (western). Paise are
  /// shown only when non-zero.
  String format({
    String symbol = '₹',
    NumberGrouping grouping = NumberGrouping.indian,
  }) {
    final abs = paise.abs();
    final rupees = _group((abs ~/ 100).toString(), grouping);
    final rem = abs % 100;
    final fraction = rem == 0 ? '' : '.${rem.toString().padLeft(2, '0')}';
    return '${isNegative ? '-' : ''}$symbol$rupees$fraction';
  }

  static String _group(String digits, NumberGrouping grouping) {
    if (digits.length <= 3) return digits;
    final head = digits.substring(0, digits.length - 3);
    final tail = digits.substring(digits.length - 3);
    final size = grouping == NumberGrouping.indian ? 2 : 3;
    final parts = <String>[];
    for (var end = head.length; end > 0; end -= size) {
      parts.insert(0, head.substring(end - size < 0 ? 0 : end - size, end));
    }
    return '${parts.join(',')},$tail';
  }
}
