import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/trip.dart';
import '../core/models/trip_stop.dart';
import '../core/ui/format.dart';
import 'trip_roadmap_tab.dart';

/// Add or edit a stop on the roadmap.
class TripStopFormScreen extends ConsumerStatefulWidget {
  const TripStopFormScreen({super.key, required this.trip, this.existing});

  final Trip trip;
  final TripStop? existing;

  @override
  ConsumerState<TripStopFormScreen> createState() => _TripStopFormScreenState();
}

class _TripStopFormScreenState extends ConsumerState<TripStopFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _place = TextEditingController(text: widget.existing?.place);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late StopType _type = widget.existing?.type ?? StopType.stay;
  late DateTime? _date = widget.existing?.date ?? widget.trip.startDate;
  bool _busy = false;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _blank(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = ref.read(tripRepositoryProvider);
    final stop = TripStop(
      id: widget.existing?.id ?? '',
      title: _title.text.trim(),
      type: _type,
      date: _date,
      place: _blank(_place.text),
      notes: _blank(_notes.text),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    try {
      if (_editing) {
        await repo.updateStop(widget.trip.id, stop);
      } else {
        await repo.addStop(widget.trip.id, stop);
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

  Future<void> _delete() async {
    await ref
        .read(tripRepositoryProvider)
        .deleteStop(widget.trip.id, widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit stop' : 'Add stop')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What',
                  hintText: 'Hotel check-in, Train to Goa...',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in StopType.values)
                    ChoiceChip(
                      avatar: Icon(stopIcon(t), size: 18),
                      label: Text(stopTypeLabel(t)),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = t),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text(
                  _date == null ? 'Pick a date' : formatShortDate(_date!),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _place,
                decoration: const InputDecoration(
                  labelText: 'Place (optional)',
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
                  child: const Text('Delete stop'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
