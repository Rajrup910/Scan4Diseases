import 'package:flutter/material.dart';

class Themes {
  Themes._();
  static const Color primary = Color(0xFF315CFF);
  static const Color primaryDark = Color(0xFF2347D6);
  static const Color mint = Color(0xFF15B79E);
  static const Color ink = Color(0xFF172033);
  static const Color muted = Color(0xFF6B7280);
  static const Color surface = Color(0xFFF7F9FC);
  static const Color border = Color(0xFFE6EAF0);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC4C64);
  static const Color bluishClr = primary;
  static const Color yellowClr = Color(0xFFFFC857);
  static const Color pinkClr = Color(0xFFFF4667);
  static const Color greenClr = mint;
  static const Color darkGreyClr = Color(0xFF121826);
  static const Color darkHeaderClr = Color(0xFF424B5A);

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: surface,
    colorScheme: ColorScheme.fromSeed(seedColor: primary, brightness: Brightness.light),
    fontFamily: 'Arial',
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: primary, width: 1.5)),
    ),
  );
}
