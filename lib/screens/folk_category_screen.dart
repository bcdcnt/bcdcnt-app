import 'package:flutter/material.dart';
import '../widgets/list_search.dart';
import '../widgets/ui.dart' show goBack, SortTabs, PagedLoader, PagedList, PageResult, infiniteListBody, nearListEnd, kSongSorts, kSongSortColumn, kSongSortOrder, kSongSortMetric;
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';

/// Folk category page — `/dan-ca/:slug`. Shows folks belonging to one
/// fcat (e.g. "Dân ca Nam Bộ"). Mirrors melody_detail_screen but reads
/// from the `fcats` query.
class FolkCategoryScreen extends StatefulWidget {
  final String slug;
  const FolkCategoryScreen({super.key, required this.slug});

  @override
  State<FolkCategoryScreen> createState() => _FolkCategoryScreenState();
}

class _FolkCategoryScreenState extends State<FolkCategoryScreen> with PagedLoader {
  static const _perPage = 20;
  // Folk rows have views / likes / downloads columns.
  static const _sorts = kSongSorts;
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
  Map<String, dynamic>? _fcat;
  bool _notFound = false;
  final _list = PagedList<Map<String, dynamic>>();

  @override
  void initState() { super.initState(); _scrollCtl.addListener(_maybeMore); _fetch(1); }
  @override
  void didUpdateWidget(FolkCategoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      setState(() { _fcat = null; _notFound = false; _list.reset(); });
      _fetch(1);
    }
  }
  @override
  void dispose() { _scrollCtl.dispose(); super.dispose(); }

  Future<void> _fetch(int page, {int? sort, bool append = false}) => loadPage(_list, page, (page, sort) async {
        final col = kSongSortColumn[_sorts[sort]]!;
        final q = '''query(\$slug: Mixed, \$page: Int, \$q: String) {
          fcats(first: 1, where: { column: "slug", value: \$slug }) {
            data {
              id title slug
              folks(first: $_perPage, page: \$page, q: \$q, orderBy: [{column: "$col", order: ${kSongSortOrder[_sorts[sort]]}}]) {
                data {
                  id title subtitle slug views likes downloads created_at play_type thumbnail { url } file { audio_url video_url duration }
                  artists(first: 5) { data { id title slug } }
                  recomposers(first: 5) { data { id slug title } }
                }
                paginatorInfo { currentPage lastPage total }
              }
            }
          }
        }''';
        final data = await ApiClient.query(q, {'slug': widget.slug, 'page': page, 'q': _q});
        final rows = (data['fcats']?['data'] ?? []) as List;
        final fcat = rows.isNotEmpty ? Map<String, dynamic>.from(rows[0] as Map) : null;
        if (mounted) setState(() { if (fcat != null) _fcat = fcat; _notFound = fcat == null; });
        return PageResult.fromPaginator(fcat?['folks'], page, (m) => m..['file_type'] = 'folk');
      }, sort: sort, scrollToTop: _scrollCtl, append: append);

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return n < 0 ? '-${buf.toString()}' : buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final hasPlayer = player.currentSong != null;
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
                leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
                title: Text('Thể loại dân ca'),
                centerTitle: true,
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  // Hero
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.album_outlined, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_fcat?['title']?.toString() ?? 'Dân ca', style: display(const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white))),
                          const SizedBox(height: 4),
                          Text(_list.allTotal > 0 ? '${_formatInt(_list.allTotal)} bài' : (!_list.loaded && !_list.failed ? 'Đang tải...' : (_list.failed ? '' : 'Chưa có bài')), style: body(const TextStyle(fontSize: 15, color: Colors.white70))),
                        ],
                      )),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  if (!_notFound) ...[
                    ListSearchField(hint: 'Tìm trong ${_list.allTotal > 0 ? '${_list.allTotal} bài ' : ''}${_fcat?['title'] ?? 'thể loại này'}', onChanged: _search),
                    ListSearchSummary(query: _q, total: _list.total, loading: _list.loading),
                    const SizedBox(height: 14),
                    SortTabs(labels: _sorts, selected: _list.sort, padding: EdgeInsets.zero, onSelect: (i) => _fetch(1, sort: i)),
                    const SizedBox(height: 14),
                  ],
                  ...infiniteListBody<Map<String, dynamic>>(
                    _list,
                    emptyText: _notFound ? 'Không tìm thấy thể loại này' : 'Chưa có bài',
                    onRetry: () => _fetch(_list.page),
                    onMore: () => _fetch(_list.page + 1, append: true),
                    empty: _q.isEmpty ? null : ListSearchEmpty(query: _q),
                    itemBuilder: (s, i) => SongRow(highlight: _q, song: s, index: i, showIndex: true, metricKey: kSongSortMetric[_sorts[_list.sort]]!, queue: asSongList(_list.items)),
                  ),
                  SizedBox(height: hasPlayer ? 90 : 20),
                ])),
              ),
            ],
          ),
          if (hasPlayer) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
        ],
      ),
    );
  }
}
