import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/reminder.dart';
import '../core/theme/app_colors.dart';
import '../settings/alarm_permission_help_screen.dart';
import '../transactions/entry_detail_screen.dart';
import 'alarm_providers.dart';
import 'reminder_form_logic.dart';
import 'reminder_form_screen.dart';
import 'reminder_list_providers.dart';
import 'reminder_lists.dart';

/// The user's reminders in three lists: Upcoming (including automatic payment
/// alarms), Completed and Missed.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  void _openForm(BuildContext context, [Reminder? r]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReminderFormScreen(existing: r)),
    );
  }

  void _openHelp(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AlarmPermissionHelpScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(reminderListsProvider);
    final data = lists.value;
    final missedCount = data?.missed.length ?? 0;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reminders'),
          actions: [
            IconButton(
              tooltip: 'Alarm and notification help',
              icon: const Icon(Icons.help_outline),
              onPressed: () => _openHelp(context),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
              Tab(
                child: Text(
                  missedCount > 0 ? 'Missed ($missedCount)' : 'Missed',
                  style: missedCount > 0
                      ? TextStyle(color: AppColors.pay(context))
                      : null,
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'reminders-add',
          onPressed: () => _openForm(context),
          icon: const Icon(Icons.add_alarm),
          label: const Text('Add reminder'),
        ),
        body: lists.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load reminders: $e')),
          data: (l) => Column(
            children: [
              _PermissionBanner(onHelp: () => _openHelp(context)),
              Expanded(
                child: TabBarView(
                  children: [
                    _UpcomingList(
                      lists: l,
                      onOpen: (r) => _openForm(context, r),
                    ),
                    _CompletedList(
                      items: l.completed,
                      onOpen: (r) => _openForm(context, r),
                    ),
                    _MissedList(
                      items: l.missed,
                      onOpen: (r) => _openForm(context, r),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionBanner extends ConsumerWidget {
  const _PermissionBanner({required this.onHelp});

  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(alarmPermissionsProvider).value;
    if (perms == null || perms.ok) return const SizedBox.shrink();
    return MaterialBanner(
      content: const Text(
        'Alarms are off. Allow notifications and exact alarms so reminders '
        'can ring.',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ref.read(alarmSchedulerProvider).ensurePermissions();
            ref.invalidate(alarmPermissionsProvider);
          },
          child: const Text('Allow'),
        ),
        TextButton(onPressed: onHelp, child: const Text('How to fix')),
      ],
    );
  }
}

class _UpcomingList extends StatelessWidget {
  const _UpcomingList({required this.lists, required this.onOpen});

  final ReminderLists lists;
  final void Function(Reminder) onOpen;

  @override
  Widget build(BuildContext context) {
    if (lists.upcoming.isEmpty) {
      return const _Empty(icon: Icons.alarm, text: 'Nothing coming up');
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final u in lists.upcoming)
          if (u.reminder != null)
            _Tile(
              reminder: u.reminder!,
              subtitle: [
                formatRing(u.when),
                repeatSummary(u.reminder!.repeat, u.reminder!.at),
                if (u.reminder!.transactionId != null) 'Linked entry',
              ].join(' · '),
              onTap: () => onOpen(u.reminder!),
            )
          else
            _AutoTile(item: u),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Repeating reminders are scheduled about 30 rings ahead and '
            'topped up each time you open the app. Payment due dates ring '
            'automatically (switch them off on each entry).',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _AutoTile extends StatelessWidget {
  const _AutoTile({required this.item});

  final UpcomingItem item;

  @override
  Widget build(BuildContext context) {
    final p = item.auto!.payload;
    return ListTile(
      leading: const Icon(Icons.payments_outlined),
      title: Text(p.title),
      subtitle: Text('${formatRing(p.at)} · Automatic payment alarm'),
      onTap: p.entryId == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EntryDetailScreen(transactionId: p.entryId!),
              ),
            ),
    );
  }
}

class _CompletedList extends ConsumerWidget {
  const _CompletedList({required this.items, required this.onOpen});

  final List<Reminder> items;
  final void Function(Reminder) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const _Empty(
        icon: Icons.check_circle_outline,
        text: 'Finished reminders appear here',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final r in items)
          _Tile(
            reminder: r,
            icon: Icons.check_circle_outline,
            subtitle: r.doneAt == null
                ? 'Done'
                : 'Done ${formatRing(r.doneAt!)}',
            trailing: TextButton(
              onPressed: () =>
                  ref.read(reminderRepositoryProvider).reopen(r.id),
              child: const Text('Reopen'),
            ),
            onTap: () => onOpen(r),
          ),
      ],
    );
  }
}

class _MissedList extends ConsumerWidget {
  const _MissedList({required this.items, required this.onOpen});

  final List<Reminder> items;
  final void Function(Reminder) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const _Empty(
        icon: Icons.notifications_off_outlined,
        text: 'No missed reminders',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final r in items)
          _Tile(
            reminder: r,
            icon: Icons.alarm_off,
            iconColor: AppColors.pay(context),
            subtitle: 'Was ${formatRing(r.at)} · tap to reschedule',
            subtitleColor: AppColors.pay(context),
            trailing: TextButton(
              onPressed: () =>
                  ref.read(reminderRepositoryProvider).markDone(r.id),
              child: const Text('Mark done'),
            ),
            onTap: () => onOpen(r),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.reminder,
    required this.subtitle,
    required this.onTap,
    this.icon = Icons.alarm,
    this.iconColor,
    this.subtitleColor,
    this.trailing,
  });

  final Reminder reminder;
  final String subtitle;
  final VoidCallback onTap;
  final IconData icon;
  final Color? iconColor;
  final Color? subtitleColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(reminder.title),
      subtitle: Text(
        subtitle,
        style: subtitleColor == null ? null : TextStyle(color: subtitleColor),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
