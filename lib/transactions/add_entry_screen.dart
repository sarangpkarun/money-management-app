import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ui/format.dart';
import '../core/data/providers.dart';
import '../core/data/transaction_repository.dart';
import '../core/models/money_transaction.dart';
import '../core/models/person.dart';
import '../core/money/money.dart';
import '../people/person_autocomplete_field.dart';
import 'entry_detail_screen.dart';
import 'entry_form_logic.dart';

/// Record money lent (they owe you) or borrowed (you owe them).
class AddEntryScreen extends ConsumerStatefulWidget {
  const AddEntryScreen({
    super.key,
    this.initialType = TransactionType.lent,
    this.initialPerson,
    this.existing,
  });

  final TransactionType initialType;

  /// Pre-selects the person (used from their ledger).
  final Person? initialPerson;

  /// When set, the screen edits this entry instead of creating one.
  final MoneyTransaction? existing;

  @override
  ConsumerState<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends ConsumerState<AddEntryScreen> {
  late TransactionType _type = widget.existing?.type ?? widget.initialType;
  late Person? _person =
      widget.initialPerson ??
      (widget.existing == null
          ? null
          : Person(
              id: widget.existing!.personId,
              name: widget.existing!.personName,
              createdAt: widget.existing!.createdAt,
            ));
  final _amount = TextEditingController();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  DateTime? _dueDate;
  EntryErrors _errors = const EntryErrors();
  InterestType _interestType = InterestType.none;
  RepaymentType _repayment = RepaymentType.flexible;
  final _rate = TextEditingController();

  bool get _borrowed => _type == TransactionType.borrowed;
  InterestType get _effectiveInterest =>
      _borrowed ? _interestType : InterestType.none;
  bool _busy = false;

  bool get _editing => widget.existing != null;

  /// EMI and instalment entries have a generated schedule, so only their
  /// descriptive fields can change.
  bool get _limited =>
      _editing &&
      (_type == TransactionType.emi || _type == TransactionType.instalment);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e == null) return;
    _amount.text = e.totalAmount.paise % 100 == 0
        ? '${e.totalAmount.paise ~/ 100}'
        : (e.totalAmount.paise / 100).toStringAsFixed(2);
    _title.text = e.title;
    _notes.text = e.notes ?? '';
    _date = e.entryDate;
    _dueDate = e.dueDate;
    _interestType = e.interestType;
    _repayment = e.repaymentType;
    if (e.interestRate != null) _rate.text = '${e.interestRate}';
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _notes.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial, {DateTime? first}) =>
      showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: first ?? DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 365 * 20)),
      );

  Future<void> _save() async {
    final errors = validateEntry(
      hasPerson: _person != null,
      amountText: _amount.text,
      date: _date,
      dueDate: _dueDate,
      interestType: _effectiveInterest,
      rateText: _rate.text,
    );
    setState(() => _errors = errors);
    if (errors.hasAny) return;

    setState(() => _busy = true);
    final now = DateTime.now();
    final title = _title.text.trim().isEmpty
        ? (_type == TransactionType.lent ? 'Money lent' : 'Money borrowed')
        : _title.text.trim();
    final repo = ref.read(transactionRepositoryProvider);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final existing = widget.existing;
    if (existing != null) {
      try {
        await repo.update(
          existing.id,
          title: _title.text.trim().isEmpty
              ? existing.title
              : _title.text.trim(),
          notes: notes,
          dueDate: _dueDate,
          clearDueDate: _dueDate == null,
          date: _date,
          totalAmount: _limited ? null : Money.parse(_amount.text)!,
          personId: _limited ? null : _person!.id,
          personName: _limited ? null : _person!.name,
          interestType: _limited ? null : _effectiveInterest,
          interestRate: _limited || _effectiveInterest == InterestType.none
              ? null
              : double.parse(_rate.text.trim()),
          repaymentType: _limited
              ? null
              : (_borrowed ? _repayment : RepaymentType.flexible),
        );
      } on EntryEditError catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _errors = EntryErrors(amount: e.message);
        });
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    final id = await repo.add(
      MoneyTransaction(
        type: _type,
        personId: _person!.id,
        personName: _person!.name,
        title: title,
        totalAmount: Money.parse(_amount.text)!,
        dueDate: _dueDate,
        interestType: _effectiveInterest,
        interestRate: _effectiveInterest == InterestType.none
            ? null
            : double.parse(_rate.text.trim()),
        repaymentType: _borrowed ? _repayment : RepaymentType.flexible,
        createdAt: now,
        date: _date,
        notes: notes,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EntryDetailScreen(transactionId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit entry' : 'Add entry')),
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
            if (!_limited)
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.lent,
                    label: Text('Lent'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                  ButtonSegment(
                    value: TransactionType.borrowed,
                    label: Text('Borrowed'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: _editing
                    ? null
                    : (s) => setState(() => _type = s.first),
              ),
            if (!_limited) const SizedBox(height: 16),
            if (!_limited)
              PersonAutocompleteField(
                initialPerson: widget.initialPerson ?? _person,
                errorText: _errors.person,
                onSelected: (p) => setState(() => _person = p),
                onTextChanged: (text) {
                  if (_person != null && text.trim() != _person!.name) {
                    setState(() => _person = null);
                  }
                },
              ),
            if (!_limited) const SizedBox(height: 16),
            if (!_limited)
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: Theme.of(context).textTheme.headlineMedium,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  errorText: _errors.amount,
                ),
              ),
            if (!_limited) const SizedBox(height: 16),
            if (_borrowed && !_limited) ...[
              Text('Interest', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<InterestType>(
                segments: [
                  for (final t in InterestType.values)
                    ButtonSegment(value: t, label: Text(interestTypeLabel(t))),
                ],
                selected: {_interestType},
                onSelectionChanged: (s) =>
                    setState(() => _interestType = s.first),
              ),
              if (_interestType != InterestType.none) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Interest rate (% per year)',
                    suffixText: '%',
                    errorText: _errors.rate,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('Repayment', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final r in RepaymentType.values)
                    ChoiceChip(
                      label: Text(repaymentLabel(r)),
                      selected: _repayment == r,
                      onSelected: (_) => setState(() => _repayment = r),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await _pick(_date);
                      if (d != null) setState(() => _date = d);
                    },
                    child: Text('Date: ${formatShortDate(_date)}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await _pick(_dueDate ?? _date, first: _date);
                      if (d != null) setState(() => _dueDate = d);
                    },
                    child: Text(
                      _dueDate == null
                          ? 'Due date (optional)'
                          : 'Due: ${formatShortDate(_dueDate!)}',
                    ),
                  ),
                ),
                if (_dueDate != null)
                  IconButton(
                    tooltip: 'Clear due date',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _dueDate = null),
                  ),
              ],
            ),
            if (_errors.dueDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _errors.dueDate!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reason or item (optional)',
              ),
            ),
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
