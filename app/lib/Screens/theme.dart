import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design system for the Scan4Disease mobile app.
///
/// Grounded in the same clinical visual language as the S4D doctor portal:
/// - Brand: Clinical Jade / Deep Teal (`#12695A` / `#0D4F44`)
/// - Semantic Triage: Urgent (`#CD2B31`), Prompt (`#946800`), Routine (`#0D6E5B`)
/// - Typography: Clean Geometric / Humanist (Plus Jakarta Sans)
/// - Elevation & Surfaces: Subtle 1px borders, restrained elevation, no AI-slop neon glows.
class Themes {
  Themes._();

  // --- Brand Tokens (matches web portal :root) ---
  static const Color brand = Color(0xFF12695A);
  static const Color brandDark = Color(0xFF0D4F44);
  static const Color brandTint = Color(0xFFE6F2EF);
  static const Color brandHover = Color(0xFF0F5D4F);

  // Vibrant Electric Teal / Cyan Glow
  static const Color tealGlow = Color(0xFF2DD4BF);
  static const Color brandTeal = Color(0xFF14B8A6);
  static const Color tealLight = Color(0xFF6FE0CD);

  // Aliases for compatibility
  static const Color primary = brand;
  static const Color primaryDark = brandDark;
  static const Color mint = Color(0xFF15B79E);

  // --- Semantic Triage Urgency (NHS / Clinical Care Card Tokens) ---
  static const Color urgent = Color(0xFFCD2B31);
  static const Color urgentBg = Color(0xFFFDE8E8);
  static const Color urgentBorder = Color(0xFFF3C9C7);

  static const Color soon = Color(0xFF946800);
  static const Color soonBg = Color(0xFFFFF4E5);
  static const Color soonBorder = Color(0xFFF5DCAE);

  static const Color routine = Color(0xFF0D6E5B);
  static const Color routineBg = Color(0xFFE6F2EF);
  static const Color routineBorder = Color(0xFFBFE0D8);

  // Danger & Warning
  static const Color danger = urgent;
  static const Color dangerTint = urgentBg;
  static const Color warning = soon;
  static const Color warningTint = soonBg;

  // --- Neutral / Ink & Surface (Light) ---
  static const Color ink = Color(0xFF1C2530);
  static const Color inkSoft = Color(0xFF5B6675);
  static const Color inkMuted = Color(0xFF8B95A3);
  static const Color muted = inkSoft;

  static const Color canvas = Color(0xFFF4F6F9);
  static const Color surface = Colors.white;
  /// Toned-up frosted glass fill (~76% alpha) so the dynamic background video motion
  /// is clearly visible underneath while all text, badges, and icons remain 100% sharp and readable.
  static const Color glass = Color(0xC2FFFFFF); // ~76% alpha toned frosted glass
  static const Color surfaceDim = Color(0xFFF0F2F5);
  static const Color border = Color(0xFFE2E6EC);
  static const Color borderSubtle = Color(0xFFEEF0F3);

  // --- Neutral / Ink & Surface (Dark - 4 tier grey depth) ---
  static const Color darkCanvas = Color(0xFF0F1117);
  static const Color darkSurface = Color(0xFF161920);
  static const Color darkSurfaceDim = Color(0xFF1C2128);
  static const Color darkBorder = Color(0xFF262A33);
  static const Color darkInk = Color(0xFFE8E9EC);
  static const Color darkInkSoft = Color(0xFF9BA1AD);
  static const Color darkBrand = Color(0xFF3EA893);
  static const Color darkBrandTint = Color(0xFF122621);

