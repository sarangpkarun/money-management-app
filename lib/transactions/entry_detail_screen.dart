import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ui/format.dart';
import '../core/data/providers.dart';
import '../core/interest/interest.dart';
import '../core/models/money_transaction.dart';
import '../core/models/payment.dart';
import '../core/status/transaction_status.dart';
import 'add_entry_screen.dart';
import 'emi_payment_sheet.dart';
import 'emi_schedule_view.dart';
import 'entry_form_logic.dart';
import 'instalment_actions.dart';
import 'prepayment_screen.dart';
import 'payment_sheet.dart';
import 'status_badge.dart';
import 'transaction_providers.dart';

class EntryDetailScreen extends ConsumerWidget {
  const EntryDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MoneyTransaction t,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('The entry and all its payments will be removed.'),
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
    await ref.read(transactionRepositoryProvider).delete(t.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  void _payNextEmi(BuildContext context, MoneyTransaction t) {
    final next = t.emiPlan!.nextUnpaid;
    if (next != null) showEmiPaymentSheet(context, txn: t, row: next);
  }

  /// Settled entries offer "Mark as unpaid" instead of a payment button.
  Widget? _settledBar(
    BuildContext context,
    WidgetRef ref,
    MoneyTransaction t,
    List<Payment>? payments,
  ) {
    final last = latestPayment(payments ?? const []);
    if (last == null) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: OutlinedButton(
          onPressed: () => _markUnpaid(context, ref, t, last),
          child: const Text('Mark as unpaid'),
        ),
      ),
    );
  }

  Future<void> _markUnpaid(
    BuildContext context,
    WidgetRef ref,
    MoneyTransaction t,
    Payment last,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mark as unpaid?'),
        content: Text(
          'The last payment of ${last.amount.format()} '
          '(${formatShortDate(last.date)}) will be removed and this entry '
          'reopened. Your other payments stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark as unpaid'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await ref
        .read(paymentRepositoryProvider)
        .reopenLastPayment(t.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reopened. Removed ${removed.amount.format()} payment.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnAsync = ref.watch(transactionProvider(transactionId));
    final payments = ref.watch(paymentsProvider(transactionId));
    final t = txnAsync.value;

    if (t == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: txnAsync.isLoading
              ? const CircularProgressIndicator()
              : const Text('This entry no longer exists'),
        ),
      );
    }

    final status = effectiveStatus(t, now: DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(t.personName),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'extra':
                  showExtraPaymentSheet(
                    context,
                    txn: t,
                    owed: outstanding(t, DateTime.now()),
                  );
                case 'prepay':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PrepaymentScreen(plan: t.emiPlan!),
                    ),
                  );
                case 'edit':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AddEntryScreen(existing: t),
                    ),
                  );
                default:
                  _delete(context, ref, t);
              }
            },
            itemBuilder: (_) => [
              if (t.type == TransactionType.instalment &&
                  !outstanding(t, DateTime.now()).isZero)
                const PopupMenuItem(
                  value: 'extra',
                  child: Text('Add extra payment'),
                ),
              if (t.type == TransactionType.emi &&
                  !outstanding(t, DateTime.now()).isZero)
                const PopupMenuItem(
                  value: 'prepay',
                  child: Text('Prepay / foreclose'),
                ),
              const PopupMenuItem(value: 'edit', child: Text('Edit entry')),
              const PopupMenuItem(value: 'delete', child: Text('Delete entry')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: outstanding(t, DateTime.now()).isZero
          ? _settledBar(context, ref, t, payments.value)
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => t.emiPlan != null
                      ? _payNextEmi(context, t)
                      : showPaymentSheet(context, txn: t),
                  child: Text(switch (t.type) {
                    TransactionType.emi => 'Pay next EMI',
                    TransactionType.instalment => 'Pay next instalment',
                    _ => payActionLabel(t),
                  }),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            t.totalAmount.format(),
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(status: status),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: paidFraction(t),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text(summaryLine(t)),
          const SizedBox(height: 16),
          Text(t.title, style: Theme.of(context).textTheme.titleMedium),
          Text(
            [
              'Date ${formatShortDate(t.entryDate)}',
              if (t.dueDate != null) 'Due ${formatShortDate(t.dueDate!)}',
            ].join(' · '),
          ),
          if (t.interestType != InterestType.none) ...[
            const SizedBox(height: 12),
            Text(interestSummary(t)),
            Text('Interest to date ${interestFor(t, DateTime.now()).format()}'),
          ],
          if (t.type == TransactionType.borrowed)
            Text('Repayment: ${repaymentLabel(t.repaymentType)}'),
          if (t.notes != null) ...[const SizedBox(height: 8), Text(t.notes!)],
          if (t.status != TransactionStatus.paid &&
              (t.dueDate != null || t.emiPlan != null))
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remind me about due dates'),
              subtitle: const Text(
                'An alarm at 9:00 the day before, on the day, and the day after',
              ),
              value: t.autoReminders,
              onChanged: (on) => ref
                  .read(transactionRepositoryProvider)
                  .setAutoReminders(t.id, on),
            ),
          if (t.emiPlan != null) ...[
            const SizedBox(height: 24),
            EmiScheduleView(
              plan: t.emiPlan!,
              now: DateTime.now(),
              instalment: t.type == TransactionType.instalment,
              onPayRow: (row) => t.type == TransactionType.instalment
                  ? showInstalmentRowSheet(context, txn: t, row: row)
                  : showEmiPaymentSheet(context, txn: t, row: row),
            ),
          ],
          const SizedBox(height: 24),
          Text('Payments', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          payments.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Could not load payments: $e'),
            data: (list) => list.isEmpty
                ? const Text('No payments yet')
                : Column(
                    children: [
                      for (final p in list)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.amount.format()),
                          subtitle: Text(
                            [
                              formatShortDate(p.date),
                              paymentModeLabel(p.mode),
                              if (p.note != null) p.note!,
                            ].join(' · '),
                          ),
                          trailing: const Icon(Icons.edit, size: 18),
                          onTap: () =>
                              showPaymentSheet(context, txn: t, existing: p),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
