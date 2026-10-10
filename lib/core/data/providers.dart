import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import 'payment_repository.dart';
import 'people_repository.dart';
import 'reminder_repository.dart';
import 'transaction_repository.dart';
import 'user_repository.dart';

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

/// Emits whenever someone signs in or out, so everything built on [uidProvider]
/// (every repository and stream) follows a change of account.
final _signedInUidProvider = StreamProvider<String?>(
  (ref) => FirebaseAuth.instance.userChanges().map((u) => u?.uid),
);

/// The signed-in user's uid. Throws if nobody is signed in; screens behind the
/// auth gate (added with the Auth step) can rely on it being set.
final uidProvider = Provider<String>((ref) {
  ref.watch(_signedInUidProvider);
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('No signed-in user');
  return user.uid;
});

final peopleRepositoryProvider = Provider(
  (ref) =>
      PeopleRepository(ref.watch(firestoreProvider), ref.watch(uidProvider)),
);

final transactionRepositoryProvider = Provider(
  (ref) => TransactionRepository(
    ref.watch(firestoreProvider),
    ref.watch(uidProvider),
  ),
);

final paymentRepositoryProvider = Provider(
  (ref) =>
      PaymentRepository(ref.watch(firestoreProvider), ref.watch(uidProvider)),
);

final userRepositoryProvider = Provider(
  (ref) => UserRepository(ref.watch(firestoreProvider), ref.watch(uidProvider)),
);

final currentProfileProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(userRepositoryProvider).watch(),
);

final reminderRepositoryProvider = Provider(
  (ref) =>
      ReminderRepository(ref.watch(firestoreProvider), ref.watch(uidProvider)),
);
