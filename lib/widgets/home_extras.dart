import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import 'anniversary_rail.dart';
import 'song_row.dart' show SongCover, playOrOpen, songByline;
import 'ui.dart';

// Five more blocks for Trang chủ, phone and desktop alike (canvas
// Main_ThemKhoi / Desktop_TrangChu_ThemKhoi, chốt 25/11): Mọi người đang
// nghe · Tuyển tập · Ngày này năm xưa · Nghe theo nhạc sĩ · Nghe theo chủ
// đề. Each loads on its own and hides itself when it has nothing to show,
// so a slow or failing query never leaves an empty title on the page.

const _songFields = 'id slug title play_type empty_file thumbnail { url } file { audio_url video_url duration } artists(first: 2) { data { id slug title } } sheet { composers(first: 2) { data { id slug title } } }';

List<Map<String, dynamic>> _maps(dynamic list) => ((list ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
bool _playable(Map s) => s['empty_file'] != 1 && (s['file']?['audio_url'] != null || s['file']?['video_url'] != null);
List<Map<String, dynamic>> _songs(dynamic list) => _maps(list).map((s) => {...s, 'file_type': s['file_type'] ?? 'song'}).where(_playable).toList();

/// Title (+ grey line under it) and an optional "Tất cả ›" at the end.
class _Head extends StatelessWidget {
  final bool mobile;
  final String title;
  final String? sub, action;
  final VoidCallback? onAction;
  const _Head({required this.mobile, required this.title, this.sub, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: mobile ? const EdgeInsets.fromLTRB(20, 32, 20, 14) : const EdgeInsets.only(top: 48, bottom: 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text))),
              if (sub != null) ...[
                const SizedBox(height: 3),
                Text(sub!, style: body(TextStyle(fontSize: mobile ? 13 : 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
              ],
            ]),
          ),
          if (action != null)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onAction,
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('$action ›', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
            ),
        ]),
      );
}

/// Desktop: [n] equal columns across the width.
Widget _grid(int n, double gap, List<Widget> children, {double runGap = 18}) => LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - gap * (n - 1)) / n;
      return Wrap(spacing: gap, runSpacing: runGap, children: [for (final x in children) SizedBox(width: w, child: x)]);
    });

/// Round white ▶ (or a spinner while the list loads).
class _PlayDot extends StatelessWidget {
  final double size;
  final bool busy;
  final VoidCallback onTap;
  const _PlayDot({required this.size, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Phát',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 10, offset: const Offset(0, 2))]),
            alignment: Alignment.center,
            child: busy
                ? SizedBox(width: size * .42, height: size * .42, child: const CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF711313)))
                : Icon(Icons.play_arrow_rounded, size: size * .6, color: const Color(0xFF711313)),
          ),
        ),
      );
}

mixin _Starter<T extends StatefulWidget> on State<T> {
  String? starting;

  /// Load a list, then play it; [key] shows the spinner meanwhile.
  Future<void> start(String key, String label, Future<List<Map<String, dynamic>>> Function() load) async {
    if (starting != null) return;
    setState(() => starting = key);
    try {
      final list = await load();
      if (mounted && list.isNotEmpty) playOrOpen(context, list.first, list, label);
    } catch (_) {
    } finally {
      if (mounted) setState(() => starting = null);
    }
  }
}

// ---------------------------------------------------------------- 1

/// Mọi người đang nghe: songs being played right now, with how many people.
class HomeLiveBlock extends StatefulWidget {
  final bool mobile;
  const HomeLiveBlock({super.key, required this.mobile});
  @override
  State<HomeLiveBlock> createState() => _HomeLiveBlockState();
}

