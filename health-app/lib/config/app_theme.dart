import 'package:flutter/material.dart';

class AppTheme {
  // Color Palette
  static const Color primaryBlue = Color(0xFF4F46E5); // Primary brand color
  static const Color primaryDark = Color(0xFF1F2937); // Dark background
  static const Color accentGreen = Color(0xFF10B981); // Positive/normal status
  static const Color accentOrange = Color(0xFFF59E0B); // Warning/elevated
  static const Color accentRed = Color(0xFFEF4444); // Critical/alert
  static const Color accentPurple = Color(0xFFA78BFA); // Secondary accent

  static const Color white = Color(0xFFFFFFFF);
  static const Color lightGray = Color(0xFFF3F4F6);
  static const Color mediumGray = Color(0xFFE5E7EB);
  static const Color darkGray = Color(0xFF6B7280);
  static const Color veryDarkGray = Color(0xFF374151);

  // Semantic colors
  static const Color successColor = accentGreen;
  static const Color warningColor = accentOrange;
  static const Color errorColor = accentRed;
  static const Color infoColor = primaryBlue;

  static ThemeData getLightTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.light(
        primary: primaryBlue,
        secondary: accentPurple,
        tertiary: accentGreen,
        error: accentRed,
        background: white,
        surface: lightGray,
        onPrimary: white,
        onSecondary: white,
        onError: white,
        onBackground: primaryDark,
        onSurface: veryDarkGray,
      ),
      scaffoldBackgroundColor: lightGray,
      appBarTheme: const AppBarTheme(
        backgroundColor: white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: primaryDark,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: primaryDark),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: white,
        elevation: 8,
        selectedItemColor: primaryBlue,
        unselectedItemColor: darkGray,
        selectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),
      cardTheme: CardThemeData(
        color: white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryBlue,
          side: const BorderSide(color: primaryBlue, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightGray,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentRed, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentRed, width: 2),
        ),
        hintStyle: TextStyle(color: darkGray, fontSize: 14),
        labelStyle: TextStyle(color: darkGray, fontSize: 14),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: primaryDark,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: primaryDark,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: primaryDark,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: primaryDark,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: primaryDark,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: primaryDark,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: primaryDark,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: primaryDark,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: primaryDark,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: veryDarkGray,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: darkGray,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: primaryDark,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: darkGray,
        ),
      ),
    );
  }
}
