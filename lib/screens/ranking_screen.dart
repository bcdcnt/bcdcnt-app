import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';
import '../widgets/shimmer.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  static const _types = [('song', 'Tân nhạc'), ('folk', 'Dân ca'), ('instrumental', 'Khí nhạc'), ('poem', 'Tiếng thơ')];
  static const _periods = [('week', 'Tuần'), ('month', 'Tháng'), ('year', 'Năm'), ('', 'Tất cả')];
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
  String _period = 'week';
  bool _loading = true;
  List<Map<String, dynamic>> _songs = [];

  @override
  void initState() {
    super.initState();
    _fetchListen();
  }

  Future<void> _fetchListen() async {
    setState(() => _loading = true);
    try {
      const q = r'''query($period: String, $type: String!) {
        statisticListen(first: 10, page: 1, period: $period, type: $type) {
          data {
            total
            object {
              ... on Song { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id title slug } } sheet { composers(first: 5) { data { id slug title } } } }
              ... on Folk { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id title slug } } }
              ... on Instrumental { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id title slug } } }
              ... on Poem { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id title slug } } }
            }
          }
        }
      }''';
      final data = await ApiClient.query(q, {'period': _period, 'type': _type});
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
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text('BẢNG XẾP HẠNG', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList(delegate: SliverChildListDelegate([
              // Hero
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(colors: [Color(0xFF711313), Color(0xFFA01818)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: const Color(0xFF711313).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Row(children: [
                  Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.leaderboard_outlined, color: Colors.white, size: 28)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Bảng xếp hạng', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                    const SizedBox(height: 4),
                    Text('Nghe nhiều, nghệ sĩ và thành viên', style: body(const TextStyle(fontSize: 13, color: Colors.white70))),
                  ])),
                ]),
              ),
              const SizedBox(height: 22),

              // Section: Listen
              Row(children: [
                Icon(Icons.trending_up, size: 16, color: AppColors.accentLight),
                const SizedBox(width: 6),
                Text('Nghe nhiều', style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
              ]),
              const SizedBox(height: 12),

              // Period chips
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _periods.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final p = _periods[i];
                    final active = _period == p.$1;
                    return InkWell(
                      onTap: active ? null : () { setState(() => _period = p.$1); _fetchListen(); },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: active ? AppColors.accent : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: active ? AppColors.accent : AppColors.border),
                        ),
                        child: Text(p.$2, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : AppColors.textSecondary))),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Type tabs
              Container(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: _types.map((t) {
                    final active = _type == t.$1;
                    return InkWell(
                      onTap: active ? null : () { setState(() => _type = t.$1); _fetchListen(); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: active ? AppColors.accent : Colors.transparent, width: 2))),
                        child: Text(t.$2, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? AppColors.text : AppColors.textMuted))),
                      ),
                    );
                  }).toList()),
                ),
              ),
              const SizedBox(height: 14),

              // Listen list (top 10) — top 3 podium, rest as SongRow
              if (_loading)
                const Padding(padding: EdgeInsets.only(top: 6), child: SongListSkeleton(rows: 8, showIndex: true))
              else if (_songs.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('Chưa có dữ liệu', style: body(TextStyle(color: AppColors.textMuted)))))
              else ...[
                if (_songs.length >= 3) ...[
                  _RankingPodium(items: _songs.take(3).toList()),
                  const SizedBox(height: 18),
                ],
                ..._songs.asMap().entries.skip(_songs.length >= 3 ? 3 : 0).map((e) {
                  final s = e.value['object'] as Map<String, dynamic>;
                  final periodTotal = e.value['total'] is num ? (e.value['total'] as num).toInt() : 0;
                  final sCopy = Map<String, dynamic>.from(s)..['views'] = periodTotal;
                  return SongRow(song: sCopy, index: e.key, showIndex: true, onTap: () => context.push('/song/${s['id']}', extra: s));
                }),
              ],

              const SizedBox(height: 30),

              // Section: Artists
              Row(children: [
                Icon(Icons.mic, size: 16, color: AppColors.accentLight),
                const SizedBox(width: 6),
                Text('Nghệ sĩ', style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
              ]),
              const SizedBox(height: 12),
              ..._artistTiles.map((t) => _bigTile(slug: t.$1, label: t.$2, icon: t.$3, color: t.$4)),

              const SizedBox(height: 24),

              // Section: Members
              Row(children: [
                Icon(Icons.people_outline, size: 16, color: AppColors.accentLight),
                const SizedBox(width: 6),
                Text('Thành viên', style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
              ]),
              const SizedBox(height: 12),
              ..._memberTiles.map((t) => _bigTile(slug: t.$1, label: t.$2, icon: t.$3, color: t.$4)),

              SizedBox(height: player.currentSong != null ? 90 : 20),
            ])),
          ),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  Widget _bigTile({required String slug, required String label, required IconData icon, required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.push('/bang-xep-hang/$slug'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.3)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: -3, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)))),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
          ]),
        ),
      ),
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
        final extra = ', {column: "id", value: 1, operator: NEQ}';
        final q = '''query(\$page: Int) {
          users(first: 20, page: \$page, orderBy: [{column: "$field", order: DESC}], where: {AND: [{column: "$field", value: 0, operator: GT}$extra]}) {
            data { id username avatar { url } $field }
            paginatorInfo { currentPage lastPage }
          }
        }''';
        final data = await ApiClient.query(q, {'page': page});
        final raw = data['users'];
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
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text(title.toUpperCase(), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
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
                  gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                ),
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: item['avatar'] != null
                      ? CachedNetworkImage(imageUrl: item['avatar'], fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.person, color: Colors.white, size: 22))
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
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight])),
            child: ClipOval(
              child: item['avatar'] != null
                  ? CachedNetworkImage(imageUrl: item['avatar'], fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.person, color: Colors.white, size: 18))
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
class _RankingPodium extends StatelessWidget {
  final List items; // each: { object: songMap, total: num }
  const _RankingPodium({required this.items});