class _HomeLiveBlockState extends State<HomeLiveBlock> {
  List<(Map<String, dynamic>, int)> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.query('query HomeNowListening { nowListening(limit: 12) { listeners song { $_songFields } } }');
      final out = <(Map<String, dynamic>, int)>[];
      for (final x in _maps(d['nowListening'])) {
        final s = x['song'];
        if (s is! Map) continue;
        final song = <String, dynamic>{...Map<String, dynamic>.from(s), 'file_type': 'song'};
        if (_playable(song)) out.add((song, (x['listeners'] as num?)?.toInt() ?? 1));
      }
      if (mounted) setState(() => _items = out);
    } catch (_) {}
  }

  Widget _cover(Map<String, dynamic> s, int n, double size) => Stack(children: [
        SongCover(song: s, size: size, radius: 16),
        Positioned(
          left: 8,
          top: 8,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(color: const Color(0xC7161112), borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFFF6B5E), shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('$n người', style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white))),
            ]),
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    if (_items.length < 3) return const SizedBox.shrink();
    final queue = [for (final x in _items) x.$1];
    const label = 'Mọi người đang nghe';
    final head = _Head(mobile: widget.mobile, title: label, sub: 'Cập nhật liên tục, chạm là nghe cùng');
    if (widget.mobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        head,
        Rail(
          height: 226,
          count: _items.length,
          builder: (_, i) => RailCard(
            cover: _cover(_items[i].$1, _items[i].$2, 148),
            title: '${_items[i].$1['title'] ?? ''}',
            subtitle: songByline(_items[i].$1),
            onTap: () => playOrOpen(context, _items[i].$1, queue, label),
          ),
        ),
      ]);
    }
    final shown = _items.take(6).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      _grid(6, 18, [
        for (final (s, n) in shown)
          LayoutBuilder(builder: (context, c) => RailCard(
                width: c.maxWidth,
                cover: _cover(s, n, c.maxWidth),
                title: '${s['title'] ?? ''}',
                subtitle: songByline(s),
                onTap: () => playOrOpen(context, s, queue, label),
              )),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------- 2

/// Tuyển tập: the site's own themed playlists, a different few each day.
/// Cover = the first four songs' pictures, as playlists show elsewhere.
class HomeCollectionsBlock extends StatefulWidget {
  final bool mobile;
  const HomeCollectionsBlock({super.key, required this.mobile});
  @override
  State<HomeCollectionsBlock> createState() => _HomeCollectionsBlockState();
}

class _HomeCollectionsBlockState extends State<HomeCollectionsBlock> with _Starter {
  List<Map<String, dynamic>> _lists = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.query(r'''query HomeCollections($w: WhereConditions) { playlists(first: 40, orderBy: [{column: "views", order: DESC}], where: $w) { data { id title thumbnail { url } items(first: 1) { paginatorInfo { total } } songs(first: 4) { data { id title thumbnail { url } } } } } }''', {
        'w': {'AND': [
          {'column': 'is_system', 'value': '1'},
          {'column': 'is_public', 'value': '1'},
        ]},
      });
      int total(Map p) => ((p['items']?['paginatorInfo']?['total'] as num?) ?? 0).toInt();
      final all = _maps(d['playlists']?['data']).where((p) => total(p) >= 5).toList();
      if (all.isEmpty) return;
      // A different window of the best-loved each day, so the row moves.
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day).difference(DateTime(2026)).inDays;
      final start = (day * 3) % all.length;
      final pick = [for (var i = 0; i < all.length && i < 8; i++) all[(start + i) % all.length]];
      if (mounted) setState(() => _lists = pick);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _songsOf(Map p) async {
    final d = await ApiClient.query('query(\$id: ID!) { playlist(id: \$id) { songs(first: 100) { data { $_songFields } } } }', {'id': '${p['id']}'});
    return _songs(d['playlist']?['songs']?['data']);
  }

  Widget _mosaic(Map p, double size) {
    final pics = [for (final s in _maps(p['songs']?['data'])) s['thumbnail']?['url']?.toString()].whereType<String>().where((u) => u.isNotEmpty).toList();
    final own = p['thumbnail']?['url']?.toString();
    if (pics.length < 4) {
      // Too few pictures for a grid: the playlist's own picture, or the first song's.
      final one = (own != null && own.isNotEmpty) ? own : (pics.isNotEmpty ? pics.first : null);
      return NetImage(url: one, width: size, height: size, fallback: Container(width: size, height: size, color: AppColors.accentSoft, child: Icon(Icons.queue_music_rounded, size: size * .4, color: AppColors.accentLight)));
    }
    final half = (size - 2) / 2;
    Widget tile(int i) => NetImage(url: pics[i], width: half, height: half);
    return Container(
      width: size,
      height: size,
      color: AppColors.bg,
      child: Column(children: [
        Row(children: [tile(0), const SizedBox(width: 2), tile(1)]),
        const SizedBox(height: 2),
        Row(children: [tile(2), const SizedBox(width: 2), tile(3)]),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> p, double size) {
    final n = ((p['items']?['paginatorInfo']?['total'] as num?) ?? 0).toInt();
    final title = '${p['title'] ?? ''}';
    return RailCard(
      width: size,
      cover: Stack(children: [
        _mosaic(p, size),
        Positioned(right: 10, bottom: 10, child: _PlayDot(size: widget.mobile ? 40 : 48, busy: starting == 'pl${p['id']}', onTap: () => start('pl${p['id']}', title, () => _songsOf(p)))),
      ]),
      title: title,
      subtitle: '$n bài',
      onTap: () => context.push('/playlist/${p['id']}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_lists.isEmpty) return const SizedBox.shrink();
    final head = _Head(mobile: widget.mobile, title: 'Tuyển tập', sub: 'Nghe liền mạch theo từng chủ đề', action: 'Xem tất cả', onAction: () => context.push('/playlist'));
    if (widget.mobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        head,
        Rail(height: 246, count: _lists.length, builder: (_, i) => _card(_lists[i], 168)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      _grid(5, 20, [for (final p in _lists.take(5)) LayoutBuilder(builder: (context, c) => _card(p, c.maxWidth))]),
    ]);
  }
}

// ---------------------------------------------------------------- 3

/// Ngày này năm xưa: birthdays and death days of composers and singers in
/// the coming week, "Kỷ niệm N năm ngày sinh/mất"; today's in red.
class HomeAnnivBlock extends StatefulWidget {
  final bool mobile;
  const HomeAnnivBlock({super.key, required this.mobile});
  @override
  State<HomeAnnivBlock> createState() => _HomeAnnivBlockState();
}

class _HomeAnnivBlockState extends State<HomeAnnivBlock> with _Starter {
  List<Anniv> _items = [];

  @override
  void initState() {
    super.initState();
    loadAnniversaries(window: 7).then((a) {
      if (!mounted) return;
      // By date, as promised by the title; the loader puts round years first.
      final list = [...a]..sort((x, y) => x.inDays.compareTo(y.inDays));
      setState(() => _items = list.take(widget.mobile ? 3 : 4).toList());
    });
  }

  String _date(Anniv a) {
    final p = a.person;
    final y = '${p[a.birth ? 'yob' : 'yod'] ?? ''}'.trim();
    return '${a.birth ? 'Sinh' : 'Mất'} ${a.date.day}/${a.date.month}${y.isNotEmpty && y != '0' ? '/$y' : ''}';
  }

  String _years(Anniv a) => a.years > 0 ? 'Kỷ niệm ${a.years} năm ngày ${a.birth ? 'sinh' : 'mất'}' : (a.birth ? 'Ngày sinh' : 'Ngày mất');

  Widget _row(Anniv a) {
    final key = 'an${a.route}${a.person['id']}${a.birth}';
    final today = a.inDays == 0;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('${a.route}${a.person['slug']}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            NetImage(url: a.person['avatar']?['url']?.toString(), width: widget.mobile ? 56 : 60, height: widget.mobile ? 56 : 60, circle: true, tint: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a.person['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)), children: [
                    TextSpan(text: '${_date(a)} · '),
                    TextSpan(text: _years(a), style: TextStyle(fontWeight: FontWeight.w800, color: today ? AppColors.accentFg : AppColors.textMuted)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(19),
              child: InkWell(
                borderRadius: BorderRadius.circular(19),
                onTap: () => start(key, '${a.person['title'] ?? ''}', () => annivSongs(a)),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  child: starting == key
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                          const SizedBox(width: 2),
                          Text('Nghe', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white))),
                        ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Head(mobile: widget.mobile, title: 'Ngày này năm xưa', sub: 'Sinh nhật, ngày mất của nhạc sĩ, nghệ sĩ'),
      Padding(
        padding: widget.mobile ? const EdgeInsets.symmetric(horizontal: 20) : EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, a) in _items.indexed) ...[if (i > 0) const SizedBox(height: 10), _row(a)],
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- 4

/// Nghe theo nhạc sĩ: composers people listened to most in 30 days.
class HomeComposersBlock extends StatefulWidget {
  final bool mobile;
  const HomeComposersBlock({super.key, required this.mobile});
  @override
  State<HomeComposersBlock> createState() => _HomeComposersBlockState();
}

class _HomeComposersBlockState extends State<HomeComposersBlock> {
  List<Map<String, dynamic>> _people = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.query('query HomeTopComposers { topComposers(days: 30, limit: 12) { id slug title avatar { url } songs(first: 1) { paginatorInfo { total } } } }');
      final list = _maps(d['topComposers']).where((p) => (p['avatar']?['url']?.toString() ?? '').isNotEmpty).toList();
      if (mounted) setState(() => _people = list);
    } catch (_) {}
  }

  Widget _person(Map p, double size) {
    final n = ((p['songs']?['paginatorInfo']?['total'] as num?) ?? 0).toInt();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      PersonBubble(name: '${p['title'] ?? ''}', image: p['avatar']?['url']?.toString(), size: size, onTap: () => context.push('/nhac-si/${p['slug']}')),
      if (n > 0) Text('$n bài', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_people.length < 3) return const SizedBox.shrink();
    final head = _Head(mobile: widget.mobile, title: 'Nghe theo nhạc sĩ', sub: 'Được nghe nhiều trong 30 ngày qua', action: 'Tất cả', onAction: () => context.push('/nhac-si'));
    if (widget.mobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        head,
        Rail(height: 176, textHeight: 76, gap: 14, count: _people.length, builder: (_, i) => _person(_people[i], 92)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      _grid(3, 14, [for (final p in _people.take(6)) Center(child: _person(p, 96))]),
    ]);
  }
}

// ---------------------------------------------------------------- 5

/// Nghe theo chủ đề: the most listened tags as coloured tiles; ▶ plays the
/// tag's songs, the tile opens its page.
class HomeTopicsBlock extends StatefulWidget {
  final bool mobile;
  const HomeTopicsBlock({super.key, required this.mobile});
  @override
  State<HomeTopicsBlock> createState() => _HomeTopicsBlockState();
}

const _topicColors = [Color(0xFF5B3A1E), Color(0xFF2F4A2B), Color(0xFF7A1F1F), Color(0xFF2B3F5C), Color(0xFF6B3B55), Color(0xFF1F5560)];

class _HomeTopicsBlockState extends State<HomeTopicsBlock> with _Starter {
  List<Map<String, dynamic>> _tags = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.query('query HomeTopics { tags(first: 30, orderBy: [{column: "listens", order: DESC}]) { data { id name slug } } }');
      // Periods ("Kháng chiến chống Pháp (1945 - 1954)") already have Theo
      // năm tháng; long names don't fit a tile.
      final list = _maps(d['tags']?['data']).where((t) {
        final n = '${t['name'] ?? ''}';
        return n.isNotEmpty && n.length <= 22 && !RegExp(r'\d').hasMatch(n);
      }).take(6).toList();
      if (mounted) setState(() => _tags = list);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _songsOf(Map t) async {
    final d = await ApiClient.query('query(\$tag: String!) { songsByTag(first: 50, page: 1, tag: \$tag, orderBy: [{column: "views", order: DESC}]) { data { $_songFields } } }', {'tag': '${t['name']}'});
    return _songs(d['songsByTag']?['data']);
  }

  Widget _tile(int i, Map t) {
    final name = '${t['name'] ?? ''}';
    final key = 'tag${t['id']}';
    return Material(
      color: _topicColors[i % _topicColors.length],
      borderRadius: BorderRadius.circular(widget.mobile ? 16 : 18),
      child: InkWell(
        borderRadius: BorderRadius.circular(widget.mobile ? 16 : 18),
        onTap: () => context.push('/tag/${t['slug']}'),
        child: Container(
          height: widget.mobile ? 64 : 84,
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Row(children: [
            Expanded(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: widget.mobile ? 16 : 17, height: 1.2, fontWeight: FontWeight.w800, color: Colors.white)))),
            Semantics(
              button: true,
              label: 'Phát $name',
              child: GestureDetector(
                onTap: () => start(key, name, () => _songsOf(t)),
                child: Container(
                  width: widget.mobile ? 34 : 38,
                  height: widget.mobile ? 34 : 38,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: starting == key
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_tags.length < 2) return const SizedBox.shrink();
    final head = _Head(mobile: widget.mobile, title: 'Nghe theo chủ đề', action: 'Tất cả', onAction: () => context.push('/tag'));
    final tiles = [for (final (i, t) in _tags.indexed) _tile(i, t)];
    if (widget.mobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _grid(2, 10, tiles, runGap: 10)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, _grid(6, 14, tiles)]);
  }
}
