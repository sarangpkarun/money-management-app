import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/interest/interest.dart';
import '../core/models/money_transaction.dart';
import '../core/models/person.dart';
import '../core/money/money.dart';
import '../core/theme/app_colors.dart';
import '../core/ui/format.dart';
import '../core/ui/initials_avatar.dart';
import '../transactions/add_entry_screen.dart';
import '../transactions/entry_detail_screen.dart';
import '../transactions/payment_sheet.dart';
import 'ledger.dart';
import 'ledger_providers.dart';
import 'people_providers.dart';
import 'person_form_screen.dart';
import 'person_summary.dart';

/// Everything with one person on a single timeline, with a running balance.
class PersonLedgerScreen extends ConsumerStatefulWidget {
  const PersonLedgerScreen({super.key, required this.personId});

  final String personId;

  @override
  ConsumerState<PersonLedgerScreen> createState() => _PersonLedgerScreenState();
}

class _PersonLedgerScreenState extends ConsumerState<PersonLedgerScreen> {
  bool _closing = false;

  List<MoneyTransaction> _openEntries() {
    final now = DateTime.now();
    final all = ref.read(allTransactionsProvider).value ?? const [];
    return [
      for (final t in all)
        if (t.personId == widget.personId && !outstanding(t, now).isZero) t,
    ];
  }

  Future<void> _receiveOrPay(Person person) async {
    final open = _openEntries();
    if (open.isEmpty) return;
    if (open.length == 1) {
      await showPaymentSheet(context, txn: open.single);
      return;
    }
    final chosen = await showModalBottomSheet<MoneyTransaction>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Which entry?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final t in open)
              ListTile(
                title: Text(
                  '${t.isReceivable ? 'Gave' : 'Borrowed'} '
                  '${t.totalAmount.format()} · ${t.title}',
                ),
                subtitle: Text(
                  'Balance ${outstanding(t, DateTime.now()).format()}',
                ),
                onTap: () => Navigator.of(context).pop(t),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      await showPaymentSheet(context, txn: chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(personSummariesProvider);
    final ledger = ref.watch(personLedgerProvider(widget.personId));
    final summary = summaries.value
        ?.where((s) => s.person.id == widget.personId)
        .firstOrNull;

    // The person was deleted (from the edit screen): leave this screen too.
    if (summaries.hasValue && summary == null && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    if (summary == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final person = summary.person;
    final hasOpen = _openEntries().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(person.name),
        actions: [
          IconButton(
            tooltip: 'Edit person',
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PersonFormScreen(person: person),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AddEntryScreen(initialPerson: person),
                    ),
                  ),
                  child: const Text('Give / Add'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: hasOpen ? () => _receiveOrPay(person) : null,
                  child: const Text('Receive / Pay'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          _Header(summary: summary),
          const Divider(height: 1),
          Expanded(
            child: ledger.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load ledger: $e')),
              data: (events) {
                if (events.isEmpty) {
                  return Center(child: Text('Nothing with ${person.name} yet'));
                }
                final newestFirst = events.reversed.toList();
                return ListView.separated(
                  itemCount: newestFirst.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _LedgerRow(event: newestFirst[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.summary});

  final PersonSummary summary;

  @override
  Widget build(BuildContext context) {
    final net = summary.net;
    final Color color;
    final String label;
    if (net.isZero) {
      color = Theme.of(context).colorScheme.onSurfaceVariant;
      label = 'Settled';
    } else if (net.isNegative) {
      color = AppColors.pay(context);
      label = 'You owe';
    } else {
      color = AppColors.receive(context);
      label = 'Owes you';
    }
    final phone = summary.person.phone;
    final email = summary.person.email;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          InitialsAvatar(name: summary.person.name, radius: 30),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.person.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (phone != null) Text(phone),
                if (email != null) Text(email),
                if (summary.hasOverdue)
                  Text(
                    'Overdue',
                    style: TextStyle(color: AppColors.pay(context)),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!net.isZero)
                Text(
                  Money(net.paise.abs()).format(),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(label, style: TextStyle(color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.event});

  final LedgerEvent event;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (event.flow) {
      LedgerFlow.moneyIn => (Icons.south_west, AppColors.receive(context)),
      LedgerFlow.moneyOut => (Icons.north_east, AppColors.pay(context)),
      LedgerFlow.none => (Icons.percent, AppColors.pending(context)),
    };

    final balance = event.balanceAfter;
    final Color balanceColor;
    final String balanceCaption;
    if (balance.isZero) {
      balanceColor = Theme.of(context).colorScheme.onSurfaceVariant;
      balanceCaption = 'settled';
    } else if (balance.isNegative) {
      balanceColor = AppColors.pay(context);
      balanceCaption = 'you owe';
    } else {
      balanceColor = AppColors.receive(context);
      balanceCaption = 'owes you';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(event.label),
      subtitle: Text(
        [
          if (event.detail != null) event.detail!,
          formatShortDate(event.date),
        ].join(' · '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            balance.isZero ? '₹0' : Money(balance.paise.abs()).format(),
            style: TextStyle(color: balanceColor, fontWeight: FontWeight.w600),
          ),
          Text(
            balanceCaption,
            style: TextStyle(color: balanceColor, fontSize: 11),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EntryDetailScreen(transactionId: event.transactionId),
        ),
      ),
    );
  }
}
