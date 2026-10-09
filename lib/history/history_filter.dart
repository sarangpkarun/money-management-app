import '../core/models/money_transaction.dart';
import '../core/money/money.dart';
import '../core/status/transaction_status.dart';

/// What the History screen is currently showing. An empty/null field means
/// "no restriction".
class HistoryFilter {
  const HistoryFilter({
    this.types = const {},
    this.personId,
    this.from,
    this.to,
    this.minAmount,
    this.maxAmount,
    this.query = '',
  });

  final Set<TransactionType> types;
  final String? personId;

  /// Settled-date range, inclusive of both days.
  final DateTime? from;
  final DateTime? to;

  /// Bounds on the amount paid, inclusive.
  final Money? minAmount;
  final Money? maxAmount;
  final String query;

  bool get isActive =>
      types.isNotEmpty ||
      personId != null ||
      from != null ||
      to != null ||
      minAmount != null ||
      maxAmount != null ||
      query.trim().isNotEmpty;

  HistoryFilter cleared() => const HistoryFilter();

  HistoryFilter copyWith({
    Set<TransactionType>? types,
    String? personId,
    bool clearPerson = false,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
    Money? minAmount,
    Money? maxAmount,
    bool clearAmounts = false,
    String? query,
  }) => HistoryFilter(
    types: types ?? this.types,
    personId: clearPerson ? null : (personId ?? this.personId),
    from: clearDates ? null : (from ?? this.from),
    to: clearDates ? null : (to ?? this.to),
    minAmount: clearAmounts ? null : (minAmount ?? this.minAmount),
    maxAmount: clearAmounts ? null : (maxAmount ?? this.maxAmount),
    query: query ?? this.query,
  );
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// History is the settled (Paid) entries, narrowed by [filter] and sorted with
/// the most recently settled first. Nothing is moved or copied: an entry
/// appears here simply because its status is Paid.
List<MoneyTransaction> applyHistoryFilter(
  List<MoneyTransaction> all,
  HistoryFilter filter,
) {
  final q = filter.query.trim().toLowerCase();
  DateTime settledOn(MoneyTransaction t) => t.settledAt ?? t.lastActivity;

  final result = all.where((t) {
    if (t.status != TransactionStatus.paid) return false;
    if (filter.types.isNotEmpty && !filter.types.contains(t.type)) return false;
    if (filter.personId != null && t.personId != filter.personId) return false;

    final day = _day(settledOn(t));
    if (filter.from != null && day.isBefore(_day(filter.from!))) return false;
    if (filter.to != null && day.isAfter(_day(filter.to!))) return false;

    if (filter.minAmount != null && t.paidTotal < filter.minAmount!) {
      return false;
    }
    if (filter.maxAmount != null && t.paidTotal > filter.maxAmount!) {
      return false;
    }
    if (q.isNotEmpty &&
        !t.personName.toLowerCase().contains(q) &&
        !t.title.toLowerCase().contains(q)) {
      return false;
    }
    return true;
  }).toList();

  result.sort((a, b) => settledOn(b).compareTo(settledOn(a)));
  return result;
}
