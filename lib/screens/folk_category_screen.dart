import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock, PillButton;
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

class _FolkCategoryScreenState extends State<FolkCategoryScreen> {
  final _scrollCtl = ScrollController();
  Map<String, dynamic>? _fcat;
  List<Map<String, dynamic>> _songs = [];
  int _page = 1, _lastPage = 1, _total = 0;
  bool _loading = true, _loadingMore = false;
  bool _failed = false, _moreFailed = false;
  int _reqId = 0;
  String _sort = 'views';

  @override
  void initState() { super.initState(); _scrollCtl.addListener(_onScroll); _fetch(1); }
  @override
  void dispose() { _scrollCtl.removeListener(_onScroll); _scrollCtl.dispose(); super.dispose(); }
  void _onScroll() {
    if (_loadingMore || _loading || _moreFailed || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(_page + 1);
  }

  Future<void> _fetch(int page) async {
    final req = ++_reqId;
    setState(() {
      if (page == 1) { _loading = true; _failed = false; } else { _loadingMore = true; }
      _moreFailed = false;
    });
    try {
      final q = '''query(\$slug: Mixed, \$page: Int) {
        fcats(first: 1, where: { column: "slug", value: \$slug }) {
          data {
            id title slug
            folks(first: 20, page: \$page, orderBy: [{column: "$_sort", order: DESC}]) {
              data {
                id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration }
                artists(first: 5) { data { id title slug } }
                recomposers(first: 5) { data { id slug title } }
              }
              paginatorInfo { currentPage lastPage total }
            }
          }
        }
      }''';
      final data = await ApiClient.query(q, {'slug': widget.slug, 'page': page});
      final fcat = ((data['fcats']?['data'] ?? []) as List).isNotEmpty
          ? Map<String, dynamic>.from(data['fcats']['data'][0] as Map) : null;
      if (req != _reqId || !mounted) return;
      if (fcat == null) { setState(() { _loading = false; _loadingMore = false; }); return; }
      final folks = ((fcat['folks']?['data'] ?? []) as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['file_type'] = 'folk';
        return m;
      }).toList();
      final pi = fcat['folks']?['paginatorInfo'] ?? {};
      setState(() {
        _fcat = fcat;
        if (page == 1) {
          _songs = folks;
        } else {
          final seen = _songs.map((e) => e['id']?.toString()).toSet();
          _songs.addAll(folks.where((e) => !seen.contains(e['id']?.toString())));
        }
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _total = pi['total'] ?? 0;
        _loading = false; _loadingMore = false;
      });
    } catch (_) {
      if (req != _reqId || !mounted) return;
      setState(() {
        if (page == 1) { _failed = true; } else { _moreFailed = true; }
        _loading = false; _loadingMore = false;
      });
    }
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
                          Text(_total > 0 ? '${_formatInt(_total)} bài' : (_loading ? 'Đang tải...' : (_failed ? '' : 'Chưa có bài')), style: body(const TextStyle(fontSize: 15, color: Colors.white70))),
                        ],
                      )),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ])),
              ),
              if (_loading && _songs.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
              else if (_failed && _songs.isEmpty)
                SliverToBoxAdapter(child: OfflineBlock(onRetry: () => _fetch(1)))
              else if (_songs.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(_fcat == null ? 'Không tìm thấy thể loại này' : 'Chưa có bài', style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)))))
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final s = _songs[i];
                      return SongRow(song: s, index: i, showIndex: true, queue: asSongList(_songs));
                    },
                    childCount: _songs.length,
                  )),
                ),
              if (_loadingMore)
                SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: AppColors.accent)))),
              if (_moreFailed)
                SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: Center(child: PillButton(label: 'Thử lại', icon: Icons.refresh, primary: false, onTap: () => _fetch(_page + 1))))),
              SliverToBoxAdapter(child: SizedBox(height: hasPlayer ? 90 : 20)),
            ],
          ),
          if (hasPlayer) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
        ],
      ),
    );
  }
}
