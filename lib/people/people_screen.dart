import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/money/money.dart';
import '../core/theme/app_colors.dart';
import '../core/ui/format.dart';
import '../core/ui/initials_avatar.dart';
import 'contact_import_screen.dart';
import 'duplicates_screen.dart';
import 'people_providers.dart';
import 'person_form_screen.dart';
import 'person_ledger_screen.dart';
import 'person_summary.dart';

const _filterLabels = {
  PeopleFilter.all: 'All',
  PeopleFilter.iOwe: 'I owe',
  PeopleFilter.theyOwe: 'They owe',
  PeopleFilter.settled: 'Settled',
  PeopleFilter.hasOverdue: 'Overdue',
};

const _sortLabels = {
  PeopleSort.name: 'Name',
  PeopleSort.highestAmount: 'Highest amount',
  PeopleSort.latestActivity: 'Latest activity',
};

class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  String _query = '';
  PeopleFilter _filter = PeopleFilter.all;
  PeopleSort _sort = PeopleSort.name;

  void _addPerson() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PersonFormScreen()));
  }

  void _importContacts() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ContactImportScreen()),
    );
  }

  void _findDuplicates() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DuplicatesScreen()));
  }

  /// Tapping a person opens their ledger; editing is inside it.
  void _openLedger(PersonSummary summary) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonLedgerScreen(personId: summary.person.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(personSummariesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          IconButton(
            tooltip: 'Add person',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _addPerson,
          ),
          IconButton(
            tooltip: 'Import from contacts',
            icon: const Icon(Icons.contacts_outlined),
            onPressed: _importContacts,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (_) => _findDuplicates(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'dupes', child: Text('Find duplicates')),
            ],
          ),
          PopupMenuButton<PeopleSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              for (final e in _sortLabels.entries)
                PopupMenuItem(value: e.key, child: Text(e.value)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search name or phone',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final e in _filterLabels.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _filter == e.key,
                      onSelected: (_) => setState(() => _filter = e.key),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: summaries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load people: $e')),
              data: (all) {
                if (all.isEmpty) {
                  return _EmptyState(
                    onAdd: _addPerson,
                    onImport: _importContacts,
                  );
                }
                final shown = applyFilters(
                  all,
                  filter: _filter,
                  sort: _sort,
                  query: _query,
                );
                if (shown.isEmpty) {
                  return const Center(child: Text('No matching people'));
                }
                return ListView.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) =>
                      _PersonRow(summary: shown[i], onTap: _openLedger),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.summary, required this.onTap});

  final PersonSummary summary;
  final void Function(PersonSummary) onTap;

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
    return ListTile(
      leading: InitialsAvatar(name: summary.person.name),
      title: Text(summary.person.name),
      subtitle: Text('Last activity ${formatShortDate(summary.lastActivity)}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!net.isZero)
            Text(
              Money(net.paise.abs()).format(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
          if (summary.hasOverdue)
            Text(
              'Overdue',
              style: TextStyle(color: AppColors.pay(context), fontSize: 11),
            ),
        ],
      ),
      onTap: () => onTap(summary),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, required this.onImport});

  final VoidCallback onAdd;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_outline, size: 64),
          const SizedBox(height: 12),
          const Text('No people yet'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onAdd, child: const Text('Add person')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onImport,
            child: const Text('Import from contacts'),
          ),
        ],
      ),
    );
  }
}
