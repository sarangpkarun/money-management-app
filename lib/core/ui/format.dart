import '../models/app_settings.dart';
import '../money/money.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

/// The date style [formatShortDate] uses. The app sets it from the settings.
class DateFormatHolder {
  const DateFormatHolder._();

  static DateStyle style = DateStyle.dMonY;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// A date in the user's chosen style: "9 Oct 2026", "09/10/2026" or
/// "10/09/2026".
String formatShortDate(DateTime d, {DateStyle? style}) =>
    switch (style ?? DateFormatHolder.style) {
      DateStyle.dMonY => '${d.day} ${_months[d.month - 1]} ${d.year}',
      DateStyle.dmy => '${_two(d.day)}/${_two(d.month)}/${d.year}',
      DateStyle.mdy => '${_two(d.month)}/${_two(d.day)}/${d.year}',
    };

/// Editable text for an amount field: "500" or "500.50", with no symbol or
/// grouping.
String plainAmount(Money m) {
  final rupees = m.paise ~/ 100;
  final paise = m.paise % 100;
  return paise == 0 ? '$rupees' : '$rupees.${paise.toString().padLeft(2, '0')}';
}
