import 'package:flutter/material.dart';

enum AppThemeMode { light, dark, midnight }

class AppTheme {
  // Brand Colors - Royal Electric Blue Accent & Clean White Surfaces
  static const Color royalBluePrimary = Color(0xFF2867E4);
  static const Color royalBlueLightBg = Color(0xFFF4F7FC);
  static const Color royalBlueLightCard = Colors.white;
  static const Color royalBlueBorderLight = Color(0xFFE2E8F0);
  
  static const Color royalBlueDarkBg = Color(0xFF090D16);
  static const Color royalBlueDarkCard = Color(0xFF111726);
  static const Color royalBlueBorderDark = Color(0xFF1E293B);

  static const Color skyAccent = Color(0xFF4F8CF6);
  static const Color indigoAccent = Color(0xFF6366F1);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: royalBlueLightBg,
      colorScheme: const ColorScheme.light(
        surface: royalBlueLightCard,
        primary: royalBluePrimary,
        secondary: skyAccent,
        tertiary: indigoAccent,
        error: Color(0xFFDC2626),
        onSurface: Color(0xFF0F172A),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: royalBlueLightBg,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Color(0xFF0F172A)),
        titleTextStyle: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: royalBlueLightCard,
        elevation: 0,
        shadowColor: const Color(0x0C2867E4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: royalBlueBorderLight),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: royalBluePrimary,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: royalBluePrimary.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: royalBluePrimary,
        secondarySelectedColor: royalBluePrimary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: royalBlueBorderLight),
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
        secondaryLabelStyle: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: royalBlueDarkBg,
      colorScheme: const ColorScheme.dark(
        surface: royalBlueDarkCard,
        primary: royalBluePrimary,
        secondary: skyAccent,
        tertiary: indigoAccent,
        error: Color(0xFFEF4444),
        onSurface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: royalBlueDarkBg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: royalBlueDarkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: royalBlueBorderDark),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: royalBluePrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  static ThemeData get midnightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        surface: Color(0xFF121212),
        primary: royalBluePrimary,
        secondary: skyAccent,
        error: Color(0xFFEF4444),
        onSurface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF121212),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF262626)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: royalBluePrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }
}
