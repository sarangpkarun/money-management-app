import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore paths under `users/{uid}`, matching the data model in the product
/// doc and the security rules.
class UserPaths {
  const UserPaths(this.db, this.uid);

  final FirebaseFirestore db;
  final String uid;

  DocumentReference<Map<String, dynamic>> get user =>
      db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> get people =>
      user.collection('people');
  CollectionReference<Map<String, dynamic>> get transactions =>
      user.collection('transactions');
  CollectionReference<Map<String, dynamic>> get reminders =>
      user.collection('reminders');
  CollectionReference<Map<String, dynamic>> get logs => user.collection('logs');
  CollectionReference<Map<String, dynamic>> payments(String txnId) =>
      transactions.doc(txnId).collection('payments');
}
