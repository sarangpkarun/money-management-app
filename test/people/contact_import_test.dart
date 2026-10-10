import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/people/contact_import.dart';
import 'package:money_manager/people/duplicates.dart';

Person person(String id, String name, {String? phone, int day = 1}) =>
    Person(id: id, name: name, phone: phone, createdAt: DateTime(2026, 1, day));

ImportCandidate cand(String name, {String? phone, bool existing = false}) =>
    ImportCandidate(
      contact: ContactInfo(name: name, phone: phone),
      existing: existing,
    );

void main() {
  group('normalizePhone', () {
    test('formats of the same Indian number match', () {
      final forms = [
        '+91 98765 43210',
        '098765 43210',
        '9876543210',
        '+91-98765-43210',
        '(0091) 98765 43210',
        '98765 43210',
      ];
      for (final f in forms) {
        expect(normalizePhone(f), '9876543210', reason: f);
      }
    });

    test(
      'different numbers stay different, even with the same country code',
      () {
        expect(
          normalizePhone('+91 98765 43210') ==
              normalizePhone('+91 91234 56789'),
          isFalse,
        );
      },
    );

    test('empty, null and too-short numbers give no key', () {
      expect(normalizePhone(null), '');
      expect(normalizePhone(''), '');
      expect(normalizePhone('12345'), '');
      expect(normalizePhone('abc'), '');
    });

    test('a short local number keeps its digits', () {
      expect(normalizePhone('2345678'), '2345678');
    });
  });

  group('nameKey', () {
    test('case and spacing do not matter', () {
      expect(nameKey('  Ravi   Kumar '), 'ravi kumar');
      expect(nameKey('RAVI kumar'), nameKey('ravi KUMAR'));
      expect(nameKey(null), '');
    });
  });

  group('importCandidates', () {
    test('marks contacts that match by number or by name', () {
      final out = importCandidates(
        [
          const ContactInfo(name: 'Asha', phone: '98765 43210'),
          const ContactInfo(name: 'Someone Else', phone: '+91 98765 43210'),
          const ContactInfo(name: 'ravi kumar'),
          const ContactInfo(name: 'New Person', phone: '9000000001'),
        ],
        [person('1', 'Asha P', phone: '9876543210'), person('2', 'Ravi Kumar')],
      );
      expect(out.map((c) => c.existing), [true, true, true, false]);
    });

    test('contacts with no name are left out', () {
      final out = importCandidates([
        const ContactInfo(name: '  ', phone: '9876543210'),
        const ContactInfo(name: ''),
      ], const []);
      expect(out, isEmpty);
    });
  });

  group('planImport', () {
    test('creates the selected people, trimmed', () {
      final plan = planImport([
        cand('  Asha ', phone: ' 98765 43210 '),
        cand('Ravi'),
      ], const []);
      expect(plan.map((c) => c.name), ['Asha', 'Ravi']);
      expect(plan.first.phone, '98765 43210');
      expect(plan.last.phone, isNull);
    });

    test('skips people already in People', () {
      final plan = planImport(
        [
          cand('Asha', phone: '9876543210'),
          cand('New', phone: '9000000001'),
          cand('Ravi Kumar'),
        ],
        [
          person('1', 'Different', phone: '+91 98765 43210'),
          person('2', 'ravi  kumar'),
        ],
      );
      expect(plan.map((c) => c.name), ['New']);
    });

    test('the same person picked twice is added once', () {
      final plan = planImport([
        cand('Asha', phone: '9876543210'),
        cand('Asha P', phone: '+91 98765 43210'),
        cand('asha'),
        cand('Meena', phone: '9000000001'),
      ], const []);
      expect(plan.map((c) => c.name), ['Asha', 'Meena']);
    });

    test('blank names are skipped', () {
      expect(planImport([cand('   ', phone: '9876543210')], const []), isEmpty);
    });

    test('an existing flag on the row does not matter, People does', () {
      // The screen greys existing rows, but planImport re-checks against People.
      final plan = planImport([cand('Asha', existing: true)], const []);
      expect(plan.map((c) => c.name), ['Asha']);
    });
  });

  group('findDuplicateGroups', () {
    test('same phone in different formats', () {
      final g = findDuplicateGroups([
        person('1', 'Asha', phone: '+91 98765 43210'),
        person('2', 'A. Sharma', phone: '09876543210'),
        person('3', 'Other', phone: '9000000001'),
      ]);
      expect(g.length, 1);
      expect(g.single.map((p) => p.id), ['1', '2']);
    });

    test('same name ignoring case and spaces', () {
      final g = findDuplicateGroups([
        person('1', 'Ravi Kumar'),
        person('2', 'ravi   kumar'),
        person('3', 'Ravi'),
      ]);
      expect(g.single.map((p) => p.id), ['1', '2']);
    });

    test('groups are transitive', () {
      final g = findDuplicateGroups([
        person('1', 'Asha', phone: '9876543210'),
        person('2', 'Asha Devi', phone: '9876543210'),
        person('3', 'asha devi', phone: '9111111111'),
      ]);
      expect(g.length, 1);
      expect(g.single.length, 3);
    });

    test('empty and missing phones never match each other', () {
      final g = findDuplicateGroups([
        person('1', 'A'),
        person('2', 'B', phone: ''),
        person('3', 'C', phone: '123'),
        person('4', 'D', phone: '123'),
      ]);
      expect(g, isEmpty);
    });

    test('different numbers with the same country code are not duplicates', () {
      final g = findDuplicateGroups([
        person('1', 'A', phone: '+91 98765 43210'),
        person('2', 'B', phone: '+91 91234 56789'),
      ]);
      expect(g, isEmpty);
    });

    test('each group is oldest first and groups are ordered by name', () {
      final g = findDuplicateGroups([
        person('z2', 'Zed', day: 5),
        person('z1', 'zed', day: 2),
        person('a2', 'Amy', day: 9),
        person('a1', 'amy', day: 3),
      ]);
      expect(g.map((x) => x.map((p) => p.id).toList()), [
        ['a1', 'a2'],
        ['z1', 'z2'],
      ]);
    });

    test('nothing to find', () {
      expect(findDuplicateGroups(const []), isEmpty);
      expect(findDuplicateGroups([person('1', 'Solo')]), isEmpty);
    });
  });
}
