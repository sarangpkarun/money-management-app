import '../core/models/reminder.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String weekdayShort(int weekday) => _days[weekday - 1];

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A short description of how a reminder repeats.
String repeatSummary(RepeatRule rule, DateTime at) => switch (rule.kind) {
  RepeatKind.none => 'Once',
  RepeatKind.daily => 'Every day',
  RepeatKind.weekly =>
    'Every ${(rule.weekdays.toList()..sort()).map(weekdayShort).join(', ')}',
  RepeatKind.monthly => 'Monthly on the ${_ordinal(at.day)}',
  RepeatKind.yearly => 'Every year on ${at.day} ${_months[at.month - 1]}',
  RepeatKind.everyNDays =>
    rule.interval == 1 ? 'Every day' : 'Every ${rule.interval} days',
};

/// The first problem with a reminder form, or null when it can be saved. A
/// one-off must be in the future when it is created; editing an old one is fine.
String? validateReminder({
  required String title,
  required DateTime at,
  required RepeatRule repeat,
  required int snoozeMinutes,
  required DateTime now,
  required bool isNew,
}) {
  if (title.trim().isEmpty) return 'Enter a title';
  if (isNew && !repeat.repeats && !at.isAfter(now)) {
    return 'Pick a time in the future';
  }
  if (repeat.kind == RepeatKind.weekly && repeat.weekdays.isEmpty) {
    return 'Pick at least one weekday';
  }
  if (repeat.kind == RepeatKind.everyNDays &&
      (repeat.interval < 1 || repeat.interval > 365)) {
    return 'Days must be between 1 and 365';
  }
  if (!snoozeChoices.contains(snoozeMinutes)) {
    return 'Snooze must be 5, 10 or 15 minutes';
  }
  return null;
}

/// 9:30 am style time of day.
String formatTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'am' : 'pm'}';
}

/// "7 Jan 2030, 9:30 am".
String formatRing(DateTime d) =>
    '${d.day} ${_months[d.month - 1]} ${d.year}, ${formatTime(d)}';
