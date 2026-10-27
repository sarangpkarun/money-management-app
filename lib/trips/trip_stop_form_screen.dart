import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/trip.dart';
import '../core/models/trip_stop.dart';
import '../core/ui/format.dart';
import 'trip_providers.dart';
import 'trip_colors.dart';

/// Add or edit a stop on the roadmap.
class TripStopFormScreen extends ConsumerStatefulWidget {
  const TripStopFormScreen({
    super.key,
    required this.trip,
    this.existing,
    this.insertIndex,
  });

  final Trip trip;
  final TripStop? existing;

  /// Where a new stop goes on the roadmap; null puts it at the end.
  final int? insertIndex;

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
      order: widget.existing?.order,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    try {
      if (_editing) {
        await repo.updateStop(widget.trip.id, stop);
      } else {
        final current = await ref.read(
          tripStopsProvider(widget.trip.id).future,
        );
        await repo.addStopAt(
          widget.trip.id,
          stop,
          current,
          widget.insertIndex ?? current.length,
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

  Future<void> _delete() async {
    final spent = (await ref.read(
      tripExpensesProvider(widget.trip.id).future,
    )).where((e) => e.stopId == widget.existing!.id).length;
    if (spent > 0 && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete this stop?'),
          content: Text(
            '$spent expense${spent == 1 ? '' : 's'} will stay on the trip '
            'as general expenses.',
          ),
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
      if (ok != true) return;
    }
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
                      avatar: Icon(
                        stopIcon(t),
                        size: 18,
                        color: _type == t
                            ? null
                            : categoryForeground(context, stopTypeColor(t)),
                      ),
                      selectedColor: categoryBackground(stopTypeColor(t)),
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
