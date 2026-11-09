import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, Skeleton, SortTabs, PagedLoader, PagedList, PageResult, pagedListBody;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import '../widgets/desktop_page.dart';
import '../widgets/playlist_cover.dart';

class PlaylistListScreen extends StatefulWidget {
  const PlaylistListScreen({super.key});

  @override
  State<PlaylistListScreen> createState() => _PlaylistListScreenState();
}

class _PlaylistListScreenState extends State<PlaylistListScreen> with PagedLoader {
  static const _perPage = 20;
  // The playlist table has views, likes and id — no downloads.
  static const _sorts = ['Nghe nhiều nhất', 'Mới cập nhật', 'Yêu thích nhất'];
  static const _sortCols = ['views', 'id', 'likes'];
  final _scrollCtl = ScrollController();
  // Newest first by default, as before.
  final _list = PagedList<Map<String, dynamic>>(sort: 1);

  @override
  void initState() {
    super.initState();
    _fetch(1);
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<void> _fetch(int page, {int? sort}) => loadPage(_list, page, (page, sort) async {
        final q = '''query(\$page: Int, \$where: WhereConditions) {
          playlists(first: $_perPage, page: \$page, where: \$where, orderBy: [{column: "${_sortCols[sort]}", order: DESC}]) {
            data { id slug title thumbnail { url } user { id username avatar { url } } items(first: 4, orderBy: [{column: "position", order: ASC}]) {
              paginatorInfo { total }
              data { object { ... on Song { thumbnail { url } } ... on Folk { thumbnail { url } } ... on Instrumental { thumbnail { url } } ... on Poem { thumbnail { url } } } }
            } }
            paginatorInfo { currentPage lastPage total }
          }
        }''';
        final data = await ApiClient.query(q, {
          'page': page,
          'where': {'AND': [{'column': 'is_public', 'value': '1'}]},
        });
        return PageResult.fromPaginator(data['playlists'], page);
      }, sort: sort, scrollToTop: _scrollCtl);

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
    final count = _list.total > 0 ? '${_formatInt(_list.total)} playlist' : (!_list.loaded && !_list.failed ? 'Đang tải...' : (_list.failed ? '' : 'Chưa có'));
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        DeskFrame(maxWidth: desk ? 1320 : double.infinity, child: CustomScrollView(
          controller: _scrollCtl,
          slivers: [
            if (!desk)
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.bg,
              title: Text('Playlist'),
              centerTitle: true,
              leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
            ),
            SliverPadding(
              padding: desk ? deskPad : const EdgeInsets.fromLTRB(20, 8, 20, 20),
              sliver: SliverList(delegate: SliverChildListDelegate([
                if (desk)
                  DeskHead(title: 'Playlist cộng đồng', subtitle: count)
                else
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: const Color(0xFF4A0C0C).withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(
                    children: [
                      Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.queue_music_outlined, color: Colors.white, size: 28)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Playlist', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                        const SizedBox(height: 4),
                        Text(count, style: body(const TextStyle(fontSize: 15, color: Colors.white70))),
                      ])),
                    ],
                  ),
                ),
                if (!desk) const SizedBox(height: 16),
                SortTabs(labels: _sorts, selected: _list.sort, padding: EdgeInsets.zero, onSelect: (i) => _fetch(1, sort: i)),
                SizedBox(height: desk ? 22 : 14),
                if (desk)
                  // Cover cards wrapping into ~180px columns; the pager and
                  // empty/offline blocks ride along as full-width Wrap children.
                  LayoutBuilder(builder: (context, c) {
                    const gap = 20.0;
                    final cols = ((c.maxWidth + gap) / 200).floor().clamp(2, 8);
                    final w = (c.maxWidth - (cols - 1) * gap) / cols;
                    return Wrap(spacing: gap, runSpacing: 24, children: pagedListBody<Map<String, dynamic>>(
                      _list,
                      perPage: _perPage,
                      emptyText: 'Chưa có playlist',
                      onRetry: () => _fetch(_list.page),
                      onPage: (p) => _fetch(p),
                      skeleton: Wrap(spacing: gap, runSpacing: 24, children: [for (var i = 0; i < cols * 2; i++) Skeleton(width: w, height: w + 44, radius: 16)]),
                      itemBuilder: (pl, i) => SizedBox(width: w, child: _DeskPlaylistCard(playlist: pl, size: w)),
                    ));
                  })
                else
                ...pagedListBody<Map<String, dynamic>>(
                  _list,
                  perPage: _perPage,
                  emptyText: 'Chưa có playlist',
                  onRetry: () => _fetch(_list.page),
                  onPage: (p) => _fetch(p),
                  skeleton: Column(children: [for (var i = 0; i < 8; i++) const Skeleton(height: 78, radius: 12, margin: EdgeInsets.only(bottom: 10))]),
                  itemBuilder: (pl, i) => _PlaylistCard(playlist: pl),
                ),
                SizedBox(height: player.currentSong != null ? 90 : 20),
              ])),
            ),
          ],
        )),
        if (player.currentSong != null)
          const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final Map<String, dynamic> playlist;
  const _PlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final pl = playlist;
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
          ClipRRect(borderRadius: BorderRadius.circular(10), child: thumb != null ? CachedNetworkImage(imageUrl: cdnImg((thumb).toString(), 140), width: 56, height: 56, fit: BoxFit.cover) : Container(width: 56, height: 56, color: AppColors.surface, child: Icon(Icons.queue_music, color: AppColors.textMuted))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(pl['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
            const SizedBox(height: 4),
            Row(children: [
              if (pl['user']?['username'] != null) ...[
                Icon(Icons.person, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 3),
                Flexible(child: Text(pl['user']['username'], maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary)))),
                const SizedBox(width: 8),
              ],
              Text('$total bài', style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary))),
            ]),
          ])),
          Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
        ]),
      ),
    );
  }
}

/// Desktop cover card: own picture, else the first songs' covers.
class _DeskPlaylistCard extends StatelessWidget {
  final Map<String, dynamic> playlist;
  final double size;
  const _DeskPlaylistCard({required this.playlist, required this.size});

  @override
  Widget build(BuildContext context) {
    final pl = playlist;
    final total = pl['items']?['paginatorInfo']?['total'] ?? 0;
    final owner = pl['user']?['username']?.toString();
    final meta = body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted));
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/playlist/${pl['id']}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PlaylistCover(thumb: pl['thumbnail']?['url']?.toString(), songThumbs: PlaylistCover.thumbsOf(pl['items']), size: size, radius: 16),
        const SizedBox(height: 8),
        Text('${pl['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w800, color: AppColors.text))),
        const SizedBox(height: 2),
        Text(owner != null ? '$owner · $total bài' : '$total bài', maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
      ]),
    );
  }
}
