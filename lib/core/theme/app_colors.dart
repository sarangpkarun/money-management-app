import 'package:flutter/material.dart';

/// Status colours from the product doc (6.1). Green always means money in, red
/// always means money out.
class AppColors {
  const AppColors._();

  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  /// To receive / Paid.
  static Color receive(BuildContext c) =>
      _dark(c) ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);

  /// To pay / Overdue.
  static Color pay(BuildContext c) =>
      _dark(c) ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  /// Pending / Due soon.
  static Color pending(BuildContext c) =>
      _dark(c) ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B);

  /// Partially paid.
  static Color partial(BuildContext c) =>
      _dark(c) ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
}
