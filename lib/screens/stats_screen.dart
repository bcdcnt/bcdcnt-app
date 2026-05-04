import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static const _categories = [
    ('listen_song', 'Tân nhạc', Color(0xFF711313)),
    ('listen_folk', 'Dân ca', Color(0xFFC9A96E)),
    ('listen_instrumental', 'Khí nhạc', Color(0xFFB48988)),
    ('listen_poem', 'Tiếng thơ', Color(0xFFD4A84B)),
    ('listen_karaoke', 'Thành viên hát', Color(0xFF6ECF8E)),
    ('listen_playlist', 'Playlist', Color(0xFF7B8EC9)),
  ];

  Map<String, dynamic> _data = {};
  bool _loading = true;
  // Real top-by-play-count from the listen_events log (server resolver
  // userTopListens). RecentListen table is per-song dedup so aggregating
  // it client-side gives recency, not play count. Streak still derives
  // from RecentListen because we don't need play count for that.
  List<_TopRow> _topSongs = [];
  List<_TopRow> _topArtists = [];
  List<_TopRow> _topComposers = [];
  int _streakDays = 0;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _fetch()); }

  Future<void> _fetch() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?['id'];
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      // 5 queries in 1 round-trip via aliases — user profile + recent
      // listens (for streak only) + 3 top-listens (song/artist/composer).
      final data = await ApiClient.query(r'''query($id: ID!) {
        user(id: $id) {
          point views listen listen_song listen_folk listen_instrumental listen_karaoke listen_poem listen_playlist
          comments(first: 1, where: {AND: [{column: "status", value: 1}]}) { paginatorInfo { total } }
          uploads(first: 1, where: {AND: [{column: "status", value: "approved"}]}) { paginatorInfo { total } }
          recentListens(first: 200, page: 1, orderBy: [{column: "id", order: DESC}]) {
            data { id created_at }
          }
        }
        topSongs: userTopListens(user_id: $id, type: "song", limit: 10) { id title slug image count object_type }
        topArtists: userTopListens(user_id: $id, type: "artist", limit: 10) { id title slug image count }
        topComposers: userTopListens(user_id: $id, type: "composer", limit: 10) { id title slug image count }
      }''', {'id': '$uid'});
      if (!mounted) return;
      final user = Map<String, dynamic>.from(data['user'] ?? {});
      final recents = ((user['recentListens']?['data'] ?? []) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      List<_TopRow> parse(dynamic raw, {bool isPerson = false, String? defaultRoutePrefix}) {
        return ((raw ?? const []) as List).map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return _TopRow(
            id: m['id']?.toString() ?? '',
            title: m['title']?.toString() ?? '',
            slug: m['slug']?.toString(),
            image: m['image']?.toString(),
            count: (m['count'] is num) ? (m['count'] as num).toInt() : 0,
            objectType: m['object_type']?.toString(),
            isPerson: isPerson,
            personRoutePrefix: defaultRoutePrefix,
          );
        }).toList();
      }
      setState(() {
        _data = user;
        _topSongs = parse(data['topSongs']);
        _topArtists = parse(data['topArtists'], isPerson: true, defaultRoutePrefix: '/nghe-si/');
        _topComposers = parse(data['topComposers'], isPerson: true, defaultRoutePrefix: '/nhac-si/');
        _streakDays = _calcStreak(recents);
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  // Consecutive listening days starting today (or yesterday if no plays
  // today). Walks unique listen days backwards; first gap > 1 day stops.
  int _calcStreak(List<Map<String, dynamic>> recents) {
    if (recents.isEmpty) return 0;
    final days = <DateTime>{};
    for (final r in recents) {
      final ts = r['created_at']?.toString();
      final dt = DateTime.tryParse(ts ?? '')?.toLocal();
      if (dt == null) continue;
      days.add(DateTime(dt.year, dt.month, dt.day));
    }
    if (days.isEmpty) return 0;
    final sorted = days.toList()..sort((a, b) => b.compareTo(a));
    final today = DateTime.now();
    final todayD = DateTime(today.year, today.month, today.day);
    // Allow streak to start at today OR yesterday (user may not have
    // listened yet today).
    var cursor = sorted.first;
    if (cursor != todayD && cursor != todayD.subtract(const Duration(days: 1))) {
      return 0;
    }
    var streak = 1;
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i] == cursor.subtract(const Duration(days: 1))) {
        streak++;
        cursor = sorted[i];
      } else if (sorted[i] == cursor) {
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  String _typenameToFileType(String tn) {
    switch (tn) {
      case 'Folk': return 'folk';
      case 'Instrumental': return 'instrumental';
      case 'Poem': return 'poem';
      case 'Karaoke': return 'karaoke';
      default: return 'song';
    }
  }


  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 == 0) buf.write('.'); buf.write(s[i]); }
    return buf.toString();
  }

  int _intOf(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final commentsTotal = _intOf(_data['comments']?['paginatorInfo']?['total']);
    final uploadsTotal = _intOf(_data['uploads']?['paginatorInfo']?['total']);
    final totalListen = _intOf(_data['listen']);
    final maxListen = _categories.map((c) => _intOf(_data[c.$1])).fold(1, (a, b) => a > b ? a : b);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text('THỐNG KÊ', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          if (_loading)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList(delegate: SliverChildListDelegate([
                // Stat cards grid + streak as the 5th tile (full-width).
                // Each card gets its own soft-tint gradient + colored icon
                // chip so the strip feels like a hero banner, not 4
                // identical surface squares (Apple Music / Wrapped vibe).
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 3.0,
                  children: [
                    _statCard('Lượt xem', _intOf(_data['views']), Icons.visibility_outlined, const Color(0xFF2C5F8D)),
                    _statCard('Bình luận', commentsTotal, Icons.chat_bubble_outline, const Color(0xFF2F7D5C)),
                    _statCard('Điểm', _intOf(_data['point']), Icons.star_outline, const Color(0xFFB8860B)),
                    _statCard('Đóng góp', uploadsTotal, Icons.upload_outlined, const Color(0xFF7A3B3A)),
                  ],
                ),
                if (_streakDays > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      const Icon(Icons.local_fire_department, size: 28, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('$_streakDays ngày liên tục', style: display(const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white))),
                          Text('Tiếp tục nghe để giữ chuỗi', style: body(const TextStyle(fontSize: 12, color: Colors.white70))),
                        ]),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.headphones, size: 16, color: AppColors.accentLight),
                      const SizedBox(width: 6),
                      Text('Tổng nghe', style: display(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text))),
                      const Spacer(),
                      Text(_formatInt(totalListen), style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
                    ]),
                    const SizedBox(height: 14),
                    ..._categories.map((c) {
                      final v = _intOf(_data[c.$1]);
                      final pct = maxListen > 0 ? v / maxListen : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(c.$2, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                            Text(_formatInt(v), style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text))),
                          ]),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct.clamp(0.0, 1.0),
                              minHeight: 6,
                              backgroundColor: AppColors.surfaceLight,
                              valueColor: AlwaysStoppedAnimation(c.$3),
                            ),
                          ),
                        ]),
                      );
                    }),
                  ]),
                ),

                // Top sections — fixed to all-time. Period tabs were
                // dropped per feedback (not adding enough value to justify
                // the extra UI noise).
                if (_topSongs.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _sectionTitle('Bài hát nghe nhiều nhất', Icons.music_note),
                  const SizedBox(height: 8),
                  _topSongList(_topSongs),
                ],
                if (_topArtists.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _sectionTitle('Nghệ sĩ nghe nhiều nhất', Icons.mic),
                  const SizedBox(height: 8),
                  _topPersonRow(_topArtists),
                ],
                if (_topComposers.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _sectionTitle('Nhạc sĩ nghe nhiều nhất', Icons.piano),
                  const SizedBox(height: 8),
                  _topPersonRow(_topComposers),
                ],

                SizedBox(height: player.currentSong != null ? 90 : 20),
              ])),
            ),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  Widget _statCard(String label, int value, IconData icon, Color tint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [tint.withValues(alpha: 0.22), tint.withValues(alpha: 0.06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.18), blurRadius: 14, spreadRadius: -4, offset: const Offset(0, 4))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Icon chip — tinted square with the stat's color so each card
        // stands apart at a glance.
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.3))),
            const SizedBox(height: 2),
            Text(_formatInt(value), style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.3))),
          ]),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String label, IconData icon) {
    return Row(children: [
      Icon(icon, size: 16, color: AppColors.accentLight),
      const SizedBox(width: 8),
      Text(label, style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
    ]);
  }

  Widget _topSongList(List<_TopRow> rows) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(children: rows.asMap().entries.map((e) {
        final i = e.key; final r = e.value;
        return InkWell(
          onTap: () => context.push('/song/${r.id}', extra: {'id': r.id, 'title': r.title, 'file_type': _typenameToFileType(r.objectType ?? 'Song')}),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              SizedBox(width: 22, child: Text('${i + 1}', textAlign: TextAlign.center, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i < 3 ? AppColors.accentLight : AppColors.textMuted)))),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: r.image != null
                    ? CachedNetworkImage(imageUrl: r.image!, width: 40, height: 40, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(width: 40, height: 40, color: AppColors.surfaceLight))
                    : Container(width: 40, height: 40, color: AppColors.surfaceLight, child: Icon(Icons.music_note, size: 18, color: AppColors.textMuted)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)))),
              const SizedBox(width: 8),
              Text('${r.count} lượt', style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
            ]),
          ),
        );
      }).toList()),
    );
  }

  Widget _topPersonRow(List<_TopRow> rows) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final r = rows[i];
          return InkWell(
            onTap: () {
              if (r.slug != null && r.personRoutePrefix != null) {
                context.push('${r.personRoutePrefix}${r.slug}');
              }
            },
            child: SizedBox(
              width: 88,
              child: Column(children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                  ),
                  child: ClipOval(
                    child: r.image != null
                        ? CachedNetworkImage(imageUrl: r.image!, fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.person, color: Colors.white70))
                        : const Icon(Icons.person, color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 6),
                Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text))),
                Text('${r.count} lượt', style: body(TextStyle(fontSize: 10, color: AppColors.textMuted))),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// One row from the userTopListens resolver — same shape works for songs
/// and persons (artist/composer) so the helpers can be shared. `objectType`
/// is set for songs only, `personRoutePrefix` for persons only.
class _TopRow {
  final String id;
  final String title;
  final String? slug;
  final String? image;
  final int count;
  final String? objectType;
  final bool isPerson;
  final String? personRoutePrefix;
  const _TopRow({required this.id, required this.title, this.slug, this.image, required this.count, this.objectType, this.isPerson = false, this.personRoutePrefix});
}
