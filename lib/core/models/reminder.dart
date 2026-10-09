import 'package:cloud_firestore/cloud_firestore.dart';

enum RepeatKind { none, daily, weekly, monthly, yearly, everyNDays }

/// How a reminder repeats. Weekly uses [weekdays] (1 = Monday ... 7 = Sunday),
/// every-N-days uses [interval].
class RepeatRule {
  const RepeatRule._(this.kind, this.weekdays, this.interval);

  const RepeatRule.none() : this._(RepeatKind.none, const {}, 1);
  const RepeatRule.daily() : this._(RepeatKind.daily, const {}, 1);
  const RepeatRule.monthly() : this._(RepeatKind.monthly, const {}, 1);
  const RepeatRule.yearly() : this._(RepeatKind.yearly, const {}, 1);
  const RepeatRule.weekly(Set<int> weekdays)
    : this._(RepeatKind.weekly, weekdays, 1);
  const RepeatRule.everyNDays(int days)
    : this._(RepeatKind.everyNDays, const {}, days);

  final RepeatKind kind;
  final Set<int> weekdays;
  final int interval;

  bool get repeats => kind != RepeatKind.none;

  Map<String, dynamic> toMap() => {
    'kind': kind.name,
    if (kind == RepeatKind.weekly) 'weekdays': (weekdays.toList()..sort()),
    if (kind == RepeatKind.everyNDays) 'interval': interval,
  };

  /// Unknown or damaged data reads as "does not repeat".
  factory RepeatRule.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const RepeatRule.none();
    switch (m['kind']) {
      case 'daily':
        return const RepeatRule.daily();
      case 'monthly':
        return const RepeatRule.monthly();
      case 'yearly':
        return const RepeatRule.yearly();
      case 'weekly':
        return RepeatRule.weekly({
          for (final d in (m['weekdays'] as List? ?? const []))
            if (d is int && d >= 1 && d <= 7) d,
        });
      case 'everyNDays':
        final n = m['interval'];
        return RepeatRule.everyNDays(n is int && n >= 1 ? n : 1);
      default:
        return const RepeatRule.none();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RepeatRule &&
      other.kind == kind &&
      other.interval == interval &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays);

  @override
  int get hashCode => Object.hash(kind, interval, weekdays.length);
}

/// The sound a reminder rings with. Applied by the alarm service.
enum ReminderTone { alarm, notification, ringtone }

enum ReminderVibration { off, short, long }

enum ReminderVolume { low, medium, high }

const snoozeChoices = [5, 10, 15];

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

class Reminder {
  const Reminder({
    this.id = '',
    required this.title,
    this.notes,
    required this.at,
    this.repeat = const RepeatRule.none(),
    this.snoozeMinutes = 10,
    this.tone = ReminderTone.alarm,
    this.vibration = ReminderVibration.long,
    this.volume = ReminderVolume.high,
    this.transactionId,
    this.done = false,
    this.doneAt,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String? notes;

  /// The first ring, as local wall-clock time. Repeats keep its time of day.
  final DateTime at;
  final RepeatRule repeat;
  final int snoozeMinutes;
  final ReminderTone tone;
  final ReminderVibration vibration;
  final ReminderVolume volume;

  /// The entry this reminder is about, if any.
  final String? transactionId;
  final bool done;
  final DateTime? doneAt;
  final DateTime createdAt;

  Reminder copyWith({
    String? title,
    String? notes,
    DateTime? at,
    RepeatRule? repeat,
    int? snoozeMinutes,
    ReminderTone? tone,
    ReminderVibration? vibration,
    ReminderVolume? volume,
    String? transactionId,
    bool clearTransaction = false,
    bool? done,
    DateTime? doneAt,
    bool clearDoneAt = false,
  }) => Reminder(
    id: id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    at: at ?? this.at,
    repeat: repeat ?? this.repeat,
    snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
    tone: tone ?? this.tone,
    vibration: vibration ?? this.vibration,
    volume: volume ?? this.volume,
    transactionId: clearTransaction
        ? null
        : (transactionId ?? this.transactionId),
    done: done ?? this.done,
    doneAt: clearDoneAt ? null : (doneAt ?? this.doneAt),
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    'notes': notes,
    'at': Timestamp.fromDate(at),
    'repeat': repeat.toMap(),
    'snoozeMinutes': snoozeMinutes,
    'tone': tone.name,
    'vibration': vibration.name,
    'volume': volume.name,
    'transactionId': transactionId,
    'done': done,
    'doneAt': doneAt == null ? null : Timestamp.fromDate(doneAt!),
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory Reminder.fromMap(String id, Map<String, dynamic> m) => Reminder(
    id: id,
    title: m['title'] as String,
    notes: m['notes'] as String?,
    at: (m['at'] as Timestamp).toDate(),
    repeat: RepeatRule.fromMap(
      m['repeat'] == null
          ? null
          : Map<String, dynamic>.from(m['repeat'] as Map),
    ),
    snoozeMinutes: snoozeChoices.contains(m['snoozeMinutes'])
        ? m['snoozeMinutes'] as int
        : 10,
    tone: _byName(ReminderTone.values, m['tone'], ReminderTone.alarm),
    vibration: _byName(
      ReminderVibration.values,
      m['vibration'],
      ReminderVibration.long,
    ),
    volume: _byName(ReminderVolume.values, m['volume'], ReminderVolume.high),
    transactionId: m['transactionId'] as String?,
    done: (m['done'] as bool?) ?? false,
    doneAt: m['doneAt'] == null ? null : (m['doneAt'] as Timestamp).toDate(),
    createdAt: (m['createdAt'] as Timestamp).toDate(),
  );
}
