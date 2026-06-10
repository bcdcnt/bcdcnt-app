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
}

/// Themes mirror bcdcnt-web's globals.css `[data-theme=*]` blocks. Same
/// names, same RGB values — so the mobile/desktop build looks the same as
/// the web for any theme the user has set.
const List<AppPalette> kAppPalettes = [
  // Default — current dark Cổ điển look.
  AppPalette(
    name: 'classic', label: 'Cổ điển',
    bg: Color(0xFF0C0A0A),
    surface: Color(0xFF1A1414),
    surfaceLight: Color(0xFF241C1C),
    surfaceHover: Color(0xFF2E2424),
    accent: Color(0xFF711313),
    accentLight: Color(0xFFB48988),
    accentSoft: Color(0x26711313),
    text: Color(0xFFF5F0EB),
    textSecondary: Color(0xFFA09090),
    textMuted: Color(0xFF6B5858),
    border: Color(0x14FFFFFF),
    borderSubtle: Color(0x0AFFFFFF),
  ),
  // Light/white theme — placed 2nd so users can flip dark↔light fast. Borders +
  // accentLight tuned dark enough to stay legible on a near-white background.
  AppPalette(
    name: 'light', label: 'Sáng',
    bg: Color(0xFFF4F1EF),
    surface: Color(0xFFFFFFFF),
    surfaceLight: Color(0xFFEEE9E6),
    surfaceHover: Color(0xFFE4DDD9),
    accent: Color(0xFF8B1A1A),
    accentLight: Color(0xFFA83232),
    accentSoft: Color(0x1A8B1A1A),
    text: Color(0xFF1A1414),
    textSecondary: Color(0xFF5C5252),
    textMuted: Color(0xFF8A8080),
    border: Color(0x14000000),
    borderSubtle: Color(0x0A000000),
  ),
  AppPalette(
    name: 'red', label: 'Đỏ rực',
    bg: Color(0xFF3D0C0C),
    surface: Color(0xFF4E1212),
    surfaceLight: Color(0xFF5E1818),
    surfaceHover: Color(0xFF6E2020),
    accent: Color(0xFFE05555),
    accentLight: Color(0xFFF5B8B8),
    accentSoft: Color(0x1AFFFFFF),
    text: Color(0xFFFFF8F5),
    textSecondary: Color(0xB3FFF8F5),
    textMuted: Color(0x66FFF8F5),
    border: Color(0x1AFFFFFF),
    borderSubtle: Color(0x0DFFFFFF),
  ),
  AppPalette(
    name: 'gray', label: 'Xám than',
    bg: Color(0xFF1A1A1E),
    surface: Color(0xFF242428),
    surfaceLight: Color(0xFF2E2E33),
    surfaceHover: Color(0xFF38383E),
    accent: Color(0xFF8B1A1A),
    accentLight: Color(0xFFB48988),
    accentSoft: Color(0x268B1A1A),
    text: Color(0xFFE8E6E3),
    textSecondary: Color(0xFF9A9A9A),
    textMuted: Color(0xFF666666),
    border: Color(0x14FFFFFF),
    borderSubtle: Color(0x0AFFFFFF),
  ),
  AppPalette(
    name: 'green', label: 'Lá rừng',
    bg: Color(0xFF0A1A0C),
    surface: Color(0xFF122016),
    surfaceLight: Color(0xFF1A2A1E),
    surfaceHover: Color(0xFF223426),
    accent: Color(0xFF2E8B3A),
    accentLight: Color(0xFF88B490),
    accentSoft: Color(0x262E8B3A),
    text: Color(0xFFE8F0EA),
    textSecondary: Color(0xB3E8F0EA),
    textMuted: Color(0x66E8F0EA),
    border: Color(0x1AFFFFFF),
    borderSubtle: Color(0x0DFFFFFF),
  ),
  AppPalette(
    name: 'blue', label: 'Biển đêm',
    bg: Color(0xFF0A0E1A),
    surface: Color(0xFF121828),
    surfaceLight: Color(0xFF1A2236),
    surfaceHover: Color(0xFF222C40),
    accent: Color(0xFF2E6B8B),
    accentLight: Color(0xFF88AAC0),
    accentSoft: Color(0x262E6B8B),
    text: Color(0xFFE8EEF5),
    textSecondary: Color(0xB3E8EEF5),
    textMuted: Color(0x66E8EEF5),
    border: Color(0x1AFFFFFF),
    borderSubtle: Color(0x0DFFFFFF),
  ),
  AppPalette(
    name: 'violet', label: 'Tím Huế',
    bg: Color(0xFF100A1A),
    surface: Color(0xFF1A1228),
    surfaceLight: Color(0xFF241A34),
    surfaceHover: Color(0xFF2E2240),
    accent: Color(0xFF7B3FA0),
    accentLight: Color(0xFFB088C8),
    accentSoft: Color(0x267B3FA0),
    text: Color(0xFFF0E8F5),
    textSecondary: Color(0xB3F0E8F5),
    textMuted: Color(0x66F0E8F5),
    border: Color(0x1AFFFFFF),
    borderSubtle: Color(0x0DFFFFFF),
  ),
  AppPalette(
    name: 'amber', label: 'Hổ phách',
    bg: Color(0xFF1A140A),
    surface: Color(0xFF241D12),
    surfaceLight: Color(0xFF2E261A),
    surfaceHover: Color(0xFF382E22),
    accent: Color(0xFFB8860B),
    accentLight: Color(0xFFE8C56C),
    accentSoft: Color(0x33B8860B),
    text: Color(0xFFF5EFE0),
    textSecondary: Color(0xB3F5EFE0),
    textMuted: Color(0x66F5EFE0),
    border: Color(0x1AFFFFFF),
    borderSubtle: Color(0x0DFFFFFF),
  ),
  AppPalette(
    name: 'rose', label: 'Hoa hồng',
    bg: Color(0xFF1A0A12),
    surface: Color(0xFF241220),
    surfaceLight: Color(0xFF2E1A2A),
    surfaceHover: Color(0xFF382234),
    accent: Color(0xFFB8326E),
    accentLight: Color(0xFFE89AB8),
    accentSoft: Color(0x33B8326E),
    text: Color(0xFFF5E8EE),
    textSecondary: Color(0xB3F5E8EE),
    textMuted: Color(0x66F5E8EE),
    border: Color(0x1AFFFFFF),
    borderSubtle: Color(0x0DFFFFFF),
  ),
  AppPalette(
    name: 'teal', label: 'Ngọc lam',
    bg: Color(0xFF0A1818),
    surface: Color(0xFF122222),
    surfaceLight: Color(0xFF1A2C2C),
    surfaceHover: Color(0xFF223636),
    accent: Color(0xFF1F7A7A),
    accentLight: Color(0xFF8FCFCF),
    accentSoft: Color(0x331F7A7A),
    text: Color(0xFFE8F0F0),
    textSecondary: Color(0xB3E8F0F0),
    textMuted: Color(0x66E8F0F0),
    border: Color(0x1AFFFFFF),
    borderSubtle: Color(0x0DFFFFFF),
  ),
  AppPalette(
    name: 'olive', label: 'Trầu',
    bg: Color(0xFF14180A),
    surface: Color(0xFF1E2210),
    surfaceLight: Color(0xFF272C18),
    surfaceHover: Color(0xFF313620),
    accent: Color(0xFF6B7A1F),
    accentLight: Color(0xFFCFD88F),
    accentSoft: Color(0x336B7A1F),
    text: Color(0xFFF0F0E0),
    textSecondary: Color(0xB3F0F0E0),
    textMuted: Color(0x66F0F0E0),
    border: Color(0x1AFFFFFF),
    borderSubtle: Color(0x0DFFFFFF),
  ),
  AppPalette(
    name: 'indigo', label: 'Chàm',
    bg: Color(0xFF0C0E1F),
    surface: Color(0xFF14182E),
    surfaceLight: Color(0xFF1C2240),
    surfaceHover: Color(0xFF242C50),
    accent: Color(0xFF4F5BD5),
    accentLight: Color(0xFFA0A8E8),
    accentSoft: Color(0x334F5BD5),
    text: Color(0xFFE8EAF5),
    textSecondary: Color(0xB3E8EAF5),
    textMuted: Color(0x66E8EAF5),
    border: Color(0x1AFFFFFF),
    borderSubtle: Color(0x0DFFFFFF),
  ),
];

