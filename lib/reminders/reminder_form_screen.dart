import '../core/ui/format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/money_transaction.dart';
import '../core/models/reminder.dart';
import '../core/status/transaction_status.dart';
import '../people/people_providers.dart';
import '../settings/settings_providers.dart';
import 'alarm_providers.dart';
import 'reminder_form_logic.dart';

const _toneLabels = {
  ReminderTone.alarm: 'Alarm sound',
  ReminderTone.notification: 'Notification sound',
  ReminderTone.ringtone: 'Ringtone',
};
const _vibrationLabels = {
  ReminderVibration.off: 'Off',
  ReminderVibration.short: 'Short',
  ReminderVibration.long: 'Long',
};
const _repeatLabels = {
  RepeatKind.none: 'Does not repeat',
  RepeatKind.daily: 'Every day',
  RepeatKind.weekly: 'Weekly',
  RepeatKind.monthly: 'Monthly',
  RepeatKind.yearly: 'Yearly',
  RepeatKind.everyNDays: 'Every N days',
};

/// Create a reminder, or edit [existing]. Passing [linkedTransactionId]
/// pre-selects the entry it is about.
class ReminderFormScreen extends ConsumerStatefulWidget {
  const ReminderFormScreen({
    super.key,
    this.existing,
    this.linkedTransactionId,
  });

  final Reminder? existing;
  final String? linkedTransactionId;

  @override
  ConsumerState<ReminderFormScreen> createState() => _ReminderFormScreenState();
}

class _ReminderFormScreenState extends ConsumerState<ReminderFormScreen> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late final _every = TextEditingController(
    text: widget.existing?.repeat.kind == RepeatKind.everyNDays
        ? '${widget.existing!.repeat.interval}'
        : '10',
  );

  late DateTime _at = widget.existing?.at ?? _defaultTime();
  late RepeatKind _kind = widget.existing?.repeat.kind ?? RepeatKind.none;
  late final Set<int> _weekdays = {
    ...?(widget.existing?.repeat.kind == RepeatKind.weekly
        ? widget.existing!.repeat.weekdays
        : null),
  };
  late int _snooze = widget.existing?.snoozeMinutes ?? 10;
  late ReminderTone _tone = widget.existing?.tone ?? ReminderTone.alarm;
  late ReminderVibration _vibration =
      widget.existing?.vibration ?? ReminderVibration.long;
  late String? _transactionId =
      widget.existing?.transactionId ?? widget.linkedTransactionId;
  String? _error;
  bool _busy = false;

  bool get _isNew => widget.existing == null;

  /// The user's default reminder time today, or tomorrow if that has passed.
  DateTime _defaultTime() {
    final m = ref.read(appSettingsProvider).autoAlarmMinutes;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, m ~/ 60, m % 60);
    return today.isAfter(now)
        ? today
        : DateTime(now.year, now.month, now.day + 1, m ~/ 60, m % 60);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _every.dispose();
    super.dispose();
  }

  RepeatRule _rule() => switch (_kind) {
    RepeatKind.none => const RepeatRule.none(),
    RepeatKind.daily => const RepeatRule.daily(),
    RepeatKind.monthly => const RepeatRule.monthly(),
    RepeatKind.yearly => const RepeatRule.yearly(),
    RepeatKind.weekly => RepeatRule.weekly(_weekdays),
    RepeatKind.everyNDays => RepeatRule.everyNDays(
      int.tryParse(_every.text.trim()) ?? 0,
    ),
  };

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) {
      setState(
        () => _at = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _at.hour,
          _at.minute,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _at.hour, minute: _at.minute),
    );
    if (picked != null) {
      setState(
        () => _at = DateTime(
          _at.year,
          _at.month,
          _at.day,
          picked.hour,
          picked.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    final rule = _rule();
    final error = validateReminder(
      title: _title.text,
      at: _at,
      repeat: rule,
      snoozeMinutes: _snooze,
      now: DateTime.now(),
      isNew: _isNew,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final repo = ref.read(reminderRepositoryProvider);
    final existing = widget.existing;
    if (existing == null) {
      await repo.add(
        Reminder(
          title: _title.text.trim(),
          notes: notes,
          at: _at,
          repeat: rule,
          snoozeMinutes: _snooze,
          tone: _tone,
          vibration: _vibration,
          transactionId: _transactionId,
          createdAt: DateTime.now(),
        ),
      );
    } else {
      await repo.update(
        Reminder(
          id: existing.id,
          title: _title.text.trim(),
          notes: notes,
          at: _at,
          repeat: rule,
          snoozeMinutes: _snooze,
          tone: _tone,
          vibration: _vibration,
          transactionId: _transactionId,
          done: existing.done,
          doneAt: existing.doneAt,
          createdAt: existing.createdAt,
        ),
      );
    }
    // Rings need notification and exact-alarm access; ask the first time.
    try {
      await ref.read(alarmSchedulerProvider).ensurePermissions();
    } catch (_) {
      // Saving never fails because alarms are unavailable.
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete this reminder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(reminderRepositoryProvider).delete(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleDone() async {
    final repo = ref.read(reminderRepositoryProvider);
    final r = widget.existing!;
    if (r.done) {
      await repo.reopen(r.id);
    } else {
      await repo.markDone(r.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _chips<T>(
    Map<T, String> labels,
    T selected,
    void Function(T) onSelected,
  ) => Wrap(
    spacing: 8,
    children: [
      for (final e in labels.entries)
        ChoiceChip(
          label: Text(e.value),
          selected: selected == e.key,
          onSelected: (_) => setState(() => onSelected(e.key)),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = [
      for (final t in ref.watch(allTransactionsProvider).value ?? const [])
        if (t.status != TransactionStatus.paid || t.id == _transactionId) t,
    ];
    final linked = entries.any((t) => t.id == _transactionId)
        ? _transactionId
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New reminder' : 'Edit reminder'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Delete reminder',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (!_isNew) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _toggleDone,
                    child: Text(widget.existing!.done ? 'Reopen' : 'Mark done'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Saving...' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(formatShortDate(_at)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(formatTime(_at)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<RepeatKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Repeat'),
              items: [
                for (final e in _repeatLabels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? RepeatKind.none),
            ),
            if (_kind == RepeatKind.weekly) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(weekdayShort(d)),
                      selected: _weekdays.contains(d),
                      onSelected: (on) => setState(
                        () => on ? _weekdays.add(d) : _weekdays.remove(d),
                      ),
                    ),
                ],
              ),
            ],
            if (_kind == RepeatKind.everyNDays) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _every,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Every how many days',
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text('Snooze', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _chips(
              {for (final m in snoozeChoices) m: '$m min'},
              _snooze,
              (v) => _snooze = v,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ReminderTone>(
              initialValue: _tone,
              decoration: const InputDecoration(labelText: 'Tone'),
              items: [
                for (final e in _toneLabels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _tone = v ?? ReminderTone.alarm),
            ),
            const SizedBox(height: 16),
            Text('Vibration', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _chips(_vibrationLabels, _vibration, (v) => _vibration = v),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: linked,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Link to an entry'),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                for (final MoneyTransaction t in entries)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      '${t.personName} · ${t.title}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _transactionId = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
