import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';
import '../widgets/mini_player.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  static const _types = [('song', 'Tân nhạc'), ('folk', 'Dân ca'), ('instrumental', 'Khí nhạc'), ('poem', 'Tiếng thơ')];
  static const _periods = [('week', 'Tuần'), ('month', 'Tháng'), ('year', 'Năm'), ('', 'Mọi lúc')];
  static const _fileTypes = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem'};

  static const _artistTiles = [
    ('nghe-si', 'Nghệ sĩ nghe nhiều', Icons.mic, Color(0xFF711313)),
    ('nhac-si', 'Nhạc sĩ nghe nhiều', Icons.music_note, Color(0xFF8B6914)),
    ('nha-tho', 'Nhà thơ nghe nhiều', Icons.auto_stories_outlined, Color(0xFF6B5210)),
    ('soan-gia', 'Soạn giả nghe nhiều', Icons.edit_outlined, Color(0xFF4A0D0D)),
  ];
  static const _memberTiles = [
    ('cong-hien', 'Top cống hiến', Icons.workspace_premium_outlined, Color(0xFF7A3B3A)),
    ('dong-gop', 'Top đóng góp bản thu', Icons.upload_outlined, Color(0xFF2D5E3A)),
    ('binh-luan', 'Top bình luận', Icons.chat_bubble_outline, Color(0xFF2D5E3A)),
    ('binh-luan-yeu-thich', 'Top bình luận yêu thích', Icons.favorite_outline, Color(0xFF6B5210)),
    ('nghe-nhieu', 'Top nghe nhiều', Icons.headphones_outlined, Color(0xFF4A0D0D)),
  ];

  String _type = 'song';
  String _period = 'month';
  bool _loading = true;
  List<Map<String, dynamic>> _songs = [];
  // Older API builds don't know `prev_rank`; then no ▲/▼/MỚI at all.
  bool _hasTrend = false;

  @override
  void initState() {
    super.initState();
    _fetchListen();
  }

  bool _failed = false;

  Future<void> _fetchListen() async {
    setState(() { _loading = true; _failed = false; });
    try {
      const q = r'''query($period: String, $type: String!) {
        statisticListen(first: 10, page: 1, period: $period, type: $type) {
          data {
            total
            prev_rank
            object {
              ... on Song { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id title slug avatar { url } } } sheet { composers(first: 5) { data { id slug title } } } }
              ... on Folk { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id title slug avatar { url } } } }
              ... on Instrumental { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id title slug avatar { url } } } }
              ... on Poem { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id title slug avatar { url } } } }
            }
          }
        }
      }''';
      Map<String, dynamic> data;
      var hasTrend = true;
      try {
        data = await ApiClient.query(q, {'period': _period, 'type': _type});
      } catch (_) {
        // API not yet updated with prev_rank → same query without it.
        hasTrend = false;
        data = await ApiClient.query(q.replaceFirst('prev_rank', ''), {'period': _period, 'type': _type});
      }
      _hasTrend = hasTrend;
      final list = ((data['statisticListen']?['data'] ?? []) as List)
          .where((d) => d['object'] != null)
          .map((d) {
        final m = Map<String, dynamic>.from(d as Map);
        m['object'] = Map<String, dynamic>.from(m['object'] as Map);
        m['object']['file_type'] = _fileTypes[m['object']['__typename']] ?? _type;
        return m;
      }).toList();
      if (!mounted) return;
      setState(() { _songs = list; _loading = false; });
    } catch (_) { if (mounted) setState(() { _loading = false; _failed = true; }); }
  }

  @override
  Widget build(BuildContext context) {
    final queue = asSongList(_songs.map((x) => {...Map<String, dynamic>.from(x['object'] as Map), 'views': x['total']}));
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const SubPageBar(title: 'Bảng xếp hạng'),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            const SizedBox(height: 6),
            Segmented(
              labels: [for (final p in _periods) p.$2],
              selected: _periods.indexWhere((p) => p.$1 == _period),
              onSelect: (i) {
                setState(() => _period = _periods[i].$1);
                _fetchListen();
              },
            ),
            const SizedBox(height: 14),
            ChipStrip(
              labels: [for (final t in _types) t.$2],
              selected: _types.indexWhere((t) => t.$1 == _type),
              onSelect: (i) {
                setState(() => _type = _types[i].$1);
                _fetchListen();
              },
            ),
            const SizedBox(height: 18),
            if (_loading)
              for (var i = 0; i < 8; i++) const SkeletonSongRow()
            else if (_failed && _songs.isEmpty)
              OfflineBlock(onRetry: _fetchListen)
            else if (_songs.isEmpty)
              const EmptyBlock(icon: Icons.leaderboard_outlined, title: 'Chưa có dữ liệu', message: 'Chưa có lượt nghe trong khoảng thời gian này.')
            else ...[
              if (_songs.length >= 3) ...[
                Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _RankingPodium(items: _songs.take(3).toList(), queue: queue)),
                const SizedBox(height: 14),
              ],
              for (var i = _songs.length >= 3 ? 3 : 0; i < _songs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 6),
                  child: SongRow(
                    song: queue[i],
                    index: i,
                    showIndex: true,
                    queue: queue,
                    sourceLabel: 'Bảng xếp hạng',
                    prevRank: (_songs[i]['prev_rank'] as num?)?.toInt(),
                    chartNew: _period.isNotEmpty && _hasTrend && _songs[i]['prev_rank'] == null,
                  ),
                ),
            ],
            const GroupLabel('Nghệ sĩ'),
            for (final t in _artistTiles) ListItem(icon: t.$3, title: t.$2, onTap: () => context.push('/bang-xep-hang/${t.$1}')),
            const GroupLabel('Thành viên'),
            for (final t in _memberTiles) ListItem(icon: t.$3, title: t.$2, onTap: () => context.push('/bang-xep-hang/${t.$1}')),
          ],
        ),
        const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}

