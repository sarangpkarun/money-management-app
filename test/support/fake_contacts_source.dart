import 'package:money_manager/people/contact_import.dart';
import 'package:money_manager/people/contacts_source.dart';

class FakeContactsSource implements ContactsSource {
  FakeContactsSource({
    this.access = ContactsAccess.granted,
    this.contacts = const [],
    this.picked,
  });

  ContactsAccess access;

  /// What the phone grants if the user taps "Allow access" after a denial.
  ContactsAccess? accessAfterRetry;
  List<ContactInfo> contacts;
  ContactInfo? picked;
  int accessRequests = 0;
  int loads = 0;

  @override
  Future<ContactsAccess> requestAccess() async {
    accessRequests++;
    final result = access;
    if (accessAfterRetry != null) access = accessAfterRetry!;
    return result;
  }

  @override
  Future<List<ContactInfo>> loadContacts() async {
    loads++;
    return contacts;
  }

  @override
  Future<ContactInfo?> pickOne() async => picked;
}
