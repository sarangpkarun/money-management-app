import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import 'paths.dart';

class UserRepository {
  UserRepository(FirebaseFirestore db, String uid)
    : _paths = UserPaths(db, uid);

  final UserPaths _paths;

  Future<AppUser?> get() async {
    final data = (await _paths.user.get()).data();
    return data == null ? null : AppUser.fromMap(data);
  }

  Future<void> save(AppUser user) =>
      _paths.user.set(user.toMap(), SetOptions(merge: true));
}
