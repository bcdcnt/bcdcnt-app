import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/activity.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';

class TagDetailScreen extends StatefulWidget {
  final String slug;
  const TagDetailScreen({super.key, required this.slug});

  @override
  State<TagDetailScreen> createState() => _TagDetailScreenState();
}

class _TagDetailScreenState extends State<TagDetailScreen> {
  Map<String, dynamic>? _tag;
  String _activeType = 'song';
  // Per-type state: items, page, lastPage, total, loading
  final Map<String, _TabState> _tabs = {
    'song': _TabState(),
    'instrumental': _TabState(),
    'karaoke': _TabState(),
  };

  static const _tabConfig = [
    ('song', 'Tân nhạc', 'songsByTag'),
    ('instrumental', 'Khí nhạc', 'instrumentalsByTag'),
    ('karaoke', 'Thành viên hát', 'karaokesByTag'),
  ];

  final _scrollCtl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    _fetchTag();
  }

  @override
  void dispose() {
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final tab = _tabs[_activeType]!;
    if (tab.loading || tab.page >= tab.lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) {
      _fetchPage(_activeType, tab.page + 1);
    }
  }

  Future<void> _fetchTag() async {
    try {
      final data = await ApiClient.query(
        r'query($slug: String!) { tag(slug: $slug) { id name slug users { id username avatar { url } } } }',
        {'slug': widget.slug},
      );
      final t = data['tag'];
      if (!mounted) return;
      if (t == null) {
        setState(() => _tag = null);
        return;
      }
      setState(() => _tag = Map<String, dynamic>.from(t));
      logActivity(context.read<AuthProvider>(), 'view', 'tag', t['id']);
      // Prefetch counts for all tabs in one round-trip so the tab labels
      // show totals immediately (not just after the user clicks them).
      _prefetchCounts();
      _fetchPage('song', 1);
    } catch (_) { if (mounted) setState(() => _tag = null); }
  }

  Future<void> _prefetchCounts() async {
    final tag = _tag;
    if (tag == null) return;
    try {
      final data = await ApiClient.query(
        r'''query($tag: String!) {
          songsByTag(first: 1, page: 1, tag: $tag) { paginatorInfo { total } }
          instrumentalsByTag(first: 1, page: 1, tag: $tag) { paginatorInfo { total } }
          karaokesByTag(first: 1, page: 1, tag: $tag) { paginatorInfo { total } }
        }''',
        {'tag': tag['name']},
      );
      if (!mounted) return;
      setState(() {
        _tabs['song']!.total = data['songsByTag']?['paginatorInfo']?['total'] ?? 0;
        _tabs['instrumental']!.total = data['instrumentalsByTag']?['paginatorInfo']?['total'] ?? 0;
        _tabs['karaoke']!.total = data['karaokesByTag']?['paginatorInfo']?['total'] ?? 0;
      });
    } catch (_) {}
  }

  // Same id can show up multiple times because the relation joins through
  // every taggable. Dedupe by id to match the legacy Vue behaviour.
  List<Map<String, dynamic>> _dedupedContributors() {
    final src = (_tag?['users'] as List?) ?? const [];
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final u in src) {
      final m = Map<String, dynamic>.from(u as Map);
      final id = m['id']?.toString();
      if (id == null || !seen.add(id)) continue;
      out.add(m);
    }
    return out;
  }

  void _playAll() {
    final st = _tabs[_activeType]!;
    if (st.items.isEmpty) return;
    final player = context.read<PlayerProvider>();
    final queue = <Map<String, dynamic>>[];
    for (final s in st.items) {
      final m = Map<String, dynamic>.from(s);
      m['audioUrl'] = m['file']?['audio_url'];
      if (m['audioUrl'] != null) queue.add(m);
    }
    if (queue.isEmpty) return;
    player.playSong(queue.first, queue);
    player.setFetchMore(null);
  }

  Future<void> _fetchPage(String type, int page) async {
    final tag = _tag;
    if (tag == null) return;
    final st = _tabs[type]!;
    setState(() => st.loading = true);
    final qmap = {
      'song': r'query($tag: String!, $page: Int) { songsByTag(first: 20, page: $page, tag: $tag, orderBy: [{column: "views", order: DESC}]) { data { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } } paginatorInfo { currentPage lastPage total } } }',
      'instrumental': r'query($tag: String!, $page: Int) { instrumentalsByTag(first: 20, page: $page, tag: $tag, orderBy: [{column: "views", order: DESC}]) { data { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } } paginatorInfo { currentPage lastPage total } } }',
      'karaoke': r'query($tag: String!, $page: Int) { karaokesByTag(first: 20, page: $page, tag: $tag, orderBy: [{column: "views", order: DESC}]) { data { id slug title views play_type thumbnail { url } file { audio_url video_url duration } users(first: 5) { data { id username avatar { url } } } } paginatorInfo { currentPage lastPage total } } }',
    };
    final dataKey = {'song': 'songsByTag', 'instrumental': 'instrumentalsByTag', 'karaoke': 'karaokesByTag'};
    try {
      final data = await ApiClient.query(qmap[type]!, {'tag': tag['name'], 'page': page});
      final raw = data[dataKey[type]];
      final items = ((raw?['data'] ?? []) as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['file_type'] = type;
        if (m['users']?['data'] != null && m['artists'] == null) {
          m['artists'] = {'data': ((m['users']['data']) as List).map((u) => {'id': u['id'], 'title': u['username']}).toList()};
        }
        return m;
      }).toList();
      final pi = raw?['paginatorInfo'] ?? {};
      if (!mounted) return;
      setState(() {
        if (page == 1) st.items = items; else st.items.addAll(items);
        st.page = pi['currentPage'] ?? page;
        st.lastPage = pi['lastPage'] ?? 1;
        st.total = pi['total'] ?? 0;
        st.loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => st.loading = false);
    }
  }

  void _setType(String t) {
    if (t == _activeType) return;
    setState(() => _activeType = t);
    final st = _tabs[t]!;
    if (st.items.isEmpty && !st.loading) _fetchPage(t, 1);
  }

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return n < 0 ? '-$buf' : buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (_tag == null) {
      return Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    }
    final st = _tabs[_activeType]!;
    final activeLabel = _tabConfig.firstWhere((t) => t.$1 == _activeType).$2;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(
          controller: _scrollCtl,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.bg.withValues(alpha: 0.88),
              title: Text('TAG', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
              centerTitle: true,
              leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              sliver: SliverList(delegate: SliverChildListDelegate([
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(colors: [Color(0xFF7A3B3A), Color(0xFF4A0D0D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: const Color(0xFF7A3B3A).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.tag, color: Colors.white, size: 28)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('#${_tag!['name']}', style: display(const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3))),
                      const SizedBox(height: 4),
                      Text('Bài hát có tag này', style: body(const TextStyle(fontSize: 12, color: Colors.white70))),
                    ])),
                  ]),
                ),
                if ((_tag!['users'] is List) && (_tag!['users'] as List).isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ContributorsStrip(users: _dedupedContributors()),
                ],
                const SizedBox(height: 14),
                // Type tabs — underline style for app-wide consistency.
                Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                  child: SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tabConfig.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 18),
                      itemBuilder: (ctx, i) {
                        final t = _tabConfig[i];
                        final active = _activeType == t.$1;
                        final total = _tabs[t.$1]!.total;
                        return InkWell(
                          onTap: active ? null : () => _setType(t.$1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: active ? AppColors.accentLight : Colors.transparent, width: 2)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(t.$2, style: body(TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? AppColors.accentLight : AppColors.textSecondary))),
                              if (total > 0) ...[
                                const SizedBox(width: 6),
                                Text('$total', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? AppColors.accentLight.withValues(alpha: 0.7) : AppColors.textMuted))),
                              ],
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: Text(activeLabel + (st.total > 0 ? ' • ${_formatInt(st.total)} bài' : ''), style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accentLight, letterSpacing: 1))),
                  ),
                  if (st.items.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: _playAll,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Phát tất cả'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        textStyle: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
              ])),
            ),
            if (st.loading && st.items.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
            else if (st.items.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Chưa có bài hát', style: body(TextStyle(color: AppColors.textMuted)))))
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final song = st.items[i];
                    return SongRow(song: song, index: i, showIndex: true, onTap: () => context.push('/song/${song['id']}', extra: song));
                  },
                  childCount: st.items.length,
                )),
              ),
            SliverToBoxAdapter(child: Column(children: [
              if (st.loading && st.items.isNotEmpty) Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
              SizedBox(height: player.currentSong != null ? 90 : 20),
            ])),
          ],
        ),
        if (player.currentSong != null)
          const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}

