import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/auth/auth_gate.dart';
import 'package:money_manager/auth/auth_providers.dart';

Widget app(User? user) => ProviderScope(
  overrides: [authStateProvider.overrideWith((ref) => Stream.value(user))],
  child: const MaterialApp(home: AuthGate(home: Text('HOME'))),
);

void main() {
  testWidgets('signed out shows login', (tester) async {
    await tester.pumpWidget(app(null));
    await tester.pump();
    expect(find.text('Log in'), findsWidgets);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('unverified user is held on verify screen', (tester) async {
    await tester.pumpWidget(
      app(MockUser(email: 'a@b.com', isEmailVerified: false)),
    );
    await tester.pump();
    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('verified user reaches home', (tester) async {
    await tester.pumpWidget(
      app(MockUser(email: 'a@b.com', isEmailVerified: true)),
    );
    await tester.pump();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('login form validates before submitting', (tester) async {
    await tester.pumpWidget(app(null));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('sign up form validates name, email and password', (
    tester,
  ) async {
    await tester.pumpWidget(app(null));
    await tester.pump();
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign up'));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
  });
}
