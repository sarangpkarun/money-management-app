import 'dart:convert';

import '../models/reminder.dart';
import '../reminders/repeat.dart';

/// Every alarm payload starts with this, so the scheduler can tell its own
/// alarms from anything else the plugin has pending.
const alarmPayloadPrefix = 'rem1:';

/// The slot (low 5 bits of an alarm id) reserved for a snoozed ring. Slots
/// 0..30 carry the upcoming rings of a reminder.
const snoozeSlot = 31;
const _maxRingSlots = 31;

const _ringsPerReminder = 30;
const _horizon = Duration(days: 60);
const _totalCap = 200;
const _keyBits = 26;
const _keyMask = (1 << _keyBits) - 1;

/// What a ringing alarm needs to know, carried in the notification payload so
/// the ring screen and the snooze action work with no database and no app.
class AlarmPayload {
  const AlarmPayload({
    required this.reminderId,
    required this.title,
    this.notes,
    required this.snoozeMinutes,
    required this.tone,
    required this.vibration,
    required this.at,
    this.snoozed = false,
    this.once = false,
  });

  final String reminderId;
  final String title;
  final String? notes;
  final int snoozeMinutes;
  final ReminderTone tone;
  final ReminderVibration vibration;

  /// When this ring is due.
  final DateTime at;
  final bool snoozed;

  /// True for a reminder that does not repeat (dismissing it finishes it).
  final bool once;

  String encode() =>
      alarmPayloadPrefix +
      jsonEncode({
        'rid': reminderId,
        't': title,
        if (notes != null) 'n': notes,
        's': snoozeMinutes,
        'tn': tone.name,
        'v': vibration.name,
        'at': at.millisecondsSinceEpoch,
        if (snoozed) 'sz': true,
        if (once) 'o': true,
      });

  /// Null when [raw] is not one of our payloads or is damaged.
  static AlarmPayload? decode(String? raw) {
    if (raw == null || !raw.startsWith(alarmPayloadPrefix)) return null;
    try {
      final m = jsonDecode(raw.substring(alarmPayloadPrefix.length));
      if (m is! Map) return null;
      T pick<T extends Enum>(List<T> values, Object? name, T fallback) {
        for (final v in values) {
          if (v.name == name) return v;
        }
        return fallback;
      }

      return AlarmPayload(
        reminderId: m['rid'] as String,
        title: m['t'] as String,
        notes: m['n'] as String?,
        snoozeMinutes: snoozeChoices.contains(m['s']) ? m['s'] as int : 10,
        tone: pick(ReminderTone.values, m['tn'], ReminderTone.alarm),
        vibration: pick(
          ReminderVibration.values,
          m['v'],
          ReminderVibration.long,
        ),
        at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
        snoozed: m['sz'] == true,
        once: m['o'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  AlarmPayload copyWith({DateTime? at, bool? snoozed}) => AlarmPayload(
    reminderId: reminderId,
    title: title,
    notes: notes,
    snoozeMinutes: snoozeMinutes,
    tone: tone,
    vibration: vibration,
    at: at ?? this.at,
    snoozed: snoozed ?? this.snoozed,
    once: once,
  );
}

/// One alarm to hand to the system: a stable [id], when, and its payload.
class PlannedAlarm {
  const PlannedAlarm({required this.id, required this.payload});

  final int id;
  final AlarmPayload payload;

  DateTime get at => payload.at;
  String get encodedPayload => payload.encode();
}

/// A 26-bit key for [reminderId] (FNV-1a), the high bits of its alarm ids.
int reminderKey(String reminderId) {
  var h = 0x811c9dc5;
  for (final c in reminderId.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h & _keyMask;
}

/// The alarm id for [key] and ring [slot] (0..31): a positive 31-bit number,
/// so it fits the system's notification id.
int alarmId(int key, int slot) => (key << 5) | slot;

/// The reminder key an alarm id belongs to, and its slot.
int keyOfAlarmId(int id) => id >> 5;
int slotOfAlarmId(int id) => id & 31;

/// The alarms that should be pending at [now]: for each active reminder its next
/// rings (up to 30, within 60 days), the soonest 200 overall. Done reminders and
/// passed one-offs have none.
///
/// [hash] gives a reminder's key; two reminders that land on the same key are
/// separated by probing (in id order), so alarm ids never clash.
List<PlannedAlarm> planAlarms(
  List<Reminder> reminders,
  DateTime now, {
  int Function(String id) hash = reminderKey,
}) {
  final keys = reminderKeys(reminders, hash: hash);
  final end = now.add(_horizon);
  final all = <PlannedAlarm>[];
  for (final r in reminders) {
    if (r.done) continue;
    final key = keys[r.id]!;
    var next = nextOccurrence(r, now);
    for (var slot = 0; next != null && slot < _ringsPerReminder; slot++) {
      if (next.isAfter(end)) break;
      all.add(
        PlannedAlarm(
          id: alarmId(key, slot),
          payload: AlarmPayload(
            reminderId: r.id,
            title: r.title,
            notes: r.notes,
            snoozeMinutes: r.snoozeMinutes,
            tone: r.tone,
            vibration: r.vibration,
            at: next,
            once: !r.repeat.repeats,
          ),
        ),
      );
      next = nextOccurrence(r, next);
    }
  }
  all.sort((a, b) => a.at.compareTo(b.at));
  return all.length > _totalCap ? all.sublist(0, _totalCap) : all;
}

/// A unique key for each reminder, in reminder-id order.
Map<String, int> reminderKeys(
  List<Reminder> reminders, {
  int Function(String id) hash = reminderKey,
}) {
  final ids = [for (final r in reminders) r.id]..sort();
  final taken = <int>{};
  final out = <String, int>{};
  for (final id in ids) {
    var k = hash(id) & _keyMask;
    while (!taken.add(k)) {
      k = (k + 1) & _keyMask;
    }
    out[id] = k;
  }
  return out;
}

/// The snoozed ring after [payload] is snoozed at [now]: the reminder's own
/// snooze minutes later, on the reserved slot, same tone and vibration.
PlannedAlarm snoozeAlarm(AlarmPayload payload, DateTime now) => PlannedAlarm(
  id: alarmId(reminderKey(payload.reminderId), snoozeSlot),
  payload: payload.copyWith(
    at: now.add(Duration(minutes: payload.snoozeMinutes)),
    snoozed: true,
  ),
);

const maxRingSlotsForTest = _maxRingSlots;
