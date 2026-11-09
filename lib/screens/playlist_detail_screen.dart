import 'dart:ui' as ui;
import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, PillButton, OfflineBlock, EmptyBlock, NetImage;
import '../widgets/desktop_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/activity.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';
import '../widgets/comment_section.dart';
import '../widgets/shimmer.dart';
import '../widgets/section_header.dart';
import '../widgets/playlist_cover.dart';
import '../services/friendly_error.dart';

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
  bool _failed = false;
  /// Real number of songs in the playlist (the list itself is capped at 200).
  int _itemTotal = 0;
  bool _descOpen = false;
  /// Long playlists show 20 songs, then 20 more per "Xem thêm".
  int _shown = 20;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _failed = false; });
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        playlist(id: $id) {
          id slug title description event_date is_system is_public thumbnail { url } user { id username avatar { url } }
          items(first: 200, orderBy: [{column: "position", order: ASC}]) {
            data {
              id position type
              object {
                __typename
                ... on Song { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } sheet { year composers(first: 2) { data { id slug title } } } }
                ... on Folk { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } recomposers(first: 2) { data { id slug title } } }
                ... on Instrumental { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } sheet { year composers(first: 2) { data { id slug title } } } }
                ... on Poem { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } poets(first: 2) { data { id slug title } } }
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
        m['_itemId'] = entry['id']?.toString();
        if (m['users']?['data'] != null && m['artists'] == null) {
          m['artists'] = {'data': ((m['users']['data']) as List).map((u) => {'id': u['id'], 'title': u['username']}).toList()};
        }
        items.add(m);
      }
      if (!mounted) return;
      final plMap = Map<String, dynamic>.from(pl);
      final rawTotal = pl['items']?['paginatorInfo']?['total'];
      setState(() {
        _playlist = plMap;
        _items = items;
        _itemTotal = rawTotal is int && rawTotal > items.length ? rawTotal : items.length;
        _loading = false;
      });
      logActivity(context.read<AuthProvider>(), 'view', 'playlist', plMap['id']);
      _fetchRelated(plMap);
    } catch (_) { if (mounted) setState(() { _loading = false; _failed = true; }); }
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
          data { id slug title event_date thumbnail { url } user { username } items(first: 1) { paginatorInfo { total } } }
        }
      }''', {'where': where});
      final list = ((data['playlists']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() => _related = list);
    } catch (_) {}
  }

  /// The owner, or BQT (manage_playlist), may change the playlist.
  int get _visible => _shown < _items.length ? _shown : _items.length;

  bool _canEdit(Map<String, dynamic> pl) {
    final auth = context.watch<AuthProvider>();
    final me = auth.user?['id']?.toString();
    return auth.isAuthenticated && ((me != null && me == pl['user']?['id']?.toString()) || auth.hasPermission('manage_playlist'));
  }

  Future<void> _edit() async {
    final r = await context.push<String>('/playlist/${widget.id}/sua');
    if (!mounted) return;
    if (r == 'deleted') {
      context.pop('deleted');
    } else if (r == 'saved') {
      _fetch();
    }
  }

  Future<void> _remove(Map<String, dynamic> song) async {
    final itemId = song['_itemId'];
    if (itemId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final at = _items.indexOf(song);
    setState(() { _items.remove(song); _itemTotal--; });
    try {
      await context.read<AuthProvider>().authedMutate(
        r'mutation($id: ID!, $item: ID!) { updatePlaylist(input: {id: $id, items: {delete: [$item]}}) { id } }',
        {'id': widget.id, 'item': itemId},
      );
      messenger.showSnackBar(SnackBar(content: Text('Đã bỏ “${song['title']}” khỏi playlist')));
    } catch (e) {
      if (!mounted) return;
      setState(() { _items.insert(at.clamp(0, _items.length), song); _itemTotal++; });
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error));
    }
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
          leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          title: Text('Playlist'),
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
        appBar: AppBar(backgroundColor: AppColors.bg, title: const Text('Playlist'), centerTitle: true, leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context))),
        body: Center(
          child: _failed
              ? OfflineBlock(onRetry: _fetch)
              : const EmptyBlock(icon: Icons.queue_music_rounded, title: 'Không tìm thấy playlist', message: 'Playlist có thể đã bị xoá hoặc để riêng tư.'),
        ),
      );
    }
    final pl = _playlist!;
    final thumb = pl['thumbnail']?['url'];
    final user = pl['user'];
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final canEdit = _canEdit(pl);
    // Apple Music-style scale-up: bigger artwork + display type on desktop.
    final thumbSize = isDesktop ? 200.0 : 120.0;
    final titleSize = isDesktop ? 32.0 : 19.0;
    const usernameSize = 15.0;
    // Tier-3 (golden ratio anchored on 32 → 14 → 11). Mobile shrinks one
    // notch since the hero is narrower.
    // Floor of 14 on mobile for older readers.
    const metaSize = 14.0;
    if (isDesktop) return _buildDesk(context, player, pl, canEdit);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.bg,
              title: Text('Playlist'),
              centerTitle: true,
              leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
              actions: [
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(backgroundColor: AppColors.surface, foregroundColor: AppColors.text, minimumSize: const Size(48, 40), shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 14)),
                      onPressed: _edit,
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: Text('Sửa', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                    ),
                  ),
              ],
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(isDesktop ? 32 : 20, isDesktop ? 16 : 8, isDesktop ? 32 : 20, 24),
              sliver: SliverList(delegate: SliverChildListDelegate([
                // Hero
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: thumbSize, height: thumbSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(isDesktop ? 12 : 16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4 * AppColors.shadowMul), blurRadius: 18, offset: const Offset(0, 8))],
                      ),
                      child: PlaylistCover(
                        thumb: thumb?.toString(),
                        songThumbs: [for (final s in _items.take(4)) if (s['thumbnail']?['url'] != null) s['thumbnail']['url'].toString()],
                        size: thumbSize,
                        radius: isDesktop ? 12 : 16,
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
                              fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                            )),
                          ),
                          const SizedBox(height: 6),
                          Text(pl['title'] ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: titleSize, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.15, letterSpacing: -0.3))),
                          const SizedBox(height: 14),
                          if (user?['username'] != null) Row(children: [
                            CircleAvatar(
                              radius: isDesktop ? 13 : 10,
                              backgroundColor: AppColors.surfaceLight,
                              backgroundImage: user['avatar']?['url'] != null ? CachedNetworkImageProvider(cdnImg((user['avatar']['url']).toString(), 160)) : null,
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: Text(user['username'], maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: usernameSize, color: AppColors.textSecondary, fontWeight: FontWeight.w600)))),
                          ]),
                          if (pl['event_date'] != null && pl['event_date'].toString().isNotEmpty) Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(children: [
                              Icon(Icons.event_outlined, size: isDesktop ? 14 : 12, color: AppColors.accentLight),
                              const SizedBox(width: 4),
                              Flexible(child: Text(_formatEventDate(pl['event_date']), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: metaSize, fontWeight: FontWeight.w600, color: AppColors.accentLight)))),
                            ]),
                          ),
                          const SizedBox(height: 6),
                          Row(children: [
                            Text('${_formatInt(_itemTotal)} bài', style: body(TextStyle(fontSize: metaSize, color: AppColors.textSecondary))),
                            // Only the owner / BQT need to know: the others see it either way.
                            if (canEdit) ...[
                              Text(' · ', style: body(TextStyle(fontSize: metaSize, color: AppColors.textSecondary))),
                              Icon(pl['is_public']?.toString() == '1' ? Icons.public_rounded : Icons.visibility_off_outlined, size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Flexible(child: Text(pl['is_public']?.toString() == '1' ? 'Công khai' : 'Không công khai', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: metaSize, color: AppColors.textSecondary)))),
                            ],
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
                if (pl['description'] != null && (pl['description'] as String).isNotEmpty) _Clamped(
                  open: _descOpen,
                  long: _isLong(pl['description'] as String),
                  onToggle: () => setState(() => _descOpen = !_descOpen),
                  child: Html(
                    data: pl['description'],
                    style: {
                      'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero, fontSize: FontSize(16), lineHeight: const LineHeight(1.6), color: AppColors.text, fontFamily: body().fontFamily),
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
                  Expanded(child: PillButton(onTap: () => _playAll(), icon: Icons.play_arrow, label: 'Phát tất cả', primary: true)),
                  const SizedBox(width: 10),
                  Expanded(child: PillButton(onTap: () => _playAll(shuffle: true), icon: Icons.shuffle, label: 'Ngẫu nhiên', primary: false)),
                ]),
                const SizedBox(height: 8),
              ])),
            ),
            if (_items.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Playlist trống', style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)))))
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i == _visible) {
                      final more = _items.length - _visible;
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextButton(
                          style: TextButton.styleFrom(backgroundColor: AppColors.surface, foregroundColor: AppColors.text, minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
                          onPressed: () => setState(() => _shown += 20),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('Xem thêm ${more > 20 ? '20' : '$more'} bài', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                            const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                          ]),
                        ),
                      );
                    }
                    final song = _items[i];
                    return SongRow(
                      song: song,
                      index: i,
                      showIndex: true,
                      onTap: () => _playAll(startIndex: i),
                      onRemove: canEdit && song['_itemId'] != null ? () => _remove(song) : null,
                    );
                  },
                  childCount: _visible + (_visible < _items.length ? 1 : 0),
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
                        Divider(color: AppColors.border, height: 1),
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
                      Icon((pl['event_date'] != null && pl['event_date'].toString().isNotEmpty) ? Icons.event_outlined : Icons.queue_music_outlined, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        (pl['event_date'] != null && pl['event_date'].toString().isNotEmpty) ? 'Playlist sự kiện khác' : 'Playlist khác',
                        style: display(TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 220,
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
                  Divider(color: AppColors.border, height: 1),
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

  bool _isEvent(Map pl) => pl['event_date'] != null && pl['event_date'].toString().isNotEmpty;

  Widget? _description(Map pl) {
    final d = pl['description'];
    if (d is! String || d.isEmpty) return null;
    return _Clamped(
      open: _descOpen,
      long: _isLong(d),
      onToggle: () => setState(() => _descOpen = !_descOpen),
      child: Html(
        data: d,
        style: {
          'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero, fontSize: FontSize(16), lineHeight: const LineHeight(1.6), color: AppColors.text, fontFamily: body().fontFamily),
          'p': Style(margin: Margins.only(bottom: 8)),
          'a': Style(color: AppColors.accentLight, textDecoration: TextDecoration.none),
          'br': Style(margin: Margins.zero),
          'img': Style(width: Width(100, Unit.percent)),
        },
        onLinkTap: (url, _, _) {
          if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        },
      ),
    );
  }

  /// Desktop: a dark band like the song page (cover, title, owner, actions),
  /// songs as a table, and "Playlist khác" beside the list when it fits.
  Widget _buildDesk(BuildContext context, PlayerProvider player, Map<String, dynamic> pl, bool canEdit) {
    final thumb = pl['thumbnail']?['url'];
    final user = pl['user'];
    final isPublic = pl['is_public']?.toString() == '1';
    const light = Color(0xFFF6E8DE);
    final meta = body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: light));
    final desc = _description(pl);

    final band = ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(children: [
        Positioned.fill(child: Container(color: const Color(0xFF2E080A))),
        if (thumb != null)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: NetImage(url: thumb.toString(), tint: true),
            ),
          ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x592E080A), Color(0xE62E080A)])),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(28),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              width: 200, height: 200,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 14))]),
              child: PlaylistCover(
                thumb: thumb?.toString(),
                songThumbs: [for (final s in _items.take(4)) if (s['thumbnail']?['url'] != null) s['thumbnail']['url'].toString()],
                size: 200,
                radius: 18,
              ),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(_isEvent(pl) ? 'PLAYLIST SỰ KIỆN' : 'PLAYLIST', style: body(const TextStyle(fontSize: 13, letterSpacing: 1, fontWeight: FontWeight.w800, color: light))),
                const SizedBox(height: 8),
                Text(pl['title'] ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, height: 1.12, letterSpacing: -0.7))),
                const SizedBox(height: 12),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
                  if (user?['username'] != null) ...[
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.white24,
                      backgroundImage: user['avatar']?['url'] != null ? CachedNetworkImageProvider(cdnImg((user['avatar']['url']).toString(), 160)) : null,
                    ),
                    Text('${user['username']}', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white))),
                  ],
                  if (_isEvent(pl)) Text('· ${_formatEventDate(pl['event_date'])}', style: meta),
                  // Public / private only matters to the owner or BQT, as on the phone.
                  Text('· ${_formatInt(_itemTotal)} bài${canEdit ? ' · ${isPublic ? 'Công khai' : 'Không công khai'}' : ''}', style: meta),
                ]),
                const SizedBox(height: 18),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  if (_items.isNotEmpty) ...[
                    _BandPill(icon: Icons.play_arrow_rounded, label: 'Phát tất cả', primary: true, onTap: () => _playAll()),
                    _BandPill(icon: Icons.shuffle_rounded, label: 'Ngẫu nhiên', onTap: () => _playAll(shuffle: true)),
                  ],
                  if (canEdit) _BandPill(icon: Icons.edit_rounded, label: 'Sửa', onTap: _edit),
                ]),
              ]),
            ),
          ]),
        ),
      ]),
    );

    final songs = <Widget>[
      if (_items.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 48), child: Center(child: Text('Playlist trống', style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)))))
      else ...[
        const SongTableHead(),
        for (var i = 0; i < _visible; i++)
          SongRow(
            song: _items[i],
            index: i,
            showIndex: true,
            onTap: () => _playAll(startIndex: i),
            onRemove: canEdit && _items[i]['_itemId'] != null ? () => _remove(_items[i]) : null,
          ),
        if (_visible < _items.length)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextButton(
              style: TextButton.styleFrom(backgroundColor: AppColors.surface, foregroundColor: AppColors.text, minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
              onPressed: () => setState(() => _shown += 20),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Xem thêm ${_items.length - _visible > 20 ? '20' : '${_items.length - _visible}'} bài', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              ]),
            ),
          ),
      ],
      const SizedBox(height: 28),
      Divider(color: AppColors.border, height: 1),
      const SizedBox(height: 16),
      CommentSection(type: 'playlist', id: widget.id),
    ];

    final related = _related.isEmpty
        ? null
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(
              icon: _isEvent(pl) ? Icons.event_outlined : Icons.queue_music_outlined,
              title: _isEvent(pl) ? 'Playlist sự kiện khác' : 'Playlist khác',
              count: '(${_related.length})',
            ),
            ..._related.take(8).map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RelatedCardCompact(item: r, formatEventDate: _formatEventDate),
                )),
          ]);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        DeskFrame(
          child: ListView(
            padding: deskPad.copyWith(bottom: player.currentSong != null ? 110 : 48),
            children: [
              band,
              ?desc,
              const SizedBox(height: 24),
              // The table needs ~760 px: the sidebar sits beside it only on
              // wide windows, otherwise it follows the comments.
              LayoutBuilder(builder: (context, c) {
                if (related != null && c.maxWidth >= 1150) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: songs)),
                    const SizedBox(width: 28),
                    SizedBox(width: 340, child: related),
                  ]);
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ...songs.take(songs.length - 3),
                  // Below the songs, above the comments.
                  if (related != null) ...[related, const SizedBox(height: 12)],
                  ...songs.skip(songs.length - 3),
                ]);
              }),
            ],
          ),
        ),
        if (player.currentSong != null)
          const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}

/// Action on the dark playlist band: light fill for the main one, glass
/// for the rest (the wine PillButton would vanish on the wine band).
class _BandPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _BandPill({required this.icon, required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final fg = primary ? AppColors.wine : Colors.white;
    return Material(
      color: primary ? Colors.white : Colors.white.withValues(alpha: 0.16),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: SizedBox(
            height: 46,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(width: 8),
              Text(label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: fg))),
            ]),
          ),
        ),
      ),
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
                ? CachedNetworkImage(imageUrl: cdnImg((thumb).toString(), 140), width: 56, height: 56, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(width: 56, height: 56, color: AppColors.surfaceLight, child: Icon(Icons.queue_music, color: AppColors.textMuted)))
                : Container(width: 56, height: 56, color: AppColors.surfaceLight, child: Icon(Icons.queue_music, color: AppColors.textMuted)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3))),
                const SizedBox(height: 3),
                if (ev != null && ev.toString().isNotEmpty)
                  Text(formatEventDate(ev), style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.accentLight)))
                else
                  _OwnerLine(owner: item['user']?['username']?.toString(), total: total, size: 14),
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
                  ? CachedNetworkImage(imageUrl: cdnImg((thumb).toString(), 640), fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: AppColors.surfaceLight, child: Icon(Icons.queue_music, color: AppColors.textMuted)))
                  : Container(color: AppColors.surfaceLight, child: Icon(Icons.queue_music, color: AppColors.textMuted)),
              ),
            ),
            const SizedBox(height: 6),
            Text(item['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3))),
            const SizedBox(height: 2),
            if (ev != null && ev.toString().isNotEmpty)
              Text(formatEventDate(ev), maxLines: 1, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentLight)))
            else
              _OwnerLine(owner: item['user']?['username']?.toString(), total: total, size: 13),
          ],
        ),
      ),
    );
  }
}

/// About four lines of giới thiệu or more (pictures count as long).
bool _isLong(String html) {
  if (RegExp(r'<img', caseSensitive: false).hasMatch(html)) return true;
  final text = html.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length > 170 || RegExp(r'<(br|/p)', caseSensitive: false).allMatches(html).length > 3;
}

/// Long giới thiệu: four lines fading out + "Xem thêm"; open: all + "Thu gọn".
class _Clamped extends StatelessWidget {
  final bool open;
  final bool long;
  final VoidCallback onToggle;
  final Widget child;
  const _Clamped({required this.open, required this.long, required this.onToggle, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!long) return Padding(padding: const EdgeInsets.only(top: 14), child: child);
    final lines = MediaQuery.textScalerOf(context).scale(16) * 1.6 * 4;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (open)
          child
        else
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Colors.black, Colors.transparent], stops: [0, 0.7, 1]).createShader(r),
            blendMode: BlendMode.dstIn,
            child: ConstrainedBox(constraints: BoxConstraints(maxHeight: lines), child: ClipRect(child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: child))),
          ),
        TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 40), foregroundColor: AppColors.accentLight),
          onPressed: onToggle,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(open ? 'Thu gọn' : 'Xem thêm', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
            Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 20),
          ]),
        ),
      ]),
    );
  }
}

/// "3 bài · Nguyễn Huy" under a related playlist, as in Playlist cộng đồng:
/// a long name is cut, the count always shows.
class _OwnerLine extends StatelessWidget {
  final String? owner;
  final dynamic total;
  final double size;
  const _OwnerLine({this.owner, this.total, required this.size});

  @override
  Widget build(BuildContext context) {
    final st = body(TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: AppColors.textMuted));
    final n = total is int ? total as int : 0;
    final count = n > 0 ? '$n bài' : '';
    if (owner == null || owner!.isEmpty) return Text(count, maxLines: 1, style: st);
    return Row(children: [
      if (count.isNotEmpty) Text('$count · ', maxLines: 1, softWrap: false, style: st),
      Flexible(child: Text(owner!, maxLines: 1, overflow: TextOverflow.ellipsis, style: st)),
    ]);
  }
}
