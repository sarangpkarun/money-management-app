import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/data/user_repository.dart';

String authErrorMessage(String code) => switch (code) {
  'wrong-password' ||
  'invalid-credential' ||
  'user-not-found' => 'Incorrect email or password.',
  'email-already-in-use' => 'An account with this email already exists.',
  'weak-password' => 'Password must be at least 6 characters.',
  'invalid-email' => 'Enter a valid email address.',
  'network-request-failed' => 'No internet connection. Try again.',
  'too-many-requests' => 'Too many attempts. Please wait and try again.',
  'requires-recent-login' => 'For security, please log in again and retry.',
  'user-disabled' => 'This account has been disabled.',
  'operation-not-allowed' || 'configuration-not-found' =>
    'Email/password sign-in is not enabled for this project yet.',
  _ => 'Something went wrong ($code). Please try again.',
};

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  factory AuthFailure.from(FirebaseAuthException e) =>
      AuthFailure(authErrorMessage(e.code));

  final String message;

  @override
  String toString() => message;
}

String? validateName(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Enter your name' : null;

String? validateEmail(String? v) {
  final text = v?.trim() ?? '';
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)
      ? null
      : 'Enter a valid email address';
}

String? validatePassword(String? v) =>
    (v == null || v.length < 8) ? 'Use at least 8 characters' : null;

class AuthRepository {
  AuthRepository(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  Stream<User?> userChanges() => _auth.userChanges();
  User? get currentUser => _auth.currentUser;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.from(e);
    }
  }

  /// Creates the account and sends the verification email. The Firestore
  /// profile is created later, once the email is verified (the security rules
  /// only allow verified users to write).
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) => _guard(() async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user!;
    await user.updateDisplayName(name.trim());
    await user.sendEmailVerification();
  });

  Future<void> signIn({required String email, required String password}) =>
      _guard(
        () => _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ),
      );

  Future<void> signOut() => _auth.signOut();

  Future<void> updateDisplayName(String name) =>
      _guard(() async => _auth.currentUser?.updateDisplayName(name.trim()));

  /// Re-checks the password, erases all the user's Firestore data, then deletes
  /// the account. (Cloud Functions cleanup is added in Phase 2 as a backstop.)
  Future<void> deleteAccount(String password) => _guard(() async {
    final user = _auth.currentUser!;
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: password),
    );
    await UserRepository(_db, user.uid).deleteAllData();
    await user.delete();
  });

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  Future<void> resendVerification() =>
      _guard(() async => _auth.currentUser?.sendEmailVerification());

  /// Refreshes the user so `emailVerified` reflects a link clicked elsewhere.
  Future<void> reloadUser() => _guard(() async {
    await _auth.currentUser?.reload();
    await _auth.currentUser?.getIdToken(true);
  });
}
