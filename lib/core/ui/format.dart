import '../money/money.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

/// e.g. "9 Oct 2026".
String formatShortDate(DateTime d) =>
    '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Editable text for an amount field: "500" or "500.50", with no symbol or
/// grouping.
String plainAmount(Money m) {
  final rupees = m.paise ~/ 100;
  final paise = m.paise % 100;
  return paise == 0 ? '$rupees' : '$rupees.${paise.toString().padLeft(2, '0')}';
}
