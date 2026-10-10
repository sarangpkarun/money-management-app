import '../models/app_settings.dart';

/// Moves [at] to the end of the quiet window if it falls inside it, otherwise
/// leaves it alone. The window starts at [QuietHours.startMinutes] (inclusive)
/// and ends at [QuietHours.endMinutes] (exclusive), and may cross midnight
/// (22:00 to 07:00). Nothing moves earlier. Off, or a window with the same start
/// and end, changes nothing.
DateTime applyQuietHours(DateTime at, QuietHours quiet) {
  if (!quiet.enabled || quiet.startMinutes == quiet.endMinutes) return at;
  final minute = at.hour * 60 + at.minute;
  final start = quiet.startMinutes;
  final end = quiet.endMinutes;
  final crossesMidnight = start > end;
  final inside = crossesMidnight
      ? (minute >= start || minute < end)
      : (minute >= start && minute < end);
  if (!inside) return at;
  // After midnight in a window that crosses it, the end is later the same day;
  // before midnight it is the next morning.
  final nextDay = crossesMidnight && minute >= start;
  return DateTime(
    at.year,
    at.month,
    at.day + (nextDay ? 1 : 0),
    end ~/ 60,
    end % 60,
  );
}