class RankingDetailScreen extends StatefulWidget {
  final String slug;
  const RankingDetailScreen({super.key, required this.slug});

  @override
  State<RankingDetailScreen> createState() => _RankingDetailScreenState();
}

class _RankingDetailScreenState extends State<RankingDetailScreen> {
  static const _configs = {
    'nghe-si': ('Nghệ sĩ nghe nhiều', 'people', 'artist'),
    'nhac-si': ('Nhạc sĩ nghe nhiều', 'people', 'composer'),
    'nha-tho': ('Nhà thơ nghe nhiều', 'people', 'poet'),
    'soan-gia': ('Soạn giả nghe nhiều', 'people', 'recomposer'),
    'cong-hien': ('Top cống hiến', 'users', 'point'),
    'nghe-nhieu': ('Top nghe nhiều', 'users', 'listen'),
    'dong-gop': ('Top đóng góp bản thu', 'custom', 'topUpload'),
    'binh-luan': ('Top bình luận', 'custom', 'topComment'),
    'binh-luan-yeu-thich': ('Top bình luận yêu thích', 'custom', 'topCommentLove'),
  };

  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _page = 1, _lastPage = 1;
  bool _loading = true, _loadingMore = false;

  @override
  void initState() { super.initState(); _scrollCtl.addListener(_onScroll); _fetch(1); }
  @override
  void dispose() { _scrollCtl.removeListener(_onScroll); _scrollCtl.dispose(); super.dispose(); }
  void _onScroll() {
    if (_loadingMore || _loading || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(_page + 1);
  }

  Future<void> _fetch(int page) async {
    setState(() { if (page == 1) _loading = true; else _loadingMore = true; });
    try {
      final cfg = _configs[widget.slug];
      if (cfg == null) { if (mounted) setState(() => _loading = false); return; }
      final type = cfg.$2;
      List<Map<String, dynamic>> list = [];
      Map pi = {};
      if (type == 'people') {
        final pt = cfg.$3;
        final whereExtra = pt == 'artist' ? ', {column: "is_group", value: 0}' : '';
        final q = '''query(\$page: Int) {
          ${pt}s(first: 20, page: \$page, orderBy: [{column: "total_listens", order: DESC}], where: {AND: [{column: "total_listens", value: 0, operator: GT}$whereExtra]}) {
            data { id title slug total_listens avatar { url } }
            paginatorInfo { currentPage lastPage }
          }
        }''';
        final data = await ApiClient.query(q, {'page': page});
        final raw = data['${pt}s'];
        list = ((raw?['data'] ?? []) as List).map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return {
            'id': m['id'], 'name': m['title'], 'slug': m['slug'],
            'avatar': m['avatar']?['url'], 'value': m['total_listens'] ?? 0,
            '_route': '/${{
              'artist': 'nghe-si', 'composer': 'nhac-si', 'poet': 'nha-tho', 'recomposer': 'soan-gia',
            }[pt]}/${m['slug']}',
            '_valueLabel': 'lượt nghe',
          };
        }).toList();
        pi = raw?['paginatorInfo'] ?? {};
      } else if (type == 'users') {
        final field = cfg.$3;
        // Public leaderboard query (API 2026-11); `users` is admin-only
        // since the PII lockdown, which left these lists empty.
        final q = '''query(\$page: Int, \$field: String!) {
          topMember(field: \$field, first: 20, page: \$page) {
            data { id username avatar { url } $field }
            paginatorInfo { currentPage lastPage }
          }
        }''';
        final data = await ApiClient.query(q, {'page': page, 'field': field});
        final raw = data['topMember'];
        list = ((raw?['data'] ?? []) as List).map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return {
            'id': m['id'], 'name': m['username'],
            'avatar': m['avatar']?['url'], 'value': m[field] ?? 0,
            '_route': '/user/${m['id']}',
            '_valueLabel': field == 'listen' ? 'lượt nghe' : 'điểm',
          };
        }).toList();
        pi = raw?['paginatorInfo'] ?? {};
      } else { // custom
        final qn = cfg.$3;
        final q = '''query(\$page: Int) {
          $qn(first: 20, page: \$page) {
            data { username avatar user_id total }
            paginatorInfo { currentPage lastPage }
          }
        }''';
        final data = await ApiClient.query(q, {'page': page});
        final raw = data[qn];
        final valueLabel = qn == 'topUpload' ? 'bản thu' : (qn == 'topComment' ? 'bình luận' : 'lượt thích');
        list = ((raw?['data'] ?? []) as List).map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return {
            'id': m['user_id'], 'name': m['username'],
            'avatar': m['avatar'], 'value': m['total'] ?? 0,
            '_route': '/user/${m['user_id']}',
            '_valueLabel': valueLabel,
          };
        }).toList();
        pi = raw?['paginatorInfo'] ?? {};
      }
      if (!mounted) return;
      setState(() {
        if (page == 1) _items = list; else _items.addAll(list);
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _loading = false; _loadingMore = false;
      });
    } catch (_) { if (mounted) setState(() { _loading = false; _loadingMore = false; }); }
  }

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 == 0) buf.write('.'); buf.write(s[i]); }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final cfg = _configs[widget.slug];
    final title = cfg?.$1 ?? 'Bảng xếp hạng';
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(controller: _scrollCtl, slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg,
            title: Text(title),
            centerTitle: true,
            leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          ),
          if (_loading && _items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else if (_items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Chưa có dữ liệu', style: AppText.bodyText)))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (ctx, i) => _row(i, _items[i]),
                childCount: _items.length,
              )),
            ),
          SliverToBoxAdapter(child: Column(children: [
            if (_loadingMore) Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
            SizedBox(height: player.currentSong != null ? 90 : 20),
          ])),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  // Map metric label → icon so trailing icon matches what's being measured
  // (instead of always showing headphones).
  IconData _metricIcon(String label) {
    switch (label) {
      case 'điểm': return Icons.workspace_premium_outlined;
      case 'bản thu': return Icons.upload_outlined;
      case 'bình luận': return Icons.chat_bubble_outline;
      case 'lượt thích': return Icons.favorite_outline;
      case 'lượt nghe':
      default: return Icons.headphones;
    }
  }

  // Top-3: gold/silver/bronze accent + brighter rank colour
  static const _medalColors = {1: Color(0xFFFFD700), 2: Color(0xFFC0C0C0), 3: Color(0xFFCD7F32)};

  Widget _row(int i, Map<String, dynamic> item) {
    final rank = i + 1;
    final isTop3 = rank <= 3;
    final value = item['value'] is num ? (item['value'] as num).toInt() : 0;
    final valueLabel = item['_valueLabel']?.toString() ?? '';
    final medal = _medalColors[rank];

    if (isTop3) {
      // Distinct podium-style row: tinted background, larger avatar with
      // medal ring, bigger rank + name. Mirrors the home BXH podium feel
      // so top-3 trồi lên hẳn so với rest of the list.
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () => context.push(item['_route'] as String),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [medal!.withValues(alpha: 0.14), medal.withValues(alpha: 0.04)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: medal.withValues(alpha: 0.35), width: 1),
            ),
            child: Row(children: [
              SizedBox(
                width: 34,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: display(TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: medal,
                    letterSpacing: -1,
                    height: 1,
                  )),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: medal, width: 2),
                  gradient: LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)]),
                ),
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: item['avatar'] != null
                      ? CachedNetworkImage(imageUrl: cdnImg((item['avatar']).toString(), 160), fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.person, color: Colors.white, size: 22))
                      : const Icon(Icons.person, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.2))),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(_metricIcon(valueLabel), size: 12, color: medal),
                      const SizedBox(width: 4),
                      Text('${_formatInt(value)} $valueLabel', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: medal))),
                    ]),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => context.push(item['_route'] as String),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderSubtle, width: 1)),
        ),
        child: Row(children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: -0.5)),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)])),
            child: ClipOval(
              child: item['avatar'] != null
                  ? CachedNetworkImage(imageUrl: cdnImg((item['avatar']).toString(), 160), fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.person, color: Colors.white, size: 18))
                  : const Icon(Icons.person, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(item['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)))),
          const SizedBox(width: 8),
          Icon(_metricIcon(valueLabel), size: 11, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text('${_formatInt(value)} $valueLabel', style: AppText.caption),
        ]),
      ),
    );
  }
}

