import '../core/interest/interest.dart';
import '../core/models/money_transaction.dart';
import '../core/models/person.dart';
import '../core/money/money.dart';
import '../core/status/transaction_status.dart';

enum PeopleFilter { all, iOwe, theyOwe, settled, hasOverdue }

enum PeopleSort { name, highestAmount, latestActivity }

/// One row of the People list: a person plus what they owe / are owed.
class PersonSummary {
  const PersonSummary({
    required this.person,
    required this.net,
    required this.hasOverdue,
    required this.lastActivity,
  });

  final Person person;

  /// Positive: they owe you. Negative: you owe them.
  final Money net;
  final bool hasOverdue;
  final DateTime lastActivity;
}

List<PersonSummary> summarize(
  List<Person> people,
  List<MoneyTransaction> transactions, {
  required DateTime now,
}) {
  final byPerson = <String, List<MoneyTransaction>>{};
  for (final t in transactions) {
    byPerson.putIfAbsent(t.personId, () => []).add(t);
  }
  return [
    for (final p in people) _summarizeOne(p, byPerson[p.id] ?? const [], now),
  ];
}

PersonSummary _summarizeOne(
  Person person,
  List<MoneyTransaction> txns,
  DateTime now,
) {
  var net = Money.zero;
  var overdue = false;
  var last = person.createdAt;
  for (final t in txns) {
    final owed = outstanding(t, now); // principal plus interest, less payments
    net = t.isReceivable ? net + owed : net - owed;
    // Recomputed from the due date: the stored status can be stale until a
    // scheduled job refreshes it.
    final status = computeStatus(
      total: t.totalAmount,
      paid: t.paidTotal,
      dueDate: t.dueDate,
      now: now,
    );
    if (status == TransactionStatus.overdue) overdue = true;
    if (t.lastActivity.isAfter(last)) last = t.lastActivity;
  }
  return PersonSummary(
    person: person,
    net: net,
    hasOverdue: overdue,
    lastActivity: last,
  );
}

List<PersonSummary> applyFilters(
  List<PersonSummary> summaries, {
  PeopleFilter filter = PeopleFilter.all,
  PeopleSort sort = PeopleSort.name,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  final result = summaries.where((s) {
    if (q.isNotEmpty) {
      final name = s.person.name.toLowerCase();
      final phone = (s.person.phone ?? '').toLowerCase();
      final email = (s.person.email ?? '').toLowerCase();
      if (!name.contains(q) && !phone.contains(q) && !email.contains(q)) {
        return false;
      }
    }
    return switch (filter) {
      PeopleFilter.all => true,
      PeopleFilter.iOwe => s.net.isNegative,
      PeopleFilter.theyOwe => s.net > Money.zero,
      PeopleFilter.settled => s.net.isZero,
      PeopleFilter.hasOverdue => s.hasOverdue,
    };
  }).toList();

  int byName(PersonSummary a, PersonSummary b) =>
      a.person.name.toLowerCase().compareTo(b.person.name.toLowerCase());

  result.sort(switch (sort) {
    PeopleSort.name => byName,
    PeopleSort.highestAmount => (a, b) {
      final c = b.net.paise.abs().compareTo(a.net.paise.abs());
      return c != 0 ? c : byName(a, b);
    },
    PeopleSort.latestActivity => (a, b) {
      final c = b.lastActivity.compareTo(a.lastActivity);
      return c != 0 ? c : byName(a, b);
    },
  });
  return result;
}
