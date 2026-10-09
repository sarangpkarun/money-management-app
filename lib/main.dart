import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_gate.dart';
import 'core/alarm/alarm_screen.dart';
import 'core/alarm/alarm_service.dart';
import 'core/data/firestore_setup.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'shell/app_shell.dart';

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
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const AuthGate(home: AppShell()),
    );
  }
}
