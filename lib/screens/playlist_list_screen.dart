import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';

class PlaylistListScreen extends StatefulWidget {
  const PlaylistListScreen({super.key});

  @override
  State<PlaylistListScreen> createState() => _PlaylistListScreenState();
}

class _PlaylistListScreenState extends State<PlaylistListScreen> {
  static const _perPage = 20;
  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    _fetch(1);
  }

  @override
  void dispose() {
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _loading || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(_page + 1);
  }

  Future<void> _fetch(int page) async {
    setState(() { if (page == 1) _loading = true; else _loadingMore = true; });
    const q = r'''query($page: Int, $where: WhereConditions) {
      playlists(first: 20, page: $page, where: $where, orderBy: [{column: "id", order: DESC}]) {
        data { id slug title thumbnail { url } user { id username avatar { url } } items(first: 1) { paginatorInfo { total } } }
        paginatorInfo { currentPage lastPage total }
      }
    }''';
    try {
      final data = await ApiClient.query(q, {
        'page': page,
        'where': {'AND': [{'column': 'is_public', 'value': '1'}]},
      });
      final raw = data['playlists'];
      final list = ((raw?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final pi = raw?['paginatorInfo'] ?? {};
      if (!mounted) return;
      setState(() {
        if (page == 1) _items = list; else _items.addAll(list);
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _total = pi['total'] ?? _total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadingMore = false; });
    }
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
      body: Stack(children: [
        CustomScrollView(
          controller: _scrollCtl,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.bg.withValues(alpha: 0.88),
              title: Text('PLAYLIST', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
              centerTitle: true,
              leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              sliver: SliverList(delegate: SliverChildListDelegate([
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(colors: [Color(0xFF388E3C), Color(0xFF81C784)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: const Color(0xFF388E3C).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(
                    children: [
                      Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.queue_music_outlined, color: Colors.white, size: 28)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Playlist', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                        const SizedBox(height: 4),
                        Text(_total > 0 ? '${_formatInt(_total)} playlist' : (_loading ? 'Đang tải...' : 'Chưa có'), style: body(const TextStyle(fontSize: 13, color: Colors.white70))),
                      ])),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ])),
            ),
            if (_loading && _items.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
            else if (_items.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Chưa có playlist', style: body(const TextStyle(color: AppColors.textMuted)))))
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final pl = _items[i];
                    final thumb = pl['thumbnail']?['url'];
                    final total = pl['items']?['paginatorInfo']?['total'] ?? 0;
                    return InkWell(
                      onTap: () => context.push('/playlist/${pl['id']}'),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                        child: Row(children: [
                          ClipRRect(borderRadius: BorderRadius.circular(10), child: thumb != null ? CachedNetworkImage(imageUrl: thumb, width: 56, height: 56, fit: BoxFit.cover) : Container(width: 56, height: 56, color: AppColors.surface, child: const Icon(Icons.queue_music, color: AppColors.textMuted))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(pl['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
                            const SizedBox(height: 4),
                            Row(children: [
                              if (pl['user']?['username'] != null) ...[
                                const Icon(Icons.person, size: 11, color: AppColors.textMuted),
                                const SizedBox(width: 3),
                                Flexible(child: Text(pl['user']['username'], maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted)))),
                                const SizedBox(width: 8),
                              ],
                              Text('$total bài', style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                            ]),
                          ])),
                          const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
                        ]),
                      ),
                    );
                  },
                  childCount: _items.length,
                )),
              ),
            SliverToBoxAdapter(child: Column(children: [
              if (_loadingMore) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
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
