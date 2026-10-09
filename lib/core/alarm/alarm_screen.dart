import 'package:flutter/material.dart';

import 'alarm_service.dart';

/// Full-screen ring UI shown when an alarm fires (spike version).
class AlarmScreen extends StatelessWidget {
  const AlarmScreen({super.key, required this.id, required this.title});

  final int id;
  final String title;

  String _time() {
    final n = TimeOfDay.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _dismiss(BuildContext context) async {
    await AlarmService.stop(id);
    if (context.mounted) Navigator.of(context).maybePop();
  }

  Future<void> _snooze(BuildContext context) async {
    await AlarmService.stop(id);
    await AlarmService.schedule(
      id: id,
      after: const Duration(minutes: 5),
      title: '$title (snoozed)',
    );
    if (context.mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
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
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 24),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.tonal(
                    onPressed: () => _snooze(context),
                    child: const Text('Snooze 5 min'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: () => _dismiss(context),
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
