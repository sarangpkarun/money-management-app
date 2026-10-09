/// Number of days in [month] (1-12) of [year], including leap years.
int daysInMonth(int year, int month) {
  if (month == 2) {
    final leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    return leap ? 29 : 28;
  }
  const thirtyDays = {4, 6, 9, 11};
  return thirtyDays.contains(month) ? 30 : 31;
}

/// [start] plus [months] calendar months, as a date (time of day dropped).
///
/// When the target month is too short for the start day, the last day of that
/// month is used (31 Jan + 1 month = 28 Feb, or 29 Feb in a leap year). Always
/// measure from the original [start], never from the previous result, so the
/// day recovers afterwards: 31 Jan, 28 Feb, 31 Mar, 30 Apr, 31 May...
DateTime addMonthsClamped(DateTime start, int months) {
  final index = start.year * 12 + (start.month - 1) + months;
  final year = index ~/ 12;
  final month = index % 12 + 1;
  final day = start.day < daysInMonth(year, month)
      ? start.day
      : daysInMonth(year, month);
  return DateTime(year, month, day);
}
