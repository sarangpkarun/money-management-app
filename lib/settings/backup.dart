import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';

import '../core/data/payment_repository.dart';
import '../core/data/people_repository.dart';
import '../core/data/reminder_repository.dart';
import '../core/data/transaction_repository.dart';
import '../core/data/user_repository.dart';
import '../core/models/app_user.dart';
import '../core/models/money_transaction.dart';
import '../core/models/payment.dart';
import '../core/models/person.dart';
import '../core/models/reminder.dart';

/// An entry with its payments, for the backup.
class BackupEntry {
  const BackupEntry(this.entry, this.payments);

  final MoneyTransaction entry;
  final List<Payment> payments;
}

/// Firestore timestamps become ISO-8601 UTC text; everything else is kept as it
/// is (money stays whole paise).
Object? _plain(Object? v) {
  if (v is Timestamp) {
    return v.toDate().toUtc().toIso8601String();
  }
  if (v is Map) {
    return {for (final e in v.entries) e.key as String: _plain(e.value)};
  }
  if (v is List) {
    return [for (final e in v) _plain(e)];
  }
  return v;
}

Map<String, dynamic> _withId(String id, Map<String, dynamic> m) => {
  'id': id,
  ...(_plain(m) as Map<String, dynamic>),
};

/// Everything in the account as plain JSON-ready data. Version 1.
Map<String, dynamic> buildBackup({
  required AppUser? profile,
  required List<Person> people,
  required List<BackupEntry> entries,
  required List<Reminder> reminders,
  required DateTime exportedAt,
}) => {
  'version': 1,
  'exportedAt': exportedAt.toUtc().toIso8601String(),
  'profile': profile == null
      ? null
      : {...profile.toMap(), 'settings': profile.settings.toMap()},
  'people': [for (final p in people) _withId(p.id, p.toMap())],
  'entries': [
    for (final e in entries)
      {
        ..._withId(e.entry.id, e.entry.toMap()),
        'payments': [for (final p in e.payments) _withId(p.id, p.toMap())],
      },
  ],
  'reminders': [for (final r in reminders) _withId(r.id, r.toMap())],
};

/// "money-manager-backup-2026-10-10.json".
String backupFileName(DateTime now) =>
    'money-manager-backup-${now.year}-'
    '${now.month.toString().padLeft(2, '0')}-'
    '${now.day.toString().padLeft(2, '0')}.json';

/// Pretty JSON text of [backup].
String backupJson(Map<String, dynamic> backup) =>
    const JsonEncoder.withIndent('  ').convert(backup);

/// Reads the whole account through the repositories.
Future<Map<String, dynamic>> collectBackup({
  required UserRepository users,
  required PeopleRepository people,
  required TransactionRepository transactions,
  required PaymentRepository payments,
  required ReminderRepository reminders,
  required DateTime now,
}) async {
  final entries = await transactions.getAll();
  return buildBackup(
    profile: await users.get(),
    people: await people.getAll(),
    entries: [
      for (final t in entries) BackupEntry(t, await payments.getAll(t.id)),
    ],
    reminders: await reminders.getAll(),
    exportedAt: now,
  );
}

/// Hands a file to the phone's share sheet (a fake in tests).
abstract class BackupSharer {
  Future<void> share({required String fileName, required String json});
}

class SharePlusBackupSharer implements BackupSharer {
  const SharePlusBackupSharer();

  @override
  Future<void> share({required String fileName, required String json}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(utf8.encode(json), mimeType: 'application/json'),
        ],
        fileNameOverrides: [fileName],
        subject: 'Money Manager backup',
      ),
    );
  }
}
