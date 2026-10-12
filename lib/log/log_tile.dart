import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/log_entry.dart';
import '../core/theme/app_colors.dart';
import '../core/ui/format.dart';
import '../core/ui/swipe_actions.dart';
import 'add_log_screen.dart';

/// One log entry as a row: tap or swipe right to edit, swipe left to delete
/// (with undo). Tasks get a checkbox. [showDate] adds the day to the subtitle
/// for lists that span many days.
class LogTile extends ConsumerWidget {
  const LogTile({super.key, required this.entry, this.showDate = false});

  final LogEntry entry;
  final bool showDate;

  void _edit(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => AddLogScreen(existing: entry)),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(logRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    final e = entry;
    final color = switch (e.kind) {
      LogKind.expense => AppColors.pay(context),
      LogKind.income => AppColors.receive(context),
      _ => scheme.onSurfaceVariant,
    };
    final details = [
      if (showDate) formatShortDate(e.date),
      if (e.account != null) e.account!,
      if (e.place != null) e.place!,
      if (e.category != null) e.category!,
    ].join(' · ');
    final sign = e.kind == LogKind.income ? '+' : '';
    return SwipeActions(
      key: ValueKey('log-${e.id}'),
      right: SwipeAction(
        label: 'Edit',
        icon: Icons.edit,
        color: scheme.primaryContainer,
        onTrigger: () async => _edit(context),
      ),
      left: SwipeAction(
        label: 'Delete',
        icon: Icons.delete,
        color: AppColors.pay(context),
        onTrigger: () async {
          await repo.delete(e.id);
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('Deleted "${e.title}"'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => repo.add(e),
                ),
              ),
            );
        },
      ),
      child: ListTile(
        onTap: () => _edit(context),
        leading: e.kind == LogKind.task
            ? Checkbox(
                value: e.done,
                onChanged: (v) => repo.setDone(e.id, v ?? false),
              )
            : Icon(logKindIcon(e.kind), color: color),
        title: Text(
          e.title,
          style: e.kind == LogKind.task && e.done
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: e.amount == null
            ? null
            : Text(
                '$sign${e.amount!.format()}',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}
