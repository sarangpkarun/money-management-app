import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/people/person_suggestions.dart';
import 'package:money_manager/people/person_summary.dart';

void main() {
  PersonSummary s(String name, DateTime activity, {String? phone}) =>
      PersonSummary(
        person: Person(
          id: name,
          name: name,
          phone: phone,
          createdAt: DateTime(2026, 1, 1),
        ),
        net: Money.zero,
        hasOverdue: false,
        lastActivity: activity,
      );

  final all = [
    s('Asha', DateTime(2026, 3, 1), phone: '98450'),
    s('Ashok', DateTime(2026, 9, 1)),
    s('Rashmi', DateTime(2026, 6, 1)),
    s('Ravi', DateTime(2026, 8, 1), phone: '77001'),
  ];

  List<String> names(Suggestions r) =>
      r.matches.map((m) => m.person.name).toList();

  test('empty query shows recent people first, limited', () {
    final r = suggestPeople(all, '', limit: 3);
    expect(names(r), ['Ashok', 'Ravi', 'Rashmi']);
    expect(r.showAddNew, isFalse);
  });

  test('prefix matches come before contains matches', () {
    final r = suggestPeople(all, 'ash');
    // Asha, Ashok are prefix matches (Ashok more recent); Rashmi merely contains.
    expect(names(r), ['Ashok', 'Asha', 'Rashmi']);
  });

  test('matches phone numbers', () {
    expect(names(suggestPeople(all, '7700')), ['Ravi']);
  });

  test('offers "add new" when there is no exact name match', () {
    expect(suggestPeople(all, 'Ash').showAddNew, isTrue);
    expect(suggestPeople(all, 'Zed').showAddNew, isTrue);
    expect(suggestPeople(all, 'Zed').matches, isEmpty);
  });

  test('no "add new" for an exact match (case-insensitive, trimmed)', () {
    expect(suggestPeople(all, '  asha ').showAddNew, isFalse);
  });

  test('whitespace-only query behaves like empty', () {
    final r = suggestPeople(all, '   ', limit: 2);
    expect(r.showAddNew, isFalse);
    expect(r.matches.length, 2);
  });
}
