import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_gate.dart';
import 'core/alarm/alarm_screen.dart';
import 'core/alarm/alarm_service.dart';
import 'core/data/firestore_setup.dart';
import 'firebase_options.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  initFirestore();
  runApp(const ProviderScope(child: MoneyManagerApp()));
}

class MoneyManagerApp extends StatefulWidget {
  const MoneyManagerApp({super.key});

  @override
  State<MoneyManagerApp> createState() => _MoneyManagerAppState();
}

class _MoneyManagerAppState extends State<MoneyManagerApp> {
  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    AlarmService.onAlarmOpened = _showAlarm;
    await AlarmService.init();
    final launched = AlarmService.launchedBy;
    if (launched != null) _showAlarm(launched.id, launched.title);
  }

  void _showAlarm(int id, String? title) {
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AlarmScreen(id: id, title: title ?? 'Alarm'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Money Manager',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF3F51B5)),
      home: const AuthGate(home: AlarmSpikeScreen()),
    );
  }
}

/// SPIKE screen (Phase 0). Replaced by the real app shell in Phase 1.
class AlarmSpikeScreen extends StatefulWidget {
  const AlarmSpikeScreen({super.key});

  @override
  State<AlarmSpikeScreen> createState() => _AlarmSpikeScreenState();
}

class _AlarmSpikeScreenState extends State<AlarmSpikeScreen> {
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
      appBar: AppBar(title: const Text('Alarm spike (Phase 0)')),
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
