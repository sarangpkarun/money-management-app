import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/emi/emi_schedule.dart';
import '../core/emi/month_dates.dart';
import '../core/models/emi_plan.dart';
import '../core/models/person.dart';
import '../core/money/money.dart';
import '../core/ui/format.dart';
import '../people/person_autocomplete_field.dart';
import 'entry_detail_screen.dart';

enum _Fee { none, flat, percent }

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
  final _lender = TextEditingController();
  final _feeValue = TextEditingController();
  final _grace = TextEditingController();
  bool _noCost = false;
  bool _triedSave = false;
  _Fee _fee = _Fee.none;
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
    _lender.dispose();
    _feeValue.dispose();
    _grace.dispose();
    super.dispose();
  }

  /// Parsed terms, or null when a field is not filled in yet.
  ({Money price, Money down, double rate, int months})? _terms() {
    final price = Money.parse(_price.text);
    final down = _down.text.trim().isEmpty
        ? Money.zero
        : Money.parse(_down.text);
    final rate = _noCost ? 0.0 : double.tryParse(_rate.text.trim());
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

  /// The lender's rate for a no-cost EMI, or null while it is not valid.
  double? _lenderRate() {
    final v = double.tryParse(_lender.text.trim());
    return v != null && v > 0 && v <= 100 ? v : null;
  }

  /// The late fee typed in: (rule, error). No rule and no error when off.
  ({LateFeeRule? rule, String? error}) _lateFee() {
    if (_fee == _Fee.none) return (rule: null, error: null);
    final graceText = _grace.text.trim();
    final grace = graceText.isEmpty ? 0 : int.tryParse(graceText);
    if (grace == null || grace < 0) {
      return (rule: null, error: 'Grace days must be 0 or more');
    }
    if (_fee == _Fee.flat) {
      final amount = Money.parse(_feeValue.text);
      if (amount == null || amount <= Money.zero) {
        return (rule: null, error: 'Enter the late fee amount');
      }
      return (rule: LateFeeRule.flat(amount, graceDays: grace), error: null);
    }
    final pct = double.tryParse(_feeValue.text.trim());
    if (pct == null || pct <= 0 || pct > 100) {
      return (rule: null, error: 'Late fee must be between 0 and 100 percent');
    }
    return (rule: LateFeeRule.percent(pct, graceDays: grace), error: null);
  }

  /// Interest the seller absorbs on a no-cost EMI, or null.
  Money? _sellerAbsorbs() {
    final t = _terms();
    final lender = _lenderRate();
    if (!_noCost || t == null || lender == null) return null;
    try {
      return generateEmiSchedule(
        price: t.price,
        downPayment: t.down,
        annualRatePercent: lender,
        months: t.months,
        startDate: _firstEmi,
      ).totalInterest;
    } on EmiInputError {
      return null;
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
    _triedSave = true;
    final fee = _lateFee();
    if (_productError != null ||
        _storeError != null ||
        t == null ||
        preview.schedule == null ||
        fee.error != null ||
        (_noCost && _lenderRate() == null)) {
      setState(() {});
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
          lateFee: fee.rule,
          noCostRate: _noCost ? _lenderRate() : null,
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
                  child: _noCost
                      ? TextField(
                          controller: _lender,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: "Lender's rate (% a year)",
                            errorText:
                                (_triedSave || _lender.text.isNotEmpty) &&
                                    _lenderRate() == null
                                ? 'Enter a rate above 0 and up to 100'
                                : null,
                          ),
                        )
                      : TextField(
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('No-cost EMI'),
              subtitle: const Text(
                'You pay no interest; the seller absorbs it',
              ),
              value: _noCost,
              onChanged: (v) => setState(() => _noCost = v),
            ),
            const SizedBox(height: 8),
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
              sellerAbsorbs: _sellerAbsorbs(),
            ),
            const SizedBox(height: 16),
            Text(
              'Late fee (estimate)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<_Fee>(
              segments: const [
                ButtonSegment(value: _Fee.none, label: Text('None')),
                ButtonSegment(value: _Fee.flat, label: Text('Flat ₹')),
                ButtonSegment(value: _Fee.percent, label: Text('Percent')),
              ],
              selected: {_fee},
              onSelectionChanged: (v) => setState(() => _fee = v.first),
            ),
            if (_fee != _Fee.none) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _feeValue,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _fee == _Fee.flat
                            ? 'Fee per late EMI'
                            : '% of the EMI',
                        prefixText: _fee == _Fee.flat ? '₹ ' : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _grace,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Grace days',
                      ),
                    ),
                  ),
                ],
              ),
              if (_lateFee().error != null &&
                  (_feeValue.text.isNotEmpty || _grace.text.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _lateFee().error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const Text(
                'Shown on the plan as an estimate. It is not added to what you owe.',
              ),
            ],
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
    this.sellerAbsorbs,
  });

  final EmiSchedule? schedule;
  final String? error;
  final bool hasTerms;
  final Money? sellerAbsorbs;

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
                  if (sellerAbsorbs != null)
                    _row('Seller absorbs (estimate)', sellerAbsorbs!.format()),
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
