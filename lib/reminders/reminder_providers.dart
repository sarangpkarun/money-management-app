import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/reminder.dart';

final remindersProvider = StreamProvider<List<Reminder>>(
  (ref) => ref.watch(reminderRepositoryProvider).watch(),
);

final reminderProvider = StreamProvider.family<Reminder?, String>(
  (ref, id) => ref.watch(reminderRepositoryProvider).watchOne(id),
);
