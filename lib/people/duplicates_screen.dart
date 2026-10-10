import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/people_repository.dart';
import '../core/data/providers.dart';
import '../core/models/person.dart';
import 'duplicates.dart';
import 'people_providers.dart';

/// People that look like the same person, with a way to merge them.
class DuplicatesScreen extends ConsumerWidget {
  const DuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider);
    final entries = ref.watch(allTransactionsProvider).value ?? const [];
    final counts = <String, int>{};
    for (final t in entries) {
      counts[t.personId] = (counts[t.personId] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Find duplicates')),
      body: people.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load people: $e')),
        data: (list) {
          final groups = findDuplicateGroups(list);
          if (groups.isEmpty) {
            return const Center(child: Text('No duplicates found'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'These people share a phone number or a name. Merging moves '
                'all their entries to the one you keep.',
              ),
              const SizedBox(height: 12),
              for (final g in groups) _GroupCard(group: g, counts: counts),
            ],
          );
        },
      ),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({required this.group, required this.counts});

  final List<Person> group;
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${group.length} people look the same',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final p in group)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${p.name}${p.phone == null ? '' : ' · ${p.phone}'} · '
                  '${_entries(counts[p.id] ?? 0)}',
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => _merge(context, ref),
                child: const Text('Merge…'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _entries(int n) => n == 1 ? '1 entry' : '$n entries';

  /// The person to keep by default: most entries, then the oldest.
  Person get _defaultKeep {
    final sorted = [...group]
      ..sort((a, b) {
        final c = (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
        return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
      });
    return sorted.first;
  }

  Future<void> _merge(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(peopleRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final keep = await showDialog<Person>(
      context: context,
      builder: (_) =>
          _MergeDialog(group: group, counts: counts, initial: _defaultKeep),
    );
    if (keep == null) return;
    try {
      final moved = await repo.merge(keep.id, [
        for (final p in group)
          if (p.id != keep.id) p.id,
      ]);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Merged into ${keep.name}. $moved '
            '${moved == 1 ? 'entry' : 'entries'} moved.',
          ),
        ),
      );
    } on PeopleMergeException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _MergeDialog extends StatefulWidget {
  const _MergeDialog({
    required this.group,
    required this.counts,
    required this.initial,
  });

  final List<Person> group;
  final Map<String, int> counts;
  final Person initial;

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  late Person _keep = widget.initial;

  @override
  Widget build(BuildContext context) {
    final moving = widget.group.where((p) => p.id != _keep.id).toList();
    final moved = moving.fold(0, (n, p) => n + (widget.counts[p.id] ?? 0));
    return AlertDialog(
      title: const Text('Which one do you keep?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioGroup<Person>(
            groupValue: _keep,
            onChanged: (p) => setState(() => _keep = p ?? _keep),
            child: Column(
              children: [
                for (final p in widget.group)
                  RadioListTile<Person>(
                    value: p,
                    title: Text(p.name),
                    subtitle: Text(p.phone ?? 'No number'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Merge ${moving.map((p) => "'${p.name}'").join(', ')} into '
            "'${_keep.name}'? $moved "
            '${moved == 1 ? 'entry moves' : 'entries move'}. '
            'This cannot be undone.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_keep),
          child: const Text('Merge'),
        ),
      ],
    );
  }
}
