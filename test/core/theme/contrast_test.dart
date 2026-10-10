import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/theme/app_colors.dart';
import 'package:money_manager/core/theme/app_theme.dart';
import 'package:money_manager/core/theme/contrast.dart';

class ContrastPair {
  const ContrastPair(
    this.label,
    this.foreground,
    this.background,
    this.minimum,
  );

  final String label;
  final Color foreground;
  final Color background;
  final double minimum;

  double get ratio => contrastRatio(foreground, background);
}

const _text = 4.5; // WCAG AA for normal text
const _large = 3.0; // large text, icons and graphics

List<ContrastPair> pairsFor(Brightness b) {
  final theme = b == Brightness.light ? AppTheme.light : AppTheme.dark;
  final s = theme.colorScheme;
  final surface = s.surface;
  final page = theme.scaffoldBackgroundColor;
  final status = {
    'to receive / paid': AppColors.receiveFor(b),
    'to pay / overdue': AppColors.payFor(b),
    'pending': AppColors.pendingFor(b),
    'partially paid': AppColors.partialFor(b),
  };
  return [
    ContrastPair('body text on page', s.onSurface, page, _text),
    ContrastPair('body text on cards', s.onSurface, surface, _text),
    ContrastPair('secondary text on page', s.onSurfaceVariant, page, _text),
    ContrastPair('secondary text on cards', s.onSurfaceVariant, surface, _text),
    ContrastPair('hint text in inputs', s.onSurfaceVariant, surface, _text),
    ContrastPair('links and primary text on cards', s.primary, surface, _text),
    ContrastPair('text on primary buttons', s.onPrimary, s.primary, _text),
    ContrastPair('error text on cards', s.error, surface, _text),
    ContrastPair('error text on page', s.error, page, _text),
    ContrastPair(
      'selected chip text',
      s.onSecondaryContainer,
      s.secondaryContainer,
      _text,
    ),
    ContrastPair('text on the nav bar', s.onSurface, surface, _text),
    for (final e in status.entries) ...[
      ContrastPair('${e.key} text on cards', e.value, surface, _text),
      ContrastPair('${e.key} text on page', e.value, page, _text),
      // The pale pill behind a status badge.
      ContrastPair(
        '${e.key} badge text on its pill (cards)',
        e.value,
        over(e.value.withValues(alpha: 0.15), surface),
        _text,
      ),
      ContrastPair(
        '${e.key} badge text on its pill (page)',
        e.value,
        over(e.value.withValues(alpha: 0.15), page),
        _text,
      ),
      ContrastPair('${e.key} dot on cards', e.value, surface, _large),
    ],
  ];
}

void main() {
  for (final b in [Brightness.light, Brightness.dark]) {
    group('${b.name} theme meets WCAG AA', () {
      for (final p in pairsFor(b)) {
        test(p.label, () {
          expect(
            p.ratio,
            greaterThanOrEqualTo(p.minimum),
            reason:
                '${p.label}: ${p.ratio.toStringAsFixed(2)}:1, needs ${p.minimum}',
          );
        });
      }
    });
  }

  test('white text on the net balance card (both ends of the gradient)', () {
    final muted = Colors.white.withValues(alpha: 0.9);
    for (final end in const [Color(0xFF3F51B5), Color(0xFF283593)]) {
      expect(contrastRatio(over(muted, end), end), greaterThanOrEqualTo(_text));
      expect(contrastRatio(Colors.white, end), greaterThanOrEqualTo(_text));
    }
  });

  group('contrastRatio itself', () {
    test('black on white is 21, same colour is 1', () {
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrastRatio(Colors.white, Colors.black), closeTo(21, 0.01));
      expect(contrastRatio(Colors.red, Colors.red), closeTo(1, 0.001));
    });

    test('known values', () {
      // #767676 on white is the classic 4.54:1 grey.
      expect(
        contrastRatio(const Color(0xFF767676), Colors.white),
        closeTo(4.54, 0.02),
      );
      // Amber on white fails: the old light "pending" colour.
      expect(contrastRatio(const Color(0xFFF59E0B), Colors.white), lessThan(3));
    });

    test('over blends a translucent colour', () {
      expect(
        over(const Color(0x80000000), Colors.white),
        const Color(0xFF7F7F7F),
      );
    });
  });
}
