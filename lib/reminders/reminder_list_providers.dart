import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../people/people_providers.dart';
import '../settings/settings_providers.dart';
import 'reminder_lists.dart';
import 'reminder_providers.dart';

/// The Upcoming / Completed / Missed lists, once reminders have loaded.
final reminderListsProvider = Provider<AsyncValue<ReminderLists>>((ref) {
  final reminders = ref.watch(remindersProvider);
  // Entries only add automatic payment alarms; the lists work without them.
  final entries = ref.watch(allTransactionsProvider).value ?? const [];
  return reminders.whenData(
    (list) => buildReminderLists(
      list,
      entries,
      DateTime.now(),
      settings: ref.watch(appSettingsProvider),
    ),
  );
});
