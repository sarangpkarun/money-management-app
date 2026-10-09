import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/data/user_repository.dart';
import '../core/models/app_user.dart';

String authErrorMessage(String code) => switch (code) {
  'wrong-password' ||
  'invalid-credential' ||
  'user-not-found' => 'Incorrect email or password.',
  'email-already-in-use' => 'An account with this email already exists.',
  'weak-password' => 'Password must be at least 6 characters.',
  'invalid-email' => 'Enter a valid email address.',
  'network-request-failed' => 'No internet connection. Try again.',
  'too-many-requests' => 'Too many attempts. Please wait and try again.',
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

  /// Creates the account, stores the profile and sends the verification email.
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
    await UserRepository(_db, user.uid).save(AppUser(name: name.trim()));
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
