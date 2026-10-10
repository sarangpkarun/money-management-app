import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/alarm/settings_opener.dart';
import '../core/data/providers.dart';
import '../core/models/person.dart';
import '../core/ui/empty_state.dart';
import '../reminders/alarm_providers.dart';
import 'contact_import.dart';
import 'contacts_providers.dart';
import 'contacts_source.dart';
import 'people_providers.dart';

/// Choose people from the phone's contacts and add them to People. Nothing is
/// imported unless it is ticked here.
class ContactImportScreen extends ConsumerStatefulWidget {
  const ContactImportScreen({super.key});

  @override
  ConsumerState<ContactImportScreen> createState() =>
      _ContactImportScreenState();
}

class _ContactImportScreenState extends ConsumerState<ContactImportScreen> {
  ContactsAccess? _access;
  bool _loading = true;
  List<ImportCandidate> _candidates = const [];
  final Set<int> _selected = {};
  String _query = '';
  bool _busy = false;

  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Wait for People to load (so "Already added" is right), and keep it
    // subscribed while this screen is open.
    ref.listenManual(peopleProvider, (_, next) {
      if (_started || next.isLoading) return;
      _started = true;
      _load();
    }, fireImmediately: true);
  }

  List<Person> get _people => ref.read(peopleProvider).value ?? const [];

  Future<void> _load() async {
    setState(() => _loading = true);
    final source = ref.read(contactsSourceProvider);
    final access = await source.requestAccess();
    var candidates = const <ImportCandidate>[];
    if (access == ContactsAccess.granted) {
      final contacts = await source.loadContacts();
      candidates = importCandidates(contacts, _people)
        ..sort(
          (a, b) => nameKey(a.contact.name).compareTo(nameKey(b.contact.name)),
        );
    }
    if (!mounted) return;
    setState(() {
      _access = access;
      _candidates = candidates;
      _selected.clear();
      _loading = false;
    });
  }

  /// The rows that match the search, with their place in the full list.
  List<int> get _visible {
    final q = nameKey(_query);
    final digits = _query.replaceAll(RegExp(r'[^0-9]'), '');
    return [
      for (var i = 0; i < _candidates.length; i++)
        if (q.isEmpty ||
            nameKey(_candidates[i].contact.name).contains(q) ||
            (digits.isNotEmpty &&
                (_candidates[i].contact.phone ?? '')
                    .replaceAll(RegExp(r'[^0-9]'), '')
                    .contains(digits)))
          i,
    ];
  }

  void _selectAllVisible() {
    setState(() {
      for (final i in _visible) {
        if (!_candidates[i].existing) _selected.add(i);
      }
    });
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    final repo = ref.read(peopleRepositoryProvider);
    final people = _people;
    final chosen = [for (final i in _selected) _candidates[i]];
    final plan = planImport(chosen, people);
    for (final c in plan) {
      await repo.add(
        Person(name: c.name, phone: c.phone, createdAt: DateTime.now()),
      );
    }
    final skipped = chosen.length - plan.length;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${plan.length} added'
          '${skipped > 0 ? ', $skipped skipped (already in People)' : ''}',
        ),
      ),
    );
  }

  Future<void> _pickOne() async {
    final picked = await ref.read(contactsSourceProvider).pickOne();
    if (picked == null || !mounted) return;
    final people = _people;
    final plan = planImport([
      ImportCandidate(contact: picked, existing: false),
    ], people);
    final messenger = ScaffoldMessenger.of(context);
    if (plan.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('${picked.name} is already in People')),
      );
      return;
    }
    await ref
        .read(peopleRepositoryProvider)
        .add(
          Person(
            name: plan.single.name,
            phone: plan.single.phone,
            createdAt: DateTime.now(),
          ),
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text('${plan.single.name} added')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import from contacts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _access == ContactsAccess.granted
          ? _list(context)
          : _noAccess(context),
      bottomNavigationBar: _access == ContactsAccess.granted && !_loading
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _selected.isEmpty || _busy ? null : _import,
                  child: Text(
                    _selected.isEmpty ? 'Import' : 'Import ${_selected.length}',
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _noAccess(BuildContext context) {
    final blocked = _access == ContactsAccess.blocked;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.contacts_outlined, size: 64),
          const SizedBox(height: 16),
          Text(
            blocked
                ? 'Contacts access is turned off for this app. Turn it on in '
                      'your phone settings to import people.'
                : 'Allow contacts access to choose people to import. Only the '
                      'people you tick are saved, and nothing is shared.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (blocked)
            FilledButton(
              onPressed: () =>
                  ref.read(settingsOpenerProvider).open(SystemSettingsPage.app),
              child: const Text('Open settings'),
            )
          else
            FilledButton(onPressed: _load, child: const Text('Allow access')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _pickOne,
            child: const Text('Pick one contact instead'),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    if (_candidates.isEmpty) {
      return const EmptyState(
        icon: Icons.contacts_outlined,
        title: 'No contacts found on this phone',
        hint: 'You can still add people one by one.',
      );
    }
    final visible = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search name or number',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _selectAllVisible,
            child: const Text('Select all matching'),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off,
                  title: 'No matching contacts',
                )
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (_, row) {
                    final i = visible[row];
                    final c = _candidates[i];
                    return CheckboxListTile(
                      value: c.existing || _selected.contains(i),
                      onChanged: c.existing
                          ? null
                          : (on) => setState(
                              () => on == true
                                  ? _selected.add(i)
                                  : _selected.remove(i),
                            ),
                      title: Text(c.contact.name),
                      subtitle: Text(
                        c.existing
                            ? 'Already added'
                            : (c.contact.phone ?? 'No number'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
