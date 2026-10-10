import '../core/models/person.dart';
import 'contact_import.dart';

/// Groups of people that look like the same person: the same phone number, or
/// the same name ignoring case and spacing. Groups are transitive (A and B share
/// a number, B and C share a name: one group of three). Each group is oldest
/// first, and only groups of two or more are returned.
List<List<Person>> findDuplicateGroups(List<Person> people) {
  final parent = List<int>.generate(people.length, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  void union(int a, int b) => parent[find(a)] = find(b);

  final byPhone = <String, int>{};
  final byName = <String, int>{};
  for (var i = 0; i < people.length; i++) {
    final phone = normalizePhone(people[i].phone);
    final name = nameKey(people[i].name);
    if (phone.isNotEmpty) {
      final first = byPhone.putIfAbsent(phone, () => i);
      if (first != i) union(first, i);
    }
    if (name.isNotEmpty) {
      final first = byName.putIfAbsent(name, () => i);
      if (first != i) union(first, i);
    }
  }

  final groups = <int, List<Person>>{};
  for (var i = 0; i < people.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(people[i]);
  }
  final out = [
    for (final g in groups.values)
      if (g.length > 1) g..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
  ];
  out.sort((a, b) => nameKey(a.first.name).compareTo(nameKey(b.first.name)));
  return out;
}
