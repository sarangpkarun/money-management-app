import '../models/reminder.dart';

/// Android fixes a channel's sound and vibration once it exists, so each tone
/// and vibration combination is its own channel.
class AlarmChannelSpec {
  const AlarmChannelSpec({
    required this.id,
    required this.name,
    required this.soundUri,
    required this.vibrationPattern,
  });

  final String id;
  final String name;
  final String soundUri;

  /// Null means no vibration.
  final List<int>? vibrationPattern;

  bool get vibrates => vibrationPattern != null;
}

const _toneUris = {
  ReminderTone.alarm: 'content://settings/system/alarm_alert',
  ReminderTone.notification: 'content://settings/system/notification_sound',
  ReminderTone.ringtone: 'content://settings/system/ringtone',
};

const _toneNames = {
  ReminderTone.alarm: 'Alarm sound',
  ReminderTone.notification: 'Notification sound',
  ReminderTone.ringtone: 'Ringtone',
};

const _vibrationNames = {
  ReminderVibration.off: 'no vibration',
  ReminderVibration.short: 'short vibration',
  ReminderVibration.long: 'long vibration',
};

const _vibrationPatterns = <ReminderVibration, List<int>?>{
  ReminderVibration.off: null,
  ReminderVibration.short: [0, 300, 200, 300],
  ReminderVibration.long: [0, 1000, 500, 1000, 500, 1000],
};

AlarmChannelSpec alarmChannelFor(ReminderTone tone, ReminderVibration vib) =>
    AlarmChannelSpec(
      id: 'alarm_${tone.name}_${vib.name}_v1',
      name: '${_toneNames[tone]}, ${_vibrationNames[vib]}',
      soundUri: _toneUris[tone]!,
      vibrationPattern: _vibrationPatterns[vib],
    );

/// Every channel the app can use.
List<AlarmChannelSpec> allAlarmChannels() => [
  for (final t in ReminderTone.values)
    for (final v in ReminderVibration.values) alarmChannelFor(t, v),
];
