import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_html/flutter_html.dart';
import '../services/share.dart';
import '../widgets/share_card.dart';
import '../constants/theme.dart';
import '../widgets/ui.dart';
import '../widgets/lyrics_text.dart';
import '../widgets/synced_video.dart';
import '../services/offline_store.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import '../services/activity.dart';
import '../services/player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_admin_actions.dart';
import '../widgets/comment_section.dart';
import '../widgets/sheet_lightbox.dart';
import '../widgets/playlist_dialog.dart';
import '../widgets/shimmer.dart';
import '../widgets/timed_lyrics.dart';
import '../widgets/section_header.dart';
import '../widgets/file_history_dialog.dart';
import '../widgets/lyric_history_dialog.dart';

class SongDetailScreen extends StatefulWidget {
  final String songId;
  final String fileType;
  final Map<String, dynamic>? initialSong;
  /// Optional comment id to deep-link to. CommentSection paginates
  /// until it surfaces, then scrolls + flashes a highlight on it.
  final String? highlightCommentId;
  /// Open scrolled to the comment box ("Góp tay": write what you know).
  final bool scrollToComments;
  const SongDetailScreen({super.key, required this.songId, this.fileType = 'song', this.initialSong, this.highlightCommentId, this.scrollToComments = false});

  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen> {
  Map<String, dynamic>? _song;
  List<dynamic> _suggestions = [];
  List<dynamic> _sameSheet = [];
  List<dynamic> _artistSongs = [];
  List<dynamic> _composerSongs = [];
  List<dynamic> _lyricEditors = [];
  List<String> _sheetImages = [];
  /// Per-image credit caption (e.g. "Bản nhạc: ten-user"). Aligned 1:1 with
  /// [_sheetImages] — empty string means "no credit available".
  List<String?> _sheetCaptions = [];
  bool _isLoved = false;
  // Real number of likes (paginatorInfo.total): the list itself stops at 100.
  int _loveTotal = 0;
  bool _loveBusy = false;
  bool _loading = true;
  // Drives the sticky-title appbar — flips to true once the user has
  // scrolled past the hero so the appbar can swap "CHI TIẾT" for the
  // song title. Listened on the main scroll controller.
  bool _showStickyTitle = false;
  final ScrollController _scrollCtl = ScrollController();
  bool _descExpanded = false;
  bool _storyExpanded = false;
  // Best long comment, shown as the song's story while it has none.
  Map<String, dynamic>? _memberStory;
  bool _lyricsExpanded = false;
  bool _sameSheetExpanded = false;
  bool _karaokeExpanded = false;

  @override
  void initState() {
    super.initState();
    _song = widget.initialSong != null ? Map<String, dynamic>.from(widget.initialSong!) : null;
    _scrollCtl.addListener(_onScroll);
    _fetch();
  }

  @override
  void dispose() {
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    super.dispose();
  }

  /// True khi bài hiện tại là video và đã có URL video để phát.
  bool get _isVideoSong =>
      _song?['play_type']?.toString() == 'video' &&
      (_song?['file']?['video_url']?.toString().isNotEmpty ?? false);

  void _onScroll() {
    // Hero is ~280-380px tall on desktop / square on mobile. Flip the
    // sticky title once the hero is roughly half-scrolled out so the
    // header doesn't fight with the inline song title.
    final shouldShow = _scrollCtl.offset > 220;
    if (shouldShow != _showStickyTitle) {
      setState(() => _showStickyTitle = shouldShow);
    }
  }

  /// Same id *and* kind: folk #3256 and tân nhạc #3256 are different songs.
  bool _isThisSong(Map? current) =>
      current != null && current['id']?.toString() == widget.songId && songKind(current) == _resolvedType;

  String get _resolvedType {
    // Priority: fetched song > navigation extras > widget default. The
    // fetched value is authoritative once data lands, so the UI matches
    // what the API returned even if extras were missing/stale.
    // `file_type` straight from the API is "audio"/"video", not a kind —
    // skip such values instead of letting them hide the next candidate.
    const kinds = ['song', 'folk', 'instrumental', 'poem', 'karaoke'];
    for (final c in [_song?['file_type'], widget.initialSong?['file_type'], widget.initialSong?['__typename']?.toString().toLowerCase(), widget.fileType]) {
      if (kinds.contains(c?.toString())) return c.toString();
    }
    return 'song';
  }

  /// Build the per-type GraphQL query for a song detail. Returned tuple
  /// is (queryString, dataKey).
  (String, String) _queryForType(String type) {
    String query; String dataKey;
    switch (type) {
        case 'folk':
          dataKey = 'folk';
          query = r'''query($id: ID!) { folk(id: $id) {
            id title subtitle slug content description views downloads file_type play_type record_year empty_file created_at
            thumbnail { id url caption }
            imageCreditor { id username }
            file { id is_hq source audio_url video_url duration created_at user { id username avatar { url } } }
            uploader { id username }
            accompaniment_instrument accompanists(first: 20) { data { id title slug avatar { url } } }
            uploads(orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: "approved"}]}) { id file { id audio_url is_hq created_at user { id username avatar { url } } } }
            sheet { id slug title year lyric_type content description }
            composers(first: 20) { data { id slug title avatar { url } } }
            recomposers(first: 20) { data { id slug title avatar { url } } }
            fcats(first: 10) { data { id slug title } }
            melodies(first: 10) { data { id slug title } }
            tags { id name slug }
            artists(first: 100) { data { id title slug avatar { url } } }
            loves(first: 100) { data { user_id user { id username avatar { url } } } paginatorInfo { total } }
          } }''';
          break;
        case 'instrumental':
          dataKey = 'instrumental';
          query = r'''query($id: ID!) { instrumental(id: $id) {
            id title subtitle slug content description views downloads file_type play_type record_year empty_file created_at
            thumbnail { id url caption }
            imageCreditor { id username }
            file { id is_hq source audio_url video_url duration created_at user { id username avatar { url } } }
            uploader { id username }
            accompaniment_instrument accompanists(first: 20) { data { id title slug avatar { url } } }
            uploads(orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: "approved"}]}) { id file { id audio_url is_hq created_at user { id username avatar { url } } } }
            sheet { id slug title year lyric_type content description }
            composers(first: 20) { data { id slug title avatar { url } } }
            tags { id name slug }
            artists(first: 100) { data { id title slug avatar { url } } }
            loves(first: 100) { data { user_id user { id username avatar { url } } } paginatorInfo { total } }
          } }''';
          break;
        case 'poem':
          dataKey = 'poem';
          query = r'''query($id: ID!) { poem(id: $id) {
            id title subtitle slug content description views downloads file_type play_type record_year empty_file created_at
            thumbnail { id url caption }
            imageCreditor { id username }
            file { id is_hq source audio_url video_url duration created_at user { id username avatar { url } } }
            uploader { id username }
            accompaniment_instrument accompanists(first: 20) { data { id title slug avatar { url } } }
            sheet { id slug title year lyric_type content description }
            poets(first: 20) { data { id slug title avatar { url } } }
            tags { id name slug }
            artists(first: 100) { data { id title slug avatar { url } } }
            loves(first: 100) { data { user_id user { id username avatar { url } } } paginatorInfo { total } }
          } }''';
          break;
        case 'karaoke':
          dataKey = 'karaoke';
          query = r'''query($id: ID!) { karaoke(id: $id) {
            id title subtitle slug content description views downloads file_type play_type record_year empty_file created_at
            thumbnail { id url caption }
            imageCreditor { id username }
            file { id is_hq source audio_url video_url duration created_at user { id username avatar { url } } }
            uploader { id username }
            accompaniment_instrument accompanists(first: 20) { data { id title slug avatar { url } } }
            sheet { id slug title year lyric_type content description tags { id name slug } composers(first: 20) { data { id slug title avatar { url } } } poets(first: 20) { data { id slug title avatar { url } } } }
            song { id slug title }
            users(first: 100) { data { id username avatar { url } } }
            loves(first: 100) { data { user_id user { id username avatar { url } } } paginatorInfo { total } }
          } }''';
          break;
        default:
          dataKey = 'song';
          query = r'''query($id: ID!) { song(id: $id) {
            id title subtitle slug content description views downloads file_type play_type record_year empty_file created_at
            thumbnail { id url caption }
            imageCreditor { id username }
            file { id is_hq source audio_url video_url duration created_at user { id username avatar { url } } }
            uploader { id username }
            accompaniment_instrument accompanists(first: 20) { data { id title slug avatar { url } } }
            uploads(orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: "approved"}]}) { id file { id audio_url is_hq created_at user { id username avatar { url } } } }
            sheet { id slug title year lyric_type content description tags { id name slug } composers(first: 20) { data { id slug title avatar { url } } } poets(first: 20) { data { id slug title avatar { url } } } }
            artists(first: 100) { data { id title slug avatar { url } } }
            loves(first: 100) { data { user_id user { id username avatar { url } } } paginatorInfo { total } }
          } }''';
    }
    return (query, dataKey);
  }

  /// [fresh]: reload after a CTV edit — authed POST (skips the CDN cache),
  /// no autoplay, no extra view log.
  Future<void> _fetch({bool fresh = false}) async {
    try {
      final type = _resolvedType;
      // IDs are NOT unique across song/folk/instrumental/poem/karaoke
      // tables — falling through to other types when one returns null
      // would silently load the wrong record. Trust the preferred type
      // strictly; fix the upstream extras instead.
      final pair = _queryForType(type);
      final data = fresh
          ? await context.read<AuthProvider>().authedQuery(pair.$1, {'id': widget.songId})
          : await ApiClient.query(pair.$1, {'id': widget.songId});
      if (!mounted) return;
      final raw = data[pair.$2];
      Map<String, dynamic>? s = raw == null ? null : Map<String, dynamic>.from(raw as Map);
      if (s != null) {
        final auth = context.read<AuthProvider>();
        final userId = auth.user?['id'];
        final loves = s['loves']?['data'] ?? [];
        // Normalize: copy type-specific fields into sheet/artists shape used by render
        final normalized = Map<String, dynamic>.from(s);
        normalized['file_type'] = type;
        // Ensure sheet has the meta fields render expects
        final sheet = normalized['sheet'] != null ? Map<String, dynamic>.from(normalized['sheet'] as Map) : <String, dynamic>{};
        // For folk/instrumental/poem, composers/poets/tags live at root level
        if (normalized['composers'] != null && sheet['composers'] == null) sheet['composers'] = normalized['composers'];
        if (normalized['poets'] != null && sheet['poets'] == null) sheet['poets'] = normalized['poets'];
        if (normalized['tags'] != null && sheet['tags'] == null) {
          // Folk/Instrumental/Poem return `tags` as a plain list at root.
          // Karaoke/Song nest it under sheet (already handled). Both shapes
          // are normalised into a List on sheet['tags'].
          final t = normalized['tags'];
          sheet['tags'] = t is List ? t : (t is Map ? (t['data'] ?? []) : []);
        }
        if (normalized['recomposers'] != null) sheet['recomposers'] = normalized['recomposers'];
        if (normalized['fcats'] != null) sheet['fcats'] = normalized['fcats'];
        if (normalized['melodies'] != null) sheet['melodies'] = normalized['melodies'];
        normalized['sheet'] = sheet;
        // Karaoke: convert users -> artists shape so existing render shows performers
        if (type == 'karaoke' && normalized['users']?['data'] != null && (normalized['artists']?['data'] ?? []).isEmpty) {
          normalized['artists'] = {
            'data': ((normalized['users']['data']) as List).map((u) => {
              'id': u['id'], 'title': u['username'], 'slug': u['username'], 'avatar': u['avatar'],
            }).toList(),
          };
        }
        if (widget.scrollToComments && !fresh) {
          Future.delayed(const Duration(milliseconds: 700), () {
            final ctx = _commentsKey.currentContext;
            if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic);
          });
        }
        final loveList = loves as List;
        final loveTotal = ((s['loves']?['paginatorInfo']?['total'] ?? loveList.length) as num).toInt();
        final lovedInList = userId != null && loveList.any((l) => l['user_id'].toString() == userId.toString());
        setState(() {
          _song = normalized;
          _loveTotal = loveTotal;
          if (userId != null) _isLoved = lovedInList;
        });
        // The list holds only the first 100 likes: past that, ask directly
        // whether this listener is one of them.
        if (userId != null && !lovedInList && loveTotal > loveList.length) _fetchMyLove(type, userId);

        final sheetId = sheet['id'];
        if (sheetId != null) {
          _fetchSameSheet(sheetId);
          _fetchSheetImages(sheetId, sheet['content']);
        }

        // These lists append, so a CTV reload (fresh) leaves them as they are.
        if (!fresh) {
          if (_plainEmpty(normalized['description']) && _plainEmpty(sheet['description'])) _fetchMemberStory(type);
          // Karaoke "artists" are members (user ids), not artists: looking
          // them up with artistByID would show some other artist's songs.
          if (type != 'karaoke') {
            final artists = (normalized['artists']?['data'] ?? []) as List;
            for (final a in artists) {
              if (a['id'] != null) _fetchArtistSongs(a['id']);
            }
          }

          final composers = (sheet['composers']?['data'] ?? []) as List;
          for (final c in composers) {
            _fetchComposerSongs(c['id']);
          }

          _fetchLyricEditors(type);
        }
      }
      if (!fresh) _fetchSuggestions();

      // Log view activity — mirrors web's SongDetailClient. Uses the
      // resolved type so folk/karaoke/etc. log to the right object_type.
      if (fresh) return;
      logActivity(context.read<AuthProvider>(), 'view', _resolvedType, _song?['id']);

      // Auto-play on detail visit. Source is read from the route's extra
      // map so callers can decide whether the navigation should count as
      // an intentional listen:
      //   * default `manual`  — song row tap, "Phát" button, recent
      //     listens etc. — counts in Nghe gần đây
      //   * `autoplay`        — search hit, "Bài gốc" karaoke link,
      //     suggestion click — plays so the user hears it but does NOT
      //     log to recentListens (PlayTracker filters by source)
      if (_song != null && mounted) {
        final player = context.read<PlayerProvider>();
        final isCurrent = _isThisSong(player.currentSong);
        // A song whose file is gone would only raise "Không phát được".
        final playable = _song!['empty_file'] != 1 && (_song!['file']?['audio_url'] != null || _song!['file']?['video_url'] != null);
        if (!isCurrent && playable) _play();
      }
      _failed = false;
    } catch (_) {
      _failed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _failed = false;

  List<String> _extractImages(String? html) {
    if (html == null) return [];
    final re = RegExp(r'<img[^>]+src="([^"]+)"', caseSensitive: false);
    return re.allMatches(html).map((m) => m.group(1)!).toList();
  }

  Future<void> _fetchSheetImages(dynamic sheetId, String? mainContent) async {
    final images = <String>[];
    final captions = <String?>[];
    try {
      final data = await ApiClient.query(
        r'''query($id: ID!) { sheet(id: $id) {
          uploader { id username }
          revisions(first: 20) { data { content uploader { id username } } }
        } }''',
        {'id': sheetId.toString()},
      );
      final sheetData = data['sheet'];
      final mainUploader = sheetData?['uploader']?['username'] as String?;
      final mainCaption = mainUploader == null ? null : 'Bản nhạc: $mainUploader';
      // Main content images use the sheet's primary uploader.
      for (final url in _extractImages(mainContent)) {
        images.add(url);
        captions.add(mainCaption);
      }
      // Each revision's images are credited to that revision's uploader.
      final revs = (sheetData?['revisions']?['data'] ?? []) as List;
      for (final rev in revs) {
        final revUser = rev['uploader']?['username'] as String?;
        final revCaption = revUser == null ? null : 'Bản nhạc: $revUser';
        for (final url in _extractImages(rev['content'])) {
          images.add(url);
          captions.add(revCaption);
        }
      }
    } catch (_) {
      // Fallback — if the credit query fails, still show images without captions.
      images.addAll(_extractImages(mainContent));
      captions.addAll(List.filled(images.length, null));
    }
    if (mounted) setState(() {
      _sheetImages = images;
      _sheetCaptions = captions;
    });
  }

  Future<void> _fetchSameSheet(dynamic sheetId) async {
    try {
      final data = await ApiClient.query(
        r'''query($id: ID!) { sheet(id: $id) {
          songs(first: 20) { data { id slug title subtitle views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } } }
          karaokes(first: 20) { data { id slug title subtitle views play_type thumbnail { url } file { audio_url video_url duration } users(first: 5) { data { id username avatar { url } } } } }
          instrumentals(first: 20) { data { id slug title subtitle views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } } }
        } }''',
        {'id': sheetId.toString()},
      );
      final sheet = data['sheet'];
      if (sheet != null) {
        final allSongs = <Map<String, dynamic>>[];
        for (final s in (sheet['songs']?['data'] ?? []) as List) {
          final m = Map<String, dynamic>.from(s);
          m['file_type'] = 'song';
          if (!_isThisSong(m)) allSongs.add(m);
        }
        for (final s in (sheet['karaokes']?['data'] ?? []) as List) {
          final m = Map<String, dynamic>.from(s);
          m['file_type'] = 'karaoke';
          // Karaoke API exposes performers as `users` (id+username+avatar);
          // SongRow + downstream UI read `artists`. Map shape so member
          // names render in "Thành viên hát bài này" rows.
          if (m['users']?['data'] != null && m['artists'] == null) {
            m['artists'] = {
              'data': ((m['users']['data']) as List).map((u) => {
                'id': u['id'],
                'title': u['username'],
                'slug': u['username'],
                'avatar': u['avatar'],
              }).toList(),
            };
          }
          if (!_isThisSong(m)) allSongs.add(m);
        }
        for (final s in (sheet['instrumentals']?['data'] ?? []) as List) {
          final m = Map<String, dynamic>.from(s);
          m['file_type'] = 'instrumental';
          if (!_isThisSong(m)) allSongs.add(m);
        }
        if (mounted) setState(() => _sameSheet = allSongs);
      }
    } catch (_) {}
  }

  Future<void> _fetchArtistSongs(dynamic artistId) async {
    try {
      final data = await ApiClient.query(
        r'''query($id: ID!) { artistByID(id: $id) { songs(first: 6, orderBy: [{column: "views", order: DESC}]) { data { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } } } } }''',
        {'id': artistId.toString()},
      );
      final songs = ((data['artistByID']?['songs']?['data'] ?? []) as List).where((x) => x['id'].toString() != widget.songId).toList();
      if (songs.isNotEmpty && mounted) setState(() {
        _artistSongs = [..._artistSongs, {'artistId': artistId, 'songs': songs}];
      });
    } catch (_) {}
  }

  Future<void> _fetchComposerSongs(dynamic composerId) async {
    try {
      final data = await ApiClient.query(
        r'''query($id: ID!) { composerByID(id: $id) { songs(first: 6, orderBy: [{column: "views", order: DESC}]) { data { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } } } } }''',
        {'id': composerId.toString()},
      );
      final songs = ((data['composerByID']?['songs']?['data'] ?? []) as List).where((x) => x['id'].toString() != widget.songId).toList();
      if (songs.isNotEmpty && mounted) setState(() {
        _composerSongs = [..._composerSongs, {'composerId': composerId, 'songs': songs}];
      });
    } catch (_) {}
  }

  Future<void> _fetchLyricEditors(String type) async {
    try {
      final data = await ApiClient.query(
        r'''query($where: WhereConditions) { activities(first: 20, orderBy: [{column: "id", order: DESC}], where: $where) { edges { node { user { id username avatar { url } } } } } }''',
        {'where': {'AND': [{'column': 'action', 'value': 'update_lyric'}, {'column': 'object_type', 'value': type}, {'column': 'object_id', 'value': widget.songId}]}},
      );
      final edges = (data['activities']?['edges'] ?? []) as List;
      final editors = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final e in edges) {
        final u = e['node']?['user'];
        if (u != null && !seen.contains(u['id'].toString())) {
          seen.add(u['id'].toString());
          editors.add(Map<String, dynamic>.from(u));
        }
      }
      if (mounted) setState(() => _lyricEditors = editors);
    } catch (_) {}
  }

  Future<void> _fetchMyLove(String type, dynamic userId) async {
    final uid = int.tryParse(userId.toString());
    if (uid == null) return;
    try {
      final d = await ApiClient.query(
        'query(\$id: ID!) { $type(id: \$id) { loves(first: 1, where: {column: "user_id", value: $uid}) { paginatorInfo { total } } } }',
        {'id': widget.songId},
      );
      final n = ((d[type]?['loves']?['paginatorInfo']?['total'] ?? 0) as num).toInt();
      if (mounted && n > 0 && !_loveBusy) setState(() => _isLoved = true);
    } catch (_) {}
  }

  Future<void> _fetchSuggestions() async {
    try {
      final data = await ApiClient.query(
        r'''query($id: ID!, $type: String!) {
          suggestSongs(first: 5, id: $id, type: $type) {
            __typename id title slug views file_type play_type
            thumbnail { url }
            file { audio_url video_url duration }
            ... on Song { subtitle artists(first: 100) { data { id title slug avatar { url } } } }
            ... on Folk { subtitle artists(first: 100) { data { id title slug avatar { url } } } }
            ... on Instrumental { subtitle artists(first: 100) { data { id title slug avatar { url } } } }
            ... on Poem { subtitle artists(first: 100) { data { id title slug avatar { url } } } }
            ... on Karaoke { subtitle users(first: 100) { data { id username avatar { url } } } }
          }
        }''',
        // Use resolved type so suggestions match the actual song type
        // (folk/instrumental/poem/karaoke), not the constructor default.
        {'id': widget.songId, 'type': _resolvedType},
      );
      // Stamp each suggestion's kind: the API's file_type is "audio", and an
      // unstamped folk/poem/karaoke row would play as the tân nhạc with the
      // same id.
      final list = ((data['suggestSongs'] ?? []) as List)
          .map((x) {
            final m = Map<String, dynamic>.from(x as Map);
            m['file_type'] = songKind(m, _resolvedType);
            return m;
          })
          .toList();
      if (!mounted) return;
      setState(() => _suggestions = list);
      // Refresh queue with suggestions now that they're loaded
      final player = context.read<PlayerProvider>();
      if (_isThisSong(player.currentSong)) {
        _updatePlayerQueue();
      }
    } catch (_) {}
  }

  void _updatePlayerQueue() {
    if (_song == null) return;
    final s = Map<String, dynamic>.from(_song!);
    s['audioUrl'] = _song!['file']?['audio_url'];
    final queue = <Map<String, dynamic>>[s];
    for (final x in _suggestions) {
      final m = Map<String, dynamic>.from(x);
      m['audioUrl'] = m['file']?['audio_url'];
      queue.add(m);
    }
    final player = context.read<PlayerProvider>();
    player.setQueue(queue, startIndex: 0);
    // Register auto-refill using suggestSongs with exceptIds
    player.setFetchMore(_fetchMoreSuggestions);
  }

  Future<List<Map<String, dynamic>>> _fetchMoreSuggestions(List<Map<String, dynamic>> currentQueue) async {
    try {
      final exceptIds = currentQueue.map((s) => s['id']).whereType<Object>().toList();
      final data = await ApiClient.query(
        r'''query($id: ID!, $type: String!, $exceptIds: Mixed) {
          suggestSongs(first: 5, id: $id, type: $type, exceptIds: $exceptIds) {
            __typename id title slug views file_type play_type
            thumbnail { url }
            file { audio_url video_url duration }
            ... on Song { subtitle artists(first: 100) { data { id title slug avatar { url } } } }
            ... on Folk { subtitle artists(first: 100) { data { id title slug avatar { url } } } }
            ... on Instrumental { subtitle artists(first: 100) { data { id title slug avatar { url } } } }
            ... on Poem { subtitle artists(first: 100) { data { id title slug avatar { url } } } }
            ... on Karaoke { subtitle users(first: 100) { data { id username avatar { url } } } }
          }
        }''',
        {'id': widget.songId, 'type': _resolvedType, 'exceptIds': exceptIds},
      );
      final list = ((data['suggestSongs'] ?? []) as List)
          .map((x) {
            final m = Map<String, dynamic>.from(x as Map);
            m['audioUrl'] = m['file']?['audio_url'];
            m['file_type'] = songKind(m, _resolvedType);
            return m;
          })
          .where((m) => m['audioUrl'] != null)
          .toList();
      return list;
    } catch (_) { return []; }
  }

  void _play({String? source}) {
    if (_song == null) return;
    final s = Map<String, dynamic>.from(_song!);
    s['audioUrl'] = _song!['file']?['audio_url'];
    final queue = <Map<String, dynamic>>[s];
    for (final x in _suggestions) {
      final m = Map<String, dynamic>.from(x);
      m['audioUrl'] = m['file']?['audio_url'];
      queue.add(m);
    }
    // Caller's source falls back to the navigation `extra._source` (set
    // when the route was pushed) and finally to 'manual' if nothing set.
    final effectiveSource = source ?? (widget.initialSong?['_source']?.toString()) ?? 'manual';
    context.read<PlayerProvider>().playSong(s, queue, effectiveSource);
  }

  /// Play a section's song list as the active queue. Used by the Phát tất
  /// cả CTA on related-section headers and artist banners.
  void _playList(List songs) {
    if (songs.isEmpty) return;
    final queue = <Map<String, dynamic>>[];
    for (final x in songs) {
      final m = Map<String, dynamic>.from(x as Map);
      m['audioUrl'] = m['file']?['audio_url'];
      queue.add(m);
    }
    context.read<PlayerProvider>().playSong(queue.first, queue);
  }

  Future<void> _share() async {
    if (_song == null) return;
    final memory = _memberStory?['plain']?.toString();
    final hook = firstLyricLine(_song!['content']) ??
        (memory == null ? null : (memory.length > 140 ? '${memory.substring(0, 138)}…' : memory));
    await showSongShareSheet(context, _song!, hook: hook, kind: _resolvedType);
  }

  void _showLoversSheet(List loves) {
    if (loves.isEmpty) return;
    final total = _loveTotal > loves.length ? _loveTotal : loves.length;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.7;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(children: [
                Icon(Icons.favorite, size: 18, color: AppColors.accentLight),
                const SizedBox(width: 8),
                Expanded(child: Text('$total người yêu thích', style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text)))),
                IconButton(icon: Icon(Icons.close, color: AppColors.textMuted), onPressed: () => Navigator.of(ctx).pop()),
              ]),
            ),
            Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: loves.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.borderSubtle, indent: 64),
                itemBuilder: (c, i) {
                  final l = loves[i] as Map;
                  final user = l['user'] as Map?;
                  final username = user?['username']?.toString() ?? 'Ẩn danh';
                  final avatar = user?['avatar']?['url']?.toString();
                  final id = user?['id'] ?? l['user_id'];
                  return InkWell(
                    onTap: id == null ? null : () { Navigator.of(c).pop(); context.push('/user/$id'); },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Row(children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceLight),
                          child: ClipOval(
                            child: avatar != null
                                ? CachedNetworkImage(imageUrl: cdnImg((avatar).toString(), 160), fit: BoxFit.cover, errorWidget: (_, _, _) => Icon(Icons.person, size: 18, color: AppColors.textMuted))
                                : Icon(Icons.person, size: 18, color: AppColors.textMuted),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(username, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)))),
                        Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }

  // Plain-text copy of the lyrics: strips HTML tags, removes [mm:ss.xx]
  // LRC timestamps so the user pastes a clean text-only version.
  Future<void> _copyLyrics(String raw) async {
    final stripped = raw
        .replaceAll(RegExp(r'\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]'), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (stripped.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: stripped));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép lời bài hát'), backgroundColor: AppColors.success, duration: Duration(seconds: 2)));
  }

  Future<void> _download() async {
    final auth = context.read<AuthProvider>();
    try {
      final data = auth.isAuthenticated
          ? await auth.authedMutate(
              r'''mutation($objectType: String!, $objectId: ID!) { download(object_type: $objectType, object_id: $objectId) { url } }''',
              {'objectType': _resolvedType, 'objectId': widget.songId},
            )
          : await ApiClient.mutate(
              r'''mutation($objectType: String!, $objectId: ID!) { download(object_type: $objectType, object_id: $objectId) { url } }''',
              {'objectType': _resolvedType, 'objectId': widget.songId},
            );
      final url = data['download']?['url'];
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bạn đã tải quá nhiều, thử lại sau'), backgroundColor: AppColors.error));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chưa tải về được. ${friendlyError(e)}'), backgroundColor: AppColors.error));
    }
  }

  void _openSheetLightbox(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SheetLightbox(images: _sheetImages, captions: _sheetCaptions, initialIndex: index)),
    );
  }

  /// Open the song's hero thumbnail in a lightbox with image credit caption.
  void _openArtworkLightbox() {
    final thumb = _song?['thumbnail']?['url'] as String?;
    if (thumb == null || thumb.isEmpty) return;
    final creditUser = _song?['imageCreditor']?['username'] as String?;
    final caption = creditUser == null ? null : 'Ảnh: $creditUser';
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SheetLightbox(images: [thumb], captions: [caption])),
    );
  }

  void _openPlaylistDialog() {
    showDialog(
      context: context,
      builder: (_) => PlaylistDialog(songId: widget.songId, type: _resolvedType),
    );
  }

  void _openFileHistory() {
    final uploads = (_song?['uploads'] ?? []) as List;
    if (uploads.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => FileHistoryDialog(
        uploads: uploads,
        currentFileId: _song?['file']?['id']?.toString(),
        songTitle: _song?['title']?.toString(),
        uploader: _song?['uploader'] is Map ? Map<String, dynamic>.from(_song!['uploader']) : null,
        songCreatedAt: _song?['created_at']?.toString(),
      ),
    );
  }

  void _openLyricHistory() {
    showDialog(
      context: context,
      builder: (_) => LyricHistoryDialog(
        songId: widget.songId,
        songType: _resolvedType,
      ),
    );
  }

  void _applyLove(bool liked, Map? user) {
    _isLoved = liked;
    _loveTotal = (_loveTotal + (liked ? 1 : -1)).clamp(0, 1 << 30);
    final loves = ((_song?['loves']?['data'] ?? []) as List).toList();
    if (user != null) {
      loves.removeWhere((l) => l['user_id'].toString() == user['id'].toString());
      if (liked) loves.insert(0, {'user_id': user['id'], 'user': user});
    }
    _song?['loves'] = {'data': loves, 'paginatorInfo': {'total': _loveTotal}};
  }

  Future<void> _toggleLove() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      await askLogin(context);
      return;
    }
    // A second tap while the first is still on its way would race it.
    if (_loveBusy) return;
    _loveBusy = true;
    final newLiked = !_isLoved;
    final user = auth.user;
    // Optimistic update
    setState(() => _applyLove(newLiked, user));
    try {
      await auth.authedMutate(
        newLiked
            // Folk / poem / karaoke pages must like their own record.
            ? 'mutation(\$id: ID!) { love(lovable_id: \$id, lovable_type: "$_resolvedType") { id } }'
            : 'mutation(\$id: ID!) { unlove(lovable_id: \$id, lovable_type: "$_resolvedType") { id } }',
        {'id': widget.songId},
      );
    } catch (e) {
      // Rollback, and say so: a heart that silently un-fills looks broken.
      if (mounted) {
        setState(() => _applyLove(!newLiked, user));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${newLiked ? 'Chưa yêu thích được' : 'Chưa bỏ yêu thích được'}. ${friendlyError(e)}'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      _loveBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _song == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg, elevation: 0,
          leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          title: Text('Chi tiết'),
          centerTitle: true,
        ),
        body: const SingleChildScrollView(child: Column(children: [
          HeroSkeleton(),
          Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SongListSkeleton(rows: 4)),
        ])),
      );
    }
    if (_song == null) {
      // A network failure is not "this song doesn't exist".
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(tooltip: 'Quay lại', icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => goBack(context))),
        body: Center(
          child: _failed
              ? OfflineBlock(onRetry: () { setState(() => _loading = true); _fetch(); })
              : const EmptyBlock(icon: Icons.music_off_outlined, title: 'Không tìm thấy bài hát', message: 'Bài có thể đã được gộp hoặc gỡ khỏi trang.'),
        ),
      );
    }

    final song = _song!;
    final artists = (song['artists']?['data'] ?? []) as List;
    final composers = (song['sheet']?['composers']?['data'] ?? []) as List;
    final poets = (song['sheet']?['poets']?['data'] ?? []) as List;
    final tags = (song['sheet']?['tags'] ?? []) as List;
    final loves = (song['loves']?['data'] ?? []) as List;
    final uploads = (song['uploads'] ?? []) as List;
    final thumb = song['thumbnail']?['url'];
    final lyrics = song['content'];
    final description = song['description'];
    final story = song['sheet']?['description'];
    final lyricType = song['sheet']?['lyric_type'];
    final year = (song['sheet']?['year']?.toString() ?? '').isEmpty ? null : song['sheet']['year'].toString();
    final recordYear = (song['record_year']?.toString() ?? '').isEmpty ? null : song['record_year'].toString();
    final emptyFile = song['empty_file'] == 1;
    // Nothing to play at all: the big button must not promise "Phát".
    // empty_file = 1 means BQT found the file gone (the URL 404s).
    final noMedia = emptyFile || ((song['file']?['audio_url'] ?? song['audioUrl']) == null && song['file']?['video_url'] == null);
    final player = context.watch<PlayerProvider>();
    final isCurrent = _isThisSong(player.currentSong);
    final w = MediaQuery.of(context).size.width;
    final hasPlayer = player.currentSong != null;
    final isDesktop = w >= 900;

    // Bài video → hình đồng bộ với trình phát nhạc thay ô artwork trong hero
    // (giống web). Player nhạc just_audio không render khung hình.
    // Video songs: sound always goes through the music player (keeps playing
    // with the screen off); while this song is the one playing, the hero
    // shows its picture in sync. Tap it for full screen.
    Widget? heroVideo;
    if (_isVideoSong && isCurrent) {
      heroVideo = GestureDetector(
        onTap: () => openFullScreenVideo(context, player, song),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            SyncedVideo(player: player, song: song),
            const Positioned(right: 10, bottom: 10, child: Icon(Icons.fullscreen_rounded, color: Colors.white, size: 28)),
          ]),
        ),
      );
    }

    // Meta block — composers/poets/performers/dates/tags. On desktop these
    // sit inside the hero info column (filling the right-of-artwork dead
    // space). On mobile they stack below the hero as before.
    // Inline credits row — every artistic fact (composer, poet, folk
    // recomposer/genre/melody, record year, upload date) folded into one
    // RichText so the hero reads like editorial credits rather than a
    // stacked "Label: Value" form. Each fact has a muted tiny label and is
    // separated by mid-dots.
    Widget? creditsRow;
    {
      final segs = <InlineSpan>[];
      final muted = TextStyle(color: AppColors.textMuted);
      void addSep() {
        if (segs.isNotEmpty) segs.add(TextSpan(text: '  ·  ', style: muted));
      }
      void addFact(String label, List<InlineSpan> linkSpans) {
        if (linkSpans.isEmpty) return;
        addSep();
        segs.add(TextSpan(text: '$label ', style: muted));
        segs.addAll(linkSpans);
      }

      if (composers.isNotEmpty) {
        addSep();
        segs.add(TextSpan(text: 'Sáng tác ', style: muted));
        segs.addAll(_linkRow(composers, 'title', (c) => context.push('/nhac-si/${c['slug']}')));
        if (year != null && isDesktop) segs.add(TextSpan(text: ' ($year)', style: muted));
      }
      // Folk extras
      final rec = (song['sheet']?['recomposers']?['data'] ?? song['recomposers']?['data'] ?? []) as List;
      addFact('Soạn giả', _linkRow(rec, 'title', (p) => context.push('/soan-gia/${p['slug']}')));
      final fcatsRaw = song['sheet']?['fcats'] ?? song['fcats'];
      final fcats = (fcatsRaw is Map ? (fcatsRaw['data'] ?? []) : (fcatsRaw ?? [])) as List;
      addFact('Thể loại', _linkRow(fcats, 'title', (f) => context.push('/dan-ca/${f['slug']}')));
      final melRaw = song['sheet']?['melodies'] ?? song['melodies'];
      final melodies = (melRaw is Map ? (melRaw['data'] ?? []) : (melRaw ?? [])) as List;
      addFact('Làn điệu', _linkRow(melodies, 'title', (m) => context.push('/lan-dieu/${m['slug']}')));
      if (poets.isNotEmpty && (_resolvedType == 'song' || _resolvedType == 'karaoke' || _resolvedType == 'poem')) {
        final poetLabel = lyricType != null && (lyricType as String).isNotEmpty ? lyricType : 'Thơ';
        addFact(poetLabel, _linkRow(poets, 'title', (p) => context.push('/nha-tho/${p['slug']}')));
      }
      if (recordYear != null && isDesktop) {
        addSep();
        segs.add(TextSpan(text: 'Thu ', style: muted));
        segs.add(TextSpan(text: recordYear, style: TextStyle(color: AppColors.accentLight, fontWeight: FontWeight.w600)));
      }
      if (song['created_at'] != null && isDesktop) {
        addSep();
        segs.add(TextSpan(text: 'Đăng ', style: muted));
        segs.add(TextSpan(text: _formatDate(song['created_at']), style: TextStyle(color: AppColors.accentLight, fontWeight: FontWeight.w600)));
      }
      if (segs.isNotEmpty) {
        creditsRow = Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: RichText(
        textScaler: MediaQuery.textScalerOf(context),
            text: TextSpan(
              style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary, height: 1.6)),
              children: segs,
            ),
          ),
        );
      }
    }

    final metaItems = <Widget>[
      if (creditsRow != null) creditsRow,
      // Trình bày — desktop already shows artists in the hero artist row,
      // so the duplicate meta line is suppressed there. Mobile keeps it
      // since the mobile hero only carries title + subtitle.
      if (artists.isNotEmpty && !isDesktop) _MetaLine(
        label: _resolvedType == 'karaoke' ? 'Thể hiện' : 'Trình bày',
        children: [
          ..._linkRow(artists, 'title', (a) {
            if (_resolvedType == 'karaoke') {
              final id = a['id'];
              if (id != null) context.push('/user/$id');
            } else {
              context.push('/nghe-si/${a['slug']}');
            }
          }),
          if (recordYear != null) TextSpan(text: ' ($recordYear)', style: TextStyle(color: AppColors.textMuted)),
        ],
      ),
      if (_resolvedType == 'karaoke' && song['song'] != null && song['song']['id'] != null)
        _MetaLine(
          label: 'Bài gốc',
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => context.push('/song/${song['song']['id']}', extra: {...?song['song'], 'file_type': 'song'}),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(song['song']['title'] ?? '', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.accentLight, decoration: TextDecoration.underline, decorationColor: AppColors.accent, decorationStyle: TextDecorationStyle.dotted))),
                ),
              ),
            ),
          ],
        ),
    ];
    final tagRowH = (28 + MediaQuery.textScalerOf(context).scale(18)).clamp(48.0, 120.0);
    final mobileTags = tags.isEmpty ? null : BleedRow(height: tagRowH, builder: (pad) => SizedBox(
      height: tagRowH,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: pad,
        itemCount: tags.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => BrandChip(label: '#${tags[i]['name'] ?? ''}', onTap: () => context.push('/tag/${tags[i]['slug']}')),
      ),
    ));

    // Credits kiểu web cho desktop hero: từng dòng "Nhãn: giá trị" đặt GIỮA
    // tiêu đề và stats. Style khớp web: nhãn 13px xám mờ (w500), giá trị 16px
    // đậm màu chữ (w700), KHÔNG gạch chân — dùng _webCreditLine/_creditLinkRow.
    final yearSpan = year != null
        ? TextSpan(text: ' ($year)', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w500)))
        : null;
    final desktopCredits = <Widget>[];
    if (composers.isNotEmpty) {
      desktopCredits.add(_webCreditLine('Sáng tác', [
        ..._creditLinkRow(composers, 'title', (c) => context.push('/nhac-si/${c['slug']}')),
        if (yearSpan != null) yearSpan,
      ]));
    }
    {
      final rec = (song['sheet']?['recomposers']?['data'] ?? song['recomposers']?['data'] ?? []) as List;
      if (rec.isNotEmpty) desktopCredits.add(_webCreditLine('Soạn giả', _creditLinkRow(rec, 'title', (p) => context.push('/soan-gia/${p['slug']}'))));
      final fcr = song['sheet']?['fcats'] ?? song['fcats'];
      final fc = (fcr is Map ? (fcr['data'] ?? []) : (fcr ?? [])) as List;
      if (fc.isNotEmpty) desktopCredits.add(_webCreditLine('Thể loại', _creditLinkRow(fc, 'title', (f) => context.push('/dan-ca/${f['slug']}'))));
      final mr = song['sheet']?['melodies'] ?? song['melodies'];
      final mel = (mr is Map ? (mr['data'] ?? []) : (mr ?? [])) as List;
      if (mel.isNotEmpty) desktopCredits.add(_webCreditLine('Làn điệu', _creditLinkRow(mel, 'title', (m) => context.push('/lan-dieu/${m['slug']}'))));
    }
    if (poets.isNotEmpty && (_resolvedType == 'song' || _resolvedType == 'karaoke' || _resolvedType == 'poem')) {
      final poetLabel = (lyricType != null && (lyricType as String).trim().isNotEmpty) ? lyricType.trim().replaceAll(RegExp(r':\s*$'), '') : 'Thơ';
      desktopCredits.add(_webCreditLine(poetLabel, _creditLinkRow(poets, 'title', (p) => context.push('/nha-tho/${p['slug']}'))));
    }
    if (artists.isNotEmpty) {
      desktopCredits.add(_webCreditLine(
        _resolvedType == 'karaoke' ? 'Thể hiện' : 'Trình bày',
        [
          ..._creditLinkRow(artists, 'title', (a) {
            if (_resolvedType == 'karaoke') { final id = a['id']; if (id != null) context.push('/user/$id'); }
            else if (a['slug'] != null) context.push('/nghe-si/${a['slug']}');
          }),
          // Record year ghép inline sau ca sĩ, dạng "(1991)" giống web.
          if (recordYear != null) TextSpan(text: ' ($recordYear)', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w500))),
        ],
      ));
    }
    if (_resolvedType == 'karaoke' && song['song'] != null && song['song']['id'] != null) {
      desktopCredits.add(_webCreditLine('Bài gốc', [
        WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GestureDetector(
          onTap: () => context.push('/song/${song['song']['id']}', extra: {...?song['song'], 'file_type': 'song'}),
          child: Text(song['song']['title'] ?? '', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
        )),
      ]));
    }
    final uploadDate = song['created_at'] != null ? _formatDate(song['created_at']) : null;
    final tagsWidget = tags.isEmpty ? null : Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 10, runSpacing: 0, children: tags.map<Widget>((t) => InkWell(
        onTap: () => context.push('/tag/${t['slug']}'),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          child: Text('#${t['name'] ?? ''}', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
        ),
      )).toList()),
    );

    final mainScroll = CustomScrollView(
            controller: _scrollCtl,
            slivers: [
              // 1. Sticky header — title swaps to the song name + artist
              // line once the user has scrolled past the hero, à la
              // Apple Music album pages.
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.bg,
                titleSpacing: 0,
                title: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _showStickyTitle
                      ? Column(
                          key: const ValueKey('song-title'),
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(song['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text))),
                            if (artists.isNotEmpty) Text(
                              artists.map((a) => a['title'] ?? a['username'] ?? '').join(', '),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: body(TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(key: ValueKey('label')),
                ),
                centerTitle: true,
                leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
                actions: [
                  // CTV tools (same menu as the web), only for members with a CTV permission.
                  if (canUseSongAdmin(context.watch<AuthProvider>()))
                    IconButton(
                      tooltip: 'Công cụ CTV',
                      icon: Icon(Icons.edit_note_rounded, color: AppColors.text),
                      onPressed: () => showSongAdminSheet(context, song: Map<String, dynamic>.from(song), type: _resolvedType, onRefresh: () => _fetch(fresh: true)),
                    ),
                  if (MediaQuery.of(context).size.width < 900)
                    IconButton(tooltip: 'Tuỳ chọn', icon: Icon(Icons.more_horiz_rounded, color: AppColors.text), onPressed: () => showSongActions(context, Map<String, dynamic>.from(song))),
                ],
              ),

              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 4),
                    // 2-3. HERO — desktop runs a horizontal Apple-Music-style
                    // split (artwork left, info column right with stats and
                    // labelled action cluster). Mobile keeps the full-bleed
                    // banner with title + play CTA stacked beneath.
                    if (isDesktop)
                      _DesktopHero(
                        song: song,
                        artists: artists,
                        resolvedType: _resolvedType,
                        isLoved: _isLoved,
                        loveCount: _loveTotal,
                        loves: loves,
                        hasUploads: uploads.isNotEmpty,
                        isCurrent: isCurrent,
                        isPlaying: player.isPlaying,
                        onPlay: () {
                          if (isCurrent) {
                            context.read<PlayerProvider>().togglePlay();
                          } else {
                            _play();
                          }
                        },
                        onLove: _toggleLove,
                        onDownload: _download,
                        onAddToPlaylist: _openPlaylistDialog,
                        onShare: _share,
                        onHistory: uploads.isNotEmpty ? _openFileHistory : null,
                        onShowLovers: () => _showLoversSheet(loves),
                        onArtistTap: (a) {
                          if (_resolvedType == 'karaoke') {
                            final id = a['id'];
                            if (id != null) context.push('/user/$id');
                          } else if (a['slug'] != null) {
                            context.push('/nghe-si/${a['slug']}');
                          }
                        },
                        onArtworkTap: heroVideo != null ? null : _openArtworkLightbox,
                        videoPlayer: heroVideo,
                        credits: desktopCredits.isEmpty ? null : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: desktopCredits),
                        uploadDate: uploadDate,
                        metaContent: tagsWidget,
                      )
                    else ...[
                      _MobileHeader(
                        song: song,
                        thumb: thumb,
                        kind: const {'song': 'Tân nhạc', 'folk': 'Dân ca', 'instrumental': 'Khí nhạc', 'poem': 'Tiếng thơ', 'karaoke': 'Thành viên hát'}[_resolvedType] ?? 'Bài hát',
                        year: year,
                        videoPlayer: heroVideo,
                        onArtworkTap: heroVideo != null ? null : _openArtworkLightbox,
                      ),
                      if (noMedia)
                        Container(
                          margin: const EdgeInsets.only(top: 14),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(Icons.info_outline_rounded, size: 22, color: AppColors.textSecondary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Bài này chưa có bản ghi âm để nghe. Bạn có bản thu? Chia sẻ trong bình luận để BQT bổ sung.',
                                style: body(TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w600, color: AppColors.text)),
                              ),
                            ),
                          ]),
                        ),
                      const SizedBox(height: 14),
                      ...metaItems,
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if ((song['views'] ?? 0) is num && (song['views'] ?? 0) > 0) '${formatViews((song['views'] as num).toInt())} lượt nghe',
                            if ((song['downloads'] ?? 0) is num && (song['downloads'] ?? 0) > 0) '${formatViews((song['downloads'] as num).toInt())} lượt tải',
                          ].join(' · '),
                          style: AppText.meta,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (noMedia)
                        Row(children: [
                          Expanded(
                            child: Builder(builder: (_) {
                              // Other recordings of this very song come first;
                              // only then fall back to similar songs.
                              final others = _sameSheet
                                  .where((x) => x['file_type'] == _resolvedType && x['id'].toString() != widget.songId && (x['file']?['audio_url'] != null || x['file']?['video_url'] != null))
                                  .map((x) => Map<String, dynamic>.from(x as Map))
                                  .toList();
                              return PillButton(
                                label: others.isNotEmpty ? 'Nghe bản thu khác (${others.length})' : 'Nghe bài tương tự',
                                icon: Icons.queue_music_rounded,
                                onTap: others.isNotEmpty ? () => _playList(others) : (_suggestions.isEmpty ? null : () => _playList(_suggestions)),
                              );
                            }),
                          ),
                        ])
                      else
                      Row(children: [
                        Expanded(
                          child: PillButton(
                            label: (isCurrent && player.isPlaying) ? 'Tạm dừng' : (isCurrent ? 'Tiếp tục' : 'Phát'),
                            icon: (isCurrent && player.isPlaying) ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            loading: isCurrent && player.isLoading,
                            onTap: () {
                              if (isCurrent) {
                                context.read<PlayerProvider>().togglePlay();
                              } else {
                                _play();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PillButton(
                            label: 'Bài tương tự',
                            icon: Icons.queue_music_rounded,
                            primary: false,
                            onTap: _suggestions.isEmpty ? null : () => _playList(_suggestions),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      Row(children: [
                        // Tap = like; long-press = who liked it.
                        Expanded(child: Semantics(
                          onLongPressHint: loves.isNotEmpty ? 'xem ai đã thích' : null,
                          child: GestureDetector(
                            onLongPress: loves.isNotEmpty ? () => _showLoversSheet(loves) : null,
                            child: LabeledAction(icon: _isLoved ? Icons.favorite_rounded : Icons.favorite_border_rounded, label: _loveTotal > 0 ? '$_loveTotal thích' : 'Yêu thích', active: _isLoved, onTap: _toggleLove),
                          ),
                        )),
                        if (!noMedia) Expanded(child: Builder(builder: (ctx) {
                          // Phones: "Tải về" saves into the app for offline listening.
                          final store = ctx.watch<OfflineStore>();
                          final typed = {...Map<String, dynamic>.from(song), 'file_type': _resolvedType};
                          final saved = store.isSaved(typed);
                          final prog = store.progressOf(typed);
                          return LabeledAction(
                            icon: saved ? Icons.download_done_rounded : Icons.download_rounded,
                            label: prog != null ? '${(prog * 100).round()}%' : (saved ? 'Đã tải' : 'Tải về'),
                            active: saved,
                            onTap: saved
                                ? () => context.push('/da-tai-ve')
                                : (prog != null ? null : () => saveForOffline(context, typed)),
                          );
                        })),
                        Expanded(child: LabeledAction(icon: Icons.playlist_add_rounded, label: 'Lưu', onTap: _openPlaylistDialog)),
                        if (uploads.isNotEmpty) Expanded(child: LabeledAction(icon: Icons.library_music_outlined, label: 'Bản thu', onTap: _openFileHistory)),
                        Expanded(child: LabeledAction(icon: Icons.ios_share_rounded, label: 'Chia sẻ', onTap: _share)),
                      ]),
                      if (mobileTags != null) ...[const SizedBox(height: 18), mobileTags],
                    ],
                    if (isDesktop && emptyFile)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0x1FF59E0B), border: Border.all(color: const Color(0x4DF59E0B)), borderRadius: BorderRadius.circular(8)),
                        child: const Text('Thiếu dữ liệu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFF59E0B))),
                      ),
                    const SizedBox(height: 8),

                    // Contributor caption removed — uploader/file owner info
                    // is admin metadata, available via API/admin tooling. A
                    // dedicated "Đóng góp" credits section can be added
                    // later if user demand surfaces.

                    // 13-23. Body sections — desktop splits into a 2-col
                    // layout (text-heavy left + related lists right) so the
                    // page doesn't scroll a kilometre. Mobile keeps a single
                    // column for vertical reading on small screens.
                    Builder(builder: (ctx) {
                      final leftItems = <Widget>[
                        // Lyrics first (what people come for); the story
                        // and the invite to share one follow the sheet music.
                        ..._buildLyricsSection(lyrics, isCurrent),
                        ..._buildLyricEditorsRow(),
                        ..._buildSheetSection(isDesktop),
                        ..._buildDescriptionSection(description),
                        ..._buildStorySection(story),
                        if (!isDesktop && _plainEmpty(description) && _plainEmpty(story)) ...(_memberStory != null ? _buildMemberStory() : _buildStoryInvite()),
                        const SizedBox(height: 28),
                        CommentSection(type: _resolvedType, id: widget.songId, highlightCommentId: widget.highlightCommentId, onPageChanged: () => _fetch(fresh: true)),
                      ];
                      final rightItems = _buildRelatedSections(artists, composers);

                      if (isDesktop && rightItems.isNotEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: leftItems)),
                              const SizedBox(width: 28),
                              SizedBox(
                                width: 360,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rightItems),
                              ),
                            ],
                          ),
                        );
                      }
                      // Mobile (or no related): everything stacks single-column.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...leftItems.sublist(0, leftItems.length - 2), // strip trailing comments
                          ...rightItems,
                          const SizedBox(height: 28),
                          KeyedSubtree(key: _commentsKey, child: CommentSection(type: _resolvedType, id: widget.songId, highlightCommentId: widget.highlightCommentId, onPageChanged: () => _fetch(fresh: true))),
                        ],
                      );
                    }),

                    const SizedBox(height: 120),
                  ]),
                ),
              ),
            ],
          );

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          mainScroll,
          if (hasPlayer) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
        ],
      ),
    );
  }

  /// Sheet music horizontal carousel (Bản nhạc).
  List<Widget> _buildSheetSection(bool isDesktop) {
    if (_sheetImages.isEmpty) return const [];
    // Sheet music is a secondary section — keep it compact (horizontal
    // scroll thumbs) so it doesn't dominate the page. Tap any thumb to
    // open the lightbox for full-size viewing.
    final thumbH = isDesktop ? 200.0 : 160.0;
    return [
      const SizedBox(height: 16),
      SectionHeader(icon: Icons.image_outlined, title: 'Bản nhạc', count: '(${_sheetImages.length})'),
      SizedBox(
        height: thumbH,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _sheetImages.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (ctx, i) => InkWell(
            onTap: () => _openSheetLightbox(i),
            borderRadius: BorderRadius.circular(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: AppColors.border), color: Colors.white),
                child: CachedNetworkImage(
                  imageUrl: cdnImg((_sheetImages[i]).toString(), 350),
                  height: thumbH,
                  fit: BoxFit.contain,
                  errorWidget: (ctx, url, err) => Container(width: 140, height: thumbH, color: AppColors.surfaceLight, child: Icon(Icons.broken_image, color: AppColors.textMuted)),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildDescriptionSection(dynamic description) {
    if (description == null) return const [];
    final str = description as String;
    if (str.replaceAll(RegExp(r'<[^>]+>'), '').trim().isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      const SectionHeader(icon: Icons.description_outlined, title: 'Giới thiệu'),
      _ExpandCard(
        expanded: _descExpanded,
        onToggle: () => setState(() => _descExpanded = !_descExpanded),
        child: Html(data: str, style: {'body': Style(color: AppColors.text, fontSize: FontSize(16), lineHeight: const LineHeight(1.6), margin: Margins.zero, padding: HtmlPaddings.zero)}),
      ),
    ];
  }

  final _commentsKey = GlobalKey();

  /// Only ~32 of 14k songs have a written story, but many have a long,
  /// well-liked comment from someone who remembers the song. Show the best
  /// one in the story slot (credited) instead of an empty invitation.
  Future<void> _fetchMemberStory(String type) async {
    const fields = {'song': 'song', 'folk': 'folk', 'instrumental': 'instrumental', 'poem': 'poem', 'karaoke': 'karaoke'};
    final field = fields[type];
    if (field == null) return;
    try {
      final d = await ApiClient.query(
        'query(\$id: ID!) { $field(id: \$id) { comments(first: 15, orderBy: [{column: "likes", order: DESC}]) { data { id content likes created_at user { id username avatar { url } } } } } }',
        {'id': widget.songId},
      );
      String plain(Object? h) => (h ?? '').toString().replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'&nbsp;|\s+'), ' ').trim();
      final picks = ((d[field]?['comments']?['data'] as List?) ?? const []).whereType<Map>().where((c) {
        final t = plain(c['content']);
        // A memory, not a question or a link dump.
        final low = t.toLowerCase();
        const asks = ['tìm giúp', 'tìm hộ', 'xin ad', 'nhờ ad', 'admin', 'ad ơi', 'cho hỏi', 'cho em hỏi', 'cho tôi hỏi', 'ai biết', 'xin bài', 'xin lời', 'up giúp', 'link'];
        return t.length >= 160 && (c['likes'] as num? ?? 0) >= 1 && !t.contains('http') && c['user'] != null && '?'.allMatches(t).length < 2 && !asks.any(low.contains);
      }).toList();
      if (picks.isEmpty || !mounted) return;
      final c = Map<String, dynamic>.from(picks.first);
      c['plain'] = plain(c['content']);
      setState(() => _memberStory = c);
    } catch (_) {}
  }

  List<Widget> _buildMemberStory() {
    final c = _memberStory!;
    final user = c['user'] as Map?;
    final year = (c['created_at'] ?? '').toString().split('-').first;
    final text = c['plain'].toString();
    return [
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CÂU CHUYỆN TỪ THÀNH VIÊN', style: AppText.eyebrow),
          const SizedBox(height: 10),
          Text(
            '“$text”',
            maxLines: _storyExpanded ? null : 7,
            overflow: _storyExpanded ? null : TextOverflow.fade,
            style: body(TextStyle(fontSize: 16, height: 1.6, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic, color: AppColors.text)),
          ),
          if (text.length > 320)
            TextButton(
              onPressed: () => setState(() => _storyExpanded = !_storyExpanded),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 40), foregroundColor: AppColors.accentLight),
              child: Text(_storyExpanded ? 'Thu gọn' : 'Đọc tiếp', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
            ),
          const SizedBox(height: 10),
          InkWell(
            onTap: user?['id'] == null ? null : () => context.push('/user/${user!['id']}'),
            child: Row(children: [
              UserAvatar(url: user?['avatar']?['url']?.toString(), name: '${user?['username'] ?? ''}', size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  [user?['username'] ?? 'Thành viên', if (year.length == 4) year, if ((c['likes'] ?? 0) > 0) '♥ ${c['likes']}'].join(' · '),
                  style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () {
              final ctx = _commentsKey.currentContext;
              if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
            },
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44), foregroundColor: AppColors.accentLight),
            icon: const Icon(Icons.edit_note_rounded, size: 22),
            label: Text('Bạn cũng có kỷ niệm? Chia sẻ', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
          ),
        ]),
      ),
    ];
  }

  bool _plainEmpty(dynamic html) => html == null || html.toString().replaceAll(RegExp(r'<[^>]+>'), '').trim().isEmpty;

  /// Most songs have no story yet (32 of 14k in 2026-11). Invite listeners
  /// who know how the song came about to share it in the comments, where
  /// BQT can pick it up for the song's description.
  List<Widget> _buildStoryInvite() => [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CÂU CHUYỆN BÀI HÁT', style: AppText.eyebrow),
            const SizedBox(height: 8),
            Text('Bạn biết hoàn cảnh ra đời, hay có kỷ niệm với bài hát này?',
                style: body(TextStyle(fontSize: 15, height: 1.55, fontWeight: FontWeight.w500, color: AppColors.text))),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                final ctx = _commentsKey.currentContext;
                if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
              },
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44), foregroundColor: AppColors.accentLight),
              icon: const Icon(Icons.edit_note_rounded, size: 22),
              label: Text('Chia sẻ câu chuyện', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
            ),
          ]),
        ),
      ];

  List<Widget> _buildStorySection(dynamic story) {
    if (story == null) return const [];
    final str = story as String;
    if (str.replaceAll(RegExp(r'<[^>]+>'), '').trim().isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      const SectionHeader(icon: Icons.auto_stories_outlined, title: 'Hoàn cảnh ra đời'),
      _ExpandCard(
        expanded: _storyExpanded,
        onToggle: () => setState(() => _storyExpanded = !_storyExpanded),
        child: Html(data: str, style: {'body': Style(color: AppColors.text, fontSize: FontSize(16), lineHeight: const LineHeight(1.6), margin: Margins.zero, padding: HtmlPaddings.zero)}),
      ),
    ];
  }

  List<Widget> _buildLyricsSection(dynamic lyrics, bool isCurrent) {
    if (_resolvedType == 'instrumental') return const [];
    if (lyrics == null) return const [];
    final str = lyrics as String;
    if (str.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      SectionHeader(
        icon: Icons.article_outlined,
        title: 'Lời bài hát',
        actionIcon: Icons.copy_outlined,
        actionText: 'Sao chép lời',
        onAction: () => _copyLyrics(str),
      ),
      _ExpandCard(
        expanded: _lyricsExpanded,
        moreLabel: 'Xem toàn bộ lời',
        onToggle: () => setState(() => _lyricsExpanded = !_lyricsExpanded),
        // Use the timed scroll viewport only when the lyrics are LRC-tagged
        // (the active line needs a fixed-height frame to centre-scroll).
        // Plain lyrics render as flowing Html so the expanded mode can grow
        // naturally — fixes the "last line clipped" issue when lyrics
        // exceed the SizedBox cap.
        child: () {
          final isLrc = RegExp(r'^\s*\[\d{1,2}:\d{2}', multiLine: true).hasMatch(str);
          if (isCurrent && isLrc) {
            return SizedBox(
              height: _lyricsExpanded ? 640 : 220,
              child: TimedLyrics(
                raw: str,
                fallback: Html(data: str, style: {'body': Style(color: AppColors.text, fontSize: FontSize(16), lineHeight: const LineHeight(1.8), margin: Margins.zero, padding: HtmlPaddings.zero)}),
              ),
            );
          }
          return LyricsText(html: str, color: AppColors.text, labelColor: AppColors.accentLight);
        }(),
      ),
    ];
  }

  List<Widget> _buildLyricEditorsRow() {
    if (_lyricEditors.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _lyricEditors.length > 5 ? 5 * 16.0 + 16 : _lyricEditors.length * 16.0 + 8,
            height: 24,
            child: Stack(
              children: [
                for (int i = 0; i < _lyricEditors.take(5).length; i++)
                  Positioned(
                    left: i * 16.0,
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: AppColors.bg, width: 1.5), borderRadius: BorderRadius.circular(12)),
                      child: ClipOval(
                        child: _lyricEditors[i]['avatar']?['url'] != null
                            ? CachedNetworkImage(imageUrl: cdnImg((_lyricEditors[i]['avatar']['url']).toString(), 60), width: 24, height: 24, fit: BoxFit.cover)
                            : Container(width: 24, height: 24, color: AppColors.surfaceLight, child: Icon(Icons.person, size: 12, color: AppColors.textMuted)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('·', style: TextStyle(color: AppColors.border)),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Lịch sử sửa lời',
            excludeSemantics: true,
            child: InkWell(
              onTap: _openLyricHistory,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Icon(Icons.access_time, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text('Lịch sử sửa lời', style: body(TextStyle(fontSize: 15, color: AppColors.textSecondary, decoration: TextDecoration.underline, decorationColor: AppColors.textMuted))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  /// Sections shown either inline below the main content (mobile) or in a
  /// fixed right column (desktop). Order mirrors the bcdcnt-web source.
  // Danh sách SongRow kèm đường kẻ mảnh giữa các dòng (khớp web).
  List<Widget> _relatedRows(List songs) {
    final out = <Widget>[];
    for (int i = 0; i < songs.length; i++) {
      final sg = Map<String, dynamic>.from(songs[i]);
      out.add(SongRow(song: sg, queue: asSongList(songs)));
      if (i < songs.length - 1) out.add(Divider(height: 1, color: AppColors.borderSubtle, indent: 60));
    }
    return out;
  }

  List<Widget> _buildRelatedSections(List artists, List composers) {
    final widgets = <Widget>[];

    // 18. Other recordings of the same composition (same type)
    if (_sameSheet.isNotEmpty) {
      final filtered = _sameSheet.where((s) => s['file_type'] == (_resolvedType == 'karaoke' ? 'song' : _resolvedType)).toList();
      if (filtered.isNotEmpty) {
        final shown = _sameSheetExpanded ? filtered : filtered.take(5).toList();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(
              icon: Icons.album_outlined,
              title: _resolvedType == 'karaoke' ? 'Ca sĩ trình bày' : 'Bản thu khác',
              count: '(${filtered.length})',
              onPlayAll: () => _playList(filtered),
            ),
            ..._relatedRows(shown),
            if (filtered.length > 5)
              _ShowMoreButton(
                expanded: _sameSheetExpanded,
                remaining: filtered.length - 5,
                onTap: () => setState(() => _sameSheetExpanded = !_sameSheetExpanded),
              ),
          ]),
        ));
      }

      // 19. Karaoke covers (when current is a song and karaoke versions exist)
      final karaokes = _sameSheet.where((s) => s['file_type'] == 'karaoke' && !_isThisSong(s)).toList();
      if (karaokes.isNotEmpty) {
        final shown = _karaokeExpanded ? karaokes : karaokes.take(5).toList();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(
              icon: Icons.mic_outlined,
              title: 'Thành viên hát bài này',
              count: '(${karaokes.length})',
              onPlayAll: () => _playList(karaokes),
            ),
            ..._relatedRows(shown),
            if (karaokes.length > 5)
              _ShowMoreButton(
                expanded: _karaokeExpanded,
                remaining: karaokes.length - 5,
                onTap: () => setState(() => _karaokeExpanded = !_karaokeExpanded),
              ),
          ]),
        ));
      }
    }

    // 20. Suggestions
    if (_suggestions.isNotEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeader(
            icon: Icons.auto_awesome_outlined,
            title: 'Có thể bạn muốn nghe',
            onPlayAll: () => _playList(_suggestions),
          ),
          ..._relatedRows(_suggestions),
        ]),
      ));
    }

    // 21. Songs grouped by artist — banner with artist avatar + name link
    for (final ag in _artistSongs) {
      final artist = artists.firstWhere((a) => a['id'].toString() == ag['artistId'].toString(), orElse: () => {'title': ''});
      final title = (artist['title'] ?? '').toString();
      final slug = artist['slug']?.toString();
      final songs = (ag['songs'] as List);
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ArtistBanner(
            name: title,
            role: 'trình bày',
            icon: Icons.mic_none_outlined,
            onTap: slug != null ? () => context.push('/nghe-si/$slug') : null,
          ),
          ..._relatedRows(songs),
        ]),
      ));
    }

    // 22. Songs grouped by composer
    for (final cg in _composerSongs) {
      final composer = composers.firstWhere((c) => c['id'].toString() == cg['composerId'].toString(), orElse: () => {'title': ''});
      final title = (composer['title'] ?? '').toString();
      final slug = composer['slug']?.toString();
      final routePrefix = _resolvedType == 'folk' ? '/soan-gia' : _resolvedType == 'poem' ? '/nha-tho' : '/nhac-si';
      final songs = (cg['songs'] as List);
      // "sáng tác" cho nhạc sĩ; folk = soạn giả, poem = nhà thơ.
      final role = _resolvedType == 'folk' ? 'soạn' : _resolvedType == 'poem' ? 'sáng tác' : 'sáng tác';
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ArtistBanner(
            name: title,
            role: role,
            icon: Icons.music_note_outlined,
            onTap: slug != null ? () => context.push('$routePrefix/$slug') : null,
          ),
          ..._relatedRows(songs),
        ]),
      ));
    }

    return widgets;
  }

  // Dòng credit kiểu web: nhãn 13px xám mờ (w500) + giá trị 16px đậm màu chữ.
  Widget _webCreditLine(String label, List<InlineSpan> valueSpans) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        textScaler: MediaQuery.textScalerOf(context),
        text: TextSpan(children: [
          TextSpan(text: '$label: ', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w500))),
          ...valueSpans,
        ]),
      ),
    );
  }

  // Link tên (nhạc sĩ/ca sĩ…) kiểu web: 16px đậm màu chữ, KHÔNG gạch chân,
  // con trỏ tay khi rê. Khác _linkRow (đỏ + gạch chân dùng cho chỗ khác).
  List<InlineSpan> _creditLinkRow(List items, String key, void Function(Map) onTap) {
    final result = <InlineSpan>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) result.add(TextSpan(text: ', ', style: body(TextStyle(fontSize: 16, color: AppColors.textSecondary))));
      final item = items[i];
      result.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(Map<String, dynamic>.from(item)),
            child: Text(item[key] ?? '', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
          ),
        ),
      ));
    }
    return result;
  }

  List<InlineSpan> _linkRow(List items, String key, void Function(Map) onTap) {
    final result = <InlineSpan>[];
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (i > 0) result.add(const TextSpan(text: ', '));
      result.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Semantics(
          link: true,
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(Map<String, dynamic>.from(item)),
          child: Padding(
          // Taller hit area for older fingers; the line already has room.
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            item[key] ?? '',
            style: body(TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600,
              color: AppColors.accentLight,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.accent,
              decorationStyle: TextDecorationStyle.dotted,
            )),
          ),
          ),
        ),
        ),
      ));
    }
    return result;
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _MetaLine extends StatelessWidget {
  final String label;
  final List<InlineSpan> children;
  const _MetaLine({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        textScaler: MediaQuery.textScalerOf(context),
        text: TextSpan(
          style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary, height: 1.5)),
          children: [
            TextSpan(text: '$label '),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Banner header for "Do X trình bày / sáng tác" sections — shows the
/// person's avatar + name (clickable) + role label, plus a play-all CTA
/// and the song count. Replaces the plain icon+text section header so
/// users see who X is at a glance.
/// Header nhóm bài theo nghệ sĩ/nhạc sĩ — kiểu web: icon + "Do [tên] trình
/// bày / sáng tác" + nút tròn "→" mở trang người đó, kèm đường kẻ mảnh.
class _ArtistBanner extends StatelessWidget {
  final String name;
  final String role; // "trình bày" (ca sĩ) | "sáng tác" (nhạc sĩ)
  final IconData icon;
  final VoidCallback? onTap;

  const _ArtistBanner({
    required this.name,
    required this.role,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.text),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Do $name $role', maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.2))),
        ),
        const SizedBox(width: 8),
        if (onTap != null)
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceLight, border: Border.all(color: AppColors.border)),
            child: Icon(Icons.arrow_forward, size: 18, color: AppColors.text),
          ),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The whole line opens the person's page, not just the small arrow.
        if (onTap != null)
          Semantics(
            button: true,
            label: 'Do $name $role, mở trang $name',
            excludeSemantics: true,
            child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: row),
          )
        else
          row,
        const SizedBox(height: 6),
        Divider(height: 1, color: AppColors.border),
      ]),
    );
  }
}

