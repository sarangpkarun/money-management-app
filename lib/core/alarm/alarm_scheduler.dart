import '../models/reminder.dart';
import 'alarm_gateway.dart';
import 'alarm_plan.dart';

/// What a sync did.
class SyncResult {
  const SyncResult({
    required this.scheduled,
    required this.cancelled,
    required this.blocked,
  });

  final int scheduled;
  final int cancelled;

  /// True when notifications or exact alarms are off, so nothing was scheduled.
  final bool blocked;
}

/// Keeps the system's pending alarms in step with the reminders. Safe to run as
/// often as you like: alarms that are already right are left alone.
class AlarmScheduler {
  AlarmScheduler(this._gateway);

  final AlarmGateway _gateway;

  Future<SyncResult> sync(List<Reminder> reminders, DateTime now) async {
    final plan = planAlarms(reminders, now);
    final planned = {for (final a in plan) a.id: a};
    final active = {
      for (final r in reminders)
        if (!r.done) r.id,
    };
    final ours = [
      for (final p in await _gateway.pending())
        if (p.payload?.startsWith(alarmPayloadPrefix) ?? false) p,
    ];

    var cancelled = 0;
    final have = <int, String?>{};
    for (final p in ours) {
      final isSnooze = slotOfAlarmId(p.id) == snoozeSlot;
      final keep = isSnooze
          ? active.contains(AlarmPayload.decode(p.payload)?.reminderId)
          : planned.containsKey(p.id);
      if (keep) {
        have[p.id] = p.payload;
      } else {
        await _gateway.cancel(p.id);
        cancelled++;
      }
    }

    final toSchedule = [
      for (final a in plan)
        if (have[a.id] != a.encodedPayload) a,
    ];
    if (toSchedule.isEmpty) {
      return SyncResult(scheduled: 0, cancelled: cancelled, blocked: false);
    }
    final perms = await _gateway.permissions();
    if (!perms.ok) {
      return SyncResult(scheduled: 0, cancelled: cancelled, blocked: true);
    }
    for (final a in toSchedule) {
      await _gateway.schedule(a);
    }
    return SyncResult(
      scheduled: toSchedule.length,
      cancelled: cancelled,
      blocked: false,
    );
  }

  /// Removes every alarm of ours (on sign-out).
  Future<void> clear() async {
    for (final p in await _gateway.pending()) {
      if (p.payload?.startsWith(alarmPayloadPrefix) ?? false) {
        await _gateway.cancel(p.id);
      }
    }
  }

  Future<AlarmPermissions> ensurePermissions() async {
    final now = await _gateway.permissions();
    return now.ok ? now : _gateway.requestPermissions();
  }
}
