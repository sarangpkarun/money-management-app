import '../core/models/log_entry.dart';
import '../core/money/money.dart';

/// Returns an error message for a log entry being saved, or null when valid.
String? validateLog({
  required String title,
  required LogKind kind,
  required String amountText,
}) {
  if (title.trim().isEmpty) return 'Enter what this is for';
  final text = amountText.trim();
  if (text.isEmpty) {
    final needsAmount = kind == LogKind.expense || kind == LogKind.income;
    return needsAmount ? 'Enter an amount' : null;
  }
  final amount = Money.parse(text);
  if (amount == null) return 'Enter a valid amount';
  if (amount.isZero) return 'Amount must be more than zero';
  return null;
}

/// Entries grouped by calendar day (time of day dropped), input order kept.
Map<DateTime, List<LogEntry>> groupByDay(Iterable<LogEntry> entries) {
  final out = <DateTime, List<LogEntry>>{};
  for (final e in entries) {
    out.putIfAbsent(e.day, () => []).add(e);
  }
  return out;
}

/// Total spent and received across [entries]; notes and tasks are ignored.
({Money spent, Money income}) totals(Iterable<LogEntry> entries) {
  var spent = Money.zero;
  var income = Money.zero;
  for (final e in entries) {
    final a = e.amount;
    if (a == null) continue;
    if (e.kind == LogKind.expense) spent += a;
    if (e.kind == LogKind.income) income += a;
  }
  return (spent: spent, income: income);
}

/// Money spent per account (entries without one under "No account"), largest
/// first. Only expenses count.
Map<String, Money> spentByAccount(Iterable<LogEntry> entries) =>
    _spentBy(entries, (e) => e.account, 'No account');

/// Money spent per category (entries without one under "Uncategorised").
Map<String, Money> spentByCategory(Iterable<LogEntry> entries) =>
    _spentBy(entries, (e) => e.category, 'Uncategorised');

Map<String, Money> _spentBy(
  Iterable<LogEntry> entries,
  String? Function(LogEntry) key,
  String fallback,
) {
  final totals = <String, Money>{};
  final spelling = <String, String>{};
  for (final e in entries) {
    if (e.kind != LogKind.expense || e.amount == null) continue;
    final label = _clean(key(e)) ?? fallback;
    final k = label.toLowerCase();
    spelling.putIfAbsent(k, () => label);
    totals[k] = (totals[k] ?? Money.zero) + e.amount!;
  }
  final sorted = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {for (final e in sorted) spelling[e.key]!: e.value};
}

/// Distinct non-empty values for suggestions, most used first, with
/// case-insensitive duplicates merged (the first spelling seen wins).
List<String> suggestions(Iterable<String?> values) {
  final counts = <String, int>{};
  final spelling = <String, String>{};
  for (final v in values) {
    final c = _clean(v);
    if (c == null) continue;
    final k = c.toLowerCase();
    spelling.putIfAbsent(k, () => c);
    counts[k] = (counts[k] ?? 0) + 1;
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  return [for (final k in keys) spelling[k]!];
}

/// Filters for the log list. Null/empty means "any".
class LogFilter {
  const LogFilter({
    this.query = '',
    this.kind,
    this.account,
    this.category,
    this.from,
    this.to,
  });

  final String query;
  final LogKind? kind;
  final String? account;
  final String? category;
  final DateTime? from;
  final DateTime? to;

  bool get isActive =>
      query.trim().isNotEmpty ||
      kind != null ||
      account != null ||
      category != null ||
      from != null ||
      to != null;

  bool matches(LogEntry e) {
    if (kind != null && e.kind != kind) return false;
    if (account != null && !_same(e.account, account)) return false;
    if (category != null && !_same(e.category, category)) return false;
    if (from != null && e.day.isBefore(_day(from!))) return false;
    if (to != null && e.day.isAfter(_day(to!))) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      e.title,
      e.account,
      e.category,
      e.place,
      e.notes,
      e.personName,
    ].any((s) => s != null && s.toLowerCase().contains(q));
  }

  List<LogEntry> apply(Iterable<LogEntry> entries) =>
      entries.where(matches).toList();
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

bool _same(String? a, String? b) =>
    _clean(a)?.toLowerCase() == _clean(b)?.toLowerCase();

String? _clean(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}
