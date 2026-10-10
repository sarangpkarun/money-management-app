import 'package:flutter/material.dart';

/// Status colours from the product doc (6.1). Green always means money in, red
/// always means money out.
class AppColors {
  const AppColors._();

  // The light-theme colours are dark enough to read as text on white (at least
  // 4.5:1, also on their own 15% tint); the dark-theme ones are the bright
  // originals. See test/core/theme/contrast_test.dart.

  static Color receiveFor(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF4ADE80) : const Color(0xFF166534);

  static Color payFor(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFF87171) : const Color(0xFFB91C1C);

  static Color pendingFor(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFFBBF24) : const Color(0xFF92400E);

  static Color partialFor(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);

  /// To receive / Paid.
  static Color receive(BuildContext c) => receiveFor(Theme.of(c).brightness);

  /// To pay / Overdue.
  static Color pay(BuildContext c) => payFor(Theme.of(c).brightness);

  /// Pending / Due soon.
  static Color pending(BuildContext c) => pendingFor(Theme.of(c).brightness);

  /// Partially paid.
  static Color partial(BuildContext c) => partialFor(Theme.of(c).brightness);
}
