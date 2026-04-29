import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
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
  String _sort = 'views';

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
      if (!mounted) return;
      if (fcat == null) { setState(() => _loading = false); return; }
      final folks = ((fcat['folks']?['data'] ?? []) as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['file_type'] = 'folk';
        return m;
      }).toList();
      final pi = fcat['folks']?['paginatorInfo'] ?? {};
      setState(() {
        _fcat = fcat;
        if (page == 1) _songs = folks; else _songs.addAll(folks);
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _total = pi['total'] ?? 0;
        _loading = false; _loadingMore = false;
      });
    } catch (_) { if (mounted) setState(() { _loading = false; _loadingMore = false; }); }
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
                backgroundColor: AppColors.bg.withValues(alpha: 0.88),
                leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
                title: Text('THỂ LOẠI DÂN CA', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
                centerTitle: true,
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  // Hero
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
                          Text(_total > 0 ? '${_formatInt(_total)} bài' : (_loading ? 'Đang tải...' : 'Chưa có bài'), style: body(const TextStyle(fontSize: 13, color: Colors.white70))),
                        ],
                      )),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ])),
              ),
              if (_loading && _songs.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
              else if (_songs.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Chưa có bài', style: body(const TextStyle(color: AppColors.textMuted)))))
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final s = _songs[i];
                      return SongRow(song: s, index: i, showIndex: true, onTap: () => context.push('/song/${s['id']}', extra: s));
                    },
                    childCount: _songs.length,
                  )),
                ),
              if (_loadingMore)
                const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: AppColors.accent)))),
              SliverToBoxAdapter(child: SizedBox(height: hasPlayer ? 90 : 20)),
            ],
          ),
          if (hasPlayer) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
        ],
      ),
    );
  }
}
