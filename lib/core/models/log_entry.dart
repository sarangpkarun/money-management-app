import 'package:cloud_firestore/cloud_firestore.dart';

import '../money/money.dart';

/// What a calendar log entry records. Only `expense` and `income` count toward
/// money totals; `note` and `task` are for everything else.
enum LogKind { expense, income, note, task }

/// A dated record in the calendar log: where money was spent, a note, a task.
/// Separate from [MoneyTransaction], so it never affects lent/borrowed totals.
class LogEntry {
  const LogEntry({
    this.id = '',
    required this.date,
    required this.title,
    this.kind = LogKind.expense,
    this.amount,
    this.account,
    this.category,
    this.place,
    this.notes,
    this.personId,
    this.personName,
    this.done = false,
    required this.createdAt,
  });

  final String id;

  /// The day this belongs to (date only; the time part is ignored).
  final DateTime date;

  /// The purpose, e.g. "Groceries".
  final String title;
  final LogKind kind;
  final Money? amount;

  /// What it was paid with or where, e.g. "HDFC Credit Card", "Cash".
  final String? account;
  final String? category;

  /// Who or where it was paid to.
  final String? place;
  final String? notes;
  final String? personId;
  final String? personName;

  /// For tasks.
  final bool done;
  final DateTime createdAt;

  DateTime get day => DateTime(date.year, date.month, date.day);

  bool get hasMoney => kind == LogKind.expense || kind == LogKind.income;

  LogEntry copyWith({bool? done}) => LogEntry(
    id: id,
    date: date,
    title: title,
    kind: kind,
    amount: amount,
    account: account,
    category: category,
    place: place,
    notes: notes,
    personId: personId,
    personName: personName,
    done: done ?? this.done,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(day),
    'title': title,
    'kind': kind.name,
    'amount': amount?.paise,
    'account': account,
    'category': category,
    'place': place,
    'notes': notes,
    'personId': personId,
    'personName': personName,
    'done': done,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory LogEntry.fromMap(String id, Map<String, dynamic> m) {
    final amount = m['amount'] as int?;
    return LogEntry(
      id: id,
      date: (m['date'] as Timestamp).toDate(),
      title: m['title'] as String,
      kind: LogKind.values.byName((m['kind'] as String?) ?? 'expense'),
      amount: amount == null ? null : Money(amount),
      account: m['account'] as String?,
      category: m['category'] as String?,
      place: m['place'] as String?,
      notes: m['notes'] as String?,
      personId: m['personId'] as String?,
      personName: m['personName'] as String?,
      done: m['done'] == true,
      createdAt: (m['createdAt'] as Timestamp).toDate(),
    );
  }
}
