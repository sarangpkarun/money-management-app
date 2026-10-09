import 'person_summary.dart';

class Suggestions {
  const Suggestions(this.matches, {required this.showAddNew});

  final List<PersonSummary> matches;

  /// Whether to offer "Add 'query' as new person".
  final bool showAddNew;
}

/// Suggestions for the person field when adding an entry. With nothing typed,
/// the most recently used people; otherwise name/phone matches with prefix
/// matches first, each group most recent first.
Suggestions suggestPeople(
  List<PersonSummary> all,
  String query, {
  int limit = 5,
}) {
  final q = query.trim().toLowerCase();
  int recent(PersonSummary a, PersonSummary b) =>
      b.lastActivity.compareTo(a.lastActivity);

  if (q.isEmpty) {
    final sorted = [...all]..sort(recent);
    return Suggestions(sorted.take(limit).toList(), showAddNew: false);
  }

  final prefix = <PersonSummary>[];
  final contains = <PersonSummary>[];
  for (final s in all) {
    final name = s.person.name.toLowerCase();
    final phone = (s.person.phone ?? '').toLowerCase();
    if (name.startsWith(q) || phone.startsWith(q)) {
      prefix.add(s);
    } else if (name.contains(q) || phone.contains(q)) {
      contains.add(s);
    }
  }
  prefix.sort(recent);
  contains.sort(recent);
  final exact = all.any((s) => s.person.name.trim().toLowerCase() == q);
  return Suggestions([...prefix, ...contains], showAddNew: !exact);
}
