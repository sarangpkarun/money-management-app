import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../reminders/alarm_providers.dart';
import '../data/providers.dart';
import 'alarm_plan.dart';

/// Full-screen ring UI shown when an alarm fires.
class AlarmScreen extends ConsumerWidget {
  const AlarmScreen({super.key, required this.id, required this.payload});

  /// The notification id of this ring.
  final int id;
  final AlarmPayload payload;

  String _time() {
    final n = TimeOfDay.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  /// Stops the ring. A reminder that does not repeat is finished by it.
  Future<void> _dismiss(BuildContext context, WidgetRef ref) async {
    final gateway = ref.read(alarmGatewayProvider);
    final repo = ref.read(reminderRepositoryProvider);
    await gateway.cancel(id);
    if (payload.once) {
      try {
        await repo.markDone(payload.reminderId);
      } catch (_) {
        // The reminder may be gone; nothing to finish.
      }
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze(BuildContext context, WidgetRef ref) async {
    final gateway = ref.read(alarmGatewayProvider);
    await gateway.cancel(id);
    await gateway.schedule(snoozeAlarm(payload, DateTime.now()));
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1115),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                Text(
                  _time(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 72,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  payload.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 24),
                ),
                if (payload.notes != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    payload.notes!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
                if (payload.snoozed) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Snoozed',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.tonal(
                    onPressed: () => _snooze(context, ref),
                    child: Text('Snooze ${payload.snoozeMinutes} min'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: () => _dismiss(context, ref),
                    child: const Text('Dismiss'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
