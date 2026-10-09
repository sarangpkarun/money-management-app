import 'package:flutter/material.dart';

import 'alarm_service.dart';

/// Phase 0 alarm test, kept for checking alarms on other phones (Oppo, Vivo,
/// Samsung, iPhone) until the real reminders arrive in Phase 2.
class AlarmTestScreen extends StatefulWidget {
  const AlarmTestScreen({super.key});

  @override
  State<AlarmTestScreen> createState() => _AlarmTestScreenState();
}

class _AlarmTestScreenState extends State<AlarmTestScreen> {
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
    final s = await AlarmService.status();
    if (mounted) setState(() => _status = s.toString());
  }

  Future<void> _schedule(Duration after) async {
    await AlarmService.schedule(id: 1, after: after);
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
                await AlarmService.requestPermissions();
                await _refresh();
              },
              child: const Text('Request permissions'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _schedule(const Duration(minutes: 1)),
              child: const Text('Schedule in 1 min'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _schedule(const Duration(minutes: 5)),
              child: const Text('Schedule in 5 min'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: AlarmService.cancelAll,
              child: const Text('Cancel all'),
            ),
          ],
        ),
      ),
    );
  }
}
