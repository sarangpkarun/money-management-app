import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/emi/month_dates.dart';
import '../core/instalments/instalment_plan.dart';
import '../core/models/emi_plan.dart';
import '../core/models/person.dart';
import '../core/money/money.dart';
import '../core/ui/format.dart';
import '../people/person_autocomplete_field.dart';
import 'entry_detail_screen.dart';

enum _By { months, monthly }

/// Record money you owe a person and will pay back month by month, with no
/// interest. Give either the number of months or the monthly amount.
class AddInstalmentScreen extends ConsumerStatefulWidget {
  const AddInstalmentScreen({super.key});

  @override
  ConsumerState<AddInstalmentScreen> createState() =>
      _AddInstalmentScreenState();
}

class _AddInstalmentScreenState extends ConsumerState<AddInstalmentScreen> {
  final _title = TextEditingController();
  final _total = TextEditingController();
  final _value = TextEditingController();
  final _notes = TextEditingController();
  Person? _person;
  _By _by = _By.months;
  late DateTime _first = addMonthsClamped(DateTime.now(), 1);

  String? _titleError;
  String? _personError;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _total.dispose();
    _value.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The plan for what is typed, or the reason it cannot be made (null error
  /// and plan while a field is still empty).
  ({EmiPlan? plan, String? error}) _preview() {
    final total = Money.parse(_total.text);
    if (total == null || _value.text.trim().isEmpty) {
      return (plan: null, error: null);
    }
    try {
      if (_by == _By.months) {
        final months = int.tryParse(_value.text.trim());
        if (months == null) return (plan: null, error: 'Enter whole months');
        return (
          plan: generateInstalmentPlan(
            total: total,
            months: months,
            startDate: _first,
          ),
          error: null,
        );
      }
      final monthly = Money.parse(_value.text);
      if (monthly == null) return (plan: null, error: 'Enter a valid amount');
      return (
        plan: generateInstalmentPlan(
          total: total,
          monthlyAmount: monthly,
          startDate: _first,
        ),
        error: null,
      );
    } on InstalmentError catch (e) {
      return (plan: null, error: e.message);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _first,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) setState(() => _first = picked);
  }

  Future<void> _save() async {
    final preview = _preview();
    setState(() {
      _titleError = _title.text.trim().isEmpty
          ? 'Enter what this is for'
          : null;
      _personError = _person == null ? 'Choose or add the person' : null;
    });
    if (_titleError != null || _personError != null || preview.plan == null) {
      return;
    }
    setState(() => _busy = true);
    final total = Money.parse(_total.text)!;
    final id = await ref
        .read(transactionRepositoryProvider)
        .addInstalmentPlan(
          personId: _person!.id,
          personName: _person!.name,
          title: _title.text.trim(),
          total: total,
          months: _by == _By.months ? int.parse(_value.text.trim()) : null,
          monthlyAmount: _by == _By.monthly ? Money.parse(_value.text) : null,
          startDate: _first,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
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
    final preview = _preview();
    final theme = Theme.of(context);
    final plan = preview.plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Pay in instalments')),
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
            PersonAutocompleteField(
              label: 'Person you owe',
              errorText: _personError,
              onSelected: (p) => setState(() => _person = p),
              onTextChanged: (text) {
                if (_person != null && text.trim() != _person!.name) {
                  setState(() => _person = null);
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'What is it for',
                errorText: _titleError,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _total,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Total you owe',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<_By>(
              segments: const [
                ButtonSegment(
                  value: _By.months,
                  label: Text('Number of months'),
                ),
                ButtonSegment(
                  value: _By.monthly,
                  label: Text('Monthly amount'),
                ),
              ],
              selected: {_by},
              onSelectionChanged: (s) => setState(() {
                _by = s.first;
                _value.clear();
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _value,
              keyboardType: _by == _By.months
                  ? TextInputType.number
                  : const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _by == _By.months ? 'Months' : 'Amount each month',
                prefixText: _by == _By.months ? null : '₹ ',
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('First payment on ${formatShortDate(_first)}'),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: plan == null
                    ? Text(
                        preview.error ??
                            'Enter the total and the months or monthly '
                                'amount to see the plan',
                        style: TextStyle(
                          color: preview.error != null
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Monthly', style: theme.textTheme.labelLarge),
                          Text(
                            plan.emi.format(),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('${plan.rows.length} payments'),
                          Text(
                            'Last payment ${formatShortDate(plan.rows.last.dueDate)}',
                          ),
                          if (plan.rows.last.amount != plan.emi)
                            Text(
                              'The last one is ${plan.rows.last.amount.format()}',
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
      ),
    );
  }
}
