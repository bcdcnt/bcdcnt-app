import 'dart:async';
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

  /// Light set (dark text on a light page) — drives shadows/contrast choices.
  final bool light;

  // Brand tones in this set's hue (see AppColors.wine…night).
  final Color wine;
  final Color wineMid;
  final Color deep;
  final Color rose;
  final Color night;

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
    required this.light,
    required this.wine,
    required this.wineMid,
    required this.deep,
    required this.rose,
    required this.night,
  });

  bool get isLight => light;
}

/// Colour sets (Cài đặt › Giao diện). 'sang' is the default; 'toi' is
/// shown as "Đen". Wine-red sets keep the logo guideline tones; the others
/// shift every surface, accent and brand tone to their own hue. Muted text
/// and white-on-accent are ≥4.5:1 in every set (design/palettes_proposal.py).
const List<AppPalette> kAppPalettes = [
  AppPalette(
    name: 'sang', label: 'Sáng', light: true,
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F1F0),
    surfaceLight: Color(0xFFEDE9E8),
    surfaceHover: Color(0xFFE5E0DF),
    accent: Color(0xFF711313),
    accentLight: Color(0xFF8E1F1F),
    accentSoft: Color(0xFFF8EDED),
    text: Color(0xFF161112),
    textSecondary: Color(0xFF4F4547),
    textMuted: Color(0xFF665C5E),
    border: Color(0xFFECE4E4),
    borderSubtle: Color(0xFFF3EEEE),
    wine: Color(0xFF711313),
    wineMid: Color(0xFF8E1F1F),
    deep: Color(0xFF4A0C0C),
    rose: Color(0xFFB48988),
    night: Color(0xFF0E0A0A),
  ),
  AppPalette(
    name: 'kem', label: 'Kem', light: true,
    bg: Color(0xFFF7F4EF),
    surface: Color(0xFFFFFFFF),
    surfaceLight: Color(0xFFECE7E0),
    surfaceHover: Color(0xFFE4DED5),
    accent: Color(0xFF8B1A1A),
    accentLight: Color(0xFF9A2424),
    accentSoft: Color(0xFFF6EAE6),
    text: Color(0xFF1A1414),
    textSecondary: Color(0xFF5E4D4D),
    textMuted: Color(0xFF6E5C5C),
    border: Color(0xFFE2DBD2),
    borderSubtle: Color(0xFFEDE7DF),
    wine: Color(0xFF711313),
    wineMid: Color(0xFF8E1F1F),
    deep: Color(0xFF4A0C0C),
    rose: Color(0xFFB48988),
    night: Color(0xFF0E0A0A),
  ),
  AppPalette(
    name: 'sepia', label: 'Nâu sepia', light: true,
    bg: Color(0xFFF1E6D2),
    surface: Color(0xFFFAF3E6),
    surfaceLight: Color(0xFFE6D7BD),
    surfaceHover: Color(0xFFDCCBAE),
    accent: Color(0xFF6B3A1E),
    accentLight: Color(0xFF7E4826),
    accentSoft: Color(0xFFF0E2CF),
    text: Color(0xFF2B1D12),
    textSecondary: Color(0xFF5A4330),
    textMuted: Color(0xFF6A5442),
    border: Color(0xFFD9C6A5),
    borderSubtle: Color(0xFFE5D6BC),
    wine: Color(0xFF6B3A1E),
    wineMid: Color(0xFF8A5230),
    deep: Color(0xFF3F2210),
    rose: Color(0xFFB8977A),
    night: Color(0xFF140D08),
  ),
  AppPalette(
    name: 'hong', label: 'Hồng phấn', light: true,
    bg: Color(0xFFFBF1F2),
    surface: Color(0xFFFFFFFF),
    surfaceLight: Color(0xFFF3E2E4),
    surfaceHover: Color(0xFFEBD6D9),
    accent: Color(0xFFA3324A),
    accentLight: Color(0xFFB23E57),
    accentSoft: Color(0xFFF9E6EA),
    text: Color(0xFF22141A),
    textSecondary: Color(0xFF5C4049),
    textMuted: Color(0xFF6E5560),
    border: Color(0xFFEBD5D9),
    borderSubtle: Color(0xFFF3E5E8),
    wine: Color(0xFFA3324A),
    wineMid: Color(0xFFC04A64),
    deep: Color(0xFF5E1426),
    rose: Color(0xFFD9A0AC),
    night: Color(0xFF12070B),
  ),
  AppPalette(
    name: 'troi', label: 'Xanh trời', light: true,
    bg: Color(0xFFEEF4F8),
    surface: Color(0xFFFFFFFF),
    surfaceLight: Color(0xFFDFE9F0),
    surfaceHover: Color(0xFFD3E0EA),
    accent: Color(0xFF1F5E86),
    accentLight: Color(0xFF286E9A),
    accentSoft: Color(0xFFE3EEF6),
    text: Color(0xFF111C24),
    textSecondary: Color(0xFF3E5160),
    textMuted: Color(0xFF566878),
    border: Color(0xFFD3E0EA),
    borderSubtle: Color(0xFFE3ECF2),
    wine: Color(0xFF1F5E86),
    wineMid: Color(0xFF2C77A6),
    deep: Color(0xFF0E3350),
    rose: Color(0xFF8FB3CC),
    night: Color(0xFF060B12),
  ),
  AppPalette(
    name: 'toi', label: 'Đen', light: false,
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
    wine: Color(0xFF711313),
    wineMid: Color(0xFF8E1F1F),
    deep: Color(0xFF4A0C0C),
    rose: Color(0xFFB48988),
    night: Color(0xFF0E0A0A),
  ),
  AppPalette(
    name: 'xam', label: 'Xám', light: false,
    bg: Color(0xFF1A1A1E),
    surface: Color(0xFF242428),
    surfaceLight: Color(0xFF2E2E33),
    surfaceHover: Color(0xFF38383E),
    // Slate accent (not wine) so Xám doesn't read as Đen.
    accent: Color(0xFF4F6274),
    accentLight: Color(0xFFBFCAD6),
    accentSoft: Color(0xFF2A3038),
    text: Color(0xFFE8E6E3),
    textSecondary: Color(0xFFBDBBB8),
    textMuted: Color(0xFF9E9E9E),
    border: Color(0xFF36363C),
    borderSubtle: Color(0xFF222226),
    wine: Color(0xFF4F6274),
    wineMid: Color(0xFF637A8F),
    deep: Color(0xFF26313C),
    rose: Color(0xFF8A9AAA),
    night: Color(0xFF101013),
  ),
  AppPalette(
    name: 'do', label: 'Đỏ đô', light: false,
    bg: Color(0xFF3D0C0C),
    surface: Color(0xFF4E1212),
    surfaceLight: Color(0xFF5E1818),
    surfaceHover: Color(0xFF6E2020),
    accent: Color(0xFFC94444),
    accentLight: Color(0xFFF5B8B8),
    accentSoft: Color(0xFF5C1A1A),
    text: Color(0xFFFFF8F5),
    textSecondary: Color(0xFFF0D6D0),
    textMuted: Color(0xFFD9AFA9),
    border: Color(0xFF6A2020),
    borderSubtle: Color(0xFF461010),
    wine: Color(0xFFC94444),
    wineMid: Color(0xFFE05555),
    deep: Color(0xFF2A0808),
    rose: Color(0xFFD98C8C),
    night: Color(0xFF1F0606),
  ),
  AppPalette(
    name: 'hophach', label: 'Hổ phách', light: false,
    bg: Color(0xFF1A1308),
    surface: Color(0xFF241A0D),
    surfaceLight: Color(0xFF2E2212),
    surfaceHover: Color(0xFF382A17),
    accent: Color(0xFF9A5F12),
    accentLight: Color(0xFFF0C987),
    accentSoft: Color(0xFF33240F),
    text: Color(0xFFF6EEDF),
    textSecondary: Color(0xFFDCCDB2),
    textMuted: Color(0xFFAE9C80),
    border: Color(0xFF3A2C17),
    borderSubtle: Color(0xFF1F170B),
    wine: Color(0xFF9A5F12),
    wineMid: Color(0xFFB97A26),
    deep: Color(0xFF4A2E08),
    rose: Color(0xFFC9A06E),
    night: Color(0xFF0E0A04),
  ),
  AppPalette(
    name: 'reu', label: 'Xanh rêu', light: false,
    bg: Color(0xFF16150B),
    surface: Color(0xFF201E10),
    surfaceLight: Color(0xFF2A2816),
    surfaceHover: Color(0xFF333019),
    accent: Color(0xFF66621A),
    accentLight: Color(0xFFD6CF86),
    accentSoft: Color(0xFF2C2A12),
    text: Color(0xFFF1EFE0),
    textSecondary: Color(0xFFD3CFB4),
    textMuted: Color(0xFFA6A182),
    border: Color(0xFF353220),
    borderSubtle: Color(0xFF1B1A0E),
    wine: Color(0xFF66621A),
    wineMid: Color(0xFF85802C),
    deep: Color(0xFF3A370C),
    rose: Color(0xFFA8A15E),
    night: Color(0xFF0C0B05),
  ),
  AppPalette(
    name: 'la', label: 'Xanh lá', light: false,
    bg: Color(0xFF0A1A0C),
    surface: Color(0xFF122016),
    surfaceLight: Color(0xFF1A2A1E),
    surfaceHover: Color(0xFF223426),
    accent: Color(0xFF287A33),
    accentLight: Color(0xFF9BD3A4),
    accentSoft: Color(0xFF15301B),
    text: Color(0xFFE8F0EA),
    textSecondary: Color(0xFFC2D3C5),
    textMuted: Color(0xFF93A897),
    border: Color(0xFF24382A),
    borderSubtle: Color(0xFF0F1D12),
    wine: Color(0xFF287A33),
    wineMid: Color(0xFF3A9A47),
    deep: Color(0xFF0F4418),
    rose: Color(0xFF7FB088),
    night: Color(0xFF06100A),
  ),
  AppPalette(
    name: 'ngoc', label: 'Xanh ngọc', light: false,
    bg: Color(0xFF08171A),
    surface: Color(0xFF0F2226),
    surfaceLight: Color(0xFF162D32),
    surfaceHover: Color(0xFF1D373D),
    accent: Color(0xFF1C6F75),
    accentLight: Color(0xFF8FD6D2),
    accentSoft: Color(0xFF123338),
    text: Color(0xFFE6F3F2),
    textSecondary: Color(0xFFBFD6D4),
    textMuted: Color(0xFF8CA9A7),
    border: Color(0xFF1F3A3F),
    borderSubtle: Color(0xFF0C1C20),
    wine: Color(0xFF1C6F75),
    wineMid: Color(0xFF268C93),
    deep: Color(0xFF0B3B40),
    rose: Color(0xFF6FAFAD),
    night: Color(0xFF040D0F),
  ),
  AppPalette(
    name: 'duong', label: 'Xanh dương', light: false,
    bg: Color(0xFF0A0F1E),
    surface: Color(0xFF111A2E),
    surfaceLight: Color(0xFF18233C),
    surfaceHover: Color(0xFF202D48),
    accent: Color(0xFF2B62A0),
    accentLight: Color(0xFF9DC2EE),
    accentSoft: Color(0xFF152A48),
    text: Color(0xFFE8EEF7),
    textSecondary: Color(0xFFC3CEE0),
    textMuted: Color(0xFF8E9DB6),
    border: Color(0xFF24314C),
    borderSubtle: Color(0xFF0E1526),
    wine: Color(0xFF2B62A0),
    wineMid: Color(0xFF3B7DC4),
    deep: Color(0xFF11305A),
    rose: Color(0xFF7FA3CF),
    night: Color(0xFF060914),
  ),
  AppPalette(
    name: 'tim', label: 'Tím', light: false,
    bg: Color(0xFF1A0C17),
    surface: Color(0xFF251220),
    surfaceLight: Color(0xFF30182A),
    surfaceHover: Color(0xFF3A1F33),
    accent: Color(0xFF8E3A7E),
    accentLight: Color(0xFFE3A8D6),
    accentSoft: Color(0xFF3A1834),
    text: Color(0xFFF7EAF3),
    textSecondary: Color(0xFFDCC5D5),
    textMuted: Color(0xFFB096A8),
    border: Color(0xFF3D2236),
    borderSubtle: Color(0xFF1F0F1B),
    wine: Color(0xFF8E3A7E),
    wineMid: Color(0xFFAC4F9A),
    deep: Color(0xFF4A1640),
    rose: Color(0xFFB87FAA),
    night: Color(0xFF10070E),
  ),
];

