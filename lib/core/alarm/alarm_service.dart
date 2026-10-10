import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'alarm_channels.dart';
import 'alarm_gateway.dart';
import 'alarm_plan.dart';

const _insistentFlag =
    4; // Notification.FLAG_INSISTENT: loop the sound until dismissed
const _snoozeActionId = 'snooze';
const _dismissActionId = 'dismiss';

final _plugin = FlutterLocalNotificationsPlugin();

/// The notification channel of the summary notifications.
const summaryChannelId = 'summary_v1';

/// Handles notification actions while the app is not running (runs in its own
/// isolate): Snooze re-schedules the same alarm after the reminder's minutes.
@pragma('vm:entry-point')
void alarmBackgroundResponse(NotificationResponse response) async {
  if (response.actionId != _snoozeActionId) return;
  final payload = AlarmPayload.decode(response.payload);
  if (payload == null) return;
  await AlarmService.init();
  if (response.id != null) await _plugin.cancel(id: response.id!);
  await PluginAlarmGateway().schedule(snoozeAlarm(payload, DateTime.now()));
}

/// Fired in the UI isolate when an alarm notification or its full-screen intent
/// opens the app. Set by the app shell to show the ring screen.
typedef AlarmOpened = void Function(int id, AlarmPayload payload);

/// Plugin set-up and the alarm that opened the app. The scheduling itself is in
/// [PluginAlarmGateway].
class AlarmService {
  static bool _ready = false;
  static AlarmOpened? onAlarmOpened;
  static ({int id, AlarmPayload payload})? launchedBy;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        final payload = AlarmPayload.decode(r.payload);
        // A summary just opens the app; only alarms open the ring screen.
        if (payload?.kind == AlarmKind.summary) return;
        if (r.actionId == null && payload != null && r.id != null) {
          onAlarmOpened?.call(r.id!, payload);
        } else {
          alarmBackgroundResponse(r);
        }
      },
      onDidReceiveBackgroundNotificationResponse: alarmBackgroundResponse,
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final r = launch?.notificationResponse;
    final payload = AlarmPayload.decode(r?.payload);
    if (launch?.didNotificationLaunchApp == true &&
        payload != null &&
        payload.kind == AlarmKind.alarm &&
        r?.id != null) {
      launchedBy = (id: r!.id!, payload: payload);
    }
    _ready = true;
  }
}

/// The phone's alarm system, through flutter_local_notifications.
class PluginAlarmGateway implements AlarmGateway {
  static final Set<String> _madeChannels = {};

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> _ensureChannel(AlarmChannelSpec spec) async {
    if (!_madeChannels.add(spec.id)) return;
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        spec.id,
        spec.name,
        description: 'Reminder alarms',
        importance: Importance.max,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        sound: UriAndroidNotificationSound(spec.soundUri),
        playSound: true,
        enableVibration: spec.vibrates,
        vibrationPattern: spec.vibrates
            ? Int64List.fromList(spec.vibrationPattern!)
            : null,
      ),
    );
  }

  @override
  Future<void> schedule(PlannedAlarm alarm) async {
    await AlarmService.init();
    final p = alarm.payload;
    if (p.kind == AlarmKind.summary) return _scheduleSummary(alarm);
    final spec = alarmChannelFor(p.tone, p.vibration);
    await _ensureChannel(spec);
    await _plugin.zonedSchedule(
      id: alarm.id,
      scheduledDate: tz.TZDateTime.from(alarm.at, tz.UTC),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          spec.id,
          spec.name,
          channelDescription: 'Reminder alarms',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          sound: UriAndroidNotificationSound(spec.soundUri),
          playSound: true,
          enableVibration: spec.vibrates,
          vibrationPattern: spec.vibrates
              ? Int64List.fromList(spec.vibrationPattern!)
              : null,
          additionalFlags: Int32List.fromList([_insistentFlag]),
          ongoing: true,
          autoCancel: false,
          actions: [
            AndroidNotificationAction(
              _snoozeActionId,
              'Snooze ${p.snoozeMinutes} min',
            ),
            const AndroidNotificationAction(
              _dismissActionId,
              'Dismiss',
              cancelNotification: true,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      title: p.title,
      body: p.notes ?? (p.snoozed ? 'Snoozed reminder' : 'Reminder'),
      payload: alarm.encodedPayload,
    );
  }

  /// Developer bisect aid: the exact Phase 0 spike configuration (one fixed
  /// channel, no vibration pattern, no payload), which rang on this phone.
  Future<void> scheduleLegacySpike(Duration after) async {
    await AlarmService.init();
    const channel = 'alarm_spike_v2';
    const sound = UriAndroidNotificationSound(
      'content://settings/system/alarm_alert',
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        channel,
        'Alarms',
        description: 'Reminder alarms',
        importance: Importance.max,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        sound: sound,
        playSound: true,
        enableVibration: true,
      ),
    );
    await _plugin.zonedSchedule(
      id: 1,
      scheduledDate: tz.TZDateTime.now(tz.UTC).add(after),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          'Alarms',
          channelDescription: 'Reminder alarms',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          sound: sound,
          playSound: true,
          enableVibration: true,
          additionalFlags: Int32List.fromList([_insistentFlag]),
          ongoing: true,
          autoCancel: false,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      title: 'Spike-config alarm',
      body: 'Old configuration',
    );
  }

  /// The daily/weekly summary: an ordinary notification with the phone's
  /// normal notification sound, no full-screen takeover and no looping.
  Future<void> _scheduleSummary(PlannedAlarm alarm) async {
    final p = alarm.payload;
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        summaryChannelId,
        'Daily and weekly summary',
        description: 'A short summary of what is due',
        importance: Importance.defaultImportance,
      ),
    );
    await _plugin.zonedSchedule(
      id: alarm.id,
      scheduledDate: tz.TZDateTime.from(alarm.at, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          summaryChannelId,
          'Daily and weekly summary',
          channelDescription: 'A short summary of what is due',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(''),
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      title: p.title,
      body: p.notes,
      payload: alarm.encodedPayload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await AlarmService.init();
    await _plugin.cancel(id: id);
  }

  @override
  Future<List<PendingAlarm>> pending() async {
    await AlarmService.init();
    return [
      for (final r in await _plugin.pendingNotificationRequests())
        PendingAlarm(id: r.id, payload: r.payload),
    ];
  }

  @override
  Future<AlarmPermissions> permissions() async {
    await AlarmService.init();
    final android = _android;
    if (android == null) {
      return const AlarmPermissions(notifications: false, exact: false);
    }
    return AlarmPermissions(
      notifications: await android.areNotificationsEnabled() ?? false,
      exact: await android.canScheduleExactNotifications() ?? false,
    );
  }

  @override
  Future<AlarmPermissions> requestPermissions() async {
    await AlarmService.init();
    final android = _android;
    if (android != null) {
      await android.requestNotificationsPermission();
      await android.requestExactAlarmsPermission();
      await android.requestFullScreenIntentPermission();
    }
    return permissions();
  }
}
