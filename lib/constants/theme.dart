import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg = Color(0xFF0C0A0A);
  static const surface = Color(0xFF1A1414);
  static const surfaceLight = Color(0xFF241C1C);
  static const surfaceHover = Color(0xFF2E2424);
  static const accent = Color(0xFF711313);
  static const accentLight = Color(0xFFB48988);
  static const accentSoft = Color(0x26711313);
  static const text = Color(0xFFF5F0EB);
  static const textSecondary = Color(0xFFA09090);
  static const textMuted = Color(0xFF6B5858);
  static const border = Color(0x14FFFFFF);
  static const borderSubtle = Color(0x0AFFFFFF);
  static const gold = Color(0xFFC9A96E);
  static const error = Color(0xFFE57373);
  static const success = Color(0xFF66BB6A);
}

// Font family helpers
TextStyle display([TextStyle? style]) => GoogleFonts.nunito(textStyle: style);
TextStyle body([TextStyle? style]) => GoogleFonts.montserrat(textStyle: style);

class AppText {
  static TextStyle get displayLarge => display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text));
  static TextStyle get displayMedium => display(const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text));
  static TextStyle get sectionTitle => display(const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text));
  static TextStyle get title => body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text));
  static TextStyle get bodyText => body(const TextStyle(fontSize: 13, color: AppColors.textSecondary));
  static TextStyle get meta => body(const TextStyle(fontSize: 12, color: AppColors.textMuted));
  static TextStyle get caption => body(const TextStyle(fontSize: 11, color: AppColors.textMuted));
}

ThemeData appTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    primaryColor: AppColors.accent,
    textTheme: GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accentLight,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      iconTheme: const IconThemeData(color: AppColors.text),
      titleTextStyle: body(const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
    ),
  );
}

const apiBase = 'https://api.bcdcnt.net/graphql';
const siteUrl = 'https://bcdcnt.net';
