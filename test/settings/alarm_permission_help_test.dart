import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/alarm/alarm_plan.dart';
import 'package:money_manager/core/alarm/settings_opener.dart';
import 'package:money_manager/core/alarm/test_alarm.dart';
import 'package:money_manager/reminders/alarm_providers.dart';
import 'package:money_manager/settings/alarm_permission_help_screen.dart';

import '../support/fake_alarm_gateway.dart';
import '../support/fake_settings_opener.dart';

void main() {
  late FakeAlarmGateway gateway;
  late FakeSettingsOpener opener;

  setUp(() {
    gateway = FakeAlarmGateway();
    opener = FakeSettingsOpener();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alarmGatewayProvider.overrideWithValue(gateway),
          settingsOpenerProvider.overrideWithValue(opener),
        ],
        child: const MaterialApp(home: AlarmPermissionHelpScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows both readable permissions as on', (tester) async {
    await pump(tester);
    expect(find.text('On'), findsNWidgets(2));
    expect(find.text('Check yourself'), findsNWidgets(2));
    expect(find.text('Off'), findsNothing);
    expect(find.text('Allow'), findsNothing);
  });

  testWidgets('shows them as off, with an Allow button, when blocked', (
    tester,
  ) async {
    gateway.allowed = false;
    await pump(tester);
    expect(find.text('Off'), findsNWidgets(2));
    expect(find.text('Allow'), findsNWidgets(2));
  });

  testWidgets('Allow asks the phone for permission and refreshes', (
    tester,
  ) async {
    gateway.allowed = false;
    await pump(tester);
    await tester.tap(find.text('Allow').first);
    await tester.pumpAndSettle();
    expect(gateway.permissionRequests, 1);
  });

  testWidgets('each Open settings button opens its own page', (tester) async {
    await pump(tester);
    final buttons = find.text('Open settings');
    expect(buttons, findsNWidgets(4));
    for (var i = 0; i < 4; i++) {
      await tester.ensureVisible(buttons.at(i));
      await tester.pumpAndSettle();
      await tester.tap(buttons.at(i));
      await tester.pumpAndSettle();
    }
    expect(opener.opened, [
      SystemSettingsPage.notifications,
      SystemSettingsPage.alarms,
      SystemSettingsPage.app,
      SystemSettingsPage.battery,
    ]);
  });

  testWidgets('coming back from settings re-checks the permissions', (
    tester,
  ) async {
    gateway.allowed = false;
    await pump(tester);
    expect(find.text('Off'), findsNWidgets(2));
    gateway.allowed = true; // the user allowed it in system settings
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('On'), findsNWidgets(2));
    expect(find.text('Off'), findsNothing);
  });

  testWidgets('the test alarm is scheduled about a minute ahead', (
    tester,
  ) async {
    await pump(tester);
    final before = DateTime.now();
    await tester.ensureVisible(find.text('Send a test alarm in 1 minute'));
    await tester.tap(find.text('Send a test alarm in 1 minute'));
    await tester.pumpAndSettle();
    final a = gateway.scheduled.values.single;
    expect(a.id, testAlarmId());
    expect(a.at.difference(before).inSeconds, inInclusiveRange(58, 62));
    expect(a.payload.title, 'Alarm test');
    expect(AlarmPayload.decode(a.encodedPayload), isNotNull);
    expect(find.textContaining('will ring in 1 minute'), findsOneWidget);
  });

  testWidgets('lists steps per phone brand, marking which were tried', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Xiaomi, Redmi, POCO'), findsOneWidget);
    expect(find.text('Tried on a real phone'), findsOneWidget);
    expect(find.text('Not yet tried by us'), findsNWidgets(3));
    await tester.ensureVisible(find.text('Xiaomi, Redmi, POCO'));
    await tester.tap(find.text('Xiaomi, Redmi, POCO'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Autostart'), findsWidgets);
  });
}
