import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import '../widgets/list_search.dart';
import '../widgets/ui.dart' show goBack, PillButton, OfflineBlock, SortTabs, PagedLoader, PagedList, PageResult, infiniteListBody, nearListEnd, kSongSorts, kSongSortColumn, kSongSortOrder, kSongSortMetric;
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
import '../widgets/shimmer.dart' show SongListSkeleton;

class TagDetailScreen extends StatefulWidget {
  final String slug;
  const TagDetailScreen({super.key, required this.slug});

  @override
  State<TagDetailScreen> createState() => _TagDetailScreenState();
}

class _TagDetailScreenState extends State<TagDetailScreen> with PagedLoader {
  static const _perPage = 20;
  // *ByTag builders filter with whereHas, so every song column sorts.
  static const _sorts = kSongSorts;
  Map<String, dynamic>? _tag;
  bool _tagLoading = true;
  bool _tagFailed = false;
  String _activeType = 'song';
  // Per-type list: its own page + sort, kept when switching tabs.
  final Map<String, PagedList<Map<String, dynamic>>> _tabs = {
    'song': PagedList(),
    'instrumental': PagedList(),
    'karaoke': PagedList(),
  };
  // Totals from the one-shot count query, shown on the type tabs before
  // a tab has been opened.
  final Map<String, int> _counts = {};

  static const _tabConfig = [
    ('song', 'Tân nhạc', 'songsByTag'),
    ('instrumental', 'Khí nhạc', 'instrumentalsByTag'),
    ('karaoke', 'Bản thu', 'karaokesByTag'),
  ];

  final _scrollCtl = ScrollController();
  /// Words in the search box ('' = whole list); applies to every tab.
  String _q = '';

  void _maybeMore() {
    final st = _tabs[_activeType]!;
    if (nearListEnd(_scrollCtl, st)) _fetchPage(_activeType, st.page + 1, append: true);
  }

