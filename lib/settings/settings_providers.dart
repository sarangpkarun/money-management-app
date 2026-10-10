import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/app_settings.dart';

/// The user's settings, or the defaults while the profile loads or when nobody
/// is signed in.
final appSettingsProvider = Provider<AppSettings>(
  (ref) =>
      ref.watch(currentProfileProvider).value?.settings ?? AppSettings.defaults,
);

/// The user's currency code (INR until the profile loads).
final appCurrencyProvider = Provider<String>(
  (ref) => ref.watch(currentProfileProvider).value?.currency ?? 'INR',
);

/// The Flutter theme mode for the user's theme choice.
ThemeMode themeModeFor(ThemeChoice choice) => switch (choice) {
  ThemeChoice.system => ThemeMode.system,
  ThemeChoice.light => ThemeMode.light,
  ThemeChoice.dark => ThemeMode.dark,
};