class _ExpandCard extends StatefulWidget {
  final Widget child;
  final bool expanded;
  final VoidCallback onToggle;
  /// Button text when collapsed ("Xem toàn bộ lời", "Đọc tiếp").
  final String moreLabel;
  const _ExpandCard({required this.child, required this.expanded, required this.onToggle, this.moreLabel = 'Đọc tiếp'});

  @override
  State<_ExpandCard> createState() => _ExpandCardState();
}

class _ExpandCardState extends State<_ExpandCard> {
  static const _collapsed = 280.0;
  final _measureKey = GlobalKey();
  // Short text is shown whole: no fade, no button that hides nothing.
  bool? _fits;

  void _measure() {
    final box = _measureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final fits = box.size.height <= _collapsed + 24;
    if (fits != _fits && mounted) setState(() => _fits = fits);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final content = KeyedSubtree(key: _measureKey, child: widget.child);
    if (_fits == true) return content;
    // Text sits straight on the page; collapsed it shows the first part and
    // fades out above the button.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.expanded ? double.infinity : _collapsed),
            child: widget.expanded
                ? content
                : ShaderMask(
                    shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.7, 1], colors: [Colors.white, Colors.transparent]).createShader(r),
                    blendMode: BlendMode.dstIn,
                    // Lets the text lay out at its natural height (so it can
                    // be measured) and just clips it while collapsed.
                    child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: content),
                  ),
          ),
        ),
        TextButton.icon(
          onPressed: () {
            final wasExpanded = widget.expanded;
            widget.onToggle();
            // Collapsing a long text: bring its start back into view.
            if (wasExpanded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final ctx = _measureKey.currentContext;
                if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.1);
              });
            }
          },
          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 48), foregroundColor: AppColors.accentLight),
          icon: Icon(widget.expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 22),
          label: Text(widget.expanded ? 'Thu gọn' : widget.moreLabel, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
        ),
      ],
    );
  }
}

