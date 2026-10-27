import 'package:cloud_firestore/cloud_firestore.dart';

import '../money/money.dart';

enum SplitMode { equal, exact, percent }

String splitModeLabel(SplitMode m) => switch (m) {
  SplitMode.equal => 'Equally',
  SplitMode.exact => 'Exact amounts',
  SplitMode.percent => 'Percentages',
};

/// Money spent on a trip, paid by one member and shared among several.
///
/// [shares] holds what each person owes in paise (keyed by lowercased email),
/// always summing to [amount]. For a percentage split, [percentBp] keeps the
/// percentages in basis points (50% = 5000) so the split can be edited later.
class TripExpense {
  const TripExpense({
    this.id = '',
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.date,
    this.category,
    this.stopId,
    this.mode = SplitMode.equal,
    required this.shares,
    this.percentBp,
    this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String title;
  final Money amount;

  /// Lowercased email of the member who paid.
  final String paidBy;
  final DateTime date;
  final String? category;
  final String? stopId;
  final SplitMode mode;
  final Map<String, int> shares;
  final Map<String, int>? percentBp;
  final String? createdBy;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'title': title,
    'amount': amount.paise,
    'paidBy': paidBy,
    'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
    'category': category,
    'stopId': stopId,
    'mode': mode.name,
    'shares': shares,
    'percentBp': percentBp,
    'createdBy': createdBy,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory TripExpense.fromMap(String id, Map<String, dynamic> m) {
    Map<String, int>? ints(Object? v) => v is Map
        ? {for (final e in v.entries) e.key as String: (e.value as num).toInt()}
        : null;
    return TripExpense(
      id: id,
      title: m['title'] as String,
      amount: Money((m['amount'] as num).toInt()),
      paidBy: m['paidBy'] as String,
      date: (m['date'] as Timestamp).toDate(),
      category: m['category'] as String?,
      stopId: m['stopId'] as String?,
      mode: SplitMode.values.byName((m['mode'] as String?) ?? 'equal'),
      shares: ints(m['shares']) ?? const {},
      percentBp: ints(m['percentBp']),
      createdBy: m['createdBy'] as String?,
      createdAt: (m['createdAt'] as Timestamp).toDate(),
    );
  }
}
