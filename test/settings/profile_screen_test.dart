import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/auth/auth_providers.dart';
import 'package:money_manager/auth/auth_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/user_repository.dart';
import 'package:money_manager/settings/profile_screen.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;

  Future<void> pumpScreen(WidgetTester tester) async {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'u1', email: 'a@b.com', displayName: 'Sarang'),
    );
    await db.collection('users').doc('u1').set({
      'name': 'Sarang',
      'currency': 'INR',
      'timezone': 'Asia/Kolkata',
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userRepositoryProvider.overrideWithValue(UserRepository(db, 'u1')),
          authRepositoryProvider.overrideWithValue(AuthRepository(auth, db)),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the saved profile and saves edits', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Sarang'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Sarang P');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = (await db.collection('users').doc('u1').get()).data()!;
    expect(saved['name'], 'Sarang P');
    expect(find.text('Profile saved'), findsOneWidget);
  });

  testWidgets('empty name is rejected', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(
      (await db.collection('users').doc('u1').get()).data()!['name'],
      'Sarang',
    );
  });

  testWidgets('delete dialog needs a password before it can be confirmed', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.ensureVisible(find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    final confirm = find.widgetWithText(TextButton, 'Delete forever');
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'secret',
    );
    await tester.pump();
    expect(tester.widget<TextButton>(confirm).onPressed, isNotNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await db.collection('users').doc('u1').get()).exists, isTrue);
  });
}
