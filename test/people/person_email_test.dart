import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/people/person_form_screen.dart';

void main() {
  test('isValidEmail', () {
    expect(isValidEmail('a@b.com'), isTrue);
    expect(isValidEmail('a@b'), isFalse);
    expect(isValidEmail('a b@c.com'), isFalse);
  });

  testWidgets('the person form saves a lowercased email and rejects a bad one', (
    tester,
  ) async {
    final repo = PeopleRepository(FakeFirebaseFirestore(), 'u1');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [peopleRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: PersonFormScreen()),
      ),
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Asha');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email (optional)'),
      'asha@',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect((await tester.runAsync(repo.getAll))!, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email (optional)'),
      'Asha@Example.com',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = (await tester.runAsync(repo.getAll))!.single;
    expect(saved.email, 'asha@example.com');
  });
}
