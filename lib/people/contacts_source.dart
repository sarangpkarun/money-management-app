import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'contact_import.dart';

/// What the phone said when asked for access to contacts.
enum ContactsAccess {
  granted,

  /// Refused this time; asking again can show the system prompt.
  denied,

  /// Refused for good: only the phone's settings can change it.
  blocked,
}

/// The phone's contacts (the real plugin on a phone, a fake in tests).
abstract class ContactsSource {
  Future<ContactsAccess> requestAccess();

  /// Every contact that has a name, with its primary (else first) number.
  Future<List<ContactInfo>> loadContacts();

  /// Shows the phone's own contact picker; null if the user cancels. The picker
  /// needs no permission, but without it only the name comes back.
  Future<ContactInfo?> pickOne();
}

class PluginContactsSource implements ContactsSource {
  const PluginContactsSource();

  static String? _primary(List<Phone> phones) {
    if (phones.isEmpty) return null;
    for (final p in phones) {
      if (p.isPrimary == true) return p.number;
    }
    return phones.first.number;
  }

  @override
  Future<ContactsAccess> requestAccess() async {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    return switch (status) {
      PermissionStatus.granted ||
      PermissionStatus.limited => ContactsAccess.granted,
      PermissionStatus.permanentlyDenied ||
      PermissionStatus.restricted => ContactsAccess.blocked,
      _ => ContactsAccess.denied,
    };
  }

  @override
  Future<List<ContactInfo>> loadContacts() async {
    final all = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );
    return [
      for (final c in all)
        if ((c.displayName ?? '').trim().isNotEmpty)
          ContactInfo(name: c.displayName!.trim(), phone: _primary(c.phones)),
    ];
  }

  @override
  Future<ContactInfo?> pickOne() async {
    Contact? picked;
    try {
      picked = await FlutterContacts.native.showPicker(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
    } on PlatformException {
      // No contacts permission: the picker still works for the name alone.
      picked = await FlutterContacts.native.showPicker();
    }
    if (picked == null || (picked.displayName ?? '').trim().isEmpty) {
      return null;
    }
    return ContactInfo(
      name: picked.displayName!.trim(),
      phone: _primary(picked.phones),
    );
  }
}
