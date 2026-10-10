import 'package:app_settings/app_settings.dart';

/// The phone settings pages the help screen can open.
enum SystemSettingsPage { notifications, alarms, battery, app }

/// Opens a system settings page (the real one on a phone, a fake in tests).
abstract class SettingsOpener {
  Future<void> open(SystemSettingsPage page);
}

class AppSettingsOpener implements SettingsOpener {
  const AppSettingsOpener();

  @override
  Future<void> open(SystemSettingsPage page) => AppSettings.openAppSettings(
    type: switch (page) {
      SystemSettingsPage.notifications => AppSettingsType.notification,
      SystemSettingsPage.alarms => AppSettingsType.alarm,
      SystemSettingsPage.battery => AppSettingsType.batteryOptimization,
      SystemSettingsPage.app => AppSettingsType.settings,
    },
  );
}
