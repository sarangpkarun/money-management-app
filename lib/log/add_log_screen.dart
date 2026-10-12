import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/log_entry.dart';
import '../core/money/money.dart';
import '../core/ui/format.dart';
import 'log_logic.dart';
import 'log_providers.dart';

String logKindLabel(LogKind k) => switch (k) {
  LogKind.expense => 'Spent',
  LogKind.income => 'Received',
  LogKind.note => 'Note',
  LogKind.task => 'Task',
};

IconData logKindIcon(LogKind k) => switch (k) {
  LogKind.expense => Icons.arrow_upward,
  LogKind.income => Icons.arrow_downward,
  LogKind.note => Icons.notes,
  LogKind.task => Icons.check_circle_outline,
};

/// Add or edit a calendar log entry: what, how much, on which day, paid with
/// what and where. Works for spending, income, notes and tasks alike.
class AddLogScreen extends ConsumerStatefulWidget {
  const AddLogScreen({super.key, this.initialDate, this.existing});

  /// The day to start on when adding (e.g. the day picked on the calendar).
  final DateTime? initialDate;

  /// When set, the screen edits this entry instead of creating one.
  final LogEntry? existing;

  @override
  ConsumerState<AddLogScreen> createState() => _AddLogScreenState();
}

class _AddLogScreenState extends ConsumerState<AddLogScreen> {
  late LogKind _kind = widget.existing?.kind ?? LogKind.expense;
  late DateTime _date =
      widget.existing?.date ?? widget.initialDate ?? DateTime.now();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _account = TextEditingController();
  final _category = TextEditingController();
  final _place = TextEditingController();
  final _notes = TextEditingController();
  String? _error;
  bool _busy = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e == null) return;
    _title.text = e.title;
    _amount.text = e.amount == null ? '' : plainAmount(e.amount!);
    _account.text = e.account ?? '';
    _category.text = e.category ?? '';
    _place.text = e.place ?? '';
    _notes.text = e.notes ?? '';
  }

  @override
  void dispose() {
    for (final c in [_title, _amount, _account, _category, _place, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    final error = validateLog(
      title: _title.text,
      kind: _kind,
      amountText: _amount.text,
    );
    setState(() => _error = error);
    if (error != null) return;
    setState(() => _busy = true);
    final old = widget.existing;
    final amountText = _amount.text.trim();
    final entry = LogEntry(
      id: old?.id ?? '',
      date: _date,
      title: _title.text.trim(),
      kind: _kind,
      amount: amountText.isEmpty ? null : Money.parse(amountText),
      account: _opt(_account),
      category: _opt(_category),
      place: _opt(_place),
      notes: _opt(_notes),
      personId: old?.personId,
      personName: old?.personName,
      done: old?.done ?? false,
      createdAt: old?.createdAt ?? DateTime.now(),
    );
    final repo = ref.read(logRepositoryProvider);
    if (_editing) {
      await repo.update(entry);
    } else {
      await repo.add(entry);
    }
    if (!mounted) return;
    Navigator.of(context).pop(DateTime(_date.year, _date.month, _date.day));
  }

  Widget _chips(
    List<String> options,
    TextEditingController controller,
    String label,
  ) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        children: [
          for (final o in options.take(8))
            ChoiceChip(
              label: Text(o),
              selected: controller.text.trim().toLowerCase() == o.toLowerCase(),
              onSelected: (on) => setState(() => controller.text = on ? o : ''),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final past = ref.watch(allLogProvider).value ?? const <LogEntry>[];
    final accounts = suggestions(past.map((e) => e.account));
    final categories = suggestions(past.map((e) => e.category));
    final money = _kind == LogKind.expense || _kind == LogKind.income;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit log entry' : 'Add to log')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving...' : 'Save'),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<LogKind>(
              segments: [
                for (final k in LogKind.values)
                  ButtonSegment(
                    value: k,
                    label: Text(logKindLabel(k)),
                    icon: Icon(logKindIcon(k)),
                  ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text('Date: ${formatShortDate(_date)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 20)),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _kind == LogKind.expense
                    ? 'What was it for?'
                    : 'Title',
              ),
            ),
            if (money) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: Theme.of(context).textTheme.headlineMedium,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _account,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: _kind == LogKind.income
                    ? 'Received in (optional)'
                    : 'Paid with (optional)',
                hintText: 'e.g. HDFC Credit Card, Cash, UPI',
              ),
            ),
            _chips(accounts, _account, 'account'),
            const SizedBox(height: 16),
            TextField(
              controller: _place,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Where / paid to (optional)',
                hintText: 'e.g. Amazon, Big Bazaar',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _category,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                hintText: 'e.g. Food, Fuel, Bills',
              ),
            ),
            _chips(categories, _category, 'category'),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
      ),
    );
  }
}
