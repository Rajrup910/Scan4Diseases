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
  /// Toned frosted glass fill (~55% alpha) so the dynamic background video
  /// clearly reads through every panel and cards feel like glass, not like
  /// solid tiles. Reduced from the previous 76% based on device-side feedback
  /// that the app had lost its glossy look after the dark-theme pass.
  static const Color glass = Color(0x8CFFFFFF); // ~55% alpha frosted glass
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
  ///
  /// Alpha defaults were reduced (light 0.68/0.44, dark 0.62/0.42) so the ambient
  /// video/blueprint backdrop reads through every panel — the previous 0.84/0.65
  /// values made cards feel like solid tiles, especially in dark mode where the
  /// values were also hardcoded and ignored the parameters. The top specular
  /// stripe was pushed brighter to keep the "glossy" impression at lower body
  /// opacity: the eye reads gloss from the highlight, not the fill.
  static BoxDecoration liquidGlassDecoration({
    double radius = 20,
    bool dark = false,
    Color? customFill,
    BorderRadius? borderRadius,
    double? topAlpha,
    double? bottomAlpha,
  }) {
    final tA = topAlpha ?? (dark ? 0.92 : 0.68);
    final bA = bottomAlpha ?? (dark ? 0.82 : 0.44);
    final baseTop = dark ? const Color(0xFF1E2430) : (customFill ?? Colors.white);
    final baseBottom = dark ? const Color(0xFF141820) : (customFill ?? Colors.white);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          baseTop.withValues(alpha: tA),
          baseBottom.withValues(alpha: bA),
        ],
      ),
      borderRadius: borderRadius ?? BorderRadius.circular(radius),
      border: Border.all(
        color: dark
            ? Themes.tealGlow.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.78),
        width: 1.1,
      ),
      boxShadow: [
        // Specular luminous rim sparkle highlight — pushed brighter to keep
        // the glossy impression when the body is more translucent.
        BoxShadow(
          color: dark
              ? Themes.tealGlow.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.65),
          blurRadius: 6,
          spreadRadius: 0.5,
        ),
        // Ambient soft depth shadow
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.38 : 0.08),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  /// Legibility halo for text that floats directly on the dynamic video
  /// background — page titles, section labels, subtitles that sit on the clip
  /// rather than inside a card.
  ///
  /// Rather than one hard drop shadow (which reads as a jagged, edgy outline
  /// over moving video), this stacks three zero-offset Gaussian blur halos of
  /// widening radius: a wide soft light lift, a mid glow, and a tight dark
  /// grounding wash. The overlapping bell-curves feather the glyph edges so the
  /// type looks soft and antialiased, and stays readable whether the motion
  /// behind it is bright (white rings) or dark. Apply as
  /// `Text(..., style: TextStyle(..., shadows: Themes.onMedia))`.
  static const List<Shadow> onMedia = [
    Shadow(color: Color(0x4DFFFFFF), blurRadius: 16),
    Shadow(color: Color(0x33FFFFFF), blurRadius: 7),
    Shadow(color: Color(0x38000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  /// Dark-theme counterpart of [onMedia]. Over the near-black emerald canvas the
  /// light lift is dropped and the glow is warmed toward the electric teal, so
  /// headings gain a soft luminous edge instead of a hard black shadow.
  static const List<Shadow> onMediaDark = [
    Shadow(color: Color(0x3A2DD4BF), blurRadius: 18),
    Shadow(color: Color(0x59000000), blurRadius: 8, offset: Offset(0, 1)),
    Shadow(color: Color(0x2E000000), blurRadius: 3),
  ];

  /// Smooth section-header text style. Rounded, softly tracked, heavy (w700+)
  /// type that sits above a card group. Pair with [sectionHeaderPill] for the
  /// frosted rounded container treatment over the dynamic background.
  static TextStyle sectionHeaderStyle({bool dark = false}) => GoogleFonts.archivo(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        height: 1.15,
        color: dark ? darkInk : ink,
        shadows: dark ? onMediaDark : onMedia,
      );

  /// Frosted rounded "pill" wrapper for a section header label. Gives headings a
  /// soft, visible, smooth chip over dynamic video backgrounds — no jagged
  /// outline — with a translucent glass fill, a hairline luminous rim, and a
  /// gentle depth shadow. Use in place of a bare `Text` section title.
  static Widget sectionHeaderPill(String label, {bool dark = false, IconData? icon}) => Container(
        padding: EdgeInsets.fromLTRB(icon == null ? 14 : 11, 7, 14, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          // Lowered from 0.72/0.58 (dark) and 0.66/0.48 (light) so the pill
          // reads as a floating chip against the ambient video, not another
          // solid tile competing with the panels it captions.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? [const Color(0xFF1E2430).withValues(alpha: 0.52), const Color(0xFF141820).withValues(alpha: 0.36)]
                : [Colors.white.withValues(alpha: 0.52), Colors.white.withValues(alpha: 0.34)],
          ),
          border: Border.all(
            color: dark ? tealGlow.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.72),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: dark ? tealGlow.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.42),
              blurRadius: 10,
              spreadRadius: -1,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.30 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: dark ? tealLight : brand),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.archivo(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: dark ? darkInk : ink,
              ),
            ),
          ],
        ),
      );

  /// App-wide page transition: a soft fade combined with a small upward glide
  /// and a barely-there scale settle. Applied through [pageTransitionsTheme] so
  /// every pushed route (result, chat, report detail, doctor share …) animates
  /// consistently and smoothly on both Android and iOS instead of the default
  /// platform-specific slide. Reused directly for any manual [PageRouteBuilder].
  static PageTransitionsTheme get pageTransitionsTheme => const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SmoothPageTransitionsBuilder(),
          TargetPlatform.iOS: SmoothPageTransitionsBuilder(),
          TargetPlatform.macOS: SmoothPageTransitionsBuilder(),
          TargetPlatform.windows: SmoothPageTransitionsBuilder(),
          TargetPlatform.linux: SmoothPageTransitionsBuilder(),
        },
      );

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
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xF8FFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1.1),
        ),
        elevation: 8,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Color(0xF8FFFFFF)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: border, width: 1.1),
          )),
          elevation: const WidgetStatePropertyAll(8),
        ),
      ),
      pageTransitionsTheme: pageTransitionsTheme,
    );
  }

  // --- Dark Theme (glossy emerald) ---
  //
  // Matches the web portal dark mode: a near-black #0F1117 canvas, #161920 dark
  // glass cards, and a #2DD4BF electric cyan/teal glow used sparingly as the
  // accent. Deep, rich, and low-glare, with the same restrained elevation and
  // hairline borders as the light theme so the two feel like one product.
  static ThemeData get darkTheme {
    final baseTextTheme = GoogleFonts.archivoTextTheme(ThemeData.dark().textTheme);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkCanvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: tealGlow,
        primary: tealGlow,
        onPrimary: const Color(0xFF06231E),
        primaryContainer: darkBrandTint,
        onPrimaryContainer: tealLight,
        secondary: brandTeal,
        surface: darkSurface,
        onSurface: darkInk,
        surfaceContainerHighest: darkSurfaceDim,
        outline: darkBorder,
        error: const Color(0xFFF87171),
        brightness: Brightness.dark,
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(color: darkInk, fontWeight: FontWeight.w800, letterSpacing: -0.02),
        displayMedium: baseTextTheme.displayMedium?.copyWith(color: darkInk, fontWeight: FontWeight.w800, letterSpacing: -0.02),
        titleLarge: baseTextTheme.titleLarge?.copyWith(color: darkInk, fontWeight: FontWeight.w700, letterSpacing: -0.01),
        titleMedium: baseTextTheme.titleMedium?.copyWith(color: darkInk, fontWeight: FontWeight.w600),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(color: darkInk),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: darkInk),
        bodySmall: baseTextTheme.bodySmall?.copyWith(color: darkInkSoft),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkInk,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        centerTitle: false,
        titleTextStyle: GoogleFonts.archivo(
          color: darkInk,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.01,
        ),
      ),
      cardTheme: CardThemeData(
        // High-opacity dark frosted glass (~95% alpha) so text is crisp and legible
        // over ambient backdrops without distracting bleed-through.
        color: const Color(0xF2161920),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: tealGlow.withValues(alpha: 0.28), width: 1.1),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.55),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tealGlow,
          foregroundColor: const Color(0xFF06231E),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.archivo(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkInk,
          side: BorderSide(color: tealGlow.withValues(alpha: 0.35), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: GoogleFonts.archivo(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tealLight,
          textStyle: GoogleFonts.archivo(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0x66232A36), // frosted translucent dark glass input fill
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tealGlow.withValues(alpha: 0.18), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tealGlow.withValues(alpha: 0.18), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: tealGlow, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFF87171)),
        ),
        labelStyle: const TextStyle(color: darkInk),
        floatingLabelStyle: const TextStyle(color: tealGlow, fontWeight: FontWeight.w600),
        hintStyle: const TextStyle(color: darkInkSoft),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        elevation: 0,
        height: 68,
        indicatorColor: darkBrandTint,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: tealGlow, size: 24);
          }
          return const IconThemeData(color: darkInkSoft, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.archivo(color: tealLight, fontWeight: FontWeight.w700, fontSize: 12);
          }
          return GoogleFonts.archivo(color: darkInkSoft, fontWeight: FontWeight.w500, fontSize: 12);
        }),
      ),
      dividerTheme: const DividerThemeData(color: darkBorder, thickness: 1, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: tealGlow.withValues(alpha: 0.16), width: 1.1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: const ListTileThemeData(iconColor: tealLight, textColor: darkInk),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? tealGlow : darkInkSoft,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? tealGlow.withValues(alpha: 0.35) : darkBorder,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xF5161922),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: tealGlow.withValues(alpha: 0.28), width: 1.1),
        ),
        elevation: 12,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Color(0xF5161922)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: tealGlow.withValues(alpha: 0.28), width: 1.1),
          )),
          elevation: const WidgetStatePropertyAll(12),
        ),
      ),
      pageTransitionsTheme: pageTransitionsTheme,
    );
  }
}

/// A single smooth cross-platform page transition: an eased fade layered with a
/// small upward glide and a subtle scale settle on the incoming route, plus a
/// gentle fade-back on the outgoing one. Kept deliberately short and low-travel
/// so navigation feels quick and calm rather than theatrical.
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final entering = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final exiting = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInCubic);

    return FadeTransition(
      opacity: entering,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(entering),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(entering),
          child: FadeTransition(
            // Ease the previous screen back a touch as the new one arrives.
            opacity: Tween<double>(begin: 1.0, end: 0.92).animate(exiting),
            child: child,
          ),
        ),
      ),
    );
  }
}

