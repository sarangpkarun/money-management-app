import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/money_transaction.dart';
import '../core/models/person.dart';
import '../core/money/money.dart';
import '../people/person_autocomplete_field.dart';
import 'entry_detail_screen.dart';
import 'entry_form_logic.dart';

String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

/// Record money lent (they owe you) or borrowed (you owe them).
class AddEntryScreen extends ConsumerStatefulWidget {
  const AddEntryScreen({super.key, this.initialType = TransactionType.lent});

  final TransactionType initialType;

  @override
  ConsumerState<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends ConsumerState<AddEntryScreen> {
  late TransactionType _type = widget.initialType;
  Person? _person;
  final _amount = TextEditingController();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  DateTime? _dueDate;
  EntryErrors _errors = const EntryErrors();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _notes.dispose();
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
    );
    setState(() => _errors = errors);
    if (errors.hasAny) return;

    setState(() => _busy = true);
    final now = DateTime.now();
    final title = _title.text.trim().isEmpty
        ? (_type == TransactionType.lent ? 'Money lent' : 'Money borrowed')
        : _title.text.trim();
    final id = await ref
        .read(transactionRepositoryProvider)
        .add(
          MoneyTransaction(
            type: _type,
            personId: _person!.id,
            personName: _person!.name,
            title: title,
            totalAmount: Money.parse(_amount.text)!,
            dueDate: _dueDate,
            createdAt: now,
            date: _date,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
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
      appBar: AppBar(title: const Text('Add entry')),
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
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            PersonAutocompleteField(
              errorText: _errors.person,
              onSelected: (p) => setState(() => _person = p),
              onTextChanged: (text) {
                if (_person != null && text.trim() != _person!.name) {
                  setState(() => _person = null);
                }
              },
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await _pick(_date);
                      if (d != null) setState(() => _date = d);
                    },
                    child: Text('Date: ${_fmtDate(_date)}'),
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
                          : 'Due: ${_fmtDate(_dueDate!)}',
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
