import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/payment_repository.dart';
import '../core/interest/interest.dart';
import '../core/data/providers.dart';
import '../core/models/money_transaction.dart';
import '../core/models/payment.dart';
import '../core/money/money.dart';
import '../core/status/transaction_status.dart';

const _modeLabels = {
  PaymentMode.cash: 'Cash',
  PaymentMode.upi: 'UPI',
  PaymentMode.bank: 'Bank',
  PaymentMode.card: 'Card',
};

String paymentModeLabel(PaymentMode m) => _modeLabels[m]!;

/// Bottom sheet to record a payment, or edit/delete an existing one.
Future<void> showPaymentSheet(
  BuildContext context, {
  required MoneyTransaction txn,
  Payment? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PaymentSheet(txn: txn, existing: existing),
  );
}

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.txn, this.existing});

  final MoneyTransaction txn;
  final Payment? existing;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  late final _amount = TextEditingController(
    text: _plain(
      widget.existing?.amount ?? outstanding(widget.txn, DateTime.now()),
    ),
  );
  late final _note = TextEditingController(text: widget.existing?.note);
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late PaymentMode _mode = widget.existing?.mode ?? PaymentMode.cash;
  String? _error;
  bool _busy = false;

  bool get _editing => widget.existing != null;

  /// What the amount may be at most: the balance, plus what the payment being
  /// edited already covers.
  Money get _available =>
      outstanding(widget.txn, DateTime.now()) +
      (widget.existing?.amount ?? Money.zero);

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// "500" or "500.50": editable text with no symbol or grouping.
  static String _plain(Money m) {
    final rupees = m.paise ~/ 100;
    final paise = m.paise % 100;
    return paise == 0
        ? '$rupees'
        : '$rupees.${paise.toString().padLeft(2, '0')}';
  }

  String? _validate(Money? amount) {
    if (amount == null) return 'Enter a valid amount';
    return switch (validatePayment(balance: _available, amount: amount)) {
      PaymentValidation.ok => null,
      PaymentValidation.notPositive => 'Enter an amount above 0',
      PaymentValidation.exceedsBalance =>
        'Cannot be more than the balance of ${_available.format()}',
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
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final repo = ref.read(paymentRepositoryProvider);
    try {
      if (_editing) {
        await repo.edit(
          widget.txn.id,
          Payment(
            id: widget.existing!.id,
            amount: amount!,
            date: _date,
            mode: _mode,
            note: note,
            screenshotUrl: widget.existing!.screenshotUrl,
          ),
        );
      } else {
        await repo.add(
          widget.txn.id,
          Payment(amount: amount!, date: _date, mode: _mode, note: note),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on PaymentException catch (e) {
      // The balance changed elsewhere since this sheet opened.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.reason == PaymentValidation.exceedsBalance
              ? 'The balance changed. Reopen and try again.'
              : 'Enter an amount above 0';
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this payment?'),
        content: const Text('The balance will be recalculated.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(paymentRepositoryProvider)
        .delete(widget.txn.id, widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = _editing
        ? 'Edit payment'
        : (widget.txn.isReceivable ? 'Receive payment' : 'Pay now');
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
            Text(title, style: Theme.of(context).textTheme.titleLarge),
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
              label: Text('Date: ${_date.day}/${_date.month}/${_date.year}'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final e in _modeLabels.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _mode == e.key,
                    onSelected: (_) => setState(() => _mode = e.key),
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
              child: Text(_busy ? 'Saving...' : 'Save payment'),
            ),
            if (_editing) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _delete,
                child: const Text('Delete payment'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