/// App-wide theme switcher. Listens for the user's pick (persisted to
/// SharedPreferences) and exposes the active [AppPalette]. UI surfaces that
/// need a colourable accent should `context.watch<ThemeProvider>()` and
/// read `palette.accent` instead of `AppColors.accent`.
class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = 'app_theme_name';
  AppPalette _palette = kAppPalettes.first;

  ThemeProvider() { _restore(); }

  AppPalette get palette => _palette;
  String get name => _palette.name;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == null) return;
    final found = kAppPalettes.where((p) => p.name == saved).toList();
    if (found.isEmpty) return;
    _palette = found.first;
    _applyToGlobalColors();
    notifyListeners();
  }

  Future<void> setTheme(String name) async {
    final found = kAppPalettes.where((p) => p.name == name).toList();
    if (found.isEmpty) return;
    if (_palette.name == name) return;
    _palette = found.first;
    _applyToGlobalColors();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, name);
  }

  // Mutate the global AppColors fields so every widget that reads them
  // (~1500 sites) picks up the new palette on the next build. main.dart
  // wraps MaterialApp in a `context.watch<ThemeProvider>()` + ValueKey so
  // the entire tree re-mounts on theme change and reads the fresh values.
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
    AppColors.isLight = _palette.name == 'light';
  }
}

/// Visual swatch for a palette — white for the light theme (its bg, logical),
/// the accent gradient for the dark ones. Shared by the settings picker and
/// the quick-theme switcher.
Widget themeSwatch(AppPalette p, {double size = 28, bool active = false}) {
  final isLight = p.name == 'light';
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
      color: isLight ? Colors.white : null,
      gradient: isLight ? null : LinearGradient(colors: [p.accent, p.accentLight]),
      border: Border.all(color: ring, width: active ? 2 : 1),
    ),
    child: active
        ? Center(child: Icon(Icons.check, size: size * 0.58, color: isLight ? Colors.black87 : Colors.white))
        : null,
  );
}
