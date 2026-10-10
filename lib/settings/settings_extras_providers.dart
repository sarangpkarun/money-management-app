import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'backup.dart';

/// Shares the backup file. Tests replace it with a fake.
final backupSharerProvider = Provider<BackupSharer>(
  (ref) => const SharePlusBackupSharer(),
);

/// "1.0.0 (3)" from the app's own package info. Tests replace it.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});
