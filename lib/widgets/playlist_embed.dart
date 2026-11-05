import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import 'song_row.dart';
import 'ui.dart' show UserAvatar, Skeleton;

// Playlist placed in a post with a shortcode, same as the web
// (bcdcnt-web components/shared/RichContent.jsx + ArtistPlaylistEmbed.jsx):
//   [playlist nghe-si="bich-lien"]
//   [playlist nhac-si="van-cao" so-bai="20" sap-xep="moi" tieu-de="…"]
// sap-xep: nghe-nhieu (default) | moi | yeu-thich. nghe-si / nhac-si take a
// slug or the person's page URL. Editors wrap it in <p> and curl the quotes.

final playlistShortcode = RegExp(r'(?:<p[^>]*>\s*)?\[playlist\b([^\]]*)\](?:\s*</p>)?', caseSensitive: false);

class PlaylistShortcode {
  final String type; // artist | composer
  final String slug;
  final int limit;
  final String sort; // views | id | likes
  final String? title;
  const PlaylistShortcode(this.type, this.slug, this.limit, this.sort, this.title);

  static PlaylistShortcode? parse(String rawAttrs) {
    final s = rawAttrs
        .replaceAll(RegExp(r'&quot;|&#34;|&ldquo;|&rdquo;|[“”]'), '"')
        .replaceAll(RegExp(r"&#39;|&apos;|&lsquo;|&rsquo;|[‘’]"), "'")
        .replaceAll(RegExp(r'&nbsp;|&#160;'), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&');
    final attrs = <String, String>{};
    for (final m in RegExp(r'''([a-z-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"']+))''', caseSensitive: false).allMatches(s)) {
      attrs[m.group(1)!.toLowerCase()] = (m.group(2) ?? m.group(3) ?? m.group(4) ?? '').trim();
    }
    final isComposer = (attrs['nhac-si'] ?? '').isNotEmpty;
    // "bich-lien" or "https://bcdcnt.net/nghe-si/bich-lien" → "bich-lien"
    final slug = (attrs[isComposer ? 'nhac-si' : 'nghe-si'] ?? '').split(RegExp(r'[?#]')).first.replaceAll(RegExp(r'/+$'), '').split('/').last;
    if (slug.isEmpty) return null;
    final limit = int.tryParse(attrs['so-bai'] ?? '') ?? 0;
    final sort = const {'moi': 'id', 'yeu-thich': 'likes'}[attrs['sap-xep']] ?? 'views';
    final title = (attrs['tieu-de'] ?? '').isEmpty ? null : attrs['tieu-de'];
    return PlaylistShortcode(isComposer ? 'composer' : 'artist', slug, limit > 0 ? limit : 300, sort, title);
  }
}

class PlaylistEmbed extends StatefulWidget {
  final PlaylistShortcode code;
  const PlaylistEmbed({super.key, required this.code});

  @override
  State<PlaylistEmbed> createState() => _PlaylistEmbedState();
}

class _PlaylistEmbedState extends State<PlaylistEmbed> {
  static const _preview = 10;
  Map<String, dynamic>? _person;
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  bool _all = false, _expanded = false, _busy = false, _loading = true;

  @override
  void initState() {
    super.initState();
    _load(_preview);
  }

  Future<Map<String, dynamic>?> _fetch(int first) async {
    final c = widget.code;
    final d = await ApiClient.query(
      'query(\$slug: String!, \$first: Int!) { ${c.type}(slug: \$slug) { id title slug avatar { url } songs(first: \$first, page: 1, orderBy: [{column: "${c.sort}", order: DESC}]) { data { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } sheet { year composers(first: 5) { data { id slug title } } } artists(first: 5) { data { id title slug avatar { url } } } } paginatorInfo { total } } } }',
      {'slug': c.slug, 'first': first},
    );
    return d[c.type] is Map ? Map<String, dynamic>.from(d[c.type]) : null;
  }

  List<Map<String, dynamic>> _songs(Map p) => ((p['songs']?['data'] as List?) ?? const [])
      .map((s) => <String, dynamic>{...Map<String, dynamic>.from(s as Map), 'file_type': 'song', 'audioUrl': s['file']?['audio_url']})
      .toList();

  Future<void> _load(int first) async {
    try {
      final p = await _fetch(first.clamp(1, widget.code.limit));
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (p == null) return;
        _person = p;
        _items = _songs(p);
        _total = ((p['songs']?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0).clamp(0, widget.code.limit);
        _all = _total <= first;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAll() async {
    if (_all) return;
    setState(() => _busy = true);
    await _load(widget.code.limit);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _playAll() async {
    await _loadAll();
    final list = _items.where((s) => s['audioUrl'] != null).toList();
    if (list.isEmpty || !mounted) return;
    context.read<PlayerProvider>().playSong(list.first, list, 'manual', widget.code.title ?? _person?['title']?.toString());
  }

  @override
  Widget build(BuildContext context) {
    final box = BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border));
    if (_loading) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(14),
        decoration: box,
        child: Column(children: [for (var i = 0; i < 4; i++) Padding(padding: const EdgeInsets.only(bottom: 10), child: Skeleton(height: i == 0 ? 48 : 40, radius: 10))]),
      );
    }
    final p = _person;
    if (p == null) return const SizedBox.shrink();
    final path = widget.code.type == 'composer' ? '/nhac-si/${p['slug']}' : '/nghe-si/${p['slug']}';
    final visible = _expanded ? _items : _items.take(_preview).toList();
    final queue = _items.where((s) => s['audioUrl'] != null).toList();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: box,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => context.push(path),
          child: Row(children: [
            UserAvatar(url: p['avatar']?['url']?.toString(), name: '${p['title'] ?? ''}', size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PLAYLIST', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textMuted))),
                Text(widget.code.title ?? '${p['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text))),
                Text('${widget.code.type == 'composer' ? 'Nhạc sĩ' : 'Nghệ sĩ'} ${p['title']} · $_total bài hát', style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (_total > 0)
          FilledButton.icon(
            onPressed: _busy ? null : _playAll,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(_busy ? 'Đang tải…' : 'Phát tất cả', style: body(const TextStyle(fontWeight: FontWeight.w800))),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white, shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        const SizedBox(height: 4),
        for (final s in visible) SongRow(song: s, queue: queue, sourceLabel: widget.code.title ?? p['title']?.toString()),
        if (_total > _preview && !_expanded)
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await _loadAll();
                    if (mounted) setState(() => _expanded = true);
                  },
            child: Text(_busy ? 'Đang tải…' : 'Xem tất cả $_total bài', style: body(TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent))),
          ),
      ]),
    );
  }
}
