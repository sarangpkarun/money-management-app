import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/auth/auth_repository.dart';

void main() {
  accountTests();
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore db;
  late AuthRepository repo;

  setUp(() {
    auth = MockFirebaseAuth();
    db = FakeFirebaseFirestore();
    repo = AuthRepository(auth, db);
  });

  test('signUp creates the user, sets the name and saves a profile', () async {
    await repo.signUp(
      name: 'Sarang',
      email: 'a@b.com',
      password: 'password123',
    );
    final user = auth.currentUser!;
    expect(user.email, 'a@b.com');
    expect(user.displayName, 'Sarang');
    final profile = await db.collection('users').doc(user.uid).get();
    expect(profile.data()!['name'], 'Sarang');
    expect(profile.data()!['currency'], 'INR');
  });

  test('signIn then signOut', () async {
    await repo.signUp(
      name: 'Sarang',
      email: 'a@b.com',
      password: 'password123',
    );
    await repo.signOut();
    expect(auth.currentUser, isNull);
    await repo.signIn(email: 'a@b.com', password: 'password123');
    expect(auth.currentUser, isNotNull);
  });

  group('friendly error messages', () {
    test('known codes', () {
      expect(authErrorMessage('wrong-password'), contains('password'));
      expect(authErrorMessage('invalid-credential'), contains('password'));
      expect(authErrorMessage('user-not-found'), contains('password'));
      expect(authErrorMessage('email-already-in-use'), contains('already'));
      expect(authErrorMessage('weak-password'), contains('6'));
      expect(authErrorMessage('invalid-email'), contains('email'));
      expect(authErrorMessage('network-request-failed'), contains('internet'));
      expect(authErrorMessage('too-many-requests'), contains('Too many'));
    });

    test('unknown code falls back', () {
      expect(authErrorMessage('something-else'), contains('went wrong'));
    });

    test('AuthFailure wraps a FirebaseAuthException', () {
      final f = AuthFailure.from(FirebaseAuthException(code: 'weak-password'));
      expect(f.message, authErrorMessage('weak-password'));
    });
  });

  group('validators', () {
    test('name', () {
      expect(validateName(''), isNotNull);
      expect(validateName('  '), isNotNull);
      expect(validateName('Sarang'), isNull);
    });
    test('email', () {
      expect(validateEmail('nope'), isNotNull);
      expect(validateEmail('a@b'), isNotNull);
      expect(validateEmail('a@b.com'), isNull);
    });
    test('password needs 8 characters', () {
      expect(validatePassword('short'), isNotNull);
      expect(validatePassword('longenough'), isNull);
    });
  });
}

void accountTests() {
  group('account management', () {
    late MockFirebaseAuth auth;
    late FakeFirebaseFirestore db;
    late AuthRepository repo;

    setUp(() async {
      auth = MockFirebaseAuth();
      db = FakeFirebaseFirestore();
      repo = AuthRepository(auth, db);
      await repo.signUp(
        name: 'Sarang',
        email: 'a@b.com',
        password: 'password123',
      );
    });

    test('updateDisplayName changes the auth name', () async {
      await repo.updateDisplayName('  New Name ');
      expect(auth.currentUser!.displayName, 'New Name');
    });

    test('deleteAccount wipes the user data', () async {
      final uid = auth.currentUser!.uid;
      await db.collection('users').doc(uid).collection('people').add({
        'name': 'Asha',
      });
      await repo.deleteAccount('password123');
      expect((await db.collection('users').doc(uid).get()).exists, isFalse);
      expect(
        (await db.collection('users').doc(uid).collection('people').get()).docs,
        isEmpty,
      );
      // user.delete() signing out is real Firebase behaviour that the mock
      // does not simulate, so it is verified manually on a device.
    });

    test('requires-recent-login has a friendly message', () {
      expect(
        authErrorMessage('requires-recent-login'),
        contains('log in again'),
      );
    });
  });
}
