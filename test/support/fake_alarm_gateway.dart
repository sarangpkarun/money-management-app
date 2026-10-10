import 'package:money_manager/core/alarm/alarm_gateway.dart';
import 'package:money_manager/core/alarm/alarm_plan.dart';

/// An in-memory stand-in for the phone's alarm system.
class FakeAlarmGateway implements AlarmGateway {
  FakeAlarmGateway({this.allowed = true});

  bool allowed;
  final Map<int, PlannedAlarm> scheduled = {};
  final Map<int, String?> foreign = {};
  int scheduleCalls = 0;
  int cancelCalls = 0;
  int permissionRequests = 0;

  @override
  Future<void> schedule(PlannedAlarm alarm) async {
    scheduleCalls++;
    scheduled[alarm.id] = alarm;
  }

  @override
  Future<void> cancel(int id) async {
    cancelCalls++;
    scheduled.remove(id);
    foreign.remove(id);
  }

  @override
  Future<List<PendingAlarm>> pending() async => [
    for (final a in scheduled.values)
      PendingAlarm(id: a.id, payload: a.encodedPayload),
    for (final e in foreign.entries) PendingAlarm(id: e.key, payload: e.value),
  ];

  @override
  Future<AlarmPermissions> permissions() async =>
      AlarmPermissions(notifications: allowed, exact: allowed);

  @override
  Future<AlarmPermissions> requestPermissions() async {
    permissionRequests++;
    return permissions();
  }
}
