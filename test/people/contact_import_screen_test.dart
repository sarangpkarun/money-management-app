import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/alarm/settings_opener.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/people/contact_import.dart';
import 'package:money_manager/people/contact_import_screen.dart';
import 'package:money_manager/people/contacts_providers.dart';
import 'package:money_manager/people/contacts_source.dart';
import 'package:money_manager/people/person_form_screen.dart';
import 'package:money_manager/people/people_screen.dart';
import 'package:money_manager/reminders/alarm_providers.dart';

import '../support/fake_contacts_source.dart';
import '../support/fake_settings_opener.dart';

void main() {
  late FakeFirebaseFirestore db;
  late PeopleRepository people;
  late FakeSettingsOpener opener;

  setUp(() {
    db = FakeFirebaseFirestore();
    people = PeopleRepository(db, 'u1');
    opener = FakeSettingsOpener();
  });

  const contacts = [
    ContactInfo(name: 'Zoya', phone: '+91 90000 00003'),
    ContactInfo(name: 'Asha Sharma', phone: '98765 43210'),
    ContactInfo(name: 'Ravi Kumar', phone: '+91 91234 56789'),
    ContactInfo(name: 'Meena'),
  ];

  Future<void> pump(
    WidgetTester tester,
    FakeContactsSource source, {
    Widget? screen,
  }) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contactsSourceProvider.overrideWithValue(source),
          peopleRepositoryProvider.overrideWithValue(people),
          transactionRepositoryProvider.overrideWithValue(
            TransactionRepository(db, 'u1'),
          ),
          settingsOpenerProvider.overrideWithValue(opener),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => screen ?? const ContactImportScreen(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<List<Map<String, dynamic>>> stored() async => [
    for (final d in (await db.collection('users/u1/people').get()).docs)
      d.data(),
  ];

  group('with access', () {
    testWidgets('lists contacts by name', (tester) async {
      await pump(tester, FakeContactsSource(contacts: contacts));
      final names = ['Asha Sharma', 'Meena', 'Ravi Kumar', 'Zoya'];
      for (final n in names) {
        expect(find.text(n), findsOneWidget);
      }
      final ys = [for (final n in names) tester.getTopLeft(find.text(n)).dy];
      expect(ys, [...ys]..sort());
      expect(find.text('No number'), findsOneWidget); // Meena
    });

    testWidgets('people already in People are marked and cannot be ticked', (
      tester,
    ) async {
      await people.add(
        Person(
          name: 'Asha',
          phone: '+91 98765 43210',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      await people.add(
        Person(name: 'ravi kumar', createdAt: DateTime(2026, 1, 1)),
      );
      await pump(tester, FakeContactsSource(contacts: contacts));
      expect(find.text('Already added'), findsNWidgets(2));
      final asha = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Asha Sharma'),
      );
      expect(asha.onChanged, isNull);
      expect(asha.value, isTrue);
      final zoya = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Zoya'),
      );
      expect(zoya.onChanged, isNotNull);
      expect(zoya.value, isFalse);
    });

    testWidgets('search by name and by number', (tester) async {
      await pump(tester, FakeContactsSource(contacts: contacts));
      await tester.enterText(find.byType(TextField), 'ravi');
      await tester.pumpAndSettle();
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('Zoya'), findsNothing);
      await tester.enterText(find.byType(TextField), '90000');
      await tester.pumpAndSettle();
      expect(find.text('Zoya'), findsOneWidget);
      expect(find.text('Ravi Kumar'), findsNothing);
      await tester.enterText(find.byType(TextField), 'nobody');
      await tester.pumpAndSettle();
      expect(find.text('No matching contacts'), findsOneWidget);
    });

    testWidgets('Import is off until something is ticked, then counts', (
      tester,
    ) async {
      await pump(tester, FakeContactsSource(contacts: contacts));
      FilledButton button() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Import'),
      );
      expect(button().onPressed, isNull);
      await tester.tap(find.text('Zoya'));
      await tester.tap(find.text('Meena'));
      await tester.pumpAndSettle();
      expect(find.text('Import 2'), findsOneWidget);
    });

    testWidgets(
      'importing creates exactly the ticked people with their number',
      (tester) async {
        await pump(tester, FakeContactsSource(contacts: contacts));
        await tester.tap(find.text('Zoya'));
        await tester.tap(find.text('Meena'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Import 2'));
        await tester.pumpAndSettle();
        final all = await stored();
        expect(all.length, 2);
        expect({for (final p in all) p['name']}, {'Zoya', 'Meena'});
        expect(
          all.firstWhere((p) => p['name'] == 'Zoya')['phone'],
          '+91 90000 00003',
        );
        expect(all.firstWhere((p) => p['name'] == 'Meena')['phone'], isNull);
        expect(find.text('2 added'), findsOneWidget);
        expect(find.text('open'), findsOneWidget); // screen closed
      },
    );

    testWidgets('Select all matching ticks the visible ones, not existing', (
      tester,
    ) async {
      await people.add(Person(name: 'Meena', createdAt: DateTime(2026, 1, 1)));
      await pump(tester, FakeContactsSource(contacts: contacts));
      await tester.tap(find.text('Select all matching'));
      await tester.pumpAndSettle();
      expect(find.text('Import 3'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zoya');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 3'));
      await tester.pumpAndSettle();
      expect((await stored()).length, 4); // Meena + 3 new
    });

    testWidgets('the same person ticked twice is added once and reported', (
      tester,
    ) async {
      final dup = [
        const ContactInfo(name: 'Asha', phone: '98765 43210'),
        const ContactInfo(name: 'Asha S', phone: '+91 98765 43210'),
      ];
      await pump(tester, FakeContactsSource(contacts: dup));
      await tester.tap(find.text('Select all matching'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 2'));
      await tester.pumpAndSettle();
      expect((await stored()).length, 1);
      expect(find.textContaining('1 added, 1 skipped'), findsOneWidget);
    });

    testWidgets('a phone with no contacts says so', (tester) async {
      await pump(tester, FakeContactsSource());
      expect(find.text('No contacts found on this phone'), findsOneWidget);
    });
  });

  group('without access', () {
    testWidgets('denied: explains, and Allow access asks again', (
      tester,
    ) async {
      final src = FakeContactsSource(
        access: ContactsAccess.denied,
        contacts: contacts,
      )..accessAfterRetry = ContactsAccess.granted;
      await pump(tester, src);
      expect(find.textContaining('Allow contacts access'), findsOneWidget);
      expect(src.loads, 0); // nothing read without permission
      await tester.tap(find.text('Allow access'));
      await tester.pumpAndSettle();
      expect(src.accessRequests, 2);
      expect(find.text('Zoya'), findsOneWidget);
    });

    testWidgets('blocked: Open settings, no Allow button', (tester) async {
      await pump(
        tester,
        FakeContactsSource(access: ContactsAccess.blocked, contacts: contacts),
      );
      expect(find.text('Allow access'), findsNothing);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(opener.opened, [SystemSettingsPage.app]);
    });

    testWidgets('the picker fallback adds one person', (tester) async {
      await pump(
        tester,
        FakeContactsSource(
          access: ContactsAccess.denied,
          picked: const ContactInfo(name: 'Picked Pat'),
        ),
      );
      await tester.tap(find.text('Pick one contact instead'));
      await tester.pumpAndSettle();
      expect((await stored()).single['name'], 'Picked Pat');
      expect(find.text('Picked Pat added'), findsOneWidget);
    });

    testWidgets('picking someone already in People adds nothing', (
      tester,
    ) async {
      await people.add(Person(name: 'Pat', createdAt: DateTime(2026, 1, 1)));
      await pump(
        tester,
        FakeContactsSource(
          access: ContactsAccess.denied,
          picked: const ContactInfo(name: ' pat '),
        ),
      );
      await tester.tap(find.text('Pick one contact instead'));
      await tester.pumpAndSettle();
      expect((await stored()).length, 1);
      expect(find.textContaining('already in People'), findsOneWidget);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      await pump(tester, FakeContactsSource(access: ContactsAccess.denied));
      await tester.tap(find.text('Pick one contact instead'));
      await tester.pumpAndSettle();
      expect(await stored(), isEmpty);
    });
  });

  group('Add person form', () {
    testWidgets('Pick from contacts fills the name and number', (tester) async {
      await pump(
        tester,
        FakeContactsSource(
          picked: const ContactInfo(name: 'Neha', phone: '90000 11111'),
        ),
        screen: const PersonFormScreen(),
      );
      await tester.tap(find.text('Pick from contacts'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Neha'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '90000 11111'), findsOneWidget);
    });

    testWidgets('a name-only pick leaves the number alone', (tester) async {
      await pump(
        tester,
        FakeContactsSource(picked: const ContactInfo(name: 'Neha')),
        screen: const PersonFormScreen(),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone (optional)'),
        '12345 67890',
      );
      await tester.tap(find.text('Pick from contacts'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Neha'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '12345 67890'), findsOneWidget);
    });

    testWidgets('not offered when editing an existing person', (tester) async {
      await pump(
        tester,
        FakeContactsSource(),
        screen: PersonFormScreen(
          person: Person(id: 'x', name: 'Old', createdAt: DateTime(2026, 1, 1)),
        ),
      );
      expect(find.text('Pick from contacts'), findsNothing);
    });
  });

  group('People tab entry points', () {
    testWidgets('the toolbar button opens the import screen', (tester) async {
      await pump(
        tester,
        FakeContactsSource(contacts: contacts),
        screen: const PeopleScreen(),
      );
      await tester.tap(find.byTooltip('Import from contacts'));
      await tester.pumpAndSettle();
      expect(find.text('Import from contacts'), findsWidgets);
      expect(find.text('Zoya'), findsOneWidget);
    });

    testWidgets('the empty state offers it too', (tester) async {
      await pump(
        tester,
        FakeContactsSource(contacts: contacts),
        screen: const PeopleScreen(),
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Import from contacts'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Zoya'), findsOneWidget);
    });
  });
}