class _ShowMoreButton extends StatelessWidget {
  final bool expanded;
  final int remaining;
  final VoidCallback onTap;
  const _ShowMoreButton({required this.expanded, required this.remaining, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded ? 'Thu gọn' : 'Xem thêm ($remaining bài)',
              style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.accentLight)),
            ),
            const SizedBox(width: 6),
            Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 22, color: AppColors.accentLight),
          ],
        ),
      ),
    ),
    );
  }
}

String _formatIntStatic(dynamic v) {
  if (v == null) return '0';
  final n = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return n < 0 ? '-$buf' : buf.toString();
}

String _typeLabelFor(String t) {
  switch (t) {
    case 'song': return 'Bài hát';
    case 'folk': return 'Dân ca';
    case 'instrumental': return 'Khí nhạc';
    case 'poem': return 'Tiếng thơ';
    case 'karaoke': return 'Thành viên hát';
    default: return 'Bài hát';
  }
}

/// Apple-Music-style desktop hero: square artwork left, info column right
/// (type label, hero title, subtitle, artist row, stats, labelled action
/// cluster, optional meta content). Replaces the cinematic banner + stacked
/// title + standalone play CTA we used for mobile.
///
/// [metaContent] is an optional slot rendered below the action cluster —
/// caller passes composers/poets/upload date/tags etc. so they fill the
/// right-of-artwork dead space instead of stacking below the hero.
class _DesktopHero extends StatelessWidget {
  final Map<String, dynamic> song;
  final List artists;
  final String resolvedType;
  final bool isLoved;
  final int loveCount;
  final List loves;
  final bool hasUploads;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onLove;
  final VoidCallback onDownload;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onShare;
  final VoidCallback? onHistory;
  final VoidCallback? onShowLovers;
  final void Function(Map artist) onArtistTap;
  final VoidCallback? onArtworkTap;
  final Widget? metaContent;
  // Credits kiểu web (Sáng tác/Thơ/Trình bày…) đặt giữa tiêu đề & stats.
  final Widget? credits;
  // Ngày đăng — hiện trong dòng stats (khớp web).
  final String? uploadDate;
  // Bài video: thay ô artwork bằng hình đồng bộ với trình phát nhạc.
  final Widget? videoPlayer;

