const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

/// e.g. "9 Oct 2026".
String formatShortDate(DateTime d) =>
    '${d.day} ${_months[d.month - 1]} ${d.year}';
