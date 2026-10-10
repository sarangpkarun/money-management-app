import 'alarm_plan.dart';

/// What the phone lets the app do about alarms.
class AlarmPermissions {
  const AlarmPermissions({required this.notifications, required this.exact});

  final bool notifications;
  final bool exact;

  bool get ok => notifications && exact;
}

/// An alarm the system is holding for us.
class PendingAlarm {
  const PendingAlarm({required this.id, required this.payload});

  final int id;
  final String? payload;
}

/// The system side of alarms (the plugin on a phone, a fake in tests).
abstract class AlarmGateway {
  Future<void> schedule(PlannedAlarm alarm);
  Future<void> cancel(int id);
  Future<List<PendingAlarm>> pending();
  Future<AlarmPermissions> permissions();
  Future<AlarmPermissions> requestPermissions();
}
