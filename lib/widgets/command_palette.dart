import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';

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

class _CommandPaletteState extends State<CommandPalette> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _listScroll = ScrollController();
  Timer? _debounce;
  List<Map<String, dynamic>> _hits = [];
  bool _loading = false;
  int _selected = 0;
  static const _rowHeight = 54.0; // matches _PaletteRow padding + content

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

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context, rootNavigator: true).pop();
      return KeyEventResult.handled;
    }
    if (_hits.isEmpty) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1) % _hits.length);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = (_selected - 1 + _hits.length) % _hits.length);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _open(_hits[_selected]);
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
                    const Icon(Icons.search, size: 20, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        autofocus: true,
                        onChanged: _onChanged,
                        cursorColor: AppColors.accent,
                        style: body(const TextStyle(fontSize: 16, color: AppColors.text)),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Tìm bài hát, nghệ sĩ, nhạc sĩ...',
                          hintStyle: body(const TextStyle(fontSize: 16, color: AppColors.textMuted)),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Esc', style: body(const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                    : _ctrl.text.trim().isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                'Gõ để tìm. Dùng ↑↓ chọn, Enter mở, Esc đóng.',
                                style: body(const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : _hits.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: Text(
                                    'Không tìm thấy kết quả',
                                    style: body(const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: _listScroll,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                itemCount: _hits.length,
                                itemBuilder: (_, i) => _PaletteRow(
                                  hit: _hits[i],
                                  selected: i == _selected,
                                  onTap: () => _open(_hits[i]),
                                ),
                              ),
              ),
            ],
          ),
        ),
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
                    ? CachedNetworkImage(imageUrl: image, width: 36, height: 36, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(width: 36, height: 36, color: AppColors.surfaceLight, child: const Icon(Icons.music_note, size: 16, color: AppColors.textMuted)))
                    : Container(width: 36, height: 36, color: AppColors.surfaceLight, child: const Icon(Icons.music_note, size: 16, color: AppColors.textMuted)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(hit['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text))),
                    if (hit['artist'] != null) ...[
                      const SizedBox(height: 1),
                      Text(hit['artist'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
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
                child: Text(_typeLabel(type), style: body(const TextStyle(fontSize: 10, color: AppColors.accentLight, fontWeight: FontWeight.w600))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
