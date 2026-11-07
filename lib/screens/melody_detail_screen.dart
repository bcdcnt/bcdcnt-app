import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock, SortTabs, PagedLoader, PagedList, PageResult, pagedListBody, kSongSorts, kSongSortColumn, kSongSortMetric;
import '../widgets/shimmer.dart' show SongListSkeleton;
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';

class MelodyDetailScreen extends StatefulWidget {
  final String slug;
  const MelodyDetailScreen({super.key, required this.slug});

  @override
  State<MelodyDetailScreen> createState() => _MelodyDetailScreenState();
}

class _MelodyDetailScreenState extends State<MelodyDetailScreen> with PagedLoader {
  static const _perPage = 20;
  // Folk rows have views / likes / downloads columns.
  static const _sorts = kSongSorts;
  final _scrollCtl = ScrollController();
  Map<String, dynamic>? _melody;
  bool _notFound = false;
  final _list = PagedList<Map<String, dynamic>>();

  @override
  void initState() { super.initState(); _fetch(1); }
  @override
  void didUpdateWidget(MelodyDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      setState(() { _melody = null; _notFound = false; _list.reset(); });
      _fetch(1);
    }
  }
  @override
  void dispose() { _scrollCtl.dispose(); super.dispose(); }

  Future<void> _fetch(int page, {int? sort}) => loadPage(_list, page, (page, sort) async {
        final col = kSongSortColumn[_sorts[sort]]!;
        final q = '''query(\$slug: Mixed, \$page: Int) {
          melodies(first: 1, where: { column: "slug", value: \$slug }) {
            data {
              id title slug
              folks(first: $_perPage, page: \$page, orderBy: [{column: "$col", order: DESC}]) {
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
        final data = await ApiClient.query(q, {'slug': widget.slug, 'page': page});
        final rows = (data['melodies']?['data'] ?? []) as List;
        final melody = rows.isNotEmpty ? Map<String, dynamic>.from(rows[0] as Map) : null;
        if (mounted) setState(() { if (melody != null) _melody = melody; _notFound = melody == null; });
        return PageResult.fromPaginator(melody?['folks'], page, (m) => m..['file_type'] = 'folk');
      }, sort: sort, scrollToTop: _scrollCtl);

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 == 0) buf.write('.'); buf.write(s[i]); }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(controller: _scrollCtl, slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg,
            title: Text('Làn điệu'),
            centerTitle: true,
            leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          ),
          if (_melody == null && !_list.failed && !_notFound)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 0), child: SongListSkeleton(rows: 8, showIndex: true)))
          else if (_melody == null && _list.failed)
            SliverToBoxAdapter(child: OfflineBlock(onRetry: () => _fetch(1)))
          else if (_melody == null)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Không tìm thấy làn điệu', style: AppText.bodyText)))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              sliver: SliverList(delegate: SliverChildListDelegate([
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(colors: [Color(0xFF8B6914), Color(0xFFC9A96E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: const Color(0xFF8B6914).withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.music_note_outlined, color: Colors.white, size: 28)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_melody!['title'] ?? '', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                      const SizedBox(height: 4),
                      Text(_list.total > 0 ? '${_formatInt(_list.total)} bài' : (_list.loading ? 'Đang tải...' : (_list.failed ? '' : 'Chưa có bài')), style: body(const TextStyle(fontSize: 15, color: Colors.white70))),
                    ])),
                  ]),
                ),
                const SizedBox(height: 14),
                SortTabs(labels: _sorts, selected: _list.sort, padding: EdgeInsets.zero, onSelect: (i) => _fetch(1, sort: i)),
                const SizedBox(height: 14),
                ...pagedListBody<Map<String, dynamic>>(
                  _list,
                  perPage: _perPage,
                  emptyText: 'Chưa có bài nào thuộc làn điệu này',
                  onRetry: () => _fetch(_list.page),
                  onPage: (p) => _fetch(p),
                  itemBuilder: (s, i) => SongRow(song: s, index: i, showIndex: true, metricKey: kSongSortMetric[_sorts[_list.sort]]!, queue: asSongList(_list.items)),
                ),
              ])),
            ),
          SliverToBoxAdapter(child: SizedBox(height: player.currentSong != null ? 90 : 20)),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
