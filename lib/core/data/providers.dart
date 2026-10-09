import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'payment_repository.dart';
import 'people_repository.dart';
import 'transaction_repository.dart';
import 'user_repository.dart';

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

/// The signed-in user's uid. Throws if nobody is signed in; screens behind the
/// auth gate (added with the Auth step) can rely on it being set.
final uidProvider = Provider<String>((ref) {
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
