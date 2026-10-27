import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/trip.dart';
import '../core/models/trip_expense.dart';
import '../core/money/money.dart';
import '../core/ui/format.dart';
import 'split_logic.dart';
import 'trip_providers.dart';

/// Add or edit an expense: what, how much, who paid, and how it is shared.
/// The split can be changed any time by editing the expense again.
class TripExpenseFormScreen extends ConsumerStatefulWidget {
  const TripExpenseFormScreen({super.key, required this.trip, this.existing});

  final Trip trip;
  final TripExpense? existing;

  @override
  ConsumerState<TripExpenseFormScreen> createState() =>
      _TripExpenseFormScreenState();
}

class _TripExpenseFormScreenState extends ConsumerState<TripExpenseFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : plainAmount(widget.existing!.amount),
  );
  late final _category = TextEditingController(text: widget.existing?.category);
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late SplitMode _mode = widget.existing?.mode ?? SplitMode.equal;
  String? _paidBy;
  String? _stopId;
  String? _error;
  bool _busy = false;

  /// Who is part of the split, and the typed amount or percent for each.
  late final Set<String> _selected;
  final Map<String, TextEditingController> _inputs = {};

  bool get _editing => widget.existing != null;
  List<TripMember> get _members => widget.trip.members;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final me = ref.read(emailProvider);
    _paidBy =
        e?.paidBy ??
        (widget.trip.memberByEmail(me) != null
            ? me
            : _members.first.email.toLowerCase());
    _stopId = e?.stopId;
    _selected = e == null
        ? {for (final m in _members) m.email.toLowerCase()}
        : e.shares.keys.toSet();
    for (final m in _members) {
      final key = m.email.toLowerCase();
      var text = '';
      if (e != null && e.mode == SplitMode.exact && e.shares[key] != null) {
        text = plainAmount(Money(e.shares[key]!));
      } else if (e != null &&
          e.mode == SplitMode.percent &&
          e.percentBp?[key] != null) {
        text = _bpText(e.percentBp![key]!);
      }
      _inputs[key] = TextEditingController(text: text)
        ..addListener(() => setState(() {}));
    }
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _category.dispose();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _bpText(int bp) =>
      bp % 100 == 0 ? '${bp ~/ 100}' : (bp / 100).toStringAsFixed(2);

  int? _bpOf(String text) {
    final v = double.tryParse(text.trim());
    return v == null || v < 0 ? null : (v * 100).round();
  }

  Money? get _total => Money.parse(_amount.text);

  /// The people in the split, in member order.
  List<String> get _participants => [
    for (final m in _members)
      if (_selected.contains(m.email.toLowerCase())) m.email.toLowerCase(),
    // Someone since removed from the trip but still in this expense.
    for (final k in _selected)
      if (!_members.any((m) => m.email.toLowerCase() == k)) k,
  ];

  /// The resolved shares, or null with [_problem] explaining why not.
  Map<String, int>? _resolve() {
    final total = _total;
    final people = _participants;
    if (total == null || total.paise <= 0) return null;
    if (people.isEmpty) return null;
    switch (_mode) {
      case SplitMode.equal:
        return equalSplit(total.paise, people);
      case SplitMode.exact:
        final shares = <String, int>{};
        for (final p in people) {
          final m = Money.parse(_inputs[p]?.text ?? '');
          if (m == null) return null;
          shares[p] = m.paise;
        }
        return exactSplitValid(total.paise, shares) ? shares : null;
      case SplitMode.percent:
        final bp = _percentInputs();
        return bp == null ? null : percentSplit(total.paise, bp);
    }
  }

  Map<String, int>? _percentInputs() {
    final bp = <String, int>{};
    for (final p in _participants) {
      final v = _bpOf(_inputs[p]?.text ?? '');
      if (v == null) return null;
      bp[p] = v;
    }
    return bp;
  }

  /// A one-line status under the split: what is left to assign, or null if
  /// the split is complete.
  String? _problem() {
    final total = _total;
    if (total == null || total.paise <= 0) return null;
    if (_participants.isEmpty) return 'Pick at least one person';
    if (_mode == SplitMode.exact) {
      var sum = 0;
      for (final p in _participants) {
        sum += Money.parse(_inputs[p]?.text ?? '')?.paise ?? 0;
      }
      final diff = total.paise - sum;
      if (diff == 0) return null;
      return diff > 0
          ? '${Money(diff).format()} left to assign'
          : '${Money(-diff).format()} over the total';
    }
    if (_mode == SplitMode.percent) {
      var sum = 0;
      for (final p in _participants) {
        sum += _bpOf(_inputs[p]?.text ?? '') ?? 0;
      }
      if (sum == 10000) return null;
      final diff = (10000 - sum) / 100;
      return diff > 0
          ? '${diff.toStringAsFixed(2)}% left to assign'
          : '${(-diff).toStringAsFixed(2)}% over 100%';
    }
    return null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final shares = _resolve();
    if (shares == null) {
      setState(() => _error = _problem() ?? 'Check the split');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final cat = _category.text.trim();
    final expense = TripExpense(
      id: widget.existing?.id ?? '',
      title: _title.text.trim(),
      amount: _total!,
      paidBy: _paidBy!,
      date: _date,
      category: cat.isEmpty ? null : cat,
      stopId: _stopId,
      mode: _mode,
      shares: shares,
      percentBp: _mode == SplitMode.percent ? _percentInputs() : null,
      createdBy: widget.existing?.createdBy ?? ref.read(emailProvider),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    final repo = ref.read(tripRepositoryProvider);
    try {
      if (_editing) {
        await repo.updateExpense(widget.trip.id, expense);
      } else {
        await repo.addExpense(widget.trip.id, expense);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(emailProvider);
    final stops =
        ref.watch(tripStopsProvider(widget.trip.id)).value ?? const [];
    final shares = _resolve();
    final problem = _problem();
    final scheme = Theme.of(context).colorScheme;
    final payerKeys = {
      for (final m in _members) m.email.toLowerCase(),
      ?_paidBy,
    };
    String nameOf(String key) {
      final m = widget.trip.memberByEmail(key);
      final base = m?.name ?? key;
      return key == me ? '$base (you)' : base;
    }

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit expense' : 'Add expense')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What',
                  hintText: 'Hotel, Fuel, Dinner...',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '${MoneyFormat.symbol} ',
                ),
                validator: (v) {
                  final m = Money.parse(v ?? '');
                  return m == null || m.paise <= 0 ? 'Enter an amount' : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _paidBy,
                decoration: const InputDecoration(labelText: 'Paid by'),
                items: [
                  for (final k in payerKeys)
                    DropdownMenuItem(value: k, child: Text(nameOf(k))),
                ],
                onChanged: (v) => setState(() => _paidBy = v),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text(formatShortDate(_date)),
              ),
              if (stops.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: stops.any((s) => s.id == _stopId)
                      ? _stopId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Roadmap stop (optional)',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final s in stops)
                      DropdownMenuItem(value: s.id, child: Text(s.title)),
                  ],
                  onChanged: (v) => setState(() => _stopId = v),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _category,
                decoration: const InputDecoration(
                  labelText: 'Category (optional)',
                ),
              ),
              const SizedBox(height: 24),
              Text('Split', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<SplitMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: SplitMode.equal, label: Text('Equal')),
                  ButtonSegment(value: SplitMode.exact, label: Text('Exact')),
                  ButtonSegment(value: SplitMode.percent, label: Text('%')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 8),
              for (final key in {
                for (final m in _members) m.email.toLowerCase(),
                ..._selected,
              })
                _SplitRow(
                  label: nameOf(key),
                  selected: _selected.contains(key),
                  mode: _mode,
                  controller: _inputs.putIfAbsent(
                    key,
                    () =>
                        TextEditingController()
                          ..addListener(() => setState(() {})),
                  ),
                  equalShare: shares?[key],
                  onChanged: (v) => setState(() {
                    if (v) {
                      _selected.add(key);
                    } else {
                      _selected.remove(key);
                    }
                  }),
                ),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(problem, style: TextStyle(color: scheme.error)),
                ),
              if (_error != null && _error != problem)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.label,
    required this.selected,
    required this.mode,
    required this.controller,
    required this.equalShare,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final SplitMode mode;
  final TextEditingController controller;
  final int? equalShare;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(value: selected, onChanged: (v) => onChanged(v ?? false)),
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (selected && mode == SplitMode.equal && equalShare != null)
          Text(Money(equalShare!).format())
        else if (selected && mode != SplitMode.equal)
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.end,
              decoration: InputDecoration(
                isDense: true,
                suffixText: mode == SplitMode.percent ? '%' : null,
                prefixText: mode == SplitMode.exact
                    ? '${MoneyFormat.symbol} '
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
