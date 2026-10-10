import '../models/reminder.dart';
import 'alarm_gateway.dart';
import 'alarm_plan.dart';

const _testId = 'alarm-test';

/// The id of the test alarm, so it can be cancelled again.
int testAlarmId() => alarmId(reminderKey(_testId), 0);

/// Schedules a one-off test alarm [after] from now, to check the phone lets
/// alarms ring.
Future<void> scheduleTestAlarm(AlarmGateway gateway, Duration after) {
  return gateway.schedule(
    PlannedAlarm(
      id: testAlarmId(),
      payload: AlarmPayload(
        reminderId: _testId,
        title: 'Alarm test',
        notes: 'If you can see and hear this, reminders will work.',
        snoozeMinutes: 5,
        tone: ReminderTone.alarm,
        vibration: ReminderVibration.long,
        at: DateTime.now().add(after),
        once: true,
      ),
    ),
  );
}
