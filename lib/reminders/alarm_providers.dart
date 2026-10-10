import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/alarm/alarm_gateway.dart';
import '../core/alarm/alarm_scheduler.dart';
import '../core/alarm/alarm_service.dart';
import 'reminder_providers.dart';

/// The phone's alarm system. Tests replace it with a fake.
final alarmGatewayProvider = Provider<AlarmGateway>(
  (ref) => PluginAlarmGateway(),
);

final alarmSchedulerProvider = Provider(
  (ref) => AlarmScheduler(ref.watch(alarmGatewayProvider)),
);

/// Keeps the phone's alarms in step with the reminders: runs once at start and
/// again on every change. Watch it from the signed-in shell to switch it on.
final alarmSyncProvider = Provider<void>((ref) {
  final scheduler = ref.watch(alarmSchedulerProvider);
  ref.listen(remindersProvider, (_, next) {
    final list = next.value;
    if (list != null) scheduler.sync(list, DateTime.now());
  }, fireImmediately: true);
});

/// Whether notifications and exact alarms are allowed right now.
final alarmPermissionsProvider = FutureProvider.autoDispose<AlarmPermissions>(
  (ref) => ref.watch(alarmGatewayProvider).permissions(),
);
