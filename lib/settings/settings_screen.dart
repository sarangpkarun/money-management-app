import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../core/alarm/alarm_test_screen.dart';
import '../core/data/providers.dart';
import '../core/models/app_settings.dart';
import '../core/models/app_user.dart';
import '../core/money/money.dart';
import '../core/ui/format.dart';
import '../history/history_screen.dart';
import '../reminders/alarm_providers.dart';
import '../reminders/reminder_form_logic.dart';
import '../transactions/entries_screen.dart';
import 'about_screen.dart';
import 'alarm_permission_help_screen.dart';
import 'backup.dart';
import 'privacy_screen.dart';
import 'profile_screen.dart';
import 'settings_extras_providers.dart';
import 'settings_providers.dart';

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "7:30 am" for minutes after midnight.
String minutesLabel(int minutes) =>
    formatTime(DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60));

String summaryLabel(SummarySettings s) => switch (s.mode) {
  SummaryMode.off => 'Off',
  SummaryMode.daily => 'Daily at ${minutesLabel(s.minutes)}',
  SummaryMode.weekly =>
    'Weekly on ${_weekdayNames[s.weekday - 1]} at ${minutesLabel(s.minutes)}',
};

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
      // Alarms belong to the account: remove them from this phone first.
      try {
        await ref.read(alarmSchedulerProvider).clear();
      } catch (_) {
        // Alarms are best-effort; never block logging out.
      }
      // The auth gate shows the login screen as soon as the user is gone.
      await ref.read(authRepositoryProvider).signOut();
    }
  }

  void _save(WidgetRef ref, AppSettings settings) =>
      ref.read(userRepositoryProvider).saveSettings(settings);

  Future<void> _pickCurrency(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final chosen = await _choose<String>(context, 'Currency', current, {
      for (final c in currencies) c: '$c  ${currencySymbol(c).trim()}',
    });
    final profile = ref.read(currentProfileProvider).value;
    if (chosen == null || chosen == current || profile == null) return;
    await ref
        .read(userRepositoryProvider)
        .save(
          AppUser(
            name: profile.name,
            currency: chosen,
            timezone: profile.timezone,
          ),
        );
  }

  Future<T?> _choose<T>(
    BuildContext context,
    String title,
    T current,
    Map<T, String> options,
  ) {
    return showDialog<T>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(title),
        children: [
          RadioGroup<T>(
            groupValue: current,
            onChanged: (v) => Navigator.of(d).pop(v),
            child: Column(
              children: [
                for (final e in options.entries)
                  RadioListTile<T>(value: e.key, title: Text(e.value)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<int?> _pickTime(BuildContext context, int minutes) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Export my data'),
        content: const Text(
          'This makes one file with everything in your account (people, '
          'entries, payments, reminders and settings). It contains private '
          'information: keep it somewhere safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final now = DateTime.now();
      final backup = await collectBackup(
        users: ref.read(userRepositoryProvider),
        people: ref.read(peopleRepositoryProvider),
        transactions: ref.read(transactionRepositoryProvider),
        payments: ref.read(paymentRepositoryProvider),
        reminders: ref.read(reminderRepositoryProvider),
        now: now,
      );
      await ref
          .read(backupSharerProvider)
          .share(fileName: backupFileName(now), json: backupJson(backup));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export your data: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final currency = ref.watch(appCurrencyProvider);
    final quiet = settings.quietHours;

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Profile'),
            onTap: () => _open(context, const ProfileScreen()),
          ),
          header('Display'),
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: const Text('Currency'),
            subtitle: Text('$currency ${currencySymbol(currency).trim()}'),
            onTap: () => _pickCurrency(context, ref, currency),
          ),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('Number format'),
            subtitle: Text(switch (settings.grouping) {
              null => 'Automatic (${settings.groupingFor(currency).name})',
              NumberGrouping.indian => 'Indian (12,34,567)',
              NumberGrouping.western => 'Western (1,234,567)',
            }),
            onTap: () async {
              const auto = 'auto';
              final chosen = await _choose<String>(
                context,
                'Number format',
                settings.grouping?.name ?? auto,
                {
                  auto: 'Automatic (by currency)',
                  'indian': 'Indian (12,34,567)',
                  'western': 'Western (1,234,567)',
                },
              );
              if (chosen == null) return;
              _save(
                ref,
                chosen == auto
                    ? settings.copyWith(clearGrouping: true)
                    : settings.copyWith(
                        grouping: NumberGrouping.values.byName(chosen),
                      ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Date format'),
            subtitle: Text(formatShortDate(DateTime.now())),
            onTap: () async {
              final sample = DateTime(2026, 10, 9);
              final chosen = await _choose<DateStyle>(
                context,
                'Date format',
                settings.dateStyle,
                {
                  for (final s in DateStyle.values)
                    s: formatShortDate(sample, style: s),
                },
              );
              if (chosen != null) {
                _save(ref, settings.copyWith(dateStyle: chosen));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            subtitle: Text(switch (settings.theme) {
              ThemeChoice.system => 'Same as the phone',
              ThemeChoice.light => 'Light',
              ThemeChoice.dark => 'Dark',
            }),
            onTap: () async {
              final chosen =
                  await _choose<ThemeChoice>(context, 'Theme', settings.theme, {
                    ThemeChoice.system: 'Same as the phone',
                    ThemeChoice.light: 'Light',
                    ThemeChoice.dark: 'Dark',
                  });
              if (chosen != null) {
                _save(ref, settings.copyWith(theme: chosen));
              }
            },
          ),
          header('Reminders'),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Payment alarm time'),
            subtitle: Text(
              '${minutesLabel(settings.autoAlarmMinutes)} · also the default '
              'time for new reminders',
            ),
            onTap: () async {
              final m = await _pickTime(context, settings.autoAlarmMinutes);
              if (m != null) _save(ref, settings.copyWith(autoAlarmMinutes: m));
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bedtime_outlined),
            title: const Text('Quiet hours'),
            subtitle: const Text(
              'Payment alarms and the summary wait until quiet hours end. '
              'Reminders you set yourself still ring on time.',
            ),
            value: quiet.enabled,
            onChanged: (on) => _save(
              ref,
              settings.copyWith(quietHours: quiet.copyWith(enabled: on)),
            ),
          ),
          if (quiet.enabled) ...[
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('From'),
              trailing: Text(minutesLabel(quiet.startMinutes)),
              onTap: () async {
                final m = await _pickTime(context, quiet.startMinutes);
                if (m != null) {
                  _save(
                    ref,
                    settings.copyWith(
                      quietHours: quiet.copyWith(startMinutes: m),
                    ),
                  );
                }
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('Until'),
              trailing: Text(minutesLabel(quiet.endMinutes)),
              onTap: () async {
                final m = await _pickTime(context, quiet.endMinutes);
                if (m != null) {
                  _save(
                    ref,
                    settings.copyWith(
                      quietHours: quiet.copyWith(endMinutes: m),
                    ),
                  );
                }
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.summarize_outlined),
            title: const Text('Daily or weekly summary'),
            subtitle: Text(summaryLabel(settings.summary)),
            onTap: () async {
              final chosen = await showDialog<SummarySettings>(
                context: context,
                builder: (_) => _SummaryDialog(initial: settings.summary),
              );
              if (chosen != null) {
                _save(ref, settings.copyWith(summary: chosen));
              }
            },
          ),
          header('Data'),
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
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Export my data'),
            subtitle: const Text('A backup file of everything'),
            onTap: () => _export(context, ref),
          ),
          header('Help'),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Alarm and notification help'),
            subtitle: const Text('Make sure reminders can ring'),
            onTap: () => _open(context, const AlarmPermissionHelpScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy'),
            onTap: () => _open(context, const PrivacyScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            onTap: () => _open(context, const AboutScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Alarm test (developer)'),
            onTap: () => _open(context, const AlarmTestScreen()),
          ),
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

class _SummaryDialog extends StatefulWidget {
  const _SummaryDialog({required this.initial});

  final SummarySettings initial;

  @override
  State<_SummaryDialog> createState() => _SummaryDialogState();
}

class _SummaryDialogState extends State<_SummaryDialog> {
  late SummarySettings _s = widget.initial;

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _s.minutes ~/ 60, minute: _s.minutes % 60),
    );
    if (t != null) {
      setState(() => _s = _s.copyWith(minutes: t.hour * 60 + t.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Summary'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final m in SummaryMode.values)
                  ChoiceChip(
                    label: Text(switch (m) {
                      SummaryMode.off => 'Off',
                      SummaryMode.daily => 'Daily',
                      SummaryMode.weekly => 'Weekly',
                    }),
                    selected: _s.mode == m,
                    onSelected: (_) =>
                        setState(() => _s = _s.copyWith(mode: m)),
                  ),
              ],
            ),
            if (_s.mode == SummaryMode.weekly) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (var d = 1; d <= 7; d++)
                    ChoiceChip(
                      label: Text(weekdayShort(d)),
                      selected: _s.weekday == d,
                      onSelected: (_) =>
                          setState(() => _s = _s.copyWith(weekday: d)),
                    ),
                ],
              ),
            ],
            if (_s.mode != SummaryMode.off) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.access_time, size: 18),
                label: Text(minutesLabel(_s.minutes)),
              ),
              const SizedBox(height: 8),
              const Text(
                'A short notification with what is overdue and due this week. '
                'It is worked out each time you open the app, so it can be a '
                'little behind if you have not opened it for a few days.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_s),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
