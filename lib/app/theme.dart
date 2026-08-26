import 'package:flutter/material.dart';
import 'theme_controller.dart';

/// Colors branch on [ThemeController] so every existing `AppColors.x` call
/// site across the app is dark-mode aware automatically, with no rewrite of
/// the widgets that reference them.
class AppColors {
  static bool get _dark => ThemeController().isDark;

  static Color get primary => _dark ? const Color(0xFF14B8A6) : const Color(0xFF0D9488);
  static Color get primaryDark => _dark ? const Color(0xFF0D9488) : const Color(0xFF0F766E);
  static Color get background => _dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  static Color get surface => _dark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF);

  static Color get textPrimary => _dark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
  static Color get textSecondary => _dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static Color get border => _dark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
}

class AppTheme {
  static ThemeData get lightTheme => _buildTheme(
        primary: const Color(0xFF0D9488),
        background: const Color(0xFFF8FAFC),
        surface: const Color(0xFFFFFFFF),
        textPrimary: const Color(0xFF1E293B),
        border: const Color(0xFFE2E8F0),
        brightness: Brightness.light,
      );

  static ThemeData get darkTheme => _buildTheme(
        primary: const Color(0xFF14B8A6),
        background: const Color(0xFF0F172A),
        surface: const Color(0xFF1E293B),
        textPrimary: const Color(0xFFF1F5F9),
        border: const Color(0xFF334155),
        brightness: Brightness.dark,
      );

  static ThemeData _buildTheme({
    required Color primary,
    required Color background,
    required Color surface,
    required Color textPrimary,
    required Color border,
    required Brightness brightness,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        primary: primary,
        surface: surface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
