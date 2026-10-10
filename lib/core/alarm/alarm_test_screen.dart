import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../reminders/alarm_providers.dart';
import 'alarm_service.dart';
import 'test_alarm.dart';

/// Phase 0 alarm test, kept for checking alarms on other phones (Oppo, Vivo,
/// Samsung, iPhone) until the real reminders arrive in Phase 2.
class AlarmTestScreen extends ConsumerStatefulWidget {
  const AlarmTestScreen({super.key});

  @override
  ConsumerState<AlarmTestScreen> createState() => _AlarmTestScreenState();
}

class _AlarmTestScreenState extends ConsumerState<AlarmTestScreen> {
  String _status = 'Initialising...';

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await AlarmService.init();
    await _refresh();
  }

  Future<void> _refresh() async {
    final s = await ref.read(alarmGatewayProvider).permissions();
    if (mounted) {
      setState(
        () => _status =
            'notifications ${s.notifications}, exact alarms ${s.exact}',
      );
    }
  }

  Future<void> _schedule(Duration after) async {
    await scheduleTestAlarm(ref.read(alarmGatewayProvider), after);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Alarm set for ${after.inMinutes} min from now')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alarm test (developer)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Permissions: $_status'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await ref.read(alarmGatewayProvider).requestPermissions();
                await _refresh();
              },
              child: const Text('Request permissions'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _schedule(const Duration(minutes: 1)),
              child: const Text('B: new reminder config, 1 min'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _schedule(const Duration(minutes: 5)),
              child: const Text('Schedule in 5 min'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await PluginAlarmGateway().scheduleLegacySpike(
                  const Duration(minutes: 1),
                );
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Old spike-config alarm in 1 min'),
                  ),
                );
              },
              child: const Text('A: old spike config, 1 min'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () =>
                  ref.read(alarmGatewayProvider).cancel(testAlarmId()),
              child: const Text('Cancel all'),
            ),
          ],
        ),
      ),
    );
  }
}
