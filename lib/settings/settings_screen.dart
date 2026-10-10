import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../core/alarm/alarm_test_screen.dart';
import '../history/history_screen.dart';
import '../reminders/alarm_providers.dart';
import '../transactions/entries_screen.dart';
import 'alarm_permission_help_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _logOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can log back in any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // The auth gate shows the login screen as soon as the user is gone.
      // Alarms belong to the account: remove them from this phone first.
      try {
        await ref.read(alarmSchedulerProvider).clear();
      } catch (_) {
        // Alarms are best-effort; never block logging out.
      }
      await ref.read(authRepositoryProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Profile'),
            onTap: () => _open(context, const ProfileScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('History'),
            subtitle: const Text('Settled entries'),
            onTap: () => _open(context, const HistoryScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('All entries'),
            onTap: () => _open(context, const EntriesScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Alarm and notification help'),
            subtitle: const Text('Make sure reminders can ring'),
            onTap: () => _open(context, const AlarmPermissionHelpScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Alarm test (developer)'),
            onTap: () => _open(context, const AlarmTestScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Money Manager',
              applicationLegalese: 'Track what you lend and borrow.',
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Log out',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => _logOut(context, ref),
          ),
        ],
      ),
    );
  }
}
