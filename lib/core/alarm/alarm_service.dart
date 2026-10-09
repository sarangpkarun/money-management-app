// SPIKE (Phase 0): proves exact, full-screen alarms on Android. The production
// reminder service in Phase 2 replaces this.
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Channel sound/vibration are immutable once created, so bump the id on change.
const _channelId = 'alarm_spike_v2';
const _alarmSound = UriAndroidNotificationSound(
  'content://settings/system/alarm_alert',
);
const _insistentFlag =
    4; // Notification.FLAG_INSISTENT: loop sound until dismissed
const alarmPayload = 'alarm';
const _snoozeActionId = 'snooze';
const _dismissActionId = 'dismiss';

final _plugin = FlutterLocalNotificationsPlugin();

NotificationDetails _details() => NotificationDetails(
  android: AndroidNotificationDetails(
    _channelId,
    'Alarms',
    channelDescription: 'Reminder alarms',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    sound: _alarmSound,
    playSound: true,
    enableVibration: true,
    additionalFlags: Int32List.fromList([_insistentFlag]),
    ongoing: true,
    autoCancel: false,
    actions: const [
      AndroidNotificationAction(_snoozeActionId, 'Snooze 5 min'),
      AndroidNotificationAction(
        _dismissActionId,
        'Dismiss',
        cancelNotification: true,
      ),
    ],
  ),
);

@pragma('vm:entry-point')
void alarmBackgroundResponse(NotificationResponse response) async {
  if (response.actionId == _snoozeActionId && response.id != null) {
    await AlarmService.init();
    await AlarmService.schedule(
      id: response.id!,
      after: const Duration(minutes: 5),
      title: 'Alarm (snoozed)',
    );
  }
}

/// Fired (in the UI isolate) when an alarm notification or its full-screen
/// intent opens the app. Set by the app shell to show the ring screen.
typedef AlarmOpened = void Function(int id, String? title);

class AlarmService {
  static bool _ready = false;
  static AlarmOpened? onAlarmOpened;
  static ({int id, String? title})? launchedBy;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.actionId == null && r.payload == alarmPayload && r.id != null) {
          onAlarmOpened?.call(r.id!, null);
        } else {
          alarmBackgroundResponse(r);
        }
      },
      onDidReceiveBackgroundNotificationResponse: alarmBackgroundResponse,
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Alarms',
        description: 'Reminder alarms',
        importance: Importance.max,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        sound: _alarmSound,
        playSound: true,
        enableVibration: true,
      ),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final r = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true &&
        r?.payload == alarmPayload &&
        r?.id != null) {
      launchedBy = (id: r!.id!, title: null);
    }
    _ready = true;
  }

  /// Requests notification, exact-alarm and full-screen-intent access.
  static Future<Map<String, bool?>> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;
    final notifications = await android.requestNotificationsPermission();
    final exact = await android.requestExactAlarmsPermission();
    final fullScreen = await android.requestFullScreenIntentPermission();
    return {
      'notifications': notifications,
      'exactAlarms': exact,
      'fullScreenIntent': fullScreen,
    };
  }

  static Future<Map<String, bool?>> status() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;
    return {
      'notifications': await android.areNotificationsEnabled(),
      'exactAlarms': await android.canScheduleExactNotifications(),
    };
  }

  static Future<void> schedule({
    required int id,
    required Duration after,
    String title = 'Alarm',
    String body = 'Spike alarm is ringing',
  }) {
    final when = tz.TZDateTime.now(tz.UTC).add(after);
    return _plugin.zonedSchedule(
      id: id,
      scheduledDate: when,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      title: title,
      body: body,
      payload: alarmPayload,
    );
  }

  static Future<void> stop(int id) => _plugin.cancel(id: id);

  static Future<void> cancelAll() => _plugin.cancelAll();
}
