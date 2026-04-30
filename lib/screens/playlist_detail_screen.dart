import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';
import '../widgets/comment_section.dart';
import '../widgets/shimmer.dart';
import '../widgets/section_header.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final String id;
  const PlaylistDetailScreen({super.key, required this.id});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  Map<String, dynamic>? _playlist;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _related = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        playlist(id: $id) {
          id slug title description event_date is_system thumbnail { url } user { id username avatar { url } }
          items(first: 200, orderBy: [{column: "position", order: ASC}]) {
            data {
              id position type
              object {
                __typename
                ... on Song { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } }
                ... on Folk { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } }
                ... on Instrumental { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } }
                ... on Poem { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } }
                ... on Karaoke { id slug title views play_type thumbnail { url } file { audio_url video_url duration } users(first: 5) { data { id username avatar { url } } } }
              }
            }
            paginatorInfo { total }
          }
        }
      }''', {'id': widget.id});
      final pl = data['playlist'];
      if (pl == null) { if (mounted) setState(() => _loading = false); return; }
      const tnMap = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem', 'Karaoke': 'karaoke'};
      final items = <Map<String, dynamic>>[];
      for (final entry in ((pl['items']?['data'] ?? []) as List)) {
        final obj = entry['object'];
        if (obj == null) continue;
        final m = Map<String, dynamic>.from(obj as Map);
        m['file_type'] = entry['type'] ?? tnMap[m['__typename']?.toString()] ?? 'song';
        if (m['users']?['data'] != null && m['artists'] == null) {
          m['artists'] = {'data': ((m['users']['data']) as List).map((u) => {'id': u['id'], 'title': u['username']}).toList()};
        }
        items.add(m);
      }
      if (!mounted) return;
      final plMap = Map<String, dynamic>.from(pl);
      setState(() {
        _playlist = plMap;
        _items = items;
        _loading = false;
      });
      _fetchRelated(plMap);
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _fetchRelated(Map<String, dynamic> pl) async {
    try {
      final isEvent = pl['event_date'] != null && pl['event_date'].toString().isNotEmpty;
      final where = {
        'AND': [
          {'column': 'is_system', 'value': '1'},
          {'column': 'is_public', 'value': '1'},
          if (isEvent) {'column': 'event_date', 'operator': 'IS_NOT_NULL'} else {'column': 'event_date', 'operator': 'IS_NULL'},
          {'column': 'id', 'value': widget.id, 'operator': 'NEQ'},
        ],
      };
      final data = await ApiClient.query(r'''query($where: WhereConditions) {
        playlists(first: 8, orderBy: [{column: "id", order: DESC}], where: $where) {
          data { id slug title event_date thumbnail { url } items(first: 1) { paginatorInfo { total } } }
        }
      }''', {'where': where});
      final list = ((data['playlists']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() => _related = list);
    } catch (_) {}
  }

  void _playAll({bool shuffle = false, int startIndex = 0}) {
    if (_items.isEmpty) return;
    final queue = <Map<String, dynamic>>[];
    for (final s in _items) {
      final m = Map<String, dynamic>.from(s);
      m['audioUrl'] = m['file']?['audio_url'];
      if (m['audioUrl'] != null) queue.add(m);
    }
    if (queue.isEmpty) return;
    if (shuffle) queue.shuffle();
    final start = shuffle ? 0 : startIndex.clamp(0, queue.length - 1);
    final player = context.read<PlayerProvider>();
    player.playSong(queue[start], queue);
    player.setFetchMore(null);
    if (shuffle && !player.shuffle) player.toggleShuffle();
  }

  String _formatEventDate(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString();
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
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
    if (_loading && _playlist == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          title: Text('PLAYLIST', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
          centerTitle: true,
        ),
        body: const SingleChildScrollView(child: Column(children: [
          HeroSkeleton(),
          Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SongListSkeleton(rows: 8, showIndex: true)),
        ])),
      );
    }
    if (_playlist == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
        body: Center(child: Text('Không tìm thấy playlist', style: AppText.bodyText)),
      );
    }
    final pl = _playlist!;
    final thumb = pl['thumbnail']?['url'];
    final user = pl['user'];
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    // Apple Music-style scale-up: bigger artwork + display type on desktop.
    final thumbSize = isDesktop ? 200.0 : 120.0;
    final titleSize = isDesktop ? 32.0 : 19.0;
    final usernameSize = isDesktop ? 14.0 : 12.0;
    final metaSize = isDesktop ? 13.0 : 11.0;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.bg.withValues(alpha: 0.88),
              title: Text('PLAYLIST', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
              centerTitle: true,
              leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(isDesktop ? 32 : 20, isDesktop ? 16 : 8, isDesktop ? 32 : 20, 24),
              sliver: SliverList(delegate: SliverChildListDelegate([
                // Hero
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: thumbSize, height: thumbSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(isDesktop ? 12 : 16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 8))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(isDesktop ? 12 : 16),
                        child: thumb != null
                            ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.queue_music, color: AppColors.textMuted, size: 60))
                            : Container(color: AppColors.surfaceLight, child: const Icon(Icons.queue_music, color: AppColors.textMuted, size: 60)),
                      ),
                    ),
                    SizedBox(width: isDesktop ? 24 : 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Playlist',
                            style: body(TextStyle(
                              fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                            )),
                          ),
                          const SizedBox(height: 6),
                          Text(pl['title'] ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: titleSize, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.15, letterSpacing: -0.3))),
                          const SizedBox(height: 10),
                          if (user?['username'] != null) Row(children: [
                            CircleAvatar(
                              radius: isDesktop ? 13 : 10,
                              backgroundColor: AppColors.surfaceLight,
                              backgroundImage: user['avatar']?['url'] != null ? CachedNetworkImageProvider(user['avatar']['url']) : null,
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: Text(user['username'], maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: usernameSize, color: AppColors.textSecondary, fontWeight: FontWeight.w600)))),
                          ]),
                          if (pl['event_date'] != null && pl['event_date'].toString().isNotEmpty) Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(children: [
                              Icon(Icons.event_outlined, size: isDesktop ? 14 : 12, color: AppColors.accentLight),
                              const SizedBox(width: 4),
                              Flexible(child: Text(_formatEventDate(pl['event_date']), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: metaSize, fontWeight: FontWeight.w600, color: AppColors.accentLight)))),
                            ]),
                          ),
                          const SizedBox(height: 8),
                          Text('${_formatInt(_items.length)} bài', style: body(TextStyle(fontSize: metaSize, color: AppColors.textMuted))),
                        ],
                      ),
                    ),
                  ],
                ),
                if (pl['description'] != null && (pl['description'] as String).isNotEmpty) Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Html(
                    data: pl['description'],
                    style: {
                      'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero, fontSize: FontSize(13), lineHeight: const LineHeight(1.6), color: AppColors.textSecondary, fontFamily: body().fontFamily),
                      'p': Style(margin: Margins.only(bottom: 8)),
                      'a': Style(color: AppColors.accentLight, textDecoration: TextDecoration.none),
                      'br': Style(margin: Margins.zero),
                      'img': Style(width: Width(100, Unit.percent)),
                    },
                    onLinkTap: (url, _, _) {
                      if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (_items.isNotEmpty) Row(children: [
                  Expanded(child: ElevatedButton.icon(
                    onPressed: () => _playAll(),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Phát tất cả'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), elevation: 0),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => _playAll(shuffle: true),
                    icon: const Icon(Icons.shuffle, size: 16),
                    label: const Text('Ngẫu nhiên'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentLight, side: const BorderSide(color: AppColors.accent), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                  )),
                ]),
                const SizedBox(height: 16),
              ])),
            ),
            if (_items.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Playlist trống', style: body(const TextStyle(color: AppColors.textMuted)))))
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final song = _items[i];
                    return SongRow(
                      song: song,
                      index: i,
                      showIndex: true,
                      onTap: () => _playAll(startIndex: i),
                    );
                  },
                  childCount: _items.length,
                )),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              sliver: SliverList(delegate: SliverChildListDelegate([
                if (isDesktop && _related.isNotEmpty) ...[
                  // Desktop: comments left flex, related playlists in a
                  // narrow vertical sidebar — Option A 2-col split.
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Divider(color: AppColors.border, height: 1),
                        const SizedBox(height: 16),
                        CommentSection(type: 'playlist', id: widget.id),
                      ]),
                    ),
                    const SizedBox(width: 28),
                    SizedBox(
                      width: 360,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SectionHeader(
                          icon: (pl['event_date'] != null && pl['event_date'].toString().isNotEmpty) ? Icons.event_outlined : Icons.queue_music_outlined,
                          title: (pl['event_date'] != null && pl['event_date'].toString().isNotEmpty) ? 'Playlist sự kiện khác' : 'Playlist khác',
                          count: '(${_related.length})',
                        ),
                        ..._related.take(8).map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RelatedCardCompact(item: r, formatEventDate: _formatEventDate),
                        )),
                      ]),
                    ),
                  ]),
                ] else ...[
                  // Mobile (or no related): keep the original stacked flow.
                  if (_related.isNotEmpty) ...[
                    Row(children: [
                      Icon((pl['event_date'] != null && pl['event_date'].toString().isNotEmpty) ? Icons.event_outlined : Icons.queue_music_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        (pl['event_date'] != null && pl['event_date'].toString().isNotEmpty) ? 'Playlist sự kiện khác' : 'Playlist khác',
                        style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 200,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _related.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (ctx, i) => _RelatedCard(
                          item: _related[i],
                          width: 130,
                          formatEventDate: _formatEventDate,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 16),
                  CommentSection(type: 'playlist', id: widget.id),
                ],
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

class _RelatedGrid extends StatelessWidget {
  final List _items;
  final String Function(dynamic) formatEventDate;
  const _RelatedGrid({required List items, required this.formatEventDate}) : _items = items;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cols = w >= 1280 ? 5 : (w >= 1100 ? 4 : 3);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length.clamp(0, cols * 2),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 18,
        crossAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (_, i) => _RelatedCard(item: _items[i], formatEventDate: formatEventDate),
    );
  }
}

/// Compact horizontal row used in the desktop sidebar — 56x56 thumb +
/// title + count, optimised for scanning a narrow column.
class _RelatedCardCompact extends StatelessWidget {
  final Map item;
  final String Function(dynamic) formatEventDate;
  const _RelatedCardCompact({required this.item, required this.formatEventDate});

  @override
  Widget build(BuildContext context) {
    final thumb = item['thumbnail']?['url'];
    final total = item['items']?['paginatorInfo']?['total'] ?? 0;
    final ev = item['event_date'];
    return InkWell(
      onTap: () => context.push('/playlist/${item['id']}'),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: thumb != null
                ? CachedNetworkImage(imageUrl: thumb, width: 56, height: 56, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(width: 56, height: 56, color: AppColors.surfaceLight, child: const Icon(Icons.queue_music, color: AppColors.textMuted)))
                : Container(width: 56, height: 56, color: AppColors.surfaceLight, child: const Icon(Icons.queue_music, color: AppColors.textMuted)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3))),
                const SizedBox(height: 3),
                if (ev != null && ev.toString().isNotEmpty)
                  Text(formatEventDate(ev), style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accentLight)))
                else if (total > 0)
                  Text('$total bài', style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _RelatedCard extends StatelessWidget {
  final Map item;
  final double? width;
  final String Function(dynamic) formatEventDate;
  const _RelatedCard({required this.item, this.width, required this.formatEventDate});

  @override
  Widget build(BuildContext context) {
    final thumb = item['thumbnail']?['url'];
    final total = item['items']?['paginatorInfo']?['total'] ?? 0;
    final ev = item['event_date'];
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: () => context.push('/playlist/${item['id']}'),
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: thumb != null
                  ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: AppColors.surfaceLight, child: const Icon(Icons.queue_music, color: AppColors.textMuted)))
                  : Container(color: AppColors.surfaceLight, child: const Icon(Icons.queue_music, color: AppColors.textMuted)),
              ),
            ),
            const SizedBox(height: 6),
            Text(item['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3))),
            const SizedBox(height: 2),
            if (ev != null && ev.toString().isNotEmpty)
              Text(formatEventDate(ev), style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accentLight)))
            else if (total > 0)
              Text('$total bài', style: body(const TextStyle(fontSize: 10, color: AppColors.textMuted))),
          ],
        ),
      ),
    );
  }
}
