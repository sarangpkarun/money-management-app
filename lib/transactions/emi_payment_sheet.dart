import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/payment_repository.dart';
import '../core/data/providers.dart';
import '../core/models/emi_plan.dart';
import '../core/models/money_transaction.dart';
import '../core/models/payment.dart';
import '../core/money/money.dart';
import '../core/status/transaction_status.dart';
import '../core/ui/format.dart';
import 'payment_sheet.dart' show paymentModeLabel;

/// Bottom sheet to mark an EMI instalment paid: date, amount (up to what is left
/// on that instalment), mode and note.
Future<void> showEmiPaymentSheet(
  BuildContext context, {
  required MoneyTransaction txn,
  required EmiRow row,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EmiPaymentSheet(txn: txn, row: row),
  );
}

class _EmiPaymentSheet extends ConsumerStatefulWidget {
  const _EmiPaymentSheet({required this.txn, required this.row});

  final MoneyTransaction txn;
  final EmiRow row;

  @override
  ConsumerState<_EmiPaymentSheet> createState() => _EmiPaymentSheetState();
}

class _EmiPaymentSheetState extends ConsumerState<_EmiPaymentSheet> {
  late final _amount = TextEditingController(
    text: plainAmount(widget.row.remaining),
  );
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  PaymentMode _mode = PaymentMode.cash;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _validate(Money? amount) {
    if (amount == null) return 'Enter a valid amount';
    return switch (validatePayment(
      balance: widget.row.remaining,
      amount: amount,
    )) {
      PaymentValidation.ok => null,
      PaymentValidation.notPositive => 'Enter an amount above 0',
      PaymentValidation.exceedsBalance =>
        'Cannot be more than what is left on this EMI '
            '(${widget.row.remaining.format()})',
    };
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = Money.parse(_amount.text);
    final error = _validate(amount);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await ref
          .read(paymentRepositoryProvider)
          .payInstallment(
            widget.txn.id,
            widget.row.number,
            amount: amount!,
            date: _date,
            mode: _mode,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } on PaymentException {
      // The row changed elsewhere since this sheet opened.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'This EMI changed. Close this and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
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
            Text(
              'Pay EMI #${row.number}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Due ${formatShortDate(row.dueDate)} · '
              '${row.remaining.format()} left of ${row.amount.format()}',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: Theme.of(context).textTheme.headlineSmall,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('Paid on ${formatShortDate(_date)}'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final m in PaymentMode.values)
                  ChoiceChip(
                    label: Text(paymentModeLabel(m)),
                    selected: _mode == m,
                    onSelected: (_) => setState(() => _mode = m),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving...' : 'Mark EMI paid'),
            ),
          ],
        ),
      ),
    );
  }
}
