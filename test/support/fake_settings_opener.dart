import 'package:money_manager/core/alarm/settings_opener.dart';

class FakeSettingsOpener implements SettingsOpener {
  final List<SystemSettingsPage> opened = [];

  @override
  Future<void> open(SystemSettingsPage page) async => opened.add(page);
}
