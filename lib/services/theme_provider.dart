import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One named theme — accent triple + a couple of surface colors. All apps
/// share the same dark base (text on dark) for now; what changes is the
/// "personality" colours.
@immutable
class AppPalette {
  final String name;
  final String label;
  final Color accent;
  final Color accentLight;
  final Color accentSoft;

  const AppPalette({
    required this.name,
    required this.label,
    required this.accent,
    required this.accentLight,
    required this.accentSoft,
  });
}

/// Mirrors the 10 themes shipped on bcdcnt-web (`globals.css` `[data-theme=*]`),
/// adapted to the mobile/macOS palette. Dark themes only — light theme is
/// out of scope for this sprint because it'd need a full AppColors codemod.
const List<AppPalette> kAppPalettes = [
  AppPalette(name: 'classic', label: 'Cổ điển',
    accent: Color(0xFF711313), accentLight: Color(0xFFB48988), accentSoft: Color(0x26711313)),
  AppPalette(name: 'red', label: 'Đỏ rực',
    accent: Color(0xFFE05555), accentLight: Color(0xFFF5B8B8), accentSoft: Color(0x33E05555)),
  AppPalette(name: 'gray', label: 'Xám than',
    accent: Color(0xFF8B1A1A), accentLight: Color(0xFFB48988), accentSoft: Color(0x268B1A1A)),
  AppPalette(name: 'green', label: 'Lá rừng',
    accent: Color(0xFF2F7D5C), accentLight: Color(0xFF8FD3B5), accentSoft: Color(0x332F7D5C)),
  AppPalette(name: 'blue', label: 'Biển đêm',
    accent: Color(0xFF2C5F8D), accentLight: Color(0xFF8FBFE8), accentSoft: Color(0x332C5F8D)),
  AppPalette(name: 'violet', label: 'Tím Huế',
    accent: Color(0xFF6B3D8E), accentLight: Color(0xFFC4A6E0), accentSoft: Color(0x336B3D8E)),
  AppPalette(name: 'amber', label: 'Hổ phách',
    accent: Color(0xFFB8860B), accentLight: Color(0xFFE8C56C), accentSoft: Color(0x33B8860B)),
  AppPalette(name: 'rose', label: 'Hoa hồng',
    accent: Color(0xFFB8326E), accentLight: Color(0xFFE89AB8), accentSoft: Color(0x33B8326E)),
  AppPalette(name: 'teal', label: 'Ngọc lam',
    accent: Color(0xFF1F7A7A), accentLight: Color(0xFF8FCFCF), accentSoft: Color(0x331F7A7A)),
  AppPalette(name: 'olive', label: 'Trầu',
    accent: Color(0xFF6B7A1F), accentLight: Color(0xFFCFD88F), accentSoft: Color(0x336B7A1F)),
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
    notifyListeners();
  }

  Future<void> setTheme(String name) async {
    final found = kAppPalettes.where((p) => p.name == name).toList();
    if (found.isEmpty) return;
    if (_palette.name == name) return;
    _palette = found.first;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, name);
  }
}
