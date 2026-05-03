import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Full palette is mutable so ThemeProvider.setTheme() can swap every
  // surface, accent, text, and border colour at runtime — mirrors how the
  // web build's `[data-theme=*]` CSS vars cascade across every component.
  // Each field is still initialised with a `const Color(...)` literal so the
  // *values* are canonical-cached; only the bindings are non-const. Any call
  // site that sat inside a `const` constructor reading these has to drop its
  // outer `const` (sweep done in same change via /tmp/fix_const.py).
  static Color bg = const Color(0xFF0C0A0A);
  static Color surface = const Color(0xFF1A1414);
  static Color surfaceLight = const Color(0xFF241C1C);
  static Color surfaceHover = const Color(0xFF2E2424);
  static Color accent = const Color(0xFF711313);
  static Color accentLight = const Color(0xFFB48988);
  static Color accentSoft = const Color(0x26711313);
  static Color text = const Color(0xFFF5F0EB);
  static Color textSecondary = const Color(0xFFA09090);
  static Color textMuted = const Color(0xFF6B5858);
  static Color border = const Color(0x14FFFFFF);
  static Color borderSubtle = const Color(0x0AFFFFFF);
  // Static accents that don't change per theme.
  static const gold = Color(0xFFC9A96E);
  static const error = Color(0xFFE57373);
  static const success = Color(0xFF66BB6A);
}

// Font helpers — pivoted to system default (SF Pro on macOS/iOS, Roboto on
// Android) so the app feels native instead of web-styled. The custom Nunito
// brand font is reserved for the wordmark via `brand()` to keep the logo
// distinctive without weighing down every label.
TextStyle display([TextStyle? style]) => style ?? const TextStyle();
TextStyle body([TextStyle? style]) => style ?? const TextStyle();
TextStyle brand([TextStyle? style]) => GoogleFonts.nunito(textStyle: style);

/// Type scale — 7 tiers from caption (11) to hero (32). Use these instead of
/// raw `fontSize:` overrides so a future tweak (e.g. font size accessibility
/// preference) only needs to touch one place.
///
///   hero        32   — detail-screen titles (song / person / playlist)
///   displayLarge 22   — section headlines, modal titles
///   displayMedium 18  — sub-headlines
///   sectionTitle 16   — list section labels
///   emphasized   15   — hero subtitles, highlighted body
///   title        14   — list item titles
///   bodyText     13   — body copy
///   meta         12   — metadata rows
///   caption      11   — caption / overline / timestamp
class AppText {
  static TextStyle get hero => display(TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.1, color: AppColors.text));
  static TextStyle get displayLarge => display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text));
  static TextStyle get displayMedium => display(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text));
  static TextStyle get sectionTitle => display(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text));
  static TextStyle get emphasized => body(TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.text));
  static TextStyle get title => body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text));
  static TextStyle get bodyText => body(TextStyle(fontSize: 13, color: AppColors.textSecondary));
  static TextStyle get meta => body(TextStyle(fontSize: 12, color: AppColors.textMuted));
  static TextStyle get caption => body(TextStyle(fontSize: 11, color: AppColors.textMuted));
}

ThemeData appTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    primaryColor: AppColors.accent,
    textTheme: ThemeData.dark().textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    colorScheme: ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accentLight,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      iconTheme: IconThemeData(color: AppColors.text),
      titleTextStyle: body(TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
    ),
  );
}

const apiBase = 'https://api.bcdcnt.net/graphql';
const siteUrl = 'https://bcdcnt.net';