/// Top-3 podium row for ranking screens — Apple Music Top-100 vibe.
/// #1 sits in the centre and is taller, #2 / #3 flank it. Each card shows
/// rank chip, artwork, title, artist, period total, and tappable navigation
/// to the song detail.
/// Top 3 as equal-size covers with big rank numbers (#2 · #1 · #3).
class _RankingPodium extends StatelessWidget {
  final List items; // each: { object: songMap, total: num }
  final List<Map<String, dynamic>> queue;
  const _RankingPodium({required this.items, required this.queue});

  Widget _card(BuildContext context, int rank) {
    final song = queue[rank - 1];
    return GestureDetector(
      onTap: () => playOrOpen(context, song, queue, 'Bảng xếp hạng'),
      onLongPress: () => showSongActions(context, song),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(aspectRatio: 1, child: LayoutBuilder(builder: (_, c) {
            // No song artwork: the singer's photo reads far better on the
            // podium than a letter placeholder.
            final face = ((song['artists']?['data'] as List?) ?? const []).whereType<Map>().map((a) => a['avatar']?['url']?.toString()).firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null);
            if (song['thumbnail']?['url'] == null && face != null) {
              return NetImage(url: face, width: c.maxWidth, height: c.maxWidth, radius: 18);
            }
            return SongCover(song: song, size: c.maxWidth, radius: 18);
          })),
          const SizedBox(height: 6),
          Text('$rank', style: display(TextStyle(fontSize: rank == 1 ? 48 : 32, height: 1, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
          const SizedBox(height: 4),
          Text(song['title']?.toString() ?? '', maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w700, color: AppColors.text))),
          const SizedBox(height: 2),
          Text(songByline(song).isEmpty ? ' ' : songByline(song), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.length < 3) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(flex: 10, child: Padding(padding: const EdgeInsets.only(top: 36), child: _card(context, 2))),
        const SizedBox(width: 10),
        Expanded(flex: 12, child: _card(context, 1)),
        const SizedBox(width: 10),
        Expanded(flex: 10, child: Padding(padding: const EdgeInsets.only(top: 36), child: _card(context, 3))),
      ],
    );
  }
}
