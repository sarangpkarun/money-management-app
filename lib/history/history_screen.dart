import '../core/ui/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/money_transaction.dart';
import '../core/money/money.dart';
import '../core/status/transaction_status.dart';
import '../core/ui/format.dart';
import '../core/ui/initials_avatar.dart';
import '../people/people_providers.dart';
import '../transactions/entry_detail_screen.dart';
import '../transactions/status_badge.dart';
import 'history_filter.dart';

/// Settled entries. Entries land here by themselves when they are fully paid
/// and leave again if they are marked as unpaid.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  HistoryFilter _filter = const HistoryFilter();

  /// Filters other than search and type (those have their own controls).
  bool get _hasSheetFilters =>
      _filter.personId != null ||
      _filter.from != null ||
      _filter.to != null ||
      _filter.minAmount != null ||
      _filter.maxAmount != null;

  void _toggleType(TransactionType type) {
    final types = {..._filter.types};
    types.contains(type) ? types.remove(type) : types.add(type);
    setState(() => _filter = _filter.copyWith(types: types));
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<HistoryFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(initial: _filter),
    );
    if (result != null) setState(() => _filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(allTransactionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            tooltip: 'Filters',
            icon: Badge(
              isLabelVisible: _hasSheetFilters,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _openFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search person or reason',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) =>
                  setState(() => _filter = _filter.copyWith(query: v)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final (type, label) in [
                  (TransactionType.lent, 'Lent'),
                  (TransactionType.borrowed, 'Borrowed'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(label),
                      selected: _filter.types.contains(type),
                      onSelected: (_) => _toggleType(type),
                    ),
                  ),
                const Spacer(),
                if (_filter.isActive)
                  TextButton(
                    onPressed: () =>
                        setState(() => _filter = const HistoryFilter()),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: entries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Could not load history: $e')),
              data: (all) {
                final anySettled = all.any(
                  (t) => t.status == TransactionStatus.paid,
                );
                if (!anySettled) {
                  return const EmptyState(
                    icon: Icons.history,
                    title: 'No settled entries yet',
                    hint: 'Entries move here once they are fully paid.',
                  );
                }
                final shown = applyHistoryFilter(all, _filter);
                if (shown.isEmpty) {
                  return const EmptyState(
                    icon: Icons.search_off,
                    title: 'No matching entries',
                    hint: 'Try different filters or search words.',
                  );
                }
                return ListView.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _HistoryRow(entry: shown[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final MoneyTransaction entry;

  @override
  Widget build(BuildContext context) {
    final settled = entry.settledAt ?? entry.lastActivity;
    return ListTile(
      leading: InitialsAvatar(name: entry.personName),
      title: Text('${entry.personName} · ${entry.title}'),
      subtitle: Text(
        '${entry.isReceivable ? 'Received' : 'Paid'} '
        '${entry.paidTotal.format()} · settled ${formatShortDate(settled)}',
      ),
      trailing: const StatusBadge(status: TransactionStatus.paid),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EntryDetailScreen(transactionId: entry.id),
        ),
      ),
    );
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});

  final HistoryFilter initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late String? _personId = widget.initial.personId;
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;
  late final _min = TextEditingController(
    text: _plain(widget.initial.minAmount),
  );
  late final _max = TextEditingController(
    text: _plain(widget.initial.maxAmount),
  );
  String? _amountError;

  static String _plain(Money? m) {
    if (m == null) return '';
    final paise = m.paise % 100;
    return paise == 0
        ? '${m.paise ~/ 100}'
        : '${m.paise ~/ 100}.${paise.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: (_from != null && _to != null)
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
    }
  }

  void _apply() {
    Money? parse(String text) => text.trim().isEmpty ? null : Money.parse(text);
    final min = parse(_min.text);
    final max = parse(_max.text);
    final bad =
        (_min.text.trim().isNotEmpty && min == null) ||
        (_max.text.trim().isNotEmpty && max == null);
    if (bad) {
      setState(() => _amountError = 'Enter valid amounts');
      return;
    }
    if (min != null && max != null && min > max) {
      setState(() => _amountError = 'Minimum is above the maximum');
      return;
    }
    Navigator.of(context).pop(
      HistoryFilter(
        types: widget.initial.types,
        query: widget.initial.query,
        personId: _personId,
        from: _from,
        to: _to,
        minAmount: min,
        maxAmount: max,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleProvider).value ?? const [];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filters', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: people.any((p) => p.id == _personId)
                  ? _personId
                  : null,
              decoration: const InputDecoration(labelText: 'Person'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Anyone')),
                for (final p in people)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _personId = v),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range),
              label: Text(
                (_from == null || _to == null)
                    ? 'Settled between...'
                    : '${formatShortDate(_from!)} - ${formatShortDate(_to!)}',
              ),
            ),
            if (_from != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _from = null;
                    _to = null;
                  }),
                  child: const Text('Clear dates'),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _min,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Min amount',
                      prefixText: '₹ ',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _max,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Max amount',
                      prefixText: '₹ ',
                      errorText: _amountError,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _apply, child: const Text('Apply filters')),
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                HistoryFilter(
                  types: widget.initial.types,
                  query: widget.initial.query,
                ),
              ),
              child: const Text('Clear filters'),
            ),
          ],
        ),
      ),
    );
  }
}
