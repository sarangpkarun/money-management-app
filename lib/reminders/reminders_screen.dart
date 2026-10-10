import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/reminder.dart';
import '../core/reminders/repeat.dart';
import '../core/theme/app_colors.dart';
import 'alarm_providers.dart';
import 'reminder_form_logic.dart';
import 'reminder_form_screen.dart';
import 'reminder_providers.dart';

/// The user's reminders: active ones by next ring, finished ones below.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  void _open(BuildContext context, [Reminder? r]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReminderFormScreen(existing: r)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(remindersProvider);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add_alarm),
        label: const Text('Add reminder'),
      ),
      body: reminders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load reminders: $e')),
        data: (all) {
          if (all.isEmpty) return const _Empty();
          final perms = ref.watch(alarmPermissionsProvider).value;
          final active = [
            for (final r in all)
              if (!r.done) r,
          ];
          final done = [
            for (final r in all)
              if (r.done) r,
          ];
          // Ones with a coming ring first (soonest first), then passed ones.
          final next = {for (final r in active) r.id: nextOccurrence(r, now)};
          active.sort((a, b) {
            final x = next[a.id];
            final y = next[b.id];
            if (x == null && y == null) return b.at.compareTo(a.at);
            if (x == null) return 1;
            if (y == null) return -1;
            return x.compareTo(y);
          });
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              if (perms != null && !perms.ok)
                MaterialBanner(
                  content: const Text(
                    'Alarms are off. Allow notifications and exact alarms so '
                    'reminders can ring.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(alarmSchedulerProvider)
                            .ensurePermissions();
                        ref.invalidate(alarmPermissionsProvider);
                      },
                      child: const Text('Allow'),
                    ),
                  ],
                ),
              if (active.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nothing coming up'),
                ),
              for (final r in active)
                _Tile(
                  reminder: r,
                  next: next[r.id],
                  onTap: () => _open(context, r),
                ),
              if (done.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 4),
                  child: Text('Done'),
                ),
                for (final r in done)
                  _Tile(
                    reminder: r,
                    next: null,
                    onTap: () => _open(context, r),
                  ),
              ],
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Repeating reminders are scheduled about 30 rings ahead and '
                  'topped up each time you open the app.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.reminder,
    required this.next,
    required this.onTap,
  });

  final Reminder reminder;
  final DateTime? next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final passed = !r.done && next == null;
    final when = r.done
        ? 'Done'
        : passed
        ? 'Passed ${formatRing(r.at)}'
        : formatRing(next!);
    return ListTile(
      leading: Icon(
        r.done ? Icons.check_circle_outline : Icons.alarm,
        color: passed ? AppColors.pay(context) : null,
      ),
      title: Text(r.title),
      subtitle: Text(
        [
          when,
          repeatSummary(r.repeat, r.at),
          if (r.transactionId != null) 'Linked entry',
        ].join(' · '),
        style: passed ? TextStyle(color: AppColors.pay(context)) : null,
      ),
      onTap: onTap,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.alarm,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text('No reminders yet', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
