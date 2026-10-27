import '../core/models/trip_expense.dart';

/// Splits [total] paise equally between [emails]; the leftover paise go one
/// each to the first people, so the shares always add up to [total].
Map<String, int> equalSplit(int total, List<String> emails) {
  if (emails.isEmpty) return {};
  final base = total ~/ emails.length;
  final extra = total - base * emails.length;
  return {
    for (var i = 0; i < emails.length; i++)
      emails[i]: base + (i < extra ? 1 : 0),
  };
}

/// Turns percentages in basis points (50% = 5000) into paise. They must add up
/// to 10000. Rounding leftovers go to the largest fractional parts, so the
/// shares add up to [total]. Returns null if the percentages do not total 100%.
Map<String, int>? percentSplit(int total, Map<String, int> percentBp) {
  if (percentBp.isEmpty) return null;
  if (percentBp.values.fold(0, (a, b) => a + b) != 10000) return null;
  final shares = <String, int>{};
  final fractions = <MapEntry<String, int>>[];
  var assigned = 0;
  for (final e in percentBp.entries) {
    final whole = total * e.value ~/ 10000;
    shares[e.key] = whole;
    assigned += whole;
    fractions.add(MapEntry(e.key, total * e.value % 10000));
  }
  fractions.sort((a, b) => b.value.compareTo(a.value));
  for (var i = 0; i < total - assigned; i++) {
    shares[fractions[i].key] = shares[fractions[i].key]! + 1;
  }
  return shares;
}

/// Whether exact [shares] add up to [total].
bool exactSplitValid(int total, Map<String, int> shares) =>
    shares.isNotEmpty &&
    shares.values.every((v) => v >= 0) &&
    shares.values.fold(0, (a, b) => a + b) == total;

/// Net position per person across [expenses]: positive means the group owes
/// them (they paid more than their share), negative means they owe.
Map<String, int> balances(Iterable<TripExpense> expenses) {
  final net = <String, int>{};
  for (final e in expenses) {
    net[e.paidBy] = (net[e.paidBy] ?? 0) + e.amount.paise;
    for (final s in e.shares.entries) {
      net[s.key] = (net[s.key] ?? 0) - s.value;
    }
  }
  return net;
}

/// One payment that helps settle up.
class Transfer {
  const Transfer(this.from, this.to, this.paise);

  final String from;
  final String to;
  final int paise;

  @override
  String toString() => 'Transfer($from -> $to, $paise)';
}

/// A short list of payments that clears every balance: the biggest debtor pays
/// the biggest creditor until nobody owes anything.
List<Transfer> settleUp(Map<String, int> net) {
  final debtors = <MapEntry<String, int>>[
    for (final e in net.entries)
      if (e.value < 0) MapEntry(e.key, -e.value),
  ]..sort((a, b) => b.value.compareTo(a.value));
  final creditors = <MapEntry<String, int>>[
    for (final e in net.entries)
      if (e.value > 0) MapEntry(e.key, e.value),
  ]..sort((a, b) => b.value.compareTo(a.value));
  final out = <Transfer>[];
  var d = 0, c = 0;
  var owe = debtors.isEmpty ? 0 : debtors[0].value;
  var due = creditors.isEmpty ? 0 : creditors[0].value;
  while (d < debtors.length && c < creditors.length) {
    final pay = owe < due ? owe : due;
    if (pay > 0) out.add(Transfer(debtors[d].key, creditors[c].key, pay));
    owe -= pay;
    due -= pay;
    if (owe == 0) {
      d++;
      if (d < debtors.length) owe = debtors[d].value;
    }
    if (due == 0) {
      c++;
      if (c < creditors.length) due = creditors[c].value;
    }
  }
  return out;
}