  void _search(String q) {
    setState(() => _q = q);
    _fetchPage(_activeType, 1);
  }

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_maybeMore);
    _fetchTag();
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<void> _fetchTag() async {
    if (!_tagLoading || _tagFailed) setState(() { _tagLoading = true; _tagFailed = false; });
    try {
      final data = await ApiClient.query(
        r'query($slug: String!) { tag(slug: $slug) { id name slug users { id username avatar { url } } } }',
        {'slug': widget.slug},
      );
      final t = data['tag'];
      if (!mounted) return;
      if (t == null) {
        setState(() { _tag = null; _tagLoading = false; });
        return;
      }
      setState(() { _tag = Map<String, dynamic>.from(t); _tagLoading = false; });
      logActivity(context.read<AuthProvider>(), 'view', 'tag', t['id']);
      // Prefetch counts for all tabs in one round-trip so the tab labels
      // show totals immediately (not just after the user clicks them).
      _prefetchCounts();
      _fetchPage('song', 1);
    } catch (_) { if (mounted) setState(() { _tag = null; _tagLoading = false; _tagFailed = true; }); }
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
        _counts['song'] = data['songsByTag']?['paginatorInfo']?['total'] ?? 0;
        _counts['instrumental'] = data['instrumentalsByTag']?['paginatorInfo']?['total'] ?? 0;
        _counts['karaoke'] = data['karaokesByTag']?['paginatorInfo']?['total'] ?? 0;
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

  void _playAll({bool shuffle = false}) {
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
    if (shuffle) queue.shuffle();
    player.playSong(queue.first, queue);
    player.setFetchMore(null);
    if (shuffle && !player.shuffle) player.toggleShuffle();
  }

  Future<void> _fetchPage(String type, int page, {int? sort, bool append = false}) async {
    final tag = _tag;
    if (tag == null) return;
    final dataKey = {'song': 'songsByTag', 'instrumental': 'instrumentalsByTag', 'karaoke': 'karaokesByTag'}[type]!;
    final people = type == 'karaoke'
        ? 'users(first: 5) { data { id username avatar { url } } }'
        : 'artists(first: 5) { data { id slug title avatar { url } } }';
    final q = _q;
    _tabs[type]!.query = q;
    await loadPage(_tabs[type]!, page, (page, sort) async {
      final col = kSongSortColumn[_sorts[sort]]!;
      final query = 'query(\$tag: String!, \$page: Int, \$q: String) { $dataKey(first: $_perPage, page: \$page, tag: \$tag, q: \$q, orderBy: [{column: "$col", order: ${kSongSortOrder[_sorts[sort]]}}]) { data { id slug title views likes downloads created_at play_type thumbnail { url } file { audio_url video_url duration } $people } paginatorInfo { currentPage lastPage total } } }';
      final data = await ApiClient.query(query, {'tag': tag['name'], 'page': page, 'q': q});
      return PageResult.fromPaginator(data[dataKey], page, (m) {
        m['file_type'] = type;
        if (m['users']?['data'] != null && m['artists'] == null) {
          m['artists'] = {'data': ((m['users']['data']) as List).map((u) => {'id': u['id'], 'title': u['username']}).toList()};
        }
        return m;
      });
    }, sort: sort, scrollToTop: _scrollCtl, append: append);
  }

  void _setType(String t) {
    if (t == _activeType) return;
    setState(() => _activeType = t);
    final st = _tabs[t]!;
    // Loaded before the search words changed: load again with them.
    if ((!st.loaded && !st.loading) || st.query != _q) _fetchPage(t, 1);
  }

  Widget _stateScaffold(Widget child) => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          title: const Text('Tag'),
          centerTitle: true,
          leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
        ),
        body: child,
      );

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
      if (_tagLoading) return _stateScaffold(const SingleChildScrollView(padding: EdgeInsets.fromLTRB(20, 8, 20, 0), child: SongListSkeleton(rows: 8, showIndex: true)));
      if (_tagFailed) return _stateScaffold(ListView(children: [OfflineBlock(onRetry: _fetchTag)]));
      return _stateScaffold(Center(child: Text('Không tìm thấy tag này', style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)))));
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
              backgroundColor: AppColors.bg,
              title: Text('Tag'),
              centerTitle: true,
              leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              sliver: SliverList(delegate: SliverChildListDelegate([
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(colors: [Color(0xFF7A3B3A), Color(0xFF4A0D0D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: const Color(0xFF7A3B3A).withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.tag, color: Colors.white, size: 28)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_tag!['name']}', style: display(const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3))),
                      const SizedBox(height: 4),
                      Text('Bài hát có tag này', style: body(const TextStyle(fontSize: 15, color: Colors.white70))),
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
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tabConfig.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 18),
                      itemBuilder: (ctx, i) {
                        final t = _tabConfig[i];
                        final active = _activeType == t.$1;
                        final total = _tabs[t.$1]!.loaded && _tabs[t.$1]!.allTotal > 0 ? _tabs[t.$1]!.allTotal : (_counts[t.$1] ?? 0);
                        return InkWell(
                          onTap: active ? null : () => _setType(t.$1),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            // Same look as the person page tabs: "Tân nhạc · 2.026",
                            // dark bold when active over a 3pt wine bar.
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: active ? AppColors.accent : Colors.transparent, width: 3)),
                            ),
                            child: Text(
                              total > 0 ? '${t.$2} · ${_formatInt(total)}' : t.$2,
                              style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: active ? AppColors.text : AppColors.textMuted)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Kind and count are on the tab above: just the play buttons.
                if (st.items.isNotEmpty) ...[
                  Row(children: [
                    Expanded(child: PillButton(onTap: () => _playAll(), icon: Icons.play_arrow, label: 'Phát tất cả', primary: true)),
                    const SizedBox(width: 10),
                    Expanded(child: PillButton(onTap: () => _playAll(shuffle: true), icon: Icons.shuffle, label: 'Ngẫu nhiên', primary: false)),
                  ]),
                  const SizedBox(height: 14),
                ],
                ListSearchField(hint: 'Tìm trong ${st.allTotal > 0 ? '${_formatInt(st.allTotal)} bài ' : ''}$activeLabel', onChanged: _search),
                ListSearchSummary(query: _q, total: st.total, loading: st.loading),
                const SizedBox(height: 14),
                SortTabs(labels: _sorts, selected: st.sort, padding: EdgeInsets.zero, onSelect: (i) => _fetchPage(_activeType, 1, sort: i)),
                const SizedBox(height: 14),
                ...infiniteListBody<Map<String, dynamic>>(
                  st,
                  emptyText: 'Chưa có bài',
                  empty: _q.isEmpty ? null : ListSearchEmpty(query: _q),
                  onRetry: () => _fetchPage(_activeType, st.page),
                  onMore: () => _fetchPage(_activeType, st.page + 1, append: true),
                  itemBuilder: (song, i) => SongRow(highlight: _q, song: song, index: i, showIndex: true, metricKey: kSongSortMetric[_sorts[st.sort]]!, queue: asSongList(st.items)),
                ),
                SizedBox(height: player.currentSong != null ? 90 : 20),
              ])),
            ),
          ],
        ),
        if (player.currentSong != null)
          const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
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
      Text('Xây dựng tag', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5))),
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
                            ? CachedNetworkImage(imageUrl: cdnImg((shown[i]['avatar']['url']).toString(), 160), fit: BoxFit.cover, errorWidget: (_, _, _) => Icon(Icons.person, size: 16, color: AppColors.textMuted))
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
                    child: Text('+$extra', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                  ),
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}
