import 'package:flutter/material.dart';

import '../core/models/trip_stop.dart';

IconData stopIcon(StopType t) => switch (t) {
  StopType.stay => Icons.hotel_outlined,
  StopType.travel => Icons.directions_bus_outlined,
  StopType.food => Icons.restaurant_outlined,
  StopType.activity => Icons.local_activity_outlined,
  StopType.other => Icons.place_outlined,
};

/// The stop type an expense category label stands for. Missing or custom
/// categories count as [StopType.other].
StopType categoryType(String? category) {
  for (final t in StopType.values) {
    if (stopTypeLabel(t).toLowerCase() == category?.trim().toLowerCase()) {
      return t;
    }
  }
  return StopType.other;
}

/// The label an expense is filed under; unknown categories fall under Other.
String categoryLabel(String? category) => stopTypeLabel(categoryType(category));

IconData categoryIcon(String? category) => stopIcon(categoryType(category));

/// One colour per category, used on the roadmap, in expenses and in forms.
Color stopTypeColor(StopType t) => switch (t) {
  StopType.stay => const Color(0xFF5C6BC0),
  StopType.travel => const Color(0xFF1E88E5),
  StopType.food => const Color(0xFFEF6C00),
  StopType.activity => const Color(0xFF2E9E5B),
  StopType.other => const Color(0xFF78909C),
};

Color categoryColor(String? category) => stopTypeColor(categoryType(category));

/// Text and icon colour for [c], lightened on dark themes so it stays legible.
Color categoryForeground(BuildContext context, Color c) =>
    Theme.of(context).brightness == Brightness.dark
    ? Color.lerp(c, Colors.white, 0.35)!
    : c;

Color categoryBackground(Color c) => c.withValues(alpha: 0.18);

/// A round icon in the category's colour.
Widget categoryAvatar(BuildContext context, String? category, {double r = 18}) {
  final c = categoryColor(category);
  return CircleAvatar(
    radius: r,
    backgroundColor: categoryBackground(c),
    child: Icon(
      categoryIcon(category),
      size: r,
      color: categoryForeground(context, c),
    ),
  );
}
