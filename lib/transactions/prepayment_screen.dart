import 'package:flutter/material.dart';

import '../core/emi/emi_schedule.dart';
import '../core/emi/prepayment.dart';
import '../core/models/emi_plan.dart';
import '../core/money/money.dart';
import '../core/ui/format.dart';

/// Estimates what closing an EMI early, or paying part of it off, would do.
/// Nothing is saved: it is a calculator on top of the current schedule.
class PrepaymentScreen extends StatelessWidget {
  const PrepaymentScreen({super.key, required this.plan});

  final EmiPlan plan;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Prepay / foreclose'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Foreclose'),
              Tab(text: 'Part prepayment'),
            ],
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.secondaryContainer,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Estimate only. Your lender may add charges or count interest '
                'differently, so check their figure before paying.',
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ForecloseTab(plan: plan),
                  _PartTab(plan: plan),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _line(String label, String value, {bool bold = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(
    children: [
      Expanded(child: Text(label)),
      Text(
        value,
        style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w600),
      ),
    ],
  ),
);

class _ForecloseTab extends StatefulWidget {
  const _ForecloseTab({required this.plan});

  final EmiPlan plan;

  @override
  State<_ForecloseTab> createState() => _ForecloseTabState();
}

class _ForecloseTabState extends State<_ForecloseTab> {
  final _charge = TextEditingController(text: '0');

  @override
  void dispose() {
    _charge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ForeclosureEstimate? result;
    String? error;
    final pct = double.tryParse(_charge.text.trim());
    if (pct == null) {
      error = 'Enter the charge as a number';
    } else {
      try {
        result = foreclosureEstimate(widget.plan, chargePercent: pct);
      } on EmiInputError catch (e) {
        error = e.message;
      }
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: _charge,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Foreclosure charge (% of principal)',
            helperText: 'Ask your lender, often 0 to 4%',
          ),
        ),
        const SizedBox(height: 16),
        if (result == null)
          Text(
            error ?? '',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'To close the loan now',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    result.total.format(),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _line('Principal left', result.principal.format()),
                  _line('Foreclosure charge', result.charge.format()),
                  _line('Interest you avoid', result.saved.format()),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Interest for the days of the current month already run is not '
          'included.',
        ),
      ],
    );
  }
}

class _PartTab extends StatefulWidget {
  const _PartTab({required this.plan});

  final EmiPlan plan;

  @override
  State<_PartTab> createState() => _PartTabState();
}

class _PartTabState extends State<_PartTab> {
  final _amount = TextEditingController();
  PrepaymentKeep _keep = PrepaymentKeep.emi;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    PartPrepaymentResult? result;
    String? error;
    final amount = Money.parse(_amount.text);
    if (_amount.text.trim().isNotEmpty) {
      if (amount == null) {
        error = 'Enter a valid amount';
      } else {
        try {
          result = partPrepayment(plan, amount, keep: _keep);
        } on EmiInputError catch (e) {
          error = e.message;
        }
      }
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Principal left ${outstandingPrincipal(plan).format()}'),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Part payment',
            prefixText: '₹ ',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Keep EMI, finish sooner'),
              selected: _keep == PrepaymentKeep.emi,
              onSelected: (_) => setState(() => _keep = PrepaymentKeep.emi),
            ),
            ChoiceChip(
              label: const Text('Keep months, lower EMI'),
              selected: _keep == PrepaymentKeep.tenure,
              onSelected: (_) => setState(() => _keep = PrepaymentKeep.tenure),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (error != null)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (result != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'After this payment',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  _line('Principal left', result.newBalance.format()),
                  _line('EMI', result.emiAfter.format()),
                  _line(
                    'Months left',
                    '${result.monthsAfter} (was ${result.monthsBefore})',
                  ),
                  _line('Last EMI', formatShortDate(result.lastDueDate)),
                  _line(
                    'Interest you save',
                    result.interestSaved.format(),
                    bold: true,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
