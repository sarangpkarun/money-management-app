import 'package:flutter/painting.dart';

/// The WCAG contrast ratio between two opaque colours: 1 (none) to 21 (black on
/// white). Body text should reach 4.5, large text and icons 3.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// [foreground] drawn over [background], so a translucent colour can be checked
/// as it will actually look.
Color over(Color foreground, Color background) =>
    Color.alphaBlend(foreground, background);
