import 'package:flutter/material.dart';

/// DoseWise visual identity — matches mockup-v1.html.
/// Warm paper + deep teal: friendly and calm, never clinical.
class DoseWiseColors {
  static const Color paper = Color(0xFFFAF8F3);
  static const Color card = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF22312D);
  static const Color muted = Color(0xFF6E7B76);
  static const Color faint = Color(0xFF9AA3A0);
  static const Color line = Color(0xFFEFEAE0);

  static const Color teal = Color(0xFF0E7C6B);
  static const Color tealDark = Color(0xFF0A5F52);
  static const Color tealSoft = Color(0xFFDFF0EA);
  static const Color tealSofter = Color(0xFFEAF3EF);

  static const Color amber = Color(0xFFE8930C);
  static const Color amberDark = Color(0xFFB26A00);
  static const Color amberSoft = Color(0xFFFDF0D9);

  static const Color red = Color(0xFFD64545);
  static const Color redSoft = Color(0xFFFBE7E7);
}

class DoseWiseTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: DoseWiseColors.teal,
      primary: DoseWiseColors.teal,
      surface: DoseWiseColors.paper,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        surface: DoseWiseColors.paper,
        onSurface: DoseWiseColors.ink,
      ),
      scaffoldBackgroundColor: DoseWiseColors.paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: DoseWiseColors.paper,
        foregroundColor: DoseWiseColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: DoseWiseColors.ink,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: DoseWiseColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DoseWiseColors.line),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DoseWiseColors.teal,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DoseWiseColors.teal,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: DoseWiseColors.card,
        selectedItemColor: DoseWiseColors.teal,
        unselectedItemColor: DoseWiseColors.faint,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
