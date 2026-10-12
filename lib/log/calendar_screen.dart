import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/log_entry.dart';
import '../core/theme/app_colors.dart';
import '../core/ui/empty_state.dart';
import '../core/ui/format.dart';
import 'add_log_screen.dart';
import 'log_list_screen.dart';
import 'log_logic.dart';
import 'log_providers.dart';
import 'log_tile.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December', //
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Month grid of the log: days with entries are marked, tapping a day lists
/// what happened on it, and "+" adds an entry on the selected day.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.today});

  /// Overrides "today" (for tests).
  final DateTime? today;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late final DateTime _today = _d(widget.today ?? DateTime.now());
  late DateTime _month = DateTime(_today.year, _today.month);
  late DateTime _selected = _today;

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  void _go(int delta) {
    final m = DateTime(_month.year, _month.month + delta);
    setState(() {
      _month = m;
      _selected = (m.year == _today.year && m.month == _today.month)
          ? _today
          : m;
    });
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(builder: (_) => AddLogScreen(initialDate: _selected)),
    );
    if (saved != null && mounted) {
      setState(() {
        _selected = saved;
        _month = DateTime(saved.year, saved.month);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(logMonthProvider(_month));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar log'),
        actions: [
          IconButton(
            tooltip: 'All entries and search',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LogListScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'log-add',
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load the log: $e')),
        data: (list) {
          final byDay = groupByDay(list);
          final t = totals(list);
          final dayEntries = byDay[_selected] ?? const <LogEntry>[];
          return Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _go(-1),
                  ),
                  Expanded(
                    child: Text(
                      '${_monthNames[_month.month - 1]} ${_month.year}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _go(1),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      'Spent ${t.spent.format()}',
                      style: TextStyle(
                        color: AppColors.pay(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Received ${t.income.format()}',
                      style: TextStyle(
                        color: AppColors.receive(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _Grid(
                month: _month,
                today: _today,
                selected: _selected,
                byDay: byDay,
                onSelect: (d) => setState(() => _selected = d),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatShortDate(_selected),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
              Expanded(
                child: dayEntries.isEmpty
                    ? EmptyState(
                        icon: Icons.event_note,
                        title: 'Nothing on this day',
                        hint: 'Tap Add to record a spend, note or task.',
                        actionLabel: 'Add entry',
                        onAction: _add,
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 88),
                        children: [
                          for (final e in dayEntries) LogTile(entry: e),
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

class _Grid extends StatelessWidget {
  const _Grid({
    required this.month,
    required this.today,
    required this.selected,
    required this.byDay,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime today;
  final DateTime selected;
  final Map<DateTime, List<LogEntry>> byDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lead = (DateTime(month.year, month.month).weekday + 6) % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _cell(context, r * 7 + c - lead + 1, days)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, int day, int days) {
    if (day < 1 || day > days) return const SizedBox(height: 48);
    final scheme = Theme.of(context).colorScheme;
    final date = DateTime(month.year, month.month, day);
    final items = byDay[date];
    final isSel = date == selected;
    final isToday = date == today;
    return Semantics(
      button: true,
      selected: isSel,
      label:
          '${formatShortDate(date)}'
          '${items == null ? '' : ', ${items.length} '
                    '${items.length == 1 ? 'entry' : 'entries'}'}',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onSelect(date),
          child: Container(
            height: 48,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: isSel ? scheme.primaryContainer : null,
              border: isToday ? Border.all(color: scheme.primary) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$day'),
                const SizedBox(height: 2),
                if (items != null)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
