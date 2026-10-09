import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/theme/app_theme.dart';

void main() {
  group('light theme matches the product palette', () {
    final t = AppTheme.light;
    test('brightness and primary', () {
      expect(t.brightness, Brightness.light);
      expect(t.colorScheme.primary, const Color(0xFF3F51B5));
    });
    test('background, surface and text', () {
      expect(t.scaffoldBackgroundColor, const Color(0xFFF6F7FB));
      expect(t.colorScheme.surface, const Color(0xFFFFFFFF));
      expect(t.colorScheme.onSurface, const Color(0xFF111827));
      expect(t.colorScheme.onSurfaceVariant, const Color(0xFF6B7280));
    });
    test('divider and error (red = money out)', () {
      expect(t.dividerTheme.color, const Color(0xFFE5E7EB));
      expect(t.colorScheme.error, const Color(0xFFDC2626));
    });
  });

  group('dark theme matches the product palette', () {
    final t = AppTheme.dark;
    test('brightness and primary', () {
      expect(t.brightness, Brightness.dark);
      expect(t.colorScheme.primary, const Color(0xFF8C9EFF));
    });
    test('background, surface and text', () {
      expect(t.scaffoldBackgroundColor, const Color(0xFF0F1115));
      expect(t.colorScheme.surface, const Color(0xFF1A1D24));
      expect(t.colorScheme.onSurface, const Color(0xFFF3F4F6));
      expect(t.colorScheme.onSurfaceVariant, const Color(0xFF9CA3AF));
    });
    test('divider and error', () {
      expect(t.dividerTheme.color, const Color(0xFF2A2F3A));
      expect(t.colorScheme.error, const Color(0xFFF87171));
    });
  });

  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    group('${entry.key} shape and inputs', () {
      final t = entry.value;
      test('cards use a 16 px radius', () {
        final shape = t.cardTheme.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(16));
      });
      test('buttons use a 12 px radius', () {
        final shape =
            t.filledButtonTheme.style!.shape!.resolve({})!
                as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(12));
      });
      test('inputs are filled', () {
        expect(t.inputDecorationTheme.filled, isTrue);
      });
    });
  }

  testWidgets('both themes render a screen without errors', (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            appBar: AppBar(title: const Text('T')),
            body: Column(
              children: [
                const Card(child: Text('card')),
                FilledButton(onPressed: () {}, child: const Text('go')),
                const TextField(decoration: InputDecoration(labelText: 'f')),
              ],
            ),
          ),
        ),
      );
      expect(find.text('card'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
