import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/person.dart';
import 'contacts_providers.dart';
import 'people_providers.dart';

/// Add a person, or edit/delete an existing one.
class PersonFormScreen extends ConsumerStatefulWidget {
  const PersonFormScreen({super.key, this.person});

  final Person? person;

  @override
  ConsumerState<PersonFormScreen> createState() => _PersonFormScreenState();
}

class _PersonFormScreenState extends ConsumerState<PersonFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.person?.name);
  late final _phone = TextEditingController(text: widget.person?.phone);
  late final _notes = TextEditingController(text: widget.person?.notes);
  bool _busy = false;

  bool get _editing => widget.person != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    final picked = await ref.read(contactsSourceProvider).pickOne();
    if (picked == null || !mounted) return;
    setState(() {
      _name.text = picked.name;
      if (picked.phone != null) _phone.text = picked.phone!;
    });
  }

  String? _blank(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = ref.read(peopleRepositoryProvider);
    final existing = widget.person;
    if (existing == null) {
      await repo.add(
        Person(
          name: _name.text.trim(),
          phone: _blank(_phone.text),
          notes: _blank(_notes.text),
          createdAt: DateTime.now(),
        ),
      );
    } else {
      await repo.update(
        Person(
          id: existing.id,
          name: _name.text.trim(),
          phone: _blank(_phone.text),
          notes: _blank(_notes.text),
          photoUrl: existing.photoUrl,
          createdAt: existing.createdAt,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final person = widget.person!;
    final entries = (ref.read(allTransactionsProvider).value ?? const [])
        .where((t) => t.personId == person.id)
        .length;
    if (entries > 0) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Can't delete yet"),
          content: Text(
            '${person.name} has $entries ${entries == 1 ? 'entry' : 'entries'}. '
            'Delete those entries first, then delete the person.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${person.name}?'),
        content: const Text('This cannot be undone.'),
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
    await ref.read(peopleRepositoryProvider).delete(person.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit person' : 'Add person')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_editing) ...[
                OutlinedButton.icon(
                  onPressed: _pickContact,
                  icon: const Icon(Icons.contacts_outlined),
                  label: const Text('Pick from contacts'),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Saving...' : 'Save'),
              ),
              if (_editing) ...[
                const SizedBox(height: 24),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: _delete,
                  child: const Text('Delete person'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
