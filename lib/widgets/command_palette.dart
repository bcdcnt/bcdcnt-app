import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../services/theme_provider.dart';

/// Cmd+K spotlight-style search overlay. Debounced text input on top, up to
/// 8 matching results below. Enter activates the highlighted result, Esc
/// closes, ↑/↓ moves the highlight. Modal route so any Navigator.pop closes
/// it cleanly.
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  /// Open the palette as a modal overlay. If [navigatorState] is null we'll
  /// look up the root Navigator from [context] — useful when called from a
  /// widget already inside the route tree. Global keyboard shortcuts pass
  /// [navigatorState] explicitly because their handler runs above any
  /// Navigator and a context lookup wouldn't find one.
  static Future<void> show(BuildContext context, {NavigatorState? navigatorState}) {
    final nav = navigatorState ?? Navigator.of(context, rootNavigator: true);
    return nav.push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (_, _, _) => const CommandPalette(),
        transitionsBuilder: (_, anim, _, child) {
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.97, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

/// Quick action — palette entry that runs a closure rather than navigating
/// to a search hit. Title shown in the row, hotkey hint surfaced when set.
class _PaletteAction {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? hotkey;
  final VoidCallback run;
  const _PaletteAction({
    required this.icon,
    required this.title,
    required this.run,
    this.subtitle,
    this.hotkey,
  });
}

class _CommandPaletteState extends State<CommandPalette> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _listScroll = ScrollController();
  Timer? _debounce;
  List<Map<String, dynamic>> _hits = [];
  bool _loading = false;
  int _selected = 0;
  static const _rowHeight = 54.0; // matches _PaletteRow padding + content

  bool get _isDesktopOS => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    if (!_listScroll.hasClients) return;
    final viewport = _listScroll.position.viewportDimension;
    final target = (_selected * _rowHeight) - (viewport / 2) + (_rowHeight / 2);
    final clamped = target.clamp(0.0, _listScroll.position.maxScrollExtent);
    _listScroll.animateTo(clamped, duration: const Duration(milliseconds: 140), curve: Curves.easeOut);
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() { _hits = []; _loading = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () => _run(v.trim()));
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.query(
        r'query($q: String!, $limit: Int, $type: String!) { search(q: $q, limit: $limit, type: $type) }',
        {'q': q, 'limit': 5, 'type': 'all'},
      );
      final raw = (data['search'] ?? []) as List;
      // Flatten the grouped results into a single list (top 8) so keyboard
      // navigation and Enter behaviour stay simple.
      final flat = <Map<String, dynamic>>[];
      for (final group in raw) {
        final type = group['type']?.toString() ?? '';
        final hits = (group['hits'] as List?) ?? [];
        for (final h in hits) {
          flat.add({...(h as Map).cast<String, dynamic>(), '_search_type': type});
          if (flat.length >= 8) break;
        }
        if (flat.length >= 8) break;
      }
      if (!mounted) return;
      setState(() {
        _hits = flat;
        _loading = false;
        _selected = 0;
      });
    } catch (_) {
      if (mounted) setState(() { _hits = []; _loading = false; });
    }
  }

  // Curated quick actions — navigation, player controls, theme switcher.
  // Built fresh per build so play state / current theme name stay live.
  List<_PaletteAction> _buildActions(BuildContext context, PlayerProvider player, ThemeProvider theme) {
    void close() => Navigator.of(context, rootNavigator: true).pop();
    void go(String path) { close(); context.push(path); }
    return [
      // Navigation
      _PaletteAction(icon: Icons.home_outlined, title: 'Trang chủ', subtitle: 'Đi tới /', run: () => go('/')),
      _PaletteAction(icon: Icons.search, title: 'Tìm kiếm', subtitle: 'Đi tới /search', run: () => go('/search')),
      _PaletteAction(icon: Icons.chat_bubble_outline, title: 'Bình luận', subtitle: 'Đi tới /binh-luan', run: () => go('/binh-luan')),
      _PaletteAction(icon: Icons.leaderboard_outlined, title: 'Bảng xếp hạng', subtitle: 'Đi tới /bang-xep-hang', run: () => go('/bang-xep-hang')),
      _PaletteAction(icon: Icons.library_music_outlined, title: 'Thư viện', subtitle: 'Đi tới /library', run: () => go('/library')),
      _PaletteAction(icon: Icons.notifications_outlined, title: 'Thông báo', subtitle: 'Đi tới /thong-bao', run: () => go('/thong-bao')),
      _PaletteAction(icon: Icons.settings_outlined, title: 'Cài đặt', subtitle: 'Đi tới /cai-dat', run: () => go('/cai-dat')),
      _PaletteAction(icon: Icons.mic_outlined, title: 'Nghệ sĩ', subtitle: 'Đi tới /nghe-si', run: () => go('/nghe-si')),
      _PaletteAction(icon: Icons.piano_outlined, title: 'Nhạc sĩ', subtitle: 'Đi tới /nhac-si', run: () => go('/nhac-si')),
      _PaletteAction(icon: Icons.tag, title: 'Tag', subtitle: 'Đi tới /tag', run: () => go('/tag')),
      // Player controls — only meaningful when something is loaded.
      if (player.currentSong != null) ...[
        _PaletteAction(
          icon: player.isPlaying ? Icons.pause : Icons.play_arrow,
          title: player.isPlaying ? 'Tạm dừng' : 'Phát',
          hotkey: 'Space',
          run: () { close(); player.togglePlay(); },
        ),
        _PaletteAction(icon: Icons.skip_next, title: 'Bài tiếp', hotkey: '⇧ →', run: () { close(); player.playNext(); }),
        _PaletteAction(icon: Icons.skip_previous, title: 'Bài trước', hotkey: '⇧ ←', run: () { close(); player.playPrev(); }),
        _PaletteAction(
          icon: player.shuffle ? Icons.shuffle_on_outlined : Icons.shuffle,
          title: player.shuffle ? 'Tắt phát ngẫu nhiên' : 'Bật phát ngẫu nhiên',
          run: () { close(); player.toggleShuffle(); },
        ),
      ],
      // Window — desktop only.
      if (_isDesktopOS)
        _PaletteAction(
          icon: Icons.fullscreen,
          title: 'Toàn màn hình',
          hotkey: 'F',
          run: () async { close(); final v = await windowManager.isFullScreen(); await windowManager.setFullScreen(!v); },
        ),
      // Theme cycler — picks the next palette in kAppPalettes after current.
      _PaletteAction(
        icon: Icons.palette_outlined,
        title: 'Đổi phối màu',
        subtitle: 'Hiện tại: ${theme.palette.label}',
        run: () {
          close();
          final i = kAppPalettes.indexWhere((p) => p.name == theme.name);
          final next = kAppPalettes[(i + 1) % kAppPalettes.length];
          theme.setTheme(next.name);
        },
      ),
    ];
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: body(TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.textMuted)),
      ),
    );
  }

  // Substring match (case + diacritic-insensitive — only for ASCII so far,
  // good enough for the action labels which are Vietnamese-with-diacritics
  // text. Lower-cases both sides; doesn't strip diacritics — matching
  // "tìm" requires typing "tìm").
  bool _matchesAction(_PaletteAction a, String q) {
    if (q.isEmpty) return true;
    final ql = q.toLowerCase();
    return a.title.toLowerCase().contains(ql) || (a.subtitle?.toLowerCase().contains(ql) ?? false);
  }

  void _open(Map<String, dynamic> hit) {
    Navigator.of(context, rootNavigator: true).pop();
    final t = hit['_search_type']?.toString();
    final id = hit['id']?.toString();
    final slug = hit['slug']?.toString();
    if (id == null) return;
    switch (t) {
      case 'song':
      case 'folk':
      case 'instrumental':
      case 'poem':
      case 'karaoke':
        final song = <String, dynamic>{
          'id': id, 'title': hit['title'], 'slug': slug, 'file_type': t,
          if (hit['image'] != null) 'thumbnail': {'url': hit['image']},
          if (hit['artist'] != null) 'artists': {'data': [{'title': hit['artist']}]},
          if (hit['audio_url'] != null || hit['video_url'] != null)
            'file': {'audio_url': hit['audio_url'], 'video_url': hit['video_url']},
          'play_type': hit['play_type'] ?? 'audio',
        };
        context.push('/song/$id', extra: song);
        break;
      case 'artist': context.push('/nghe-si/$slug'); break;
      case 'composer': context.push('/nhac-si/$slug'); break;
      case 'poet': context.push('/nha-tho/$slug'); break;
      case 'recomposer': context.push('/soan-gia/$slug'); break;
      case 'playlist': context.push('/playlist/$id'); break;
      case 'sheet': context.push('/sheet/$id'); break;
      case 'document': context.push('/tu-lieu/chi-tiet/$id'); break;
      case 'discussion': context.push('/thao-luan/$id'); break;
      case 'tag': context.push('/tag/$slug'); break;
    }
  }

  // Compute the live combined list once per key/build call so handlers and
  // renderer agree on what _selected points at. Actions first, then API
  // search hits.
  List<_PaletteAction> _filteredActions() {
    final player = context.read<PlayerProvider>();
    final theme = context.read<ThemeProvider>();
    return _buildActions(context, player, theme).where((a) => _matchesAction(a, _ctrl.text.trim())).toList();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context, rootNavigator: true).pop();
      return KeyEventResult.handled;
    }
    final actions = _filteredActions();
    final total = actions.length + _hits.length;
    if (total == 0) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1) % total);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = (_selected - 1 + total) % total);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (_selected < actions.length) {
        actions[_selected].run();
      } else {
        _open(_hits[_selected - actions.length]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Material ancestor is required by TextField/InkWell. Use transparent
    // so the surrounding scrim stays visible.
    return Material(
      type: MaterialType.transparency,
      child: Center(
      child: Container(
        // Fixed height so the popup stops jumping between empty / few /
        // many results — Spotify-style. Body scrolls inside when results
        // overflow the available space.
        width: 640,
        height: 480,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 32, offset: const Offset(0, 12))],
        ),
        child: Focus(
          onKeyEvent: _handleKey,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 20, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        autofocus: true,
                        onChanged: _onChanged,
                        cursorColor: AppColors.accent,
                        style: body(TextStyle(fontSize: 16, color: AppColors.text)),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Tìm bài hát, nghệ sĩ, nhạc sĩ...',
                          hintStyle: body(TextStyle(fontSize: 16, color: AppColors.textMuted)),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Esc', style: body(TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.border),
              Expanded(child: Builder(builder: (ctx) {
                final actions = _filteredActions();
                final hasInput = _ctrl.text.trim().isNotEmpty;
                if (_loading && _hits.isEmpty && actions.isEmpty) {
                  return Center(child: CircularProgressIndicator(color: AppColors.accent));
                }
                if (actions.isEmpty && _hits.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        hasInput ? 'Không tìm thấy kết quả' : 'Gõ để tìm. Dùng ↑↓ chọn, Enter mở, Esc đóng.',
                        style: body(TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final children = <Widget>[];
                if (actions.isNotEmpty) {
                  children.add(_sectionHeader(hasInput ? 'Lệnh' : 'Hành động nhanh'));
                  for (var i = 0; i < actions.length; i++) {
                    children.add(_ActionRow(
                      action: actions[i],
                      selected: i == _selected,
                      onTap: actions[i].run,
                    ));
                  }
                }
                if (_hits.isNotEmpty) {
                  children.add(_sectionHeader('Kết quả tìm kiếm'));
                  for (var i = 0; i < _hits.length; i++) {
                    final globalIdx = actions.length + i;
                    children.add(_PaletteRow(
                      hit: _hits[i],
                      selected: globalIdx == _selected,
                      onTap: () => _open(_hits[i]),
                    ));
                  }
                }
                return ListView(
                  controller: _listScroll,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: children,
                );
              })),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final _PaletteAction action;
  final bool selected;
  final VoidCallback onTap;
  const _ActionRow({required this.action, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          color: selected ? AppColors.surfaceLight : Colors.transparent,
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(action.icon, size: 18, color: selected ? AppColors.accentLight : AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text))),
                  if (action.subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(action.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
                  ],
                ],
              ),
            ),
            if (action.hotkey != null) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.border)),
                child: Text(action.hotkey!, style: body(TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  final Map<String, dynamic> hit;
  final bool selected;
  final VoidCallback onTap;
  const _PaletteRow({required this.hit, required this.selected, required this.onTap});

  String _typeLabel(String? t) {
    switch (t) {
      case 'song': return 'Bài hát';
      case 'folk': return 'Dân ca';
      case 'instrumental': return 'Khí nhạc';
      case 'poem': return 'Tiếng thơ';
      case 'karaoke': return 'Karaoke';
      case 'artist': return 'Nghệ sĩ';
      case 'composer': return 'Nhạc sĩ';
      case 'poet': return 'Nhà thơ';
      case 'recomposer': return 'Soạn giả';
      case 'playlist': return 'Playlist';
      case 'sheet': return 'Bản nhạc';
      case 'document': return 'Tư liệu';
      case 'discussion': return 'Thảo luận';
      case 'tag': return 'Tag';
      default: return t ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = hit['image']?.toString();
    final type = hit['_search_type']?.toString();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          color: selected ? AppColors.surfaceLight : Colors.transparent,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: image != null
                    ? CachedNetworkImage(imageUrl: image, width: 36, height: 36, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(width: 36, height: 36, color: AppColors.surfaceLight, child: Icon(Icons.music_note, size: 16, color: AppColors.textMuted)))
                    : Container(width: 36, height: 36, color: AppColors.surfaceLight, child: Icon(Icons.music_note, size: 16, color: AppColors.textMuted)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(hit['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text))),
                    if (hit['artist'] != null) ...[
                      const SizedBox(height: 1),
                      Text(hit['artist'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_typeLabel(type), style: body(TextStyle(fontSize: 10, color: AppColors.accentLight, fontWeight: FontWeight.w600))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
