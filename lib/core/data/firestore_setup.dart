import 'package:cloud_firestore/cloud_firestore.dart';

/// Turns on offline persistence so entries made without internet sync later.
/// Call once, after `Firebase.initializeApp`.
void initFirestore() {
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );
}
