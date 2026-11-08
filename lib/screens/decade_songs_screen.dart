import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, PillButton, SortTabs, PagedLoader, PagedList, PageResult, pagedListBody, kSongSorts, kSongSortColumn, kSongSortOrder, kSongSortMetric;
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';

class DecadeSongsScreen extends StatefulWidget {
  final int decade;
  const DecadeSongsScreen({super.key, required this.decade});

  @override
  State<DecadeSongsScreen> createState() => _DecadeSongsScreenState();
}

class _DecadeSongsScreenState extends State<DecadeSongsScreen> with PagedLoader {
  static const _perPage = 20;
  static const _sorts = kSongSorts;
  final _scrollCtl = ScrollController();
  final _list = PagedList<Map<String, dynamic>>();

  @override
  void initState() {
    super.initState();
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

  Future<void> _fetch(int page, {int? sort}) => loadPage(_list, page, (page, sort) async {
        final d = widget.decade;
        final col = kSongSortColumn[_sorts[sort]]!;
        final q = '''query(\$page: Int, \$where: WhereConditions) {
          songs(first: $_perPage, page: \$page, orderBy: [{column: "$col", order: ${kSongSortOrder[_sorts[sort]]}}], where: \$where) {
            data { id slug title subtitle views likes downloads created_at play_type thumbnail { url } file { audio_url video_url duration } sheet { year } artists(first: 5) { data { id slug title avatar { url } } } }
            paginatorInfo { currentPage lastPage total }
          }
        }''';
        final data = await ApiClient.query(q, {
          'page': page,
          'where': {'AND': [
            {'column': 'year', 'operator': 'GTE', 'value': '$d'},
            {'column': 'year', 'operator': 'LT', 'value': '${d + 10}'},
          ]},
        });
        return PageResult.fromPaginator(data['songs'], page);
      }, sort: sort, scrollToTop: _scrollCtl);

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
                title: Text('Thập niên'),
                centerTitle: true,
                leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                          alignment: Alignment.center,
                          child: const Icon(Icons.history_toggle_off, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Thập niên ${widget.decade}', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                              const SizedBox(height: 4),
                              Text(_list.total > 0 ? '${_formatInt(_list.total)} bài hát' : (!_list.loaded && !_list.failed ? 'Đang tải...' : (_list.failed ? '' : 'Chưa có')), style: body(const TextStyle(fontSize: 15, color: Colors.white70))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_list.items.isNotEmpty)
                    Row(children: [
                      Expanded(child: PillButton(onTap: () => _playAll(), icon: Icons.play_arrow, label: 'Phát tất cả', primary: true)),
                      const SizedBox(width: 10),
                      Expanded(child: PillButton(onTap: () => _playAll(shuffle: true), icon: Icons.shuffle, label: 'Ngẫu nhiên', primary: false)),
                    ]),
                  const SizedBox(height: 14),
                  SortTabs(labels: _sorts, selected: _list.sort, padding: EdgeInsets.zero, onSelect: (i) => _fetch(1, sort: i)),
                  const SizedBox(height: 14),
                  ...pagedListBody<Map<String, dynamic>>(
                    _list,
                    perPage: _perPage,
                    emptyText: 'Chưa có bài hát',
                    onRetry: () => _fetch(_list.page),
                    onPage: (p) => _fetch(p),
                    itemBuilder: (song, i) => SongRow(song: song, index: i, showIndex: true, metricKey: kSongSortMetric[_sorts[_list.sort]]!, queue: asSongList(_list.items)),
                  ),
                  SizedBox(height: player.currentSong != null ? 90 : 20),
                ])),
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
