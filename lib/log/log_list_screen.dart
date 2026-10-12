import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/log_entry.dart';
import '../core/ui/empty_state.dart';
import '../core/ui/format.dart';
import 'add_log_screen.dart';
import 'log_logic.dart';
import 'log_providers.dart';
import 'log_tile.dart';

/// Every log entry, newest first, with search and filters, so "where did I
/// pay for that?" is a quick lookup. Totals reflect the current filter.
class LogListScreen extends ConsumerStatefulWidget {
  const LogListScreen({super.key});

  @override
  ConsumerState<LogListScreen> createState() => _LogListScreenState();
}

class _LogListScreenState extends ConsumerState<LogListScreen> {
  LogFilter _filter = const LogFilter();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _set({
    String? query,
    Object? kind = _keep,
    Object? account = _keep,
    Object? category = _keep,
    Object? from = _keep,
    Object? to = _keep,
  }) {
    final f = _filter;
    setState(
      () => _filter = LogFilter(
        query: query ?? f.query,
        kind: identical(kind, _keep) ? f.kind : kind as LogKind?,
        account: identical(account, _keep) ? f.account : account as String?,
        category: identical(category, _keep) ? f.category : category as String?,
        from: identical(from, _keep) ? f.from : from as DateTime?,
        to: identical(to, _keep) ? f.to : to as DateTime?,
      ),
    );
  }

  static const _keep = Object();

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 20)),
      initialDateRange: _filter.from != null && _filter.to != null
          ? DateTimeRange(start: _filter.from!, end: _filter.to!)
          : null,
    );
    if (r != null) _set(from: r.start, to: r.end);
  }

  Future<void> _pickFrom(
    String title,
    List<String> options,
    void Function(String?) onPick,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(title, style: Theme.of(c).textTheme.titleMedium),
            ),
            ListTile(
              title: const Text('Any'),
              onTap: () => Navigator.pop(c, ''),
            ),
            for (final o in options)
              ListTile(title: Text(o), onTap: () => Navigator.pop(c, o)),
          ],
        ),
      ),
    );
    if (choice != null) onPick(choice.isEmpty ? null : choice);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(allLogProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('All log entries')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'log-list-add',
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const AddLogScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load the log: $e')),
        data: (list) {
          final shown = _filter.apply(list);
          final t = totals(shown);
          final accounts = suggestions(list.map((e) => e.account));
          final categories = suggestions(list.map((e) => e.category));
          final byAccount = spentByAccount(shown);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: _search,
                  onChanged: (q) => _set(query: q),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search title, place, notes…',
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final k in LogKind.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(logKindLabel(k)),
                          selected: _filter.kind == k,
                          onSelected: (on) => _set(kind: on ? k : null),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: const Icon(
                          Icons.account_balance_wallet,
                          size: 18,
                        ),
                        label: Text(_filter.account ?? 'Account'),
                        onPressed: () => _pickFrom(
                          'Paid with',
                          accounts,
                          (v) => _set(account: v),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: const Icon(Icons.sell, size: 18),
                        label: Text(_filter.category ?? 'Category'),
                        onPressed: () => _pickFrom(
                          'Category',
                          categories,
                          (v) => _set(category: v),
                        ),
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        _filter.from == null
                            ? 'Dates'
                            : '${formatShortDate(_filter.from!)} – '
                                  '${formatShortDate(_filter.to!)}',
                      ),
                      onPressed: _pickRange,
                    ),
                  ],
                ),
              ),
              if (_filter.isActive)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      _search.clear();
                      setState(() => _filter = const LogFilter());
                    },
                    child: const Text('Clear filters'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Spent ${t.spent.format()} · Received ${t.income.format()}'
                  '${byAccount.isEmpty ? '' : '\n${byAccount.entries.take(4).map((e) => '${e.key}: ${e.value.format()}').join(' · ')}'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: list.isEmpty
                            ? 'No log entries yet'
                            : 'No entries match',
                        hint: list.isEmpty
                            ? 'Record where you spent, notes or tasks by date.'
                            : 'Try clearing a filter.',
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 88),
                        children: [
                          for (final e in shown)
                            LogTile(entry: e, showDate: true),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