  String _fmt(num n) {
    final s = n.toInt().abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return n < 0 ? '-$buf' : buf.toString();
  }

  Widget _card(BuildContext context, int rank, Map<String, dynamic> entry, {required bool tall}) {
    final song = entry['object'] as Map<String, dynamic>;
    final total = entry['total'] is num ? entry['total'] as num : 0;
    final thumb = song['thumbnail']?['url']?.toString();
    final artists = (song['artists']?['data'] ?? song['artists'] ?? []) as List;
    final artistText = artists.map((a) => a['title'] ?? '').join(', ');

    final rankColors = {
      1: const [Color(0xFFFFD700), Color(0xFFB8860B)], // gold
      2: const [Color(0xFFC0C0C0), Color(0xFF808080)], // silver
      3: const [Color(0xFFCD7F32), Color(0xFF8B4513)], // bronze
    };
    final colors = rankColors[rank] ?? rankColors[1]!;

    final cover = AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: thumb != null
            ? CachedNetworkImage(
                imageUrl: thumb,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(color: AppColors.surfaceLight, child: Icon(Icons.music_note, color: AppColors.textMuted, size: 36)),
              )
            : Container(color: AppColors.surfaceLight, child: Icon(Icons.music_note, color: AppColors.textMuted, size: 36)),
      ),
    );

    return InkWell(
      onTap: () => context.push('/song/${song['id']}', extra: song),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tall ? 0 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                cover,
                Positioned(
                  top: 8, left: 8,
                  child: Container(
                    width: tall ? 36 : 30, height: tall ? 36 : 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3))],
                    ),
                    child: Text('$rank', style: display(TextStyle(fontSize: tall ? 16 : 14, fontWeight: FontWeight.w900, color: Colors.white))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              song['title']?.toString() ?? '',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: display(TextStyle(fontSize: tall ? 15 : 13, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.25)),
            ),
            if (artistText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(artistText, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 11, color: AppColors.textSecondary))),
            ],
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.headphones, size: 11, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(_fmt(total), style: body(TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.length < 3) return const SizedBox.shrink();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // #2
          Expanded(flex: 4, child: Padding(padding: const EdgeInsets.only(right: 6), child: _card(context, 2, items[1] as Map<String, dynamic>, tall: false))),
          // #1
          Expanded(flex: 5, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _card(context, 1, items[0] as Map<String, dynamic>, tall: true))),
          // #3
          Expanded(flex: 4, child: Padding(padding: const EdgeInsets.only(left: 6), child: _card(context, 3, items[2] as Map<String, dynamic>, tall: false))),
        ],
      ),
    );
  }
}
