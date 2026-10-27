import 'package:cloud_firestore/cloud_firestore.dart';

enum TripRole { owner, editor, viewer }

String tripRoleLabel(TripRole r) => switch (r) {
  TripRole.owner => 'Owner',
  TripRole.editor => 'Editor',
  TripRole.viewer => 'Viewer',
};

/// How a member's email is used as a map key: lowercased, with `.` swapped for
/// `,` because Firestore reads dots in map keys as paths.
String emailKey(String email) =>
    email.trim().toLowerCase().replaceAll('.', ',');

/// Someone on a trip, identified by email. [uid] is null until the person
/// signs in with that email and the invite is claimed.
class TripMember {
  const TripMember({
    required this.email,
    required this.name,
    required this.role,
    this.uid,
  });

  final String email;
  final String name;
  final TripRole role;
  final String? uid;

  bool get pending => uid == null;
  bool get canEdit => role != TripRole.viewer;

  TripMember copyWith({String? name, TripRole? role, String? uid}) =>
      TripMember(
        email: email,
        name: name ?? this.name,
        role: role ?? this.role,
        uid: uid ?? this.uid,
      );

  Map<String, dynamic> toMap() => {
    'email': email,
    'name': name,
    'role': role.name,
    'uid': uid,
  };

  factory TripMember.fromMap(Map<String, dynamic> m) => TripMember(
    email: m['email'] as String,
    name: (m['name'] as String?) ?? (m['email'] as String),
    role: TripRole.values.byName((m['role'] as String?) ?? 'viewer'),
    uid: m['uid'] as String?,
  );
}

/// A shared plan with a roadmap of stops, expenses and a group of members.
/// Lives in the top-level `trips` collection so every member can read it.
class Trip {
  const Trip({
    this.id = '',
    required this.name,
    this.description,
    this.startDate,
    this.endDate,
    required this.ownerUid,
    required this.members,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final String ownerUid;
  final List<TripMember> members;
  final DateTime createdAt;

  TripMember? memberByEmail(String email) {
    final key = emailKey(email);
    for (final m in members) {
      if (emailKey(m.email) == key) return m;
    }
    return null;
  }

  TripMember? memberByUid(String uid) {
    for (final m in members) {
      if (m.uid == uid) return m;
    }
    return null;
  }

  /// The signed-in person's role, matched by uid, then by email.
  TripRole? roleOf({String? uid, String? email}) {
    final m =
        (uid == null ? null : memberByUid(uid)) ??
        (email == null ? null : memberByEmail(email));
    return m?.role;
  }

  Trip copyWith({
    String? name,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    List<TripMember>? members,
  }) => Trip(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    ownerUid: ownerUid,
    members: members ?? this.members,
    createdAt: createdAt,
  );

  /// The lists besides `members` exist so security rules and queries can
  /// check membership without walking the map.
  Map<String, dynamic> toMap() => {
    'name': name,
    'description': description,
    'startDate': startDate == null ? null : Timestamp.fromDate(startDate!),
    'endDate': endDate == null ? null : Timestamp.fromDate(endDate!),
    'ownerUid': ownerUid,
    'members': {for (final m in members) emailKey(m.email): m.toMap()},
    'memberEmails': [for (final m in members) m.email.toLowerCase()],
    'memberUids': [
      for (final m in members)
        if (m.uid != null) m.uid,
    ],
    'editorUids': [
      for (final m in members)
        if (m.uid != null && m.canEdit) m.uid,
    ],
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory Trip.fromMap(String id, Map<String, dynamic> m) {
    final raw = (m['members'] as Map?) ?? const {};
    final members = [
      for (final v in raw.values)
        TripMember.fromMap(Map<String, dynamic>.from(v as Map)),
    ];
    members.sort((a, b) {
      final byRole = a.role.index.compareTo(b.role.index);
      return byRole != 0
          ? byRole
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return Trip(
      id: id,
      name: m['name'] as String,
      description: m['description'] as String?,
      startDate: (m['startDate'] as Timestamp?)?.toDate(),
      endDate: (m['endDate'] as Timestamp?)?.toDate(),
      ownerUid: m['ownerUid'] as String,
      members: members,
      createdAt: (m['createdAt'] as Timestamp).toDate(),
    );
  }
}