/// Text-size preference ("Cỡ chữ" in Cài đặt).
const Map<String, double> kTextScales = {'vua': 1.0, 'lon': 1.18, 'ratlon': 1.35};
const Map<String, String> kTextScaleLabels = {'vua': 'Vừa', 'lon': 'Lớn', 'ratlon': 'Rất lớn'};

/// App-wide theme switcher. Persists the chosen colour set, whether to
/// follow the OS light/dark switch (using the last light and the last dark
/// set picked), and the text-size preference.
class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const _prefsKey = 'app_theme_name';
  static const _scaleKey = 'app_text_scale';
  static const _panelKey = 'app_panel_auto_open';
  static const _tintKey = 'app_tint_photos';
  static const _hintsKey = 'app_shortcut_hints';
  static const _followKey = 'app_theme_follow_system';
  static const _lightKey = 'app_theme_light_pick';
  static const _darkKey = 'app_theme_dark_pick';
  AppPalette _palette = kAppPalettes.first;
  /// The set the user picked last (shown when not following the OS).
  String _pick = 'sang';
  /// Last light / dark set picked: what "Theo giao diện máy" switches between.
  String _lightPick = 'sang';
  String _darkPick = 'toi';
  bool _followSystem = false;
  String _scale = 'vua';
  bool _panelAutoOpen = true;
  bool _tintPhotos = true;
  bool _shortcutHints = false;
  final Completer<void> _restored = Completer<void>();

  ThemeProvider() {
    _applyToGlobalColors();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  AppPalette get palette => _palette;
  String get name => _palette.name;
  /// A palette name, or 'system' while following the OS.
  String get mode => _followSystem ? 'system' : _pick;
  /// The set the user chose (highlighted in the picker).
  String get pick => _pick;
  bool get followSystem => _followSystem;
  String get lightPick => _lightPick;
  String get darkPick => _darkPick;
  String get textScaleKey => _scale;
  double get textScale => kTextScales[_scale] ?? 1.0;
  /// Desktop: the right panel (Lời · Bình luận · Hàng đợi) opens by itself
  /// on wide windows.
  bool get panelAutoOpen => _panelAutoOpen;
  /// Archive photos get the wine/paper duotone ([BrandTint]).
  bool get tintPhotos => _tintPhotos;
  /// Desktop tooltips name their key: "Phát (Space)".
  bool get shortcutHints => _shortcutHints;
  /// Completes once saved preferences have been read.
  Future<void> get ready => _restored.future;

  static AppPalette _byName(String n, [String fallback = 'sang']) =>
      kAppPalettes.firstWhere((p) => p.name == n, orElse: () => kAppPalettes.firstWhere((p) => p.name == fallback));

  bool get _osDark => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;

  AppPalette _current() => _followSystem ? _byName(_osDark ? _darkPick : _lightPick, _osDark ? 'toi' : 'sang') : _byName(_pick);

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    // 2026-11 brand redesign: every older palette (hoaico, classic, light,
    // red…) resets once to the new light default.
    if (prefs.getBool('app_theme_brand_migrated') != true) {
      await prefs.setBool('app_theme_brand_migrated', true);
      await prefs.remove(_prefsKey);
    }
    // Screenshot hook (desktop debug runs): BCDCNT_THEME=<set name>.
    final forced = (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) ? Platform.environment['BCDCNT_THEME'] : null;
    final saved = forced ?? prefs.getString(_prefsKey);
    // Before the colour sets the saved value could be 'system'.
    _followSystem = forced == null && (prefs.getBool(_followKey) ?? saved == 'system');
    _pick = kAppPalettes.any((p) => p.name == saved) ? saved! : 'sang';
    _lightPick = prefs.getString(_lightKey) ?? (_byName(_pick).light ? _pick : 'sang');
    _darkPick = prefs.getString(_darkKey) ?? (_byName(_pick).light ? 'toi' : _pick);
    _scale = kTextScales.containsKey(prefs.getString(_scaleKey)) ? prefs.getString(_scaleKey)! : 'vua';
    _palette = _current();
    _panelAutoOpen = prefs.getBool(_panelKey) ?? true;
    _tintPhotos = prefs.getBool(_tintKey) ?? true;
    _shortcutHints = prefs.getBool(_hintsKey) ?? false;
    _applyToGlobalColors();
    if (!_restored.isCompleted) _restored.complete();
    notifyListeners();
  }

  @override
  void didChangePlatformBrightness() {
    if (!_followSystem) return;
    final next = _current();
    if (next.name == _palette.name) return;
    _palette = next;
    _applyToGlobalColors();
    notifyListeners();
  }

  void _show() {
    final next = _current();
    if (next.name != _palette.name) {
      _palette = next;
      _applyToGlobalColors();
    }
    notifyListeners();
  }

  /// Picks a colour set by name ('system' = follow the OS, kept for old
  /// callers). It also becomes the light or dark set used when following
  /// the OS; if that would hide it right now (a dark set picked in daytime),
  /// following is switched off so the pick shows.
  Future<void> setTheme(String name) async {
    if (name == 'system') return setFollowSystem(true);
    if (!kAppPalettes.any((p) => p.name == name)) return;
    final p = _byName(name);
    _pick = name;
    if (p.light) {
      _lightPick = name;
    } else {
      _darkPick = name;
    }
    if (_followSystem && p.light == _osDark) _followSystem = false;
    _show();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, name);
    await prefs.setString(p.light ? _lightKey : _darkKey, name);
    await prefs.setBool(_followKey, _followSystem);
  }

  Future<void> setFollowSystem(bool v) async {
    if (v == _followSystem) return;
    _followSystem = v;
    _show();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_followKey, v);
  }

  Future<void> setTextScale(String key) async {
    if (!kTextScales.containsKey(key) || key == _scale) return;
    _scale = key;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scaleKey, key);
  }

  Future<void> setPanelAutoOpen(bool v) => _setFlag(_panelKey, v, () => _panelAutoOpen = v);
  Future<void> setTintPhotos(bool v) => _setFlag(_tintKey, v, () => _tintPhotos = v);
  Future<void> setShortcutHints(bool v) => _setFlag(_hintsKey, v, () => _shortcutHints = v);

  Future<void> _setFlag(String key, bool v, VoidCallback apply) async {
    apply();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
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
    AppColors.wine = _palette.wine;
    AppColors.wineMid = _palette.wineMid;
    AppColors.deep = _palette.deep;
    AppColors.rose = _palette.rose;
    AppColors.night = _palette.night;
    AppColors.love = _palette.name == 'do' ? const Color(0xFFFFB3BA) : (_palette.light ? const Color(0xFFD23B3B) : const Color(0xFFE5484D));
  }
}

/// Visual swatch for a palette: its page colour with an accent half, so
/// light and dark sets read alike. Shared by the settings pickers.
Widget themeSwatch(AppPalette p, {double size = 28, bool active = false}) {
  final ring = active ? (AppColors.isLight ? Colors.black54 : Colors.white) : AppColors.border;
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(colors: [p.bg, p.bg, p.wine, p.wine], stops: const [0, 0.5, 0.5, 1], begin: Alignment.topLeft, end: Alignment.bottomRight),
      border: Border.all(color: ring, width: active ? 2 : 1),
    ),
    child: active ? Center(child: Icon(Icons.check, size: size * 0.5, color: Colors.white, shadows: const [Shadow(color: Colors.black54, blurRadius: 3)])) : null,
  );
}
