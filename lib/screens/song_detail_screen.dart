import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_html/flutter_html.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';
import '../widgets/comment_section.dart';
import '../widgets/sheet_lightbox.dart';
import '../widgets/playlist_dialog.dart';
import '../widgets/shimmer.dart';
import '../widgets/file_history_dialog.dart';
import '../widgets/lyric_history_dialog.dart';

class SongDetailScreen extends StatefulWidget {
  final String songId;
  final String fileType;
  final Map<String, dynamic>? initialSong;
  const SongDetailScreen({super.key, required this.songId, this.fileType = 'song', this.initialSong});

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
  bool _isLoved = false;
  bool _loading = true;
  bool _descExpanded = false;
  bool _storyExpanded = false;
  bool _lyricsExpanded = false;
  bool _sameSheetExpanded = false;
  bool _karaokeExpanded = false;

  @override
  void initState() {
    super.initState();
    _song = widget.initialSong != null ? Map<String, dynamic>.from(widget.initialSong!) : null;
    _fetch();
  }

  String get _resolvedType {
    // Priority: fetched song > navigation extras > widget default. The
    // fetched value is authoritative once data lands, so the UI matches
    // what the API returned even if extras were missing/stale.
    final t = (_song?['file_type']
        ?? widget.initialSong?['file_type']
        ?? widget.fileType).toString();
    return ['song', 'folk', 'instrumental', 'poem', 'karaoke'].contains(t) ? t : 'song';
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
            thumbnail { url }
            imageCreditor { id username }
            file { id is_hq audio_url video_url duration created_at user { id username avatar { url } } }
            uploader { id username }
            uploads(orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: "approved"}]}) { id file { id audio_url is_hq created_at user { id username avatar { url } } } }
            sheet { id slug title year lyric_type content description }
            composers(first: 20) { data { id slug title } }
            recomposers(first: 20) { data { id slug title } }
            fcats(first: 10) { data { id slug title } }
            melodies(first: 10) { data { id slug title } }
            tags { id name slug }
            artists(first: 100) { data { id title slug avatar { url } } }
            loves(first: 100) { data { user_id user { id username avatar { url } } } }
          } }''';
          break;
        case 'instrumental':
          dataKey = 'instrumental';
          query = r'''query($id: ID!) { instrumental(id: $id) {
            id title subtitle slug content description views downloads file_type play_type record_year empty_file created_at
            thumbnail { url }
            imageCreditor { id username }
            file { id is_hq audio_url video_url duration created_at user { id username avatar { url } } }
            uploader { id username }
            uploads(orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: "approved"}]}) { id file { id audio_url is_hq created_at user { id username avatar { url } } } }
            sheet { id slug title year lyric_type content description }
            composers(first: 20) { data { id slug title } }
            tags { id name slug }
            artists(first: 100) { data { id title slug avatar { url } } }
            loves(first: 100) { data { user_id user { id username avatar { url } } } }
          } }''';
          break;
        case 'poem':
          dataKey = 'poem';
          query = r'''query($id: ID!) { poem(id: $id) {
            id title subtitle slug content description views downloads file_type play_type record_year empty_file created_at
            thumbnail { url }
            imageCreditor { id username }
            file { id is_hq audio_url video_url duration created_at user { id username avatar { url } } }
            uploader { id username }
            sheet { id slug title year lyric_type content description }
            poets(first: 20) { data { id slug title } }
            tags { id name slug }
            artists(first: 100) { data { id title slug avatar { url } } }
            loves(first: 100) { data { user_id user { id username avatar { url } } } }
          } }''';
          break;
        case 'karaoke':
          dataKey = 'karaoke';
          query = r'''query($id: ID!) { karaoke(id: $id) {
            id title subtitle slug content description views downloads file_type play_type record_year empty_file created_at
            thumbnail { url }
            imageCreditor { id username }
            file { id is_hq audio_url video_url duration created_at user { id username avatar { url } } }
            uploader { id username }
            sheet { id slug title year lyric_type content description tags { id name slug } composers(first: 20) { data { id slug title } } poets(first: 20) { data { id slug title } } }
            song { id slug title }
            users(first: 100) { data { id username avatar { url } } }
            loves(first: 100) { data { user_id user { id username avatar { url } } } }
          } }''';
          break;
        default:
          dataKey = 'song';
          query = r'''query($id: ID!) { song(id: $id) {
            id title subtitle slug content description views downloads file_type play_type record_year empty_file created_at
            thumbnail { url }
            imageCreditor { id username }
            file { id is_hq audio_url video_url duration created_at user { id username avatar { url } } }
            uploader { id username }
            uploads(orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: "approved"}]}) { id file { id audio_url is_hq created_at user { id username avatar { url } } } }
            sheet { id slug title year lyric_type content description tags { id name slug } composers(first: 20) { data { id slug title } } poets(first: 20) { data { id slug title } } }
            artists(first: 100) { data { id title slug avatar { url } } }
            loves(first: 100) { data { user_id user { id username avatar { url } } } }
          } }''';
    }
    return (query, dataKey);
  }

  Future<void> _fetch() async {
    try {
      final type = _resolvedType;
      // IDs are NOT unique across song/folk/instrumental/poem/karaoke
      // tables — falling through to other types when one returns null
      // would silently load the wrong record. Trust the preferred type
      // strictly; fix the upstream extras instead.
      final pair = _queryForType(type);
      final data = await ApiClient.query(pair.$1, {'id': widget.songId});
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
        setState(() {
          _song = normalized;
          if (userId != null) {
            _isLoved = (loves as List).any((l) => l['user_id'].toString() == userId.toString());
          }
        });

        final sheetId = sheet['id'];
        if (sheetId != null) {
          _fetchSameSheet(sheetId);
          _fetchSheetImages(sheetId, sheet['content']);
        }

        final artists = (normalized['artists']?['data'] ?? []) as List;
        for (final a in artists) {
          if (a['id'] != null) _fetchArtistSongs(a['id']);
        }

        final composers = (sheet['composers']?['data'] ?? []) as List;
        for (final c in composers) {
          _fetchComposerSongs(c['id']);
        }

        _fetchLyricEditors();
      }
      _fetchSuggestions();

      // Auto-play on first visit
      if (_song != null && mounted) {
        final player = context.read<PlayerProvider>();
        final isCurrent = player.currentSong?['id']?.toString() == _song!['id'].toString();
        if (!isCurrent) _play();
      }
    } catch (e) { print('fetch error: $e'); }
    setState(() => _loading = false);
  }

  List<String> _extractImages(String? html) {
    if (html == null) return [];
    final re = RegExp(r'<img[^>]+src="([^"]+)"', caseSensitive: false);
    return re.allMatches(html).map((m) => m.group(1)!).toList();
  }

  Future<void> _fetchSheetImages(dynamic sheetId, String? mainContent) async {
    final images = <String>[..._extractImages(mainContent)];
    try {
      final data = await ApiClient.query(
        r'''query($id: ID!) { sheet(id: $id) { revisions(first: 20) { data { content } } } }''',
        {'id': sheetId.toString()},
      );
      final revs = (data['sheet']?['revisions']?['data'] ?? []) as List;
      for (final rev in revs) {
        images.addAll(_extractImages(rev['content']));
      }
    } catch (_) {}
    if (mounted) setState(() => _sheetImages = images);
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
          if (m['id'].toString() != widget.songId) allSongs.add(m);
        }
        for (final s in (sheet['karaokes']?['data'] ?? []) as List) {
          final m = Map<String, dynamic>.from(s);
          m['file_type'] = 'karaoke';
          if (m['id'].toString() != widget.songId) allSongs.add(m);
        }
        for (final s in (sheet['instrumentals']?['data'] ?? []) as List) {
          final m = Map<String, dynamic>.from(s);
          m['file_type'] = 'instrumental';
          if (m['id'].toString() != widget.songId) allSongs.add(m);
        }
        setState(() => _sameSheet = allSongs);
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
      if (songs.isNotEmpty) setState(() {
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
      if (songs.isNotEmpty) setState(() {
        _composerSongs = [..._composerSongs, {'composerId': composerId, 'songs': songs}];
      });
    } catch (_) {}
  }

  Future<void> _fetchLyricEditors() async {
    try {
      final data = await ApiClient.query(
        r'''query($where: WhereConditions) { activities(first: 20, orderBy: [{column: "id", order: DESC}], where: $where) { edges { node { user { id username avatar { url } } } } } }''',
        {'where': {'AND': [{'column': 'action', 'value': 'update_lyric'}, {'column': 'object_type', 'value': 'song'}, {'column': 'object_id', 'value': widget.songId}]}},
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
      setState(() => _lyricEditors = editors);
    } catch (_) {}
  }

  Future<void> _fetchSuggestions() async {
    try {
      final data = await ApiClient.query(
        r'''query($id: ID!, $type: String!) {
          suggestSongs(first: 5, id: $id, type: $type) {
            id title slug views file_type play_type
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
      final list = (data['suggestSongs'] ?? []) as List;
      if (!mounted) return;
      setState(() => _suggestions = list);
      // Refresh queue with suggestions now that they're loaded
      final player = context.read<PlayerProvider>();
      if (player.currentSong?['id']?.toString() == widget.songId) {
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
            id title slug views file_type play_type
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
            return m;
          })
          .where((m) => m['audioUrl'] != null)
          .toList();
      return list;
    } catch (_) { return []; }
  }

  void _play() {
    if (_song == null) return;
    final s = Map<String, dynamic>.from(_song!);
    s['audioUrl'] = _song!['file']?['audio_url'];
    final queue = <Map<String, dynamic>>[s];
    for (final x in _suggestions) {
      final m = Map<String, dynamic>.from(x);
      m['audioUrl'] = m['file']?['audio_url'];
      queue.add(m);
    }
    context.read<PlayerProvider>().playSong(s, queue);
  }

  Future<void> _share() async {
    if (_song == null) return;
    final slug = _song!['slug'];
    final id = _song!['id'];
    final url = '$siteUrl/bai-hat/$slug-$id';
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã sao chép link: $url'), backgroundColor: AppColors.success, duration: const Duration(seconds: 2)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(url)));
    }
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải: $e'), backgroundColor: AppColors.error));
    }
  }

  void _openSheetLightbox(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SheetLightbox(images: _sheetImages, initialIndex: index)),
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

  Future<void> _toggleLove() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng đăng nhập để yêu thích'), backgroundColor: AppColors.error));
      return;
    }
    final newLiked = !_isLoved;
    final user = auth.user;
    // Optimistic update
    setState(() {
      _isLoved = newLiked;
      final loves = ((_song?['loves']?['data'] ?? []) as List).toList();
      if (newLiked && user != null) {
        loves.insert(0, {'user_id': user['id'], 'user': user});
      } else if (user != null) {
        loves.removeWhere((l) => l['user_id'].toString() == user['id'].toString());
      }
      _song?['loves'] = {'data': loves};
    });
    try {
      await auth.authedMutate(
        newLiked
            ? r'''mutation($id: ID!) { love(lovable_id: $id, lovable_type: "song") { id } }'''
            : r'''mutation($id: ID!) { unlove(lovable_id: $id, lovable_type: "song") { id } }''',
        {'id': widget.songId},
      );
    } catch (_) {
      // Rollback
      setState(() {
        _isLoved = !newLiked;
        final loves = ((_song?['loves']?['data'] ?? []) as List).toList();
        if (newLiked && user != null) {
          loves.removeWhere((l) => l['user_id'].toString() == user['id'].toString());
        } else if (user != null) {
          loves.insert(0, {'user_id': user['id'], 'user': user});
        }
        _song?['loves'] = {'data': loves};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _song == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          title: Text('CHI TIẾT', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
          centerTitle: true,
        ),
        body: const SingleChildScrollView(child: Column(children: [
          HeroSkeleton(),
          Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SongListSkeleton(rows: 4)),
        ])),
      );
    }
    if (_song == null) {
      return Scaffold(backgroundColor: AppColors.bg, appBar: AppBar(), body: Center(child: Text('Không tìm thấy', style: AppText.bodyText)));
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
    final player = context.watch<PlayerProvider>();
    final isCurrent = player.currentSong?['id']?.toString() == song['id'].toString();
    final isVideo = player.currentSong?['play_type'] == 'video';
    final w = MediaQuery.of(context).size.width;
    final hasPlayer = player.currentSong != null;
    final isDesktop = w >= 900;

    final mainScroll = CustomScrollView(
            slivers: [
              // 1. Sticky header
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.bg.withValues(alpha: 0.88),
                title: const Text('CHI TIẾT', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary, fontFamily: 'System')),
                centerTitle: true,
                leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
                // Share lives in the player's "more" sheet on desktop where
                // the shell already shows queue + comments toggles in the
                // top-right; keeping it here would overlap them.
                actions: MediaQuery.of(context).size.width >= 900
                    ? const []
                    : [IconButton(icon: const Icon(Icons.share, color: AppColors.textSecondary), onPressed: _share)],
              ),

              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 2. Hero thumbnail — square on mobile; on desktop a
                    // wide cinematic banner: blurred stretched art behind a
                    // crisp centred crop, à la Apple Music album header.
                    const SizedBox(height: 4),
                    SizedBox(
                      height: isDesktop ? 280 : (w - 40),
                      width: double.infinity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [AppColors.accent, AppColors.accentLight],
                                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                            if (thumb != null)
                              CachedNetworkImage(
                                imageUrl: thumb,
                                fit: BoxFit.cover,
                                errorWidget: (ctx, url, err) => const Center(child: Icon(Icons.music_note, size: 80, color: Colors.white38)),
                              ),
                            Positioned(
                              left: 0, right: 0, bottom: 0, height: 80,
                              child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, AppColors.bg]))),
                            ),
                            // Image credit icon (tap to reveal popup)
                            if (song['imageCreditor']?['username'] != null) Positioned(
                              right: 10, bottom: 10,
                              child: InkWell(
                                onTap: () {
                                  showDialog(context: context, builder: (ctx) => AlertDialog(
                                    backgroundColor: AppColors.surface,
                                    title: Row(children: const [
                                      Icon(Icons.camera_alt_outlined, size: 18, color: AppColors.accentLight),
                                      SizedBox(width: 8),
                                      Text('Tín dụng ảnh', style: TextStyle(fontSize: 14, color: AppColors.text)),
                                    ]),
                                    content: Text(
                                      'Ảnh minh hoạ bởi ${song['imageCreditor']['username']}',
                                      style: body(const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
                                    ],
                                  ));
                                },
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.camera_alt_outlined, size: 14, color: Colors.white70),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 3. Title + subtitle (hero scale on desktop)
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(text: song['title'] ?? '', style: display(TextStyle(
                            fontSize: isDesktop ? 32 : 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                            height: 1.15,
                            letterSpacing: -0.3,
                          ))),
                          if (song['subtitle'] != null && (song['subtitle'] as String).isNotEmpty)
                            TextSpan(text: ' ${song['subtitle']}', style: display(TextStyle(
                              fontSize: isDesktop ? 22 : 18,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textMuted,
                            ))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 3b. Primary play button — prominent CTA right below the
                    // title, like Apple Music / Spotify album pages. The
                    // existing icon row below shows secondary actions
                    // (like, download, add to playlist).
                    _PrimaryPlayButton(
                      isCurrent: isCurrent,
                      isPlaying: player.isPlaying,
                      onPlay: () {
                        if (isCurrent) {
                          context.read<PlayerProvider>().togglePlay();
                        } else {
                          _play();
                        }
                      },
                    ),
                    const SizedBox(height: 6),

                    // 4. Empty file warning
                    if (emptyFile)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0x1FF59E0B), border: Border.all(color: const Color(0x4DF59E0B)), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: const [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFF59E0B)),
                            SizedBox(width: 8),
                            Expanded(child: Text('Thiếu dữ liệu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFF59E0B)))),
                          ],
                        ),
                      ),

                    const SizedBox(height: 14),

                    // 5. Composers / Sáng tác
                    if (composers.isNotEmpty) _MetaLine(
                      label: 'Sáng tác',
                      children: [
                        ..._linkRow(composers, 'title', (c) => context.push('/nhac-si/${c['slug']}')),
                        if (year != null) TextSpan(text: ' ($year)', style: const TextStyle(color: AppColors.textMuted)),
                      ],
                    ),

                    // 5b. Folk extras — Soạn giả / Thể loại / Làn điệu.
                    // Render whenever the data is present (don't gate on
                    // _resolvedType, so the blocks still appear if the
                    // type detection is off but the API returned the
                    // fields). The normalizer copies fcats/melodies/
                    // recomposers from the root into `sheet` for any folk
                    // record so we read from a single path.
                    Builder(builder: (ctx) {
                      final rec = (song['sheet']?['recomposers']?['data'] ?? song['recomposers']?['data'] ?? []) as List;
                      if (rec.isEmpty) return const SizedBox.shrink();
                      return _MetaLine(
                        label: 'Soạn giả',
                        children: _linkRow(rec, 'title', (p) => context.push('/soan-gia/${p['slug']}')),
                      );
                    }),
                    Builder(builder: (ctx) {
                      final raw = song['sheet']?['fcats'] ?? song['fcats'];
                      // ignore: avoid_print
                      print('[detail] fcats raw=$raw');
                      final fcats = (raw is Map ? (raw['data'] ?? []) : (raw ?? [])) as List;
                      if (fcats.isEmpty) return const SizedBox.shrink();
                      return _MetaLine(
                        label: 'Thể loại',
                        children: _linkRow(fcats, 'title', (f) => context.push('/dan-ca/${f['slug']}')),
                      );
                    }),
                    Builder(builder: (ctx) {
                      final raw = song['sheet']?['melodies'] ?? song['melodies'];
                      // ignore: avoid_print
                      print('[detail] melodies raw=$raw');
                      final melodies = (raw is Map ? (raw['data'] ?? []) : (raw ?? [])) as List;
                      if (melodies.isEmpty) return const SizedBox.shrink();
                      return _MetaLine(
                        label: 'Làn điệu',
                        children: _linkRow(melodies, 'title', (m) => context.push('/lan-dieu/${m['slug']}')),
                      );
                    }),

                    // 6. Poets / lyricType
                    if (poets.isNotEmpty && (_resolvedType == 'song' || _resolvedType == 'karaoke' || _resolvedType == 'poem'))
                      _MetaLine(
                        label: lyricType != null && (lyricType as String).isNotEmpty ? lyricType : 'Thơ',
                        children: _linkRow(poets, 'title', (p) => context.push('/nha-tho/${p['slug']}')),
                      ),

                    // 8. Artists / Performers (Karaoke uses users → already normalized to artists)
                    if (artists.isNotEmpty) _MetaLine(
                      label: _resolvedType == 'karaoke' ? 'Thể hiện' : 'Trình bày',
                      children: [
                        ..._linkRow(artists, 'title', (a) {
                          if (_resolvedType == 'karaoke') {
                            // a.slug here is username → user detail
                            final id = a['id'];
                            if (id != null) context.push('/user/$id');
                          } else {
                            context.push('/nghe-si/${a['slug']}');
                          }
                        }),
                        if (recordYear != null) TextSpan(text: ' ($recordYear)', style: const TextStyle(color: AppColors.textMuted)),
                      ],
                    ),

                    // 8b. For karaoke: link back to source song
                    if (_resolvedType == 'karaoke' && song['song'] != null && song['song']['id'] != null)
                      _MetaLine(
                        label: 'Bài gốc',
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              onTap: () => context.push('/song/${song['song']['id']}', extra: {...?song['song'], 'file_type': 'song'}),
                              child: Text(song['song']['title'] ?? '', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentLight, decoration: TextDecoration.underline, decorationColor: AppColors.accent, decorationStyle: TextDecorationStyle.dotted))),
                            ),
                          ),
                        ],
                      ),

                    // 9. Upload date — same accent style as other meta
                    // values for visual consistency (no underline since the
                    // date isn't a link).
                    if (song['created_at'] != null)
                      _MetaLine(
                        label: 'Ngày đăng',
                        children: [TextSpan(text: _formatDate(song['created_at']), style: const TextStyle(color: AppColors.accentLight, fontWeight: FontWeight.w600))],
                      ),

                    // 13. Sheet music link (not inline images on mobile for now)
                    // Description (label changed to match web: "Giới thiệu")


                    // 10. Tags
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: tags.map<Widget>((t) => InkWell(
                          onTap: () => context.push('/tag/${t['slug']}'),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(20)),
                            child: Text('#${t['name'] ?? ''}', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
                          ),
                        )).toList(),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // 11. Stats + action buttons
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.border),
                          bottom: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.visibility, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text('${_formatInt(song['views'])}', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                          if ((song['downloads'] ?? 0) > 0) ...[
                            const SizedBox(width: 16),
                            const Icon(Icons.download, size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text('${_formatInt(song['downloads'])}', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                          ],
                          const Spacer(),
                          _IconBtn(
                            icon: _isLoved ? Icons.favorite : Icons.favorite_border,
                            color: _isLoved ? AppColors.accent : AppColors.textSecondary,
                            bg: _isLoved ? AppColors.accentSoft : AppColors.surfaceLight,
                            badge: loves.isNotEmpty ? loves.length.toString() : null,
                            onTap: _toggleLove,
                          ),
                          if (uploads.isNotEmpty) _IconBtn(icon: Icons.history, color: AppColors.textSecondary, bg: AppColors.surfaceLight, onTap: _openFileHistory),
                          _IconBtn(icon: Icons.download, color: AppColors.textSecondary, bg: AppColors.surfaceLight, onTap: _download),
                          _IconBtn(icon: Icons.add, color: AppColors.textSecondary, bg: AppColors.surfaceLight, onTap: _openPlaylistDialog),
                        ],
                      ),
                    ),

                    // 12. Contributor info
                    if (song['uploader'] != null || song['file']?['user'] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          children: [
                            if (song['uploader'] != null) Text(song['uploader']['username'], style: AppText.caption),
                            if (song['created_at'] != null) Text(timeago(song['created_at']), style: AppText.caption),
                            if (song['file']?['user'] != null && song['file']?['user']?['id'] != song['uploader']?['id']) ...[
                              Text('·', style: AppText.caption),
                              Text(song['file']['user']['username'], style: AppText.caption),
                              if (song['file']?['created_at'] != null) Text(timeago(song['file']['created_at']), style: AppText.caption),
                            ],
                          ],
                        ),
                      ),

                    // 13. Sheet music images
                    if (_sheetImages.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionHeader(icon: Icons.image_outlined, title: 'Bản nhạc'),
                      SizedBox(
                        height: 160,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _sheetImages.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (ctx, i) => InkWell(
                            onTap: () => _openSheetLightbox(i),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
                                child: CachedNetworkImage(
                                  imageUrl: _sheetImages[i],
                                  height: 160,
                                  fit: BoxFit.cover,
                                  errorWidget: (ctx, url, err) => Container(width: 120, height: 160, color: AppColors.surfaceLight, child: const Icon(Icons.broken_image, color: AppColors.textMuted)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],

                    // 14. Description (label: "Giới thiệu")
                    if (description != null && (description as String).replaceAll(RegExp(r'<[^>]+>'), '').trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionHeader(icon: Icons.description_outlined, title: 'Giới thiệu'),
                      _ExpandCard(
                        expanded: _descExpanded,
                        onToggle: () => setState(() => _descExpanded = !_descExpanded),
                        child: Html(data: description, style: {'body': Style(color: AppColors.textSecondary, fontSize: FontSize(14), lineHeight: const LineHeight(2), margin: Margins.zero, padding: HtmlPaddings.zero)}),
                      ),
                    ],

                    // 15. Birth story
                    if (story != null && (story as String).replaceAll(RegExp(r'<[^>]+>'), '').trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionHeader(icon: Icons.auto_stories_outlined, title: 'Hoàn cảnh ra đời'),
                      _ExpandCard(
                        expanded: _storyExpanded,
                        onToggle: () => setState(() => _storyExpanded = !_storyExpanded),
                        child: Html(data: story, style: {'body': Style(color: AppColors.textSecondary, fontSize: FontSize(14), lineHeight: const LineHeight(2), margin: Margins.zero, padding: HtmlPaddings.zero)}),
                      ),
                    ],

                    // 16. Lyrics
                    if (_resolvedType != 'instrumental' && lyrics != null && (lyrics as String).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionHeader(icon: Icons.article_outlined, title: 'Lời bài hát'),
                      _ExpandCard(
                        expanded: _lyricsExpanded,
                        onToggle: () => setState(() => _lyricsExpanded = !_lyricsExpanded),
                        child: Html(data: lyrics, style: {'body': Style(color: AppColors.textSecondary, fontSize: FontSize(14), lineHeight: const LineHeight(2), margin: Margins.zero, padding: HtmlPaddings.zero)}),
                      ),
                    ],

                    // 17. Lyric editors — stacked avatars + history link (after lyrics)
                    if (_lyricEditors.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Stacked avatars
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
                                            ? CachedNetworkImage(imageUrl: _lyricEditors[i]['avatar']['url'], width: 24, height: 24, fit: BoxFit.cover)
                                            : Container(width: 24, height: 24, color: AppColors.surfaceLight, child: const Icon(Icons.person, size: 12, color: AppColors.textMuted)),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('·', style: TextStyle(color: AppColors.border)),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _openLyricHistory,
                            child: Row(
                              children: [
                                const Icon(Icons.access_time, size: 12, color: AppColors.textMuted),
                                const SizedBox(width: 4),
                                Text('Lịch sử sửa lời', style: body(const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],

                    // 18-22. Related sections (same sheet, suggestions, by artist,
                    // by composer). Always inline on both mobile and desktop —
                    // the native macOS shell uses a left sidebar instead of a
                    // right "engagement" column.
                    ..._buildRelatedSections(artists, composers),

                    // 23. Comments
                    const SizedBox(height: 28),
                    CommentSection(type: _resolvedType, id: widget.songId),

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

  /// Sections shown either inline below the main content (mobile) or in a
  /// fixed right column (desktop). Order mirrors the bcdcnt-web source.
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
            _SectionHeader(icon: Icons.album_outlined, title: _resolvedType == 'karaoke' ? 'Thành viên hát bài này' : '${filtered.length} bản thu khác của cùng bài này'),
            ...shown.map((s) {
              final sg = Map<String, dynamic>.from(s);
              return SongRow(song: sg, onTap: () => context.push('/song/${sg['id']}', extra: sg));
            }),
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
      final karaokes = _sameSheet.where((s) => s['file_type'] == 'karaoke' && s['id'].toString() != widget.songId).toList();
      if (karaokes.isNotEmpty) {
        final shown = _karaokeExpanded ? karaokes : karaokes.take(5).toList();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SectionHeader(icon: Icons.mic_outlined, title: 'Thành viên hát bài này'),
            ...shown.map((s) {
              final sg = Map<String, dynamic>.from(s);
              return SongRow(song: sg, onTap: () => context.push('/song/${sg['id']}', extra: sg));
            }),
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
          _SectionHeader(icon: Icons.music_note_outlined, title: 'Có thể bạn muốn nghe'),
          ..._suggestions.map((s) {
            final sg = Map<String, dynamic>.from(s);
            return SongRow(song: sg, onTap: () => context.push('/song/${sg['id']}', extra: sg));
          }),
        ]),
      ));
    }

    // 21. Songs grouped by artist
    for (final ag in _artistSongs) {
      final artist = artists.firstWhere((a) => a['id'].toString() == ag['artistId'].toString(), orElse: () => {'title': ''});
      final title = artist['title'] ?? '';
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionHeader(icon: Icons.mic_outlined, title: 'Do $title trình bày'),
          ...((ag['songs'] as List).map((s) {
            final sg = Map<String, dynamic>.from(s);
            return SongRow(song: sg, onTap: () => context.push('/song/${sg['id']}', extra: sg));
          })),
        ]),
      ));
    }

    // 22. Songs grouped by composer
    for (final cg in _composerSongs) {
      final composer = composers.firstWhere((c) => c['id'].toString() == cg['composerId'].toString(), orElse: () => {'title': ''});
      final title = composer['title'] ?? '';
      final label = _resolvedType == 'folk' ? 'soạn giả' : _resolvedType == 'poem' ? 'là tác giả' : 'sáng tác';
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionHeader(icon: Icons.music_note_outlined, title: 'Do $title $label'),
          ...((cg['songs'] as List).map((s) {
            final sg = Map<String, dynamic>.from(s);
            return SongRow(song: sg, onTap: () => context.push('/song/${sg['id']}', extra: sg));
          })),
        ]),
      ));
    }

    return widgets;
  }

  List<InlineSpan> _linkRow(List items, String key, void Function(Map) onTap) {
    final result = <InlineSpan>[];
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (i > 0) result.add(const TextSpan(text: ', '));
      result.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => onTap(Map<String, dynamic>.from(item)),
          child: Text(
            item[key] ?? '',
            style: body(const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: AppColors.accentLight,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.accent,
              decorationStyle: TextDecorationStyle.dotted,
            )),
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

  String _formatInt(dynamic n) {
    if (n == null) return '0';
    final v = n is num ? n.toInt() : (int.tryParse(n.toString()) ?? 0);
    final s = v.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return v < 0 ? '-${buf.toString()}' : buf.toString();
  }
}

