import 'package:flutter/material.dart';

const _palette = <Color>[
  Color(0xFF3F51B5),
  Color(0xFF009688),
  Color(0xFFE65100),
  Color(0xFF8E24AA),
  Color(0xFF00796B),
  Color(0xFFC2185B),
  Color(0xFF455A64),
  Color(0xFF6D4C41),
];

/// Up to two capital letters from the first two words of [name].
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.take(2).map((w) => w[0].toUpperCase()).join();
}

/// The same name always gets the same colour.
Color avatarColorFor(String name) {
  final sum = name.trim().toLowerCase().codeUnits.fold<int>(0, (a, b) => a + b);
  return _palette[sum % _palette.length];
}

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.radius = 22});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = initialsOf(name);
    return CircleAvatar(
      radius: radius,
      backgroundColor: avatarColorFor(name),
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
