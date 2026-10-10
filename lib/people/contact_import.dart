import '../core/models/person.dart';

/// A contact from the phone: a name and (if it has one) a phone number.
class ContactInfo {
  const ContactInfo({required this.name, this.phone});

  final String name;
  final String? phone;
}

/// Digits of [raw] to compare numbers by: the last 10 digits, so
/// `+91 98765 43210`, `098765 43210` and `9876543210` match. Anything with fewer
/// than 7 digits is too short to trust and gives an empty key (it matches
/// nothing).
String normalizePhone(String? raw) {
  if (raw == null) return '';
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 7) return '';
  return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
}

/// A name to compare people by: trimmed, lower-case, spaces collapsed.
String nameKey(String? name) =>
    (name ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// A contact in the import list, and whether the person is already in People.
class ImportCandidate {
  const ImportCandidate({required this.contact, required this.existing});

  final ContactInfo contact;
  final bool existing;
}

bool _matchesExisting(ContactInfo c, Iterable<Person> people) {
  final phone = normalizePhone(c.phone);
  final name = nameKey(c.name);
  for (final p in people) {
    if (phone.isNotEmpty && normalizePhone(p.phone) == phone) return true;
    if (name.isNotEmpty && nameKey(p.name) == name) return true;
  }
  return false;
}

/// The import list: every contact with a name, marked when it matches someone
/// already in People (same number, or same name).
List<ImportCandidate> importCandidates(
  List<ContactInfo> contacts,
  List<Person> existing,
) => [
  for (final c in contacts)
    if (c.name.trim().isNotEmpty)
      ImportCandidate(contact: c, existing: _matchesExisting(c, existing)),
];

/// The people to create from [selected]: blank names and anyone already in
/// People are skipped, and the same person picked twice (same number or name)
/// is added once.
List<ContactInfo> planImport(
  List<ImportCandidate> selected,
  List<Person> existing,
) {
  final out = <ContactInfo>[];
  final phones = <String>{};
  final names = <String>{};
  for (final s in selected) {
    final c = s.contact;
    final name = nameKey(c.name);
    final phone = normalizePhone(c.phone);
    if (name.isEmpty) continue;
    if (_matchesExisting(c, existing)) continue;
    if (names.contains(name) || (phone.isNotEmpty && phones.contains(phone))) {
      continue;
    }
    names.add(name);
    if (phone.isNotEmpty) phones.add(phone);
    out.add(ContactInfo(name: c.name.trim(), phone: c.phone?.trim()));
  }
  return out;
}
