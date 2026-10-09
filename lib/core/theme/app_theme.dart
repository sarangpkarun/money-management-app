import 'package:flutter/material.dart';

/// Light and dark themes built from the product palette (doc 6.1). Status
/// colours (green in, red out, amber pending, blue partial) live in
/// [AppColors] and are picked per brightness there.
class AppTheme {
  const AppTheme._();

  static final ThemeData light = _build(
    brightness: Brightness.light,
    primary: const Color(0xFF3F51B5),
    background: const Color(0xFFF6F7FB),
    surface: const Color(0xFFFFFFFF),
    text: const Color(0xFF111827),
    textSecondary: const Color(0xFF6B7280),
    divider: const Color(0xFFE5E7EB),
    error: const Color(0xFFDC2626),
  );

  static final ThemeData dark = _build(
    brightness: Brightness.dark,
    primary: const Color(0xFF8C9EFF),
    background: const Color(0xFF0F1115),
    surface: const Color(0xFF1A1D24),
    text: const Color(0xFFF3F4F6),
    textSecondary: const Color(0xFF9CA3AF),
    divider: const Color(0xFF2A2F3A),
    error: const Color(0xFFF87171),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color background,
    required Color surface,
    required Color text,
    required Color textSecondary,
    required Color divider,
    required Color error,
  }) {
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    );
    final scheme = base.copyWith(
      primary: primary,
      onPrimary: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF0F1115),
      surface: surface,
      onSurface: text,
      onSurfaceVariant: textSecondary,
      outlineVariant: divider,
      error: error,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      dividerTheme: DividerThemeData(color: divider, space: 1, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: buttonShape,
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: buttonShape,
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.15),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
    );
  }
}