class _TabState {
  List<Map<String, dynamic>> items = [];
  int page = 1;
  int lastPage = 1;
  int total = 0;
  bool loading = false;
}

/// "Xây dựng tag" — overlapping avatars of users who tagged content with
/// this tag. Mirrors the legacy Vue version of TagDetail.
class _ContributorsStrip extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  const _ContributorsStrip({required this.users});

  @override
  Widget build(BuildContext context) {
    const maxShown = 8;
    final shown = users.take(maxShown).toList();
    final extra = users.length - shown.length;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text('Xây dựng tag', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5))),
      const SizedBox(width: 12),
      Expanded(
        child: SizedBox(
          height: 32,
          child: Stack(
            children: [
              for (int i = 0; i < shown.length; i++)
                Positioned(
                  left: i * 22.0,
                  child: GestureDetector(
                    onTap: () { final id = shown[i]['id']; if (id != null) context.push('/user/$id'); },
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bg, width: 2),
                        color: AppColors.surfaceLight,
                      ),
                      child: ClipOval(
                        child: shown[i]['avatar']?['url'] != null
                            ? CachedNetworkImage(imageUrl: shown[i]['avatar']['url'], fit: BoxFit.cover, errorWidget: (_, _, _) => Icon(Icons.person, size: 16, color: AppColors.textMuted))
                            : Icon(Icons.person, size: 16, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ),
              if (extra > 0)
                Positioned(
                  left: shown.length * 22.0,
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 2),
                      color: AppColors.surface,
                    ),
                    alignment: Alignment.center,
                    child: Text('+$extra', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                  ),
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}
