import 'package:flutter/material.dart';
import '../widgets/list_search.dart';
import '../widgets/desktop_page.dart';
import '../widgets/ui.dart' show goBack, PillButton, SortTabs, PagedLoader, PagedList, PageResult, infiniteListBody, nearListEnd, kSongSorts, kSongSortColumn, kSongSortOrder, kSongSortMetric;
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';

/// Songs of one decade (`/bai-hat/thap-nien/:decade`), or with [video]
/// every song that has a video (`/bai-hat/video`, as on the web).
class DecadeSongsScreen extends StatefulWidget {
  final int decade;
  final bool video;
  const DecadeSongsScreen({super.key, this.decade = 0, this.video = false});

  @override
  State<DecadeSongsScreen> createState() => _DecadeSongsScreenState();
}

class _DecadeSongsScreenState extends State<DecadeSongsScreen> with PagedLoader {
  static const _perPage = 20;
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
  final _list = PagedList<Map<String, dynamic>>();

  @override
  void initState() {
    super.initState(); _scrollCtl.addListener(_maybeMore);
    _fetch(1);
  }

  @override
  void didUpdateWidget(DecadeSongsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.decade != widget.decade) {
      setState(() => _list.reset());
      _fetch(1);
    }
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<void> _fetch(int page, {int? sort, bool append = false}) => loadPage(_list, page, (page, sort) async {
        final d = widget.decade;
        final col = kSongSortColumn[_sorts[sort]]!;
        final q = '''query(\$page: Int, \$where: WhereConditions, \$q: String) {
          songs(first: $_perPage, page: \$page, q: \$q, orderBy: [{column: "$col", order: ${kSongSortOrder[_sorts[sort]]}}], where: \$where) {
            data { id slug title subtitle views likes downloads created_at play_type thumbnail { url } file { audio_url video_url duration } year sheet { year composers(first: 2) { data { id slug title } } } composers(first: 2) { data { id slug title } } artists(first: 5) { data { id slug title avatar { url } } } }
            paginatorInfo { currentPage lastPage total }
          }
        }''';
        final data = await ApiClient.query(q, {
          'page': page,
          'q': _q,
          'where': widget.video
              ? {'AND': [{'column': 'play_type', 'value': 'video'}]}
              : {'AND': [
                  {'column': 'year', 'operator': 'GTE', 'value': '$d'},
                  {'column': 'year', 'operator': 'LT', 'value': '${d + 10}'},
                ]},
        });
        return PageResult.fromPaginator(data['songs'], page);
      }, sort: sort, scrollToTop: _scrollCtl, append: append);

  void _playAll({bool shuffle = false}) {
    if (_list.items.isEmpty) return;
    final queue = <Map<String, dynamic>>[];
    for (final s in _list.items) {
      final m = Map<String, dynamic>.from(s);
      m['audioUrl'] = m['file']?['audio_url'];
      if (m['audioUrl'] != null) queue.add(m);
    }
    if (queue.isEmpty) return;
    if (shuffle) queue.shuffle();
    final player = context.read<PlayerProvider>();
    player.playSong(queue.first, queue);
    player.setFetchMore(null);
    if (shuffle && !player.shuffle) player.toggleShuffle();
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
    final desk = isDesk(context);
    final count = _list.allTotal > 0 ? '${_formatInt(_list.allTotal)} ${widget.video ? 'video' : 'bài hát'}' : (!_list.loaded && !_list.failed ? 'Đang tải...' : (_list.failed ? '' : 'Chưa có'));
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          DeskFrame(maxWidth: desk ? 1320 : double.infinity, child: CustomScrollView(
            controller: _scrollCtl,
            slivers: [
              if (!desk)
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.bg,
                title: Text(widget.video ? 'Video' : 'Thập niên'),
                centerTitle: true,
                leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
              ),
              SliverPadding(
                padding: desk ? deskPad : const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  if (desk)
                    DeskHead(title: widget.video ? 'Video' : 'Thập niên ${widget.decade}', subtitle: count, actions: _list.items.isEmpty ? const [] : deskPlayButtons(play: () => _playAll(), shuffle: () => _playAll(shuffle: true)))
                  else
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(colors: AppColors.heroGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                          alignment: Alignment.center,
                          child: Icon(widget.video ? Icons.smart_display_outlined : Icons.history_toggle_off, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.video ? 'Video' : 'Thập niên ${widget.decade}', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                              const SizedBox(height: 4),
                              Text(count, style: body(const TextStyle(fontSize: 15, color: Colors.white70))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!desk) const SizedBox(height: 14),
                  if (_list.items.isNotEmpty && !desk)
                    Row(children: [
                      Expanded(child: PillButton(onTap: () => _playAll(), icon: Icons.play_arrow, label: 'Phát tất cả', primary: true)),
                      const SizedBox(width: 10),
                      Expanded(child: PillButton(onTap: () => _playAll(shuffle: true), icon: Icons.shuffle, label: 'Ngẫu nhiên', primary: false)),
                    ]),
                  if (!desk) const SizedBox(height: 14),
                  ListSearchField(hint: widget.video ? 'Tìm trong ${_list.allTotal > 0 ? '${_list.allTotal} ' : ''}video' : 'Tìm trong ${_list.allTotal > 0 ? '${_list.allTotal} bài ' : ''}thập niên ${widget.decade}', onChanged: _search),
                  ListSearchSummary(query: _q, total: _list.total, loading: _list.loading),
                  const SizedBox(height: 14),
                  SortTabs(labels: _sorts, selected: _list.sort, padding: EdgeInsets.zero, onSelect: (i) => _fetch(1, sort: i)),
                  const SizedBox(height: 14),
                  if (desk) SongTableHead(metric: songMetricLabel(kSongSortMetric[_sorts[_list.sort]]!)),
                  ...infiniteListBody<Map<String, dynamic>>(
                    _list,
                    emptyText: 'Chưa có bài hát',
                    onRetry: () => _fetch(_list.page),
                    onMore: () => _fetch(_list.page + 1, append: true),
                    empty: _q.isEmpty ? null : ListSearchEmpty(query: _q),
                    itemBuilder: (song, i) => SongRow(highlight: _q, song: song, index: i, showIndex: true, metricKey: kSongSortMetric[_sorts[_list.sort]]!, queue: asSongList(_list.items)),
                  ),
                  SizedBox(height: player.currentSong != null ? 90 : 20),
                ])),
              ),
            ],
          )),
          if (player.currentSong != null)
            const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
        ],
      ),
    );
  }
}