  /// Liquid Glass decoration matching the iOS Liquid Glass UI kit & website portal:
  /// Frosted translucent body + glossy top specular sheen + bright luminous rim + dual depth shadows.
  static BoxDecoration liquidGlassDecoration({
    double radius = 20,
    bool dark = false,
    Color? customFill,
    BorderRadius? borderRadius,
    double topAlpha = 0.84,
    double bottomAlpha = 0.65,
  }) =>
      BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [
                  const Color(0xFF1E2430).withValues(alpha: 0.85),
                  const Color(0xFF141820).withValues(alpha: 0.70),
                ]
              : [
                  (customFill ?? Colors.white).withValues(alpha: topAlpha),
                  (customFill ?? Colors.white).withValues(alpha: bottomAlpha),
                ],
        ),
        borderRadius: borderRadius ?? BorderRadius.circular(radius),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.85),
          width: 1.2,
        ),
        boxShadow: [
          // Specular luminous rim sparkle highlight
          BoxShadow(
            color: Colors.white.withValues(alpha: dark ? 0.08 : 0.55),
            blurRadius: 4,
            spreadRadius: 0.5,
          ),
          // Ambient soft depth shadow
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      );

  /// Legibility halo for text that floats directly on the dynamic video
  /// background — page titles, section labels, subtitles that sit on the clip
  /// rather than inside a card. A soft light lift plus a dark grounding shadow
  /// keep the glyphs readable whether the brain graphic behind them is bright
  /// (white rings) or dark, so headings never vanish when the motion shifts.
  /// Apply as `Text(..., style: TextStyle(..., shadows: Themes.onMedia))`.
  static const List<Shadow> onMedia = [
    Shadow(color: Color(0x59FFFFFF), blurRadius: 11),
    Shadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  // Legacy compat aliases
  static const Color bluishClr = brand;
  static const Color yellowClr = soon;
  static const Color pinkClr = urgent;
  static const Color greenClr = routine;
  static const Color darkGreyClr = darkCanvas;
  static const Color darkHeaderClr = darkSurface;

  /// Monospace face for technical tags & micro-labels — the Neurotrace
  /// "[01]" / "/AI that detects…" style. Mirrors the portal's `--font-mono`.
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.spaceMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  // --- Light Theme ---
  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.archivoTextTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brand,
        primary: brand,
        onPrimary: Colors.white,
        primaryContainer: brandTint,
        onPrimaryContainer: brandDark,
        surface: surface,
        onSurface: ink,
        error: danger,
        brightness: Brightness.light,
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(color: ink, fontWeight: FontWeight.w800, letterSpacing: -0.02),
        displayMedium: baseTextTheme.displayMedium?.copyWith(color: ink, fontWeight: FontWeight.w800, letterSpacing: -0.02),
        titleLarge: baseTextTheme.titleLarge?.copyWith(color: ink, fontWeight: FontWeight.w700, letterSpacing: -0.01),
        titleMedium: baseTextTheme.titleMedium?.copyWith(color: ink, fontWeight: FontWeight.w600),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(color: ink),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: ink),
        bodySmall: baseTextTheme.bodySmall?.copyWith(color: inkSoft),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: ink.withValues(alpha: 0.06),
        centerTitle: false,
        titleTextStyle: GoogleFonts.archivo(
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.01,
        ),
      ),
      cardTheme: CardThemeData(
        color: glass,   // toned frosted glass so dynamic background shows through while text stays crisp
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
        ),
        shadowColor: Colors.white.withValues(alpha: 0.35),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.archivo(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: border, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: GoogleFonts.archivo(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          textStyle: GoogleFonts.archivo(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0x66FFFFFF), // frosted translucent glass input fill
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: danger),
        ),
        labelStyle: TextStyle(color: ink),
        floatingLabelStyle: TextStyle(color: brand, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(color: inkMuted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        height: 68,
        indicatorColor: brandTint,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: brand, size: 24);
          }
          return const IconThemeData(color: inkSoft, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.archivo(color: brand, fontWeight: FontWeight.w700, fontSize: 12);
          }
          return GoogleFonts.archivo(color: inkSoft, fontWeight: FontWeight.w500, fontSize: 12);
        }),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
    );
  }
}

