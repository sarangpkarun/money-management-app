import 'package:cloud_firestore/cloud_firestore.dart';

class Person {
  const Person({
    this.id = '',
    required this.name,
    this.phone,
    this.notes,
    this.photoUrl,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? phone;
  final String? notes;
  final String? photoUrl;
  final DateTime createdAt;

  Person copyWith({
    String? name,
    String? phone,
    String? notes,
    String? photoUrl,
  }) => Person(
    id: id,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    notes: notes ?? this.notes,
    photoUrl: photoUrl ?? this.photoUrl,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'phone': phone,
    'notes': notes,
    'photoUrl': photoUrl,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory Person.fromMap(String id, Map<String, dynamic> m) => Person(
    id: id,
    name: m['name'] as String,
    phone: m['phone'] as String?,
    notes: m['notes'] as String?,
    photoUrl: m['photoUrl'] as String?,
    createdAt: (m['createdAt'] as Timestamp).toDate(),
  );
}
