import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/log_entry.dart';

/// Entries for one month (pass any date in it; only year and month matter).
final logMonthProvider = StreamProvider.autoDispose
    .family<List<LogEntry>, DateTime>(
      (ref, month) => ref
          .watch(logRepositoryProvider)
          .watchMonth(DateTime(month.year, month.month)),
    );

final allLogProvider = StreamProvider.autoDispose<List<LogEntry>>(
  (ref) => ref.watch(logRepositoryProvider).watchAll(),
);