  const _DesktopHero({
    required this.song,
    required this.artists,
    required this.resolvedType,
    required this.isLoved,
    required this.loveCount,
    this.loves = const [],
    required this.hasUploads,
    required this.isCurrent,
    required this.isPlaying,
    required this.onPlay,
    required this.onLove,
    required this.onDownload,
    required this.onAddToPlaylist,
    required this.onShare,
    this.onHistory,
    this.onShowLovers,
    required this.onArtistTap,
    this.onArtworkTap,
    this.metaContent,
    this.credits,
    this.uploadDate,
    this.videoPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = song['thumbnail']?['url'];
    final subtitle = song['subtitle'] as String?;
    final views = song['views'] ?? 0;
    final downloads = song['downloads'] ?? 0;
    final showPause = isCurrent && isPlaying;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bài video → trình phát video thay đúng ô artwork (giống web).
          if (videoPlayer != null)
            SizedBox(
              width: 440,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: videoPlayer!,
              ),
            )
          else
          // Artwork — tap to open lightbox with credit caption.
          MouseRegion(
            cursor: onArtworkTap != null ? SystemMouseCursors.click : MouseCursor.defer,
            child: GestureDetector(
              onTap: onArtworkTap,
              child: Container(
                width: 300, height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45 * AppColors.shadowMul), blurRadius: 24, offset: const Offset(0, 10))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: thumb != null
                      ? CachedNetworkImage(imageUrl: cdnImg((thumb).toString(), 640), fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: AppColors.surfaceLight, child: const Center(child: Icon(Icons.music_note, size: 56, color: Colors.white24))))
                      : Container(
                          decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                          child: const Center(child: Icon(Icons.music_note, size: 64, color: Colors.white38)),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 28),
          // Info column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Vertical rhythm follows golden ratio (φ ≈ 1.618):
                //   font tier   36 → 22 → 14 → 11 (anchor = title)
                //   space tier   6 → 14 → 22 → 26 (within / between groups)
                // Groups: [TYPE] · [TITLE] · [ARTIST + STATS] · [ACTIONS] · [META].
                Text(
                  _typeLabelFor(resolvedType).toUpperCase(),
                  style: body(TextStyle(fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w800, color: AppColors.textMuted)),
                ),
                const SizedBox(height: 6),
                // Title with subtitle inlined as a smaller muted suffix —
                // matches editorial layouts (Apple Music / Spotify) where
                // disambiguators like "(bản 1)" sit beside the title rather
                // than claiming a full 20px line of their own.
                RichText(
        textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: display(TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.text, height: 1.1, letterSpacing: -0.5)),
                    children: [
                      TextSpan(text: song['title'] ?? ''),
                      if (subtitle != null && subtitle.isNotEmpty)
                        TextSpan(text: ' $subtitle', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w400, color: AppColors.textMuted, letterSpacing: -0.2))),
                    ],
                  ),
                ),
                // Credits kiểu web (Sáng tác / Thơ / Trình bày…) — giữa tiêu đề
                // và stats, thay cho dòng nghệ sĩ đơn lẻ trước đây.
                if (credits != null) ...[
                  const SizedBox(height: 16),
                  credits!,
                ],
                const SizedBox(height: 10),
                // Stat strip — Wrap so the 3 metric chunks reflow onto a
                // second line when the info column gets squeezed (narrow
                // desktop window). Row would just print "RenderFlex
                // overflowed by N pixels" + clip the rightmost stat.
                Wrap(
                  spacing: 14, runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.headphones, size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text('${_formatIntStatic(views)} lượt nghe', style: body(TextStyle(fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w600))),
                    ]),
                    if (downloads > 0)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.download, size: 13, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text('${_formatIntStatic(downloads)} tải về', style: body(TextStyle(fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w600))),
                      ]),
                    if (uploadDate != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.calendar_today, size: 12, color: AppColors.textMuted),
                        const SizedBox(width: 5),
                        Text('đăng $uploadDate', style: body(TextStyle(fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w600))),
                      ]),
                  ],
                ),
                const SizedBox(height: 22),
                // Action cluster
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _PrimaryActionPill(
                    icon: showPause ? Icons.pause : Icons.play_arrow,
                    label: showPause ? 'Tạm dừng' : (isCurrent ? 'Tiếp tục' : 'Phát'),
                    onTap: onPlay,
                    primary: true,
                  ),
                  _PrimaryActionPill(
                    icon: isLoved ? Icons.favorite : Icons.favorite_border,
                    label: loveCount > 0 ? '$loveCount yêu thích' : 'Yêu thích',
                    onTap: onLove,
                    activeAccent: isLoved,
                  ),
                  _PrimaryActionPill(icon: Icons.download_outlined, label: 'Tải về', onTap: onDownload),
                  // Overflow — Playlist + Chia sẻ + Lịch sử vào menu "..." để
                  // hàng nút gọn 4 nút giống web.
                  _OverflowActionPill(onShare: onShare, onHistory: onHistory, onAddToPlaylist: onAddToPlaylist),
                ]),
                // Hàng "đã thích" — avatar chồng của những người đã thích + chữ
                // "đã thích" (bấm mở danh sách), khớp web.
                if (loves.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: onShowLovers,
                    borderRadius: BorderRadius.circular(6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        height: 28,
                        width: 28 + (loves.length.clamp(1, 4) - 1) * 20.0,
                        child: Stack(
                          children: [
                            for (int i = 0; i < loves.length.clamp(0, 4); i++)
                              Positioned(
                                left: i * 20.0,
                                child: Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2), color: AppColors.surfaceLight),
                                  child: ClipOval(child: _LoverAvatar(love: loves[i])),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('đã thích', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted, decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted, decorationColor: AppColors.textMuted))),
                    ]),
                  ),
                ],
                if (metaContent != null) ...[
                  const SizedBox(height: 22),
                  metaContent!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile fallback hero — keeps the previous full-bleed banner UX since it
/// reads better on a narrow viewport than the desktop split layout.
class _LoverAvatar extends StatelessWidget {
  final dynamic love;
  const _LoverAvatar({required this.love});
  @override
  Widget build(BuildContext context) {
    final user = love is Map ? love['user'] as Map? : null;
    final url = user?['avatar']?['url']?.toString();
    final name = user?['username']?.toString() ?? '?';
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(imageUrl: cdnImg((url).toString(), 70), width: 28, height: 28, fit: BoxFit.cover, errorWidget: (_, _, _) => _initial(name));
    }
    return _initial(name);
  }

  Widget _initial(String name) => Container(
        color: AppColors.accent,
        alignment: Alignment.center,
        child: Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
      );
}

