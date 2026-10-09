import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/payment_repository.dart';
import '../core/data/providers.dart';
import '../core/instalments/instalment_plan.dart';
import '../core/models/emi_plan.dart';
import '../core/models/money_transaction.dart';
import '../core/models/payment.dart';
import '../core/money/money.dart';
import '../core/ui/format.dart';
import 'emi_payment_sheet.dart';
import 'payment_sheet.dart' show paymentModeLabel;

/// What can be done to one unpaid payment of an instalment plan.
Future<void> showInstalmentRowSheet(
  BuildContext context, {
  required MoneyTransaction txn,
  required EmiRow row,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Payment #${row.number} · ${row.amount.format()} · '
                '${formatShortDate(row.dueDate)}',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Mark paid'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showEmiPaymentSheet(context, txn: txn, row: row);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Change amount'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _changeAmount(context, txn, row);
            },
          ),
          if (row.paidAmount.isZero)
            ListTile(
              leading: const Icon(Icons.skip_next_outlined),
              title: const Text('Skip this month'),
              subtitle: const Text('This and later payments move a month on'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _skip(context, txn, row);
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> _skip(
  BuildContext context,
  MoneyTransaction txn,
  EmiRow row,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Skip this month?'),
      content: Text(
        'Payment #${row.number} and every later payment move one month later. '
        'The last payment date moves too.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(d).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(d).pop(true),
          child: const Text('Skip'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await _run(context, (repo) => repo.skipMonth(txn.id, row.number));
}

Future<void> _changeAmount(
  BuildContext context,
  MoneyTransaction txn,
  EmiRow row,
) async {
  final amount = await showDialog<Money>(
    context: context,
    builder: (_) => _ChangeAmountDialog(row: row),
  );
  if (amount == null || !context.mounted) return;
  await _run(
    context,
    (repo) => repo.changeInstalmentAmount(txn.id, row.number, amount),
  );
}

/// Runs a plan change and shows the engine's message if it is refused.
Future<void> _run(
  BuildContext context,
  Future<void> Function(PaymentRepository repo) action,
) async {
  final container = ProviderScope.containerOf(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action(container.read(paymentRepositoryProvider));
  } on InstalmentError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } on PaymentException {
    messenger.showSnackBar(
      const SnackBar(content: Text('This plan changed. Try again.')),
    );
  }
}

class _ChangeAmountDialog extends StatefulWidget {
  const _ChangeAmountDialog({required this.row});

  final EmiRow row;

  @override
  State<_ChangeAmountDialog> createState() => _ChangeAmountDialogState();
}

class _ChangeAmountDialogState extends State<_ChangeAmountDialog> {
  late final _amount = TextEditingController(
    text: plainAmount(widget.row.amount),
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = Money.parse(_amount.text);
    if (amount == null || amount <= Money.zero) {
      setState(() => _error = 'Enter an amount above 0');
      return;
    }
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Change payment #${widget.row.number}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('The later payments are re-spread so the total stays.'),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'New amount',
              prefixText: '₹ ',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Change')),
      ],
    );
  }
}

/// An extra payment towards the whole plan: the schedule shortens from the end.
Future<void> showExtraPaymentSheet(
  BuildContext context, {
  required MoneyTransaction txn,
  required Money owed,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ExtraPaymentSheet(txn: txn, owed: owed),
  );
}

class _ExtraPaymentSheet extends ConsumerStatefulWidget {
  const _ExtraPaymentSheet({required this.txn, required this.owed});

  final MoneyTransaction txn;
  final Money owed;

  @override
  ConsumerState<_ExtraPaymentSheet> createState() => _ExtraPaymentSheetState();
}

class _ExtraPaymentSheetState extends ConsumerState<_ExtraPaymentSheet> {
  final _amount = TextEditingController();
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
    if (amount == null || amount <= Money.zero) {
      setState(() => _error = 'Enter an amount above 0');
      return;
    }
    if (amount > widget.owed) {
      setState(
        () => _error =
            'Cannot be more than what is left (${widget.owed.format()})',
      );
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await ref
          .read(paymentRepositoryProvider)
          .payExtra(
            widget.txn.id,
            amount: amount,
            date: _date,
            mode: _mode,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } on InstalmentError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } on PaymentException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'This plan changed. Close this and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              'Add extra payment',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${widget.owed.format()} left. The plan shortens from the last '
              'payment.',
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
              child: Text(_busy ? 'Saving...' : 'Add extra payment'),
            ),
          ],
        ),
      ),
    );
  }
}
