import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/alarm/settings_opener.dart';
import '../core/alarm/test_alarm.dart';
import '../core/theme/app_colors.dart';
import '../reminders/alarm_providers.dart';

/// Explains what the phone must allow for reminders to ring, shows what it
/// does allow, and links straight to the right settings pages.
class AlarmPermissionHelpScreen extends ConsumerStatefulWidget {
  const AlarmPermissionHelpScreen({super.key});

  @override
  ConsumerState<AlarmPermissionHelpScreen> createState() =>
      _AlarmPermissionHelpScreenState();
}

class _AlarmPermissionHelpScreenState
    extends ConsumerState<AlarmPermissionHelpScreen>
    with WidgetsBindingObserver {
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the system settings: look at the permissions again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(alarmPermissionsProvider);
    }
  }

  Future<void> _open(SystemSettingsPage page) =>
      ref.read(settingsOpenerProvider).open(page);

  Future<void> _allow() async {
    await ref.read(alarmSchedulerProvider).ensurePermissions();
    ref.invalidate(alarmPermissionsProvider);
  }

  Future<void> _test() async {
    await scheduleTestAlarm(
      ref.read(alarmGatewayProvider),
      const Duration(minutes: 1),
    );
    if (mounted) {
      setState(
        () => _testMessage =
            'A test alarm will ring in 1 minute. Lock your phone to see the '
            'full-screen alarm.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(alarmPermissionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Alarm and notification help')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'For a reminder to ring loudly on time, even with the app closed '
            'and the phone locked, your phone has to allow a few things.',
          ),
          const SizedBox(height: 16),
          _StatusTile(
            title: 'Notifications',
            help:
                'Lets the app show reminders at all. Without it nothing '
                'appears.',
            status: perms.whenData((p) => p.notifications).value,
            onOpen: () => _open(SystemSettingsPage.notifications),
            onAllow: _allow,
          ),
          _StatusTile(
            title: 'Exact alarms',
            help:
                'Lets reminders ring at the exact minute instead of '
                'somewhere near it.',
            status: perms.whenData((p) => p.exact).value,
            onOpen: () => _open(SystemSettingsPage.alarms),
            onAllow: _allow,
          ),
          _StatusTile(
            title: 'Full-screen alarm when locked',
            help:
                'Cannot be checked by the app. If a locked phone shows only a '
                'small banner, allow notifications on the lock screen and '
                '"display over other apps" for this app.',
            status: null,
            onOpen: () => _open(SystemSettingsPage.app),
          ),
          _StatusTile(
            title: 'Battery restrictions',
            help:
                'Cannot be checked by the app. Set this app to '
                '"No restrictions" so the phone does not stop its alarms to '
                'save battery.',
            status: null,
            onOpen: () => _open(SystemSettingsPage.battery),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _test,
            icon: const Icon(Icons.alarm),
            label: const Text('Send a test alarm in 1 minute'),
          ),
          if (_testMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_testMessage!),
            ),
          const SizedBox(height: 24),
          Text(
            'Steps for your phone',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const _BrandTile(
            brand: 'Xiaomi, Redmi, POCO',
            tested: true,
            steps: [
              'Settings > Apps > Manage apps > this app > Autostart: on.',
              'Same page > Other permissions: allow "Show on Lock screen" and '
                  '"Display pop-up windows while running in the background".',
              'Battery saver > "No restrictions".',
            ],
          ),
          const _BrandTile(
            brand: 'Samsung',
            tested: false,
            steps: [
              'Settings > Battery > Background usage limits > Never sleeping '
                  'apps: add this app.',
              'Settings > Apps > this app > Battery > Unrestricted.',
            ],
          ),
          const _BrandTile(
            brand: 'Oppo, Realme, OnePlus',
            tested: false,
            steps: [
              'Settings > Apps > this app > Battery usage: allow background '
                  'activity.',
              'Allow auto-launch / "Auto start" for this app.',
            ],
          ),
          const _BrandTile(
            brand: 'Vivo, iQOO',
            tested: false,
            steps: [
              'Settings > Battery > Background power consumption: allow this '
                  'app.',
              'Allow "Autostart" for this app.',
            ],
          ),
        ],
      ),
    );
  }
}

/// One permission: a tick or a cross when the app can read it, otherwise a
/// "check yourself" note, with a button to the settings page.
class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.title,
    required this.help,
    required this.status,
    required this.onOpen,
    this.onAllow,
  });

  final String title;
  final String help;

  /// True allowed, false blocked, null when the app cannot tell.
  final bool? status;
  final VoidCallback onOpen;
  final VoidCallback? onAllow;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (status) {
      true => (Icons.check_circle, AppColors.receive(context), 'On'),
      false => (Icons.cancel, AppColors.pay(context), 'Off'),
      null => (
        Icons.help_outline,
        Theme.of(context).colorScheme.onSurfaceVariant,
        'Check yourself',
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(label, style: TextStyle(color: color)),
              ],
            ),
            const SizedBox(height: 8),
            Text(help),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (status == false && onAllow != null)
                  FilledButton(onPressed: onAllow, child: const Text('Allow')),
                OutlinedButton(
                  onPressed: onOpen,
                  child: const Text('Open settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandTile extends StatelessWidget {
  const _BrandTile({
    required this.brand,
    required this.steps,
    required this.tested,
  });

  final String brand;
  final List<String> steps;
  final bool tested;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(brand),
      subtitle: Text(tested ? 'Tried on a real phone' : 'Not yet tried by us'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('${i + 1}. ${steps[i]}'),
          ),
      ],
    );
  }
}
