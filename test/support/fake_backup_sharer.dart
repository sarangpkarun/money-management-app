import 'package:money_manager/settings/backup.dart';

class FakeBackupSharer implements BackupSharer {
  final List<({String fileName, String json})> shared = [];
  Object? failWith;

  @override
  Future<void> share({required String fileName, required String json}) async {
    if (failWith != null) throw failWith!;
    shared.add((fileName: fileName, json: json));
  }
}
