import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/emi/emi_schedule.dart';
import '../core/emi/month_dates.dart';
import '../core/models/person.dart';
import '../core/money/money.dart';
import '../core/ui/format.dart';
import '../people/person_autocomplete_field.dart';
import 'entry_detail_screen.dart';

/// Record something bought on EMI: a live preview of the monthly amount and the
/// total cost updates as the terms are typed.
class AddEmiScreen extends ConsumerStatefulWidget {
  const AddEmiScreen({super.key});

  @override
  ConsumerState<AddEmiScreen> createState() => _AddEmiScreenState();
}

class _AddEmiScreenState extends ConsumerState<AddEmiScreen> {
  final _product = TextEditingController();
  final _price = TextEditingController();
  final _down = TextEditingController();
  final _rate = TextEditingController(text: '0');
  final _months = TextEditingController();
  final _notes = TextEditingController();
  Person? _store;
  late DateTime _firstEmi = addMonthsClamped(DateTime.now(), 1);

  String? _productError;
  String? _storeError;
  bool _busy = false;

  @override
  void dispose() {
    _product.dispose();
    _price.dispose();
    _down.dispose();
    _rate.dispose();
    _months.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Parsed terms, or null when a field is not filled in yet.
  ({Money price, Money down, double rate, int months})? _terms() {
    final price = Money.parse(_price.text);
    final down = _down.text.trim().isEmpty
        ? Money.zero
        : Money.parse(_down.text);
    final rate = double.tryParse(_rate.text.trim());
    final months = int.tryParse(_months.text.trim());
    if (price == null || down == null || rate == null || months == null) {
      return null;
    }
    return (price: price, down: down, rate: rate, months: months);
  }

  /// The schedule for what is typed, or the reason it cannot be made.
  ({EmiSchedule? schedule, String? error}) _preview() {
    final t = _terms();
    if (t == null) return (schedule: null, error: null);
    try {
      return (
        schedule: generateEmiSchedule(
          price: t.price,
          downPayment: t.down,
          annualRatePercent: t.rate,
          months: t.months,
          startDate: _firstEmi,
        ),
        error: null,
      );
    } on EmiInputError catch (e) {
      return (schedule: null, error: e.message);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstEmi,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) setState(() => _firstEmi = picked);
  }

  Future<void> _save() async {
    final t = _terms();
    final preview = _preview();
    setState(() {
      _productError = _product.text.trim().isEmpty
          ? 'Enter what you bought'
          : null;
      _storeError = _store == null ? 'Choose or add the store or bank' : null;
    });
    if (_productError != null ||
        _storeError != null ||
        t == null ||
        preview.schedule == null) {
      return;
    }
    setState(() => _busy = true);
    final id = await ref
        .read(transactionRepositoryProvider)
        .addEmi(
          personId: _store!.id,
          personName: _store!.name,
          title: _product.text.trim(),
          price: t.price,
          downPayment: t.down,
          annualRatePercent: t.rate,
          months: t.months,
          startDate: _firstEmi,
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
    return Scaffold(
      appBar: AppBar(title: const Text('EMI purchase')),
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
            TextField(
              controller: _product,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Product',
                errorText: _productError,
              ),
            ),
            const SizedBox(height: 16),
            PersonAutocompleteField(
              label: 'Store or bank',
              errorText: _storeError,
              onSelected: (p) => setState(() => _store = p),
              onTextChanged: (text) {
                if (_store != null && text.trim() != _store!.name) {
                  setState(() => _store = null);
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Total price',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _down,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Down payment (optional)',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rate,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Interest (% a year)',
                      helperText: '0 for a no-cost EMI',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _months,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Months'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('First EMI on ${formatShortDate(_firstEmi)}'),
            ),
            const SizedBox(height: 16),
            _PreviewCard(
              schedule: preview.schedule,
              error: preview.error,
              hasTerms: _terms() != null,
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

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.schedule,
    required this.error,
    required this.hasTerms,
  });

  final EmiSchedule? schedule;
  final String? error;
  final bool hasTerms;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = schedule;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: s == null
            ? Text(
                error ??
                    (hasTerms
                        ? ''
                        : 'Enter the price, interest and months to see the EMI'),
                style: TextStyle(
                  color: error != null
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monthly EMI', style: theme.textTheme.labelLarge),
                  Text(
                    s.emi.format(),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _row('Total interest', s.totalInterest.format()),
                  _row('Total payable', s.totalPayable.format()),
                  _row('Last EMI', formatShortDate(s.lastInstallment.dueDate)),
                ],
              ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
