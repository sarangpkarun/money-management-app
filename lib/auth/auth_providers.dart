import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/data/user_repository.dart';
import 'auth_repository.dart';

final authRepositoryProvider = Provider(
  (ref) => AuthRepository(FirebaseAuth.instance, ref.watch(firestoreProvider)),
);

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).userChanges(),
);

/// Creates the Firestore profile the first time a verified user is seen.
final profileBootstrapProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null || !user.emailVerified) return;
  await UserRepository(
    ref.watch(firestoreProvider),
    user.uid,
  ).ensureProfile(user.displayName ?? '');
});
