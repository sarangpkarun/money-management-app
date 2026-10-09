import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/interest/interest.dart';
import '../core/models/money_transaction.dart';
import 'entry_form_logic.dart';
import 'payment_sheet.dart';
import 'status_badge.dart';
import 'transaction_providers.dart';

String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

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
            onSelected: (_) => _delete(context, ref, t),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete entry')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: outstanding(t, DateTime.now()).isZero
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => showPaymentSheet(context, txn: t),
                  child: Text(payActionLabel(t)),
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
              'Date ${_fmtDate(t.entryDate)}',
              if (t.dueDate != null) 'Due ${_fmtDate(t.dueDate!)}',
            ].join(' · '),
          ),
          if (t.interestType != InterestType.none) ...[
            const SizedBox(height: 12),
            Text(
              '${interestTypeLabel(t.interestType)} interest at '
              '${formatRate(t.interestRate ?? 0)}% a year',
            ),
            Text('Interest to date ${interestFor(t, DateTime.now()).format()}'),
          ],
          if (t.type == TransactionType.borrowed)
            Text('Repayment: ${repaymentLabel(t.repaymentType)}'),
          if (t.notes != null) ...[const SizedBox(height: 8), Text(t.notes!)],
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
                              _fmtDate(p.date),
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
