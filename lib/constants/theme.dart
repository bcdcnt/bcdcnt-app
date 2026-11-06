import 'package:flutter/material.dart';

class AppColors {
  // Full palette is mutable so ThemeProvider can swap every surface, accent,
  // text, and border colour at runtime. Each field is still initialised with
  // a `const Color(...)` literal so the *values* are canonical-cached; only
  // the bindings are non-const. Defaults = the light brand palette.
  static Color bg = const Color(0xFFFFFFFF);
  static Color surface = const Color(0xFFF4F1F0);
  static Color surfaceLight = const Color(0xFFEDE9E8);
  static Color surfaceHover = const Color(0xFFE5E0DF);
  static Color accent = const Color(0xFF711313);
  static Color accentLight = const Color(0xFF8E1F1F);
  static Color accentSoft = const Color(0xFFF8EDED);
  static Color text = const Color(0xFF161112);
  static Color textSecondary = const Color(0xFF4F4547);
  // #665C5E: 5.3:1 on surfaceLight (the old #73686A was 4.45:1).
  static Color textMuted = const Color(0xFF665C5E);
  static Color border = const Color(0xFFECE4E4);
  static Color borderSubtle = const Color(0xFFF3EEEE);

  /// True when the light theme is active. The decorative coloured "glow"
  /// shadows that read as a soft halo on dark backgrounds look harsh and
  /// exposed on white, so callers scale their shadow alpha by [shadowMul].
  static bool isLight = true;
  static double get shadowMul => isLight ? 0.32 : 1.0;

  /// Accent for text/icons/switch tracks drawn ON the background. The dark
  /// theme's `accent` (#8E1F1F) is only 2.2:1 on its near-black bg, so use
  /// the light accent there (10:1). Fills behind white text keep `accent`.
  static Color get accentFg => isLight ? accent : accentLight;

  /// Status text colours, ≥4.5:1 on surface/surfaceLight in both themes.
  static Color get errorText => isLight ? const Color(0xFFA32020) : const Color(0xFFFF8A80);
  static Color get warningText => isLight ? const Color(0xFF8A5A00) : const Color(0xFFFFC870);
  static Color get successText => isLight ? const Color(0xFF1A6B3C) : const Color(0xFF7FD69F);

  /// Theme-aware decorative glow. Use instead of inline `BoxShadow(...)` for
  /// card/header halos so they soften automatically on the light theme.
  static List<BoxShadow> glow(
    Color color, {
    double alpha = 0.3,
    double blur = 16,
    Offset offset = const Offset(0, 6),
    double spread = 0,
  }) =>
      [BoxShadow(color: color.withValues(alpha: alpha * shadowMul), blurRadius: blur, offset: offset, spreadRadius: spread)];

  // Brand constants from the BCĐCNT logo guideline (do not change per theme).
  static const wine = Color(0xFF711313);
  static const rose = Color(0xFFB48988);
  /// Near-black used behind the player and in the dark theme.
  static const night = Color(0xFF0E0A0A);
  static const gold = Color(0xFFC9A96E);
  static const error = Color(0xFFD23B3B);
  static const success = Color(0xFF1F7A45);
}

// Font helpers. Everything is Montserrat (see pubspec `fonts:`); display()
// is kept for headings and tightens tracking on large sizes the way the
// brand mockups do, body() is for everything else.
const kDisplayFont = 'Montserrat';
const kBodyFont = 'Montserrat';
TextStyle display([TextStyle? style]) {
  final s = style ?? const TextStyle();
  final size = s.fontSize ?? 14;
  return s.copyWith(
    fontFamily: kDisplayFont,
    letterSpacing: s.letterSpacing ?? (size >= 18 ? -size * 0.02 : null),
  );
}
TextStyle body([TextStyle? style]) => (style ?? const TextStyle()).copyWith(fontFamily: kBodyFont);
TextStyle brand([TextStyle? style]) => (style ?? const TextStyle()).copyWith(fontFamily: kDisplayFont, fontWeight: FontWeight.w800);

/// Type scale. Use these instead of raw `fontSize:` overrides so the
/// app-wide text-size preference only needs to touch one place. Nothing
/// below 12 — most listeners are 40+.
///
///   hero          30   — detail-screen titles (song / person / playlist)
///   displayLarge  24   — page titles, modal titles
///   displayMedium 20   — section headlines
///   sectionTitle  17   — list section labels
///   emphasized    15   — highlighted body
///   title         16   — list item titles
///   bodyText      16   — body copy
///   meta          14   — metadata rows
///   caption       13   — caption / overline / timestamp
class AppText {
  static TextStyle get hero => display(TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.12, color: AppColors.text));
  static TextStyle get displayLarge => display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text));
  static TextStyle get displayMedium => display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text));
  static TextStyle get sectionTitle => display(TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text));
  static TextStyle get emphasized => body(TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.text));
  static TextStyle get title => body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text));
  static TextStyle get bodyText => body(TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textSecondary));
  static TextStyle get meta => body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted));
  static TextStyle get caption => body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted));
  /// Small uppercase label ("GỢI Ý HÔM NAY", "LỜI 1 & 3").
  static TextStyle get eyebrow => body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: AppColors.accentLight));
}

ThemeData appTheme() {
  final light = AppColors.isLight;
  final base = light ? ThemeData.light() : ThemeData.dark();
  return ThemeData(
    brightness: light ? Brightness.light : Brightness.dark,
    fontFamily: kBodyFont,
    scaffoldBackgroundColor: AppColors.bg,
    primaryColor: AppColors.accent,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(
      fontFamily: kBodyFont,
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    colorScheme: (light ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.accentLight,
      surface: AppColors.bg,
      onSurface: AppColors.text,
      error: AppColors.error,
    ),
    dividerColor: AppColors.border,
    dividerTheme: DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF161112),
      contentTextStyle: body(const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: const Color(0x33000000),
      centerTitle: true,
      iconTheme: IconThemeData(color: AppColors.text),
      titleTextStyle: display(TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
    ),
  );
}

const apiBase = 'https://api.bcdcnt.net/graphql';
const siteUrl = 'https://bcdcnt.net';
