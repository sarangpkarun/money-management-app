import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'contacts_source.dart';

/// The phone's contacts. Tests replace it with a fake.
final contactsSourceProvider = Provider<ContactsSource>(
  (ref) => const PluginContactsSource(),
);
