import 'package:flutter/material.dart';
import '../widgets/list_search.dart';
import '../widgets/ui.dart' show goBack, PillButton, SortTabs, PagedLoader, PagedList, PageResult, infiniteListBody, nearListEnd, kSongSorts, kSongSortColumn, kSongSortOrder, kSongSortMetric;
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';

class _CatCfg {
  final String name, slug, query, artistField, composerField, fileType;
  final Color bg;
  final IconData icon;
  const _CatCfg({
    required this.name, required this.slug, required this.query,
    required this.artistField, required this.composerField,
    required this.fileType, required this.bg, required this.icon,
  });
}

const _cats = <String, _CatCfg>{
  'tan-nhac': _CatCfg(name: 'Tân nhạc', slug: 'tan-nhac', query: 'songs', artistField: 'artists', composerField: 'composers', fileType: 'song', bg: Color(0xFF711313), icon: Icons.music_note),
  'dan-ca': _CatCfg(name: 'Dân ca', slug: 'dan-ca', query: 'folks', artistField: 'artists', composerField: 'recomposers', fileType: 'folk', bg: Color(0xFF8B6914), icon: Icons.music_note),
  'khi-nhac': _CatCfg(name: 'Khí nhạc', slug: 'khi-nhac', query: 'instrumentals', artistField: 'artists', composerField: 'composers', fileType: 'instrumental', bg: Color(0xFF7A3B3A), icon: Icons.piano),
  'tieng-tho': _CatCfg(name: 'Tiếng thơ', slug: 'tieng-tho', query: 'poems', artistField: 'artists', composerField: 'poets', fileType: 'poem', bg: Color(0xFF6B5210), icon: Icons.auto_stories_outlined),
  'thanh-vien-hat': _CatCfg(name: 'Bản thu', slug: 'thanh-vien-hat', query: 'karaokes', artistField: 'users', composerField: 'composers', fileType: 'karaoke', bg: Color(0xFF2D5E3A), icon: Icons.mic),
};

class CategoryDetailScreen extends StatefulWidget {
  final String slug;
  const CategoryDetailScreen({super.key, required this.slug});

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> with PagedLoader {
  static const _perPage = 10;
  // Every category table has views / likes / downloads columns.
  static const _sorts = kSongSorts;
  _CatCfg? get _cfg => _cats[widget.slug];
  final _list = PagedList<Map<String, dynamic>>();
  final _scrollCtl = ScrollController();
  /// Words in the search box ('' = whole list).
  String _q = '';

  void _maybeMore() {
    if (nearListEnd(_scrollCtl, _list)) _fetch(_list.page + 1, append: true);
  }

  void _search(String q) {
    setState(() => _q = _list.query = q);
    _fetch(1);
  }

  @override
  void initState() {
    super.initState(); _scrollCtl.addListener(_maybeMore);
    _fetch(1);
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CategoryDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      setState(() => _list.reset());
      _fetch(1);
    }
  }

  Future<void> _fetch(int page, {int? sort, bool append = false}) async {
    final cfg = _cfg;
    if (cfg == null) return;
    await loadPage(_list, page, (page, sort) async {
      final sortCol = kSongSortColumn[_sorts[sort]]!;
      final artistNested = cfg.artistField == 'users'
          ? 'users(first: 5) { data { id username } }'
          : 'artists(first: 5) { data { id title slug avatar { url } } }';
      final composerNested = '${cfg.composerField}(first: 20) { data { id slug title } }';
      final q = 'query(\$page: Int, \$q: String) { ${cfg.query}(first: $_perPage, page: \$page, q: \$q, orderBy: [{column: "$sortCol", order: ${kSongSortOrder[_sorts[sort]]}}]) { data { id title subtitle slug views downloads likes created_at play_type thumbnail { url } file { audio_url video_url duration } sheet { year } $artistNested $composerNested } paginatorInfo { total currentPage lastPage } } }';
      final data = await ApiClient.query(q, {'page': page, 'q': _q});
      return PageResult.fromPaginator(data[cfg.query], page, (m) {
        m['file_type'] = cfg.fileType;
        // Normalize karaoke users -> artists shape
        if (cfg.artistField == 'users' && m['users']?['data'] != null) {
          m['artists'] = {'data': ((m['users']['data']) as List).map((u) => {'id': u['id'], 'title': u['username']}).toList()};
        }
        return m;
      });
    }, sort: sort, scrollToTop: _scrollCtl, append: append);
  }

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return n < 0 ? '-${buf.toString()}' : buf.toString();
  }

  void _playAll({bool shuffle = false}) {
    if (_list.items.isEmpty) return;
    final player = context.read<PlayerProvider>();
    final queue = <Map<String, dynamic>>[];
    for (final s in _list.items) {
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

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    if (cfg == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context))),
        body: Center(child: Text('Không tìm thấy thể loại', style: AppText.bodyText)),
      );
    }
    final player = context.watch<PlayerProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollCtl,
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.bg,
                title: Text('Thể loại'),
                centerTitle: true,
                leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Hero banner
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(colors: [cfg.bg, cfg.bg.withValues(alpha: 0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        boxShadow: [BoxShadow(color: cfg.bg.withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                            child: Icon(cfg.icon, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cfg.name, style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                                const SizedBox(height: 4),
                                Text(
                                  _list.allTotal > 0 ? '${_formatInt(_list.allTotal)} bài' : (!_list.loaded && !_list.failed ? 'Đang tải...' : (_list.failed ? '' : 'Chưa có bài')),
                                  style: body(const TextStyle(fontSize: 15, color: Colors.white70)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Play all
                    if (_list.items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            Expanded(child: PillButton(onTap: () => _playAll(), icon: Icons.play_arrow, label: 'Phát tất cả', primary: true)),
                            const SizedBox(width: 10),
                            Expanded(child: PillButton(onTap: () => _playAll(shuffle: true), icon: Icons.shuffle, label: 'Ngẫu nhiên', primary: false)),
                          ],
                        ),
                      ),

                    ListSearchField(hint: 'Tìm trong ${_list.allTotal > 0 ? '${_formatInt(_list.allTotal)} bài ' : ''}${cfg.name}', onChanged: _search),

                    ListSearchSummary(query: _q, total: _list.total, loading: _list.loading),

                    const SizedBox(height: 14),

                    SortTabs(
                      labels: _sorts,
                      selected: _list.sort,
                      padding: EdgeInsets.zero,
                      onSelect: (i) => _fetch(1, sort: i),
                    ),
                    const SizedBox(height: 14),

                    ...infiniteListBody<Map<String, dynamic>>(
                      _list,
                      onRetry: () => _fetch(_list.page),
                      onMore: () => _fetch(_list.page + 1, append: true),
                      empty: _q.isEmpty ? null : ListSearchEmpty(query: _q),
                      itemBuilder: (song, i) => SongRow(highlight: _q, 
                        song: song,
                        index: i,
                        showIndex: true,
                        metricKey: kSongSortMetric[_sorts[_list.sort]]!,
                        queue: asSongList(_list.items),
                      ),
                    ),

                    SizedBox(height: player.currentSong != null ? 90 : 20),
                  ]),
                ),
              ),
            ],
          ),
          if (player.currentSong != null)
            const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
        ],
      ),
    );
  }
}