/// Primary play CTA shown directly below the title — Apple Music / Spotify
/// pattern. When the song is the current track we flip into a "Tạm dừng /
/// Đang phát" toggle so it stays useful instead of re-triggering playback.
class _PrimaryPlayButton extends StatelessWidget {
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onPlay;
  const _PrimaryPlayButton({
    required this.isCurrent,
    required this.isPlaying,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final showPause = isCurrent && isPlaying;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(showPause ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  showPause ? 'Tạm dừng' : (isCurrent ? 'Tiếp tục' : 'Phát'),
                  style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.3)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final String label;
  final List<InlineSpan> children;
  const _MetaLine({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RichText(
        text: TextSpan(
          style: body(const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          children: [
            TextSpan(text: '$label: '),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onAction;
  final String? actionText;
  const _SectionHeader({required this.icon, required this.title, this.onAction, this.actionText});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: display(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text)))),
          if (onAction != null && actionText != null) GestureDetector(
            onTap: onAction,
            child: Text(actionText!, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
          ),
        ],
      ),
    );
  }
}

class _ExpandCard extends StatelessWidget {
  final Widget child;
  final bool expanded;
  final VoidCallback onToggle;
  const _ExpandCard({required this.child, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: expanded ? double.infinity : 200),
              child: ClipRect(child: child),
            ),
          ),
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(expanded ? 'Thu gọn' : 'Xem thêm', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final String? badge;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.color, required this.bg, this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: color),
            ),
            if (badge != null) Positioned(
              top: -4, right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: Text(badge!, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
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
              style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentLight)),
            ),
            const SizedBox(width: 6),
            Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: AppColors.accentLight),
          ],
        ),
      ),
    );
  }
}
