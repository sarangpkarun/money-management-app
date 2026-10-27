import 'package:cloud_firestore/cloud_firestore.dart';

enum StopType { stay, travel, food, activity, other }

String stopTypeLabel(StopType t) => switch (t) {
  StopType.stay => 'Stay',
  StopType.travel => 'Travel',
  StopType.food => 'Food',
  StopType.activity => 'Activity',
  StopType.other => 'Other',
};

/// One step on a trip's roadmap: a room, a journey, a meal, an activity.
class TripStop {
  const TripStop({
    this.id = '',
    required this.title,
    this.type = StopType.other,
    this.date,
    this.place,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String title;
  final StopType type;
  final DateTime? date;
  final String? place;
  final String? notes;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'title': title,
    'type': type.name,
    'date': date == null ? null : Timestamp.fromDate(date!),
    'place': place,
    'notes': notes,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory TripStop.fromMap(String id, Map<String, dynamic> m) => TripStop(
    id: id,
    title: m['title'] as String,
    type: StopType.values.byName((m['type'] as String?) ?? 'other'),
    date: (m['date'] as Timestamp?)?.toDate(),
    place: m['place'] as String?,
    notes: m['notes'] as String?,
    createdAt: (m['createdAt'] as Timestamp).toDate(),
  );
}
