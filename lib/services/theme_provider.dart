import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme.dart';

/// Full palette — mirrors the web build's `[data-theme=*]` CSS variable
/// blocks. Every theme overrides the entire surface/accent/text/border
/// stack, not just the accent triple, so the background actually shifts
/// instead of staying the same dark base across themes.
@immutable
class AppPalette {
  final String name;
  final String label;

  // Surfaces
  final Color bg;
  final Color surface;
  final Color surfaceLight;
  final Color surfaceHover;

  // Accent triple
  final Color accent;
  final Color accentLight;
  final Color accentSoft;

  // Text scale
  final Color text;
  final Color textSecondary;
  final Color textMuted;

  // Borders
  final Color border;
  final Color borderSubtle;

  const AppPalette({
    required this.name,
    required this.label,
    required this.bg,
    required this.surface,
    required this.surfaceLight,
    required this.surfaceHover,
    required this.accent,
    required this.accentLight,
    required this.accentSoft,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderSubtle,
  });

  bool get isLight => name == 'sang';
}

/// Brand palettes (BCĐCNT logo guideline: white, #B48988, #711313).
/// 'sang' is the default; 'toi' is the dark variant. Older palette names
/// saved by previous versions fall back to the default.
const List<AppPalette> kAppPalettes = [
  AppPalette(
    name: 'sang', label: 'Sáng',
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F1F0),
    surfaceLight: Color(0xFFEDE9E8),
    surfaceHover: Color(0xFFE5E0DF),
    accent: Color(0xFF711313),
    accentLight: Color(0xFF8E1F1F),
    accentSoft: Color(0xFFF8EDED),
    text: Color(0xFF161112),
    textSecondary: Color(0xFF4F4547),
    textMuted: Color(0xFF73686A),
    border: Color(0xFFECE4E4),
    borderSubtle: Color(0xFFF3EEEE),
  ),
  AppPalette(
    name: 'toi', label: 'Tối',
    bg: Color(0xFF0E0A0A),
    surface: Color(0xFF1B1515),
    surfaceLight: Color(0xFF271F1F),
    surfaceHover: Color(0xFF302626),
    accent: Color(0xFF8E1F1F),
    accentLight: Color(0xFFE0AEAC),
    accentSoft: Color(0xFF2A1A1A),
    text: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFD5CACA),
    textMuted: Color(0xFFA39494),
    border: Color(0xFF2A2222),
    borderSubtle: Color(0xFF201919),
  ),
];

/// Text-size preference ("Cỡ chữ" in Cài đặt).
const Map<String, double> kTextScales = {'vua': 1.0, 'lon': 1.18, 'ratlon': 1.35};
const Map<String, String> kTextScaleLabels = {'vua': 'Vừa', 'lon': 'Lớn', 'ratlon': 'Rất lớn'};

/// App-wide theme switcher. Persists the user's pick — 'sang', 'toi' or
/// 'system' (follow the OS) — and the text-size preference.
class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const _prefsKey = 'app_theme_name';
  static const _scaleKey = 'app_text_scale';
  AppPalette _palette = kAppPalettes.first;
  String _mode = 'sang';
  String _scale = 'vua';

  ThemeProvider() {
    _applyToGlobalColors();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  AppPalette get palette => _palette;
  String get name => _palette.name;
  /// 'sang' | 'toi' | 'system'
  String get mode => _mode;
  String get textScaleKey => _scale;
  double get textScale => kTextScales[_scale] ?? 1.0;

  AppPalette _resolve(String mode) {
    if (mode == 'system') {
      final dark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
      return kAppPalettes[dark ? 1 : 0];
    }
    return kAppPalettes.firstWhere((p) => p.name == mode, orElse: () => kAppPalettes.first);
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    // 2026-11 brand redesign: every older palette (hoaico, classic, light,
    // red…) resets once to the new light default.
    if (prefs.getBool('app_theme_brand_migrated') != true) {
      await prefs.setBool('app_theme_brand_migrated', true);
      await prefs.remove(_prefsKey);
    }
    // Screenshot hook (desktop debug runs): BCDCNT_THEME=toi|sang.
    final forced = (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) ? Platform.environment['BCDCNT_THEME'] : null;
    final saved = forced ?? prefs.getString(_prefsKey);
    _mode = (saved == 'toi' || saved == 'system') ? saved! : 'sang';
    _scale = kTextScales.containsKey(prefs.getString(_scaleKey)) ? prefs.getString(_scaleKey)! : 'vua';
    _palette = _resolve(_mode);
    _applyToGlobalColors();
    notifyListeners();
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode != 'system') return;
    final next = _resolve('system');
    if (next.name == _palette.name) return;
    _palette = next;
    _applyToGlobalColors();
    notifyListeners();
  }

  /// Accepts a palette name ('sang' / 'toi') or 'system'.
  Future<void> setTheme(String name) async {
    if (name != 'system' && !kAppPalettes.any((p) => p.name == name)) return;
    if (_mode == name) return;
    _mode = name;
    _palette = _resolve(name);
    _applyToGlobalColors();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, name);
  }

  Future<void> setTextScale(String key) async {
    if (!kTextScales.containsKey(key) || key == _scale) return;
    _scale = key;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scaleKey, key);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Mutate the global AppColors fields so every widget that reads them
  // picks up the new palette on the next build. main.dart wraps MaterialApp
  // in a `context.watch<ThemeProvider>()` + ValueKey so the entire tree
  // re-mounts on theme change and reads the fresh values.
  void _applyToGlobalColors() {
    AppColors.bg = _palette.bg;
    AppColors.surface = _palette.surface;
    AppColors.surfaceLight = _palette.surfaceLight;
    AppColors.surfaceHover = _palette.surfaceHover;
    AppColors.accent = _palette.accent;
    AppColors.accentLight = _palette.accentLight;
    AppColors.accentSoft = _palette.accentSoft;
    AppColors.text = _palette.text;
    AppColors.textSecondary = _palette.textSecondary;
    AppColors.textMuted = _palette.textMuted;
    AppColors.border = _palette.border;
    AppColors.borderSubtle = _palette.borderSubtle;
    AppColors.isLight = _palette.isLight;
  }
}

/// Visual swatch for a palette — white for the light theme (its bg, logical),
/// the accent gradient for the dark ones. Shared by the settings picker and
/// the quick-theme switcher.
Widget themeSwatch(AppPalette p, {double size = 28, bool active = false}) {
  final isLight = p.isLight;
  // Active swatch gets a contrasting ring + a check mark so the current theme
  // is unmistakable (the accent-coloured ring alone blended into the swatch).
  final ring = active
      ? (isLight ? Colors.black54 : Colors.white)
      : (isLight ? const Color(0x33000000) : Colors.transparent);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: isLight ? p.bg : null,
      gradient: isLight ? null : LinearGradient(colors: [p.accent, p.accentLight]),
      border: Border.all(color: ring, width: active ? 2 : 1),
    ),
    child: active
        ? Center(child: Icon(Icons.check, size: size * 0.58, color: isLight ? Colors.black87 : Colors.white))
        : null,
  );
}
