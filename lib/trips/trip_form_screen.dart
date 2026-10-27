import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/trip.dart';
import '../core/ui/format.dart';

/// Create a trip, or edit the name, description and dates of an existing one.
class TripFormScreen extends ConsumerStatefulWidget {
  const TripFormScreen({super.key, this.trip});

  final Trip? trip;

  @override
  ConsumerState<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends ConsumerState<TripFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.trip?.name);
  late final _description = TextEditingController(
    text: widget.trip?.description,
  );
  late DateTime? _start = widget.trip?.startDate;
  late DateTime? _end = widget.trip?.endDate;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final now = DateTime.now();
    final initial = (start ? _start : _end) ?? _start ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
        if (_start != null && _start!.isAfter(picked)) _start = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = ref.read(tripRepositoryProvider);
    final desc = _description.text.trim();
    try {
      final existing = widget.trip;
      if (existing == null) {
        final profile = ref.read(currentProfileProvider).value?.name ?? '';
        final email = ref.read(emailProvider);
        final name = profile.isEmpty ? email : profile;
        await repo.create(
          name: _name.text.trim(),
          ownerName: name,
          description: desc.isEmpty ? null : desc,
          startDate: _start,
          endDate: _end,
        );
      } else {
        await repo.updateDetails(
          Trip(
            id: existing.id,
            name: _name.text.trim(),
            description: desc.isEmpty ? null : desc,
            startDate: _start,
            endDate: _end,
            ownerUid: existing.ownerUid,
            members: existing.members,
            createdAt: existing.createdAt,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.trip != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit trip' : 'New trip')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Goa trip, Office offsite...',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(true),
                      icon: const Icon(Icons.event),
                      label: Text(
                        _start == null ? 'Start' : formatShortDate(_start!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(false),
                      icon: const Icon(Icons.event),
                      label: Text(
                        _end == null ? 'End' : formatShortDate(_end!),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Saving...' : 'Save'),
              ),
              if (!editing)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'You can add people from your People list once the trip '
                    'is created.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
