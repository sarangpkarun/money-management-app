import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/alarm/alarm_gateway.dart';
import '../core/alarm/alarm_scheduler.dart';
import '../core/alarm/alarm_service.dart';
import '../core/alarm/settings_opener.dart';
import '../people/people_providers.dart';
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
  void run() {
    final reminders = ref.read(remindersProvider).value;
    final entries = ref.read(allTransactionsProvider).value;
    if (reminders == null || entries == null) return;
    scheduler.sync(reminders, DateTime.now(), transactions: entries);
  }

  ref.listen(remindersProvider, (_, _) => run(), fireImmediately: true);
  ref.listen(allTransactionsProvider, (_, _) => run(), fireImmediately: true);
});

/// Opens system settings pages. Tests replace it with a fake.
final settingsOpenerProvider = Provider<SettingsOpener>(
  (ref) => const AppSettingsOpener(),
);

/// Whether notifications and exact alarms are allowed right now.
final alarmPermissionsProvider = FutureProvider.autoDispose<AlarmPermissions>(
  (ref) => ref.watch(alarmGatewayProvider).permissions(),
);
