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
      return const Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList(delegate: SliverChildListDelegate([
                // Hero
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 8))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: thumb != null
                            ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.queue_music, color: AppColors.textMuted, size: 60))
                            : Container(color: AppColors.surfaceLight, child: const Icon(Icons.queue_music, color: AppColors.textMuted, size: 60)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pl['title'] ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.2, letterSpacing: -0.3))),
                          const SizedBox(height: 6),
                          if (user?['username'] != null) Row(children: [
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: AppColors.surfaceLight,
                              backgroundImage: user['avatar']?['url'] != null ? CachedNetworkImageProvider(user['avatar']['url']) : null,
                            ),
                            const SizedBox(width: 6),
                            Flexible(child: Text(user['username'], maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)))),
                          ]),
                          if (pl['event_date'] != null && pl['event_date'].toString().isNotEmpty) Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(children: [
                              const Icon(Icons.event_outlined, size: 12, color: AppColors.accentLight),
                              const SizedBox(width: 4),
                              Flexible(child: Text(_formatEventDate(pl['event_date']), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accentLight)))),
                            ]),
                          ),
                          const SizedBox(height: 6),
                          Text('${_formatInt(_items.length)} bài', style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
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
                      itemBuilder: (ctx, i) {
                        final r = _related[i];
                        final thumb = r['thumbnail']?['url'];
                        final total = r['items']?['paginatorInfo']?['total'] ?? 0;
                        final ev = r['event_date'];
                        return InkWell(
                          onTap: () => context.push('/playlist/${r['id']}'),
                          child: SizedBox(
                            width: 130,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: thumb != null
                                    ? CachedNetworkImage(imageUrl: thumb, width: 130, height: 130, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(width: 130, height: 130, color: AppColors.surfaceLight, child: const Icon(Icons.queue_music, color: AppColors.textMuted)))
                                    : Container(width: 130, height: 130, color: AppColors.surfaceLight, child: const Icon(Icons.queue_music, color: AppColors.textMuted)),
                              ),
                              const SizedBox(height: 6),
                              Text(r['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3))),
                              const SizedBox(height: 2),
                              if (ev != null && ev.toString().isNotEmpty)
                                Text(_formatEventDate(ev), style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accentLight)))
                              else if (total > 0)
                                Text('$total bài', style: body(const TextStyle(fontSize: 10, color: AppColors.textMuted))),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 16),
                CommentSection(type: 'playlist', id: widget.id),
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