class _PrimaryActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool activeAccent;

  const _PrimaryActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.activeAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : (activeAccent ? AppColors.accent : AppColors.text);
    final bgColor = primary ? null : (activeAccent ? AppColors.accentSoft : AppColors.surfaceLight);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: primary ? LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)]) : null,
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
            border: primary || activeAccent ? null : Border.all(color: AppColors.border),
            boxShadow: primary ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.4 * AppColors.shadowMul), blurRadius: 12, offset: const Offset(0, 4))] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(label, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg))),
          ]),
        ),
      ),
    );
  }
}

/// Overflow pill (...) — bundles low-priority actions (Chia sẻ, Lịch sử)
/// into a popup menu so the visible action cluster stays at 4 pills.
class _OverflowActionPill extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback? onHistory;
  final VoidCallback? onAddToPlaylist;

  const _OverflowActionPill({required this.onShare, this.onHistory, this.onAddToPlaylist});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '',
      offset: const Offset(0, 48),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: AppColors.border)),
      onSelected: (v) {
        if (v == 'playlist' && onAddToPlaylist != null) onAddToPlaylist!();
        if (v == 'share') onShare();
        if (v == 'history' && onHistory != null) onHistory!();
      },
      itemBuilder: (ctx) => [
        if (onAddToPlaylist != null)
          PopupMenuItem(
            value: 'playlist',
            child: Row(children: [
              Icon(Icons.playlist_add, size: 16, color: AppColors.text),
              const SizedBox(width: 10),
              Text('Thêm vào playlist', style: body(TextStyle(fontSize: 13, color: AppColors.text))),
            ]),
          ),
        PopupMenuItem(
          value: 'share',
          child: Row(children: [
            Icon(Icons.ios_share, size: 16, color: AppColors.text),
            const SizedBox(width: 10),
            Text('Chia sẻ', style: body(TextStyle(fontSize: 13, color: AppColors.text))),
          ]),
        ),
        if (onHistory != null)
          PopupMenuItem(
            value: 'history',
            child: Row(children: [
              Icon(Icons.history, size: 16, color: AppColors.text),
              const SizedBox(width: 10),
              Text('Lịch sử bản thu', style: body(TextStyle(fontSize: 13, color: AppColors.text))),
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(Icons.more_horiz, size: 18, color: AppColors.text),
      ),
    );
  }
}


/// Phone header (2026-11): cover beside kind · year and the title.
class _MobileHeader extends StatelessWidget {
  final Map<String, dynamic> song;
  final String? thumb;
  final String kind;
  final String? year;
  final Widget? videoPlayer;
  final VoidCallback? onArtworkTap;
  const _MobileHeader({required this.song, required this.thumb, required this.kind, this.year, this.videoPlayer, this.onArtworkTap});

  @override
  Widget build(BuildContext context) {
    final title = (song['title'] ?? '').toString();
    final subtitle = (song['subtitle'] ?? '').toString();
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text([kind, if (year != null) year!].join(' · ').toUpperCase(), style: AppText.eyebrow),
        const SizedBox(height: 4),
        Text(noOrphan(title), style: display(TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w800, color: AppColors.text))),
        if (subtitle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle, style: AppText.meta)),
      ],
    );
    if (videoPlayer != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(18), child: videoPlayer!),
        const SizedBox(height: 16),
        head,
      ]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: onArtworkTap,
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: AppColors.isLight ? 0.14 : 0.45), blurRadius: 20, offset: const Offset(0, 8))]),
            child: SongCover(song: song, size: 136, radius: 20),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: head),
      ],
    );
  }
}
