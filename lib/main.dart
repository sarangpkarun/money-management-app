import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_gate.dart';
import 'core/alarm/alarm_plan.dart';
import 'core/alarm/alarm_screen.dart';
import 'core/alarm/alarm_service.dart';
import 'core/data/firestore_setup.dart';
import 'core/theme/app_theme.dart';
import 'settings/format_host.dart';
import 'settings/settings_providers.dart';
import 'firebase_options.dart';
import 'shell/app_shell.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  initFirestore();
  runApp(const ProviderScope(child: MoneyManagerApp()));
}

class MoneyManagerApp extends ConsumerStatefulWidget {
  const MoneyManagerApp({super.key});

  @override
  ConsumerState<MoneyManagerApp> createState() => _MoneyManagerAppState();
}

class _MoneyManagerAppState extends ConsumerState<MoneyManagerApp> {
  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    if (kIsWeb) return; // no phone alarms in the browser
    AlarmService.onAlarmOpened = _showAlarm;
    await AlarmService.init();
    final launched = AlarmService.launchedBy;
    if (launched != null) _showAlarm(launched.id, launched.payload);
  }

  void _showAlarm(int id, AlarmPayload payload) {
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AlarmScreen(id: id, payload: payload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(appSettingsProvider).theme;
    return FormatHost(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Money Manager',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeModeFor(theme),
        home: const AuthGate(home: AppShell()),
      ),
    );
  }
}
