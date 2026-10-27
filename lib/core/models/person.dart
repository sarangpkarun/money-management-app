import 'package:cloud_firestore/cloud_firestore.dart';

/// A light check: something@something.tld, no spaces.
bool isValidEmail(String s) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s.trim());

class Person {
  const Person({
    this.id = '',
    required this.name,
    this.phone,
    this.email,
    this.notes,
    this.photoUrl,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? phone;

  /// Lowercased. Only people with an email can be added to a trip.
  final String? email;
  final String? notes;
  final String? photoUrl;
  final DateTime createdAt;

  Person copyWith({
    String? name,
    String? phone,
    String? email,
    String? notes,
    String? photoUrl,
  }) => Person(
    id: id,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    notes: notes ?? this.notes,
    photoUrl: photoUrl ?? this.photoUrl,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'phone': phone,
    'email': email,
    'notes': notes,
    'photoUrl': photoUrl,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory Person.fromMap(String id, Map<String, dynamic> m) => Person(
    id: id,
    name: m['name'] as String,
    phone: m['phone'] as String?,
    email: m['email'] as String?,
    notes: m['notes'] as String?,
    photoUrl: m['photoUrl'] as String?,
    createdAt: (m['createdAt'] as Timestamp).toDate(),
  );
}
