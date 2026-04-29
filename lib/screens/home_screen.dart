import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/theme.dart';
import 'package:provider/provider.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/section_header.dart';
import '../widgets/waveform_player.dart';
import '../widgets/gallery_lightbox.dart';
import '../widgets/video_poster.dart';
import '../widgets/shimmer.dart';
import '../widgets/hero_spotlight.dart';
import '../widgets/login_dialog.dart';

// --- Queries ---

const _stickyQuery = '''query {
  stickySongs(first: 20, random: true) {
    id slug title subtitle views play_type thumbnail { url } file { audio_url video_url duration }
    artists(first: 5) { data { id slug title avatar { url } } }
  }
}''';

const _latestQuery = '''query(\$page: Int, \$cat: String!) {
  songs: catSongs(category: \$cat, first: 5, page: \$page, orderBy: [{column: "id", order: DESC}]) {
    data { id slug title subtitle views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } }
    paginatorInfo { currentPage lastPage }
  }
}''';

const _artistsQuery = '''query(\$where: WhereConditions) {
  artists(first: 20, orderBy: [{column: "total_listens", order: DESC}], where: \$where) {
    data { id slug title avatar { url } total_listens }
  }
}''';

const _composersQuery = '''query(\$where: WhereConditions) {
  composers(first: 20, orderBy: [{column: "total_listens", order: DESC}], where: \$where) {
    data { id slug title avatar { url } total_listens }
  }
}''';

const _artistsWhere = {
  'where': {'AND': [
    {'column': 'type', 'value': 'domestic'},
    {'column': 'is_group', 'value': '0'},
    {'column': 'total_listens', 'operator': 'GT', 'value': '100000'},
    {'column': 'image_id', 'operator': 'GT', 'value': '0'},
  ]}
};
const _composersWhere = {
  'where': {'AND': [
    {'column': 'type', 'value': 'domestic'},
    {'column': 'total_listens', 'operator': 'GT', 'value': '100000'},
    {'column': 'image_id', 'operator': 'GT', 'value': '0'},
  ]}
};

const _videoQuery = '''query {
  songs(first: 15, where: {AND: [{column: "play_type", value: "video"}]}, orderBy: [{column: "id", order: DESC}]) {
    data { id slug title subtitle views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } }
  }
}''';

const _trendingQuery = '''query {
  statisticListen(first: 5, type: "song", period: "week") {
    data { total object { ... on Song { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id title slug } } } } }
  }
}''';

const _rankingQuery = '''query {
  statisticListen(first: 5, type: "song", period: "week") {
    data { total object { ... on Song { id title subtitle slug views play_type thumbnail { url } artists(first: 5) { data { id title slug } } } } }
  }
}''';

const _playlistsQuery = '''query(\$where: WhereConditions) {
  playlists(first: 30, orderBy: [{column: "is_sticky", order: DESC}, {column: "id", order: DESC}], where: \$where) {
    data { id slug title thumbnail { url } user { id username } items(first: 1) { paginatorInfo { total } } }
  }
}''';

const _galleryQuery = '''query(\$where: WhereConditions) {
  documents(first: 24, orderBy: [{column: "id", order: DESC}], where: \$where) {
    data { id slug title views downloads thumbnail { url } uploader { id username } comments(first: 0) { paginatorInfo { total } } }
  }
}''';

const _audioQuery = '''query(\$where: WhereConditions) {
  documents(first: 6, orderBy: [{column: "id", order: DESC}], where: \$where) {
    data { id slug title views downloads file { audio_url } uploader { id username } comments(first: 0) { paginatorInfo { total } } }
  }
}''';

const _videoDocQuery = '''query(\$where: WhereConditions) {
  documents(first: 6, orderBy: [{column: "id", order: DESC}], where: \$where) {
    data { id slug title views downloads thumbnail { url } file { video_url } uploader { id username } comments(first: 0) { paginatorInfo { total } } }
  }
}''';

const _newsQuery = '''query(\$where: WhereConditions) {
  documents(first: 6, orderBy: [{column: "id", order: DESC}], where: \$where) {
    data { id slug title thumbnail { url } content created_at uploader { id username } }
  }
}''';

// Memorial (is_sticky=1, yod>0)
const _stickyBase = 'id slug title yob dod mod yod avatar { url }';
const _stickySongData = 'data { id title slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id slug title avatar { url } } } }';
const _memorialArtists = '''query(\$where: WhereConditions) {
  artists(first: 20, orderBy: [{column: "id", order: DESC}], where: \$where) {
    data { $_stickyBase songs(first: 5, orderBy: [{column: "views", order: DESC}]) { $_stickySongData } }
  }
}''';
const _memorialComposers = '''query(\$where: WhereConditions) {
  composers(first: 20, orderBy: [{column: "id", order: DESC}], where: \$where) {
    data { $_stickyBase songs(first: 5, orderBy: [{column: "views", order: DESC}]) { $_stickySongData } }
  }
}''';
const _memorialPoets = '''query(\$where: WhereConditions) {
  poets(first: 20, orderBy: [{column: "id", order: DESC}], where: \$where) {
    data { $_stickyBase poems(first: 5, orderBy: [{column: "views", order: DESC}]) { $_stickySongData } }
  }
}''';
const _memorialRecomposers = '''query(\$where: WhereConditions) {
  recomposers(first: 20, orderBy: [{column: "id", order: DESC}], where: \$where) {
    data { $_stickyBase folks(first: 5, orderBy: [{column: "views", order: DESC}]) { $_stickySongData } }
  }
}''';
const _stickyWhere = {
  'where': {'AND': [{'column': 'is_sticky', 'value': 1}, {'column': 'yod', 'operator': 'GT', 'value': '0'}]}
};

// Events (date-based)
const _eventQuery = '''query(\$where: WhereConditions) {
  playlists(first: 10, where: \$where) {
    data { id slug title description excerpt event_date event_use_cover thumbnail { url } items(first: 1, orderBy: [{column: "position", order: ASC}]) { data { type object { ... on Song { id slug title thumbnail { url } } ... on Folk { id slug title thumbnail { url } } ... on Instrumental { id slug title thumbnail { url } } ... on Poem { id slug title thumbnail { url } } ... on Karaoke { id slug title thumbnail { url } } } } } }
  }
}''';

// --- Constants ---

class _Cat {
  final String name, slug, query, fileType, routePrefix;
  final Color bg;
  final IconData icon;
  const _Cat(this.name, this.slug, this.bg, this.icon, {required this.query, required this.fileType, required this.routePrefix});
}

const _categories = [
  _Cat('Tân nhạc', 'tan-nhac', Color(0xFF711313), Icons.music_note, query: 'songs', fileType: 'song', routePrefix: '/bai-hat/'),
  _Cat('Dân ca', 'dan-ca', Color(0xFF8B6914), Icons.music_note, query: 'folks', fileType: 'folk', routePrefix: '/dan-ca/'),
  _Cat('Khí nhạc', 'khi-nhac', Color(0xFF7A3B3A), Icons.piano, query: 'instrumentals', fileType: 'instrumental', routePrefix: '/khi-nhac/'),
  _Cat('Tiếng thơ', 'tieng-tho', Color(0xFF6B5210), Icons.auto_stories_outlined, query: 'poems', fileType: 'poem', routePrefix: '/tieng-tho/'),
  _Cat('Thành viên hát', 'thanh-vien-hat', Color(0xFF2D5E3A), Icons.mic, query: 'karaokes', fileType: 'karaoke', routePrefix: '/thanh-vien-hat/'),
];

// --- Helper ---

String _plainExcerpt(String? html, {int maxLen = 120}) {
  if (html == null || html.isEmpty) return '';
  final s = html.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.length <= maxLen) return s;
  return '${s.substring(0, maxLen).replaceAll(RegExp(r'\s+\S*$'), '')}…';
}

String _formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _personRoute(String? personType, String? slug) {
  const map = {'artist': '/nghe-si/', 'composer': '/nhac-si/', 'poet': '/nha-tho/', 'recomposer': '/soan-gia/'};
  return '${map[personType] ?? '/nghe-si/'}$slug';
}

// --- Screen ---

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _hotSongs = [];
  Map<String, dynamic>? _trendingSong;
  List<dynamic> _artists = [];
  List<dynamic> _composers = [];
  List<dynamic> _videos = [];
  List<dynamic> _playlists = [];
  List<dynamic> _chartSongs = [];
  String _chartPeriod = 'week';
  String _chartType = 'song';
  bool _chartLoading = false;

  // Top-level ranking tab: 0=listens 1=contributors 2=uploaders 3=commentLoves
  int _rankTab = 0;
  final Map<String, List<Map<String, dynamic>>> _memberRanks = {};
  final Map<String, bool> _memberLoading = {};
  List<dynamic> _galleryDocs = [];
  List<dynamic> _audioDocs = [];
  List<dynamic> _videoDocs = [];
  List<dynamic> _newsDocs = [];
  List<Map<String, dynamic>> _memorial = [];
  List<dynamic> _events = [];

  // Latest with tabs
  int _latestTab = 0; // index into _categories
  final Map<String, List<dynamic>> _latestCat = {};
  final Map<String, int> _latestPage = {};
  final Map<String, int> _latestLastPage = {};
  bool _latestLoading = false;

  bool _loading = true;
  int _archiveTab = 0; // 0=Ảnh 1=Âm thanh 2=Video 3=Bài viết

  // Lightbox infinite-load state per doc type
  final Map<String, int> _docPage = {'image': 1, 'audio': 1, 'video': 1};
  final Map<String, bool> _docExhausted = {'image': false, 'audio': false, 'video': false};

  // Personalized (only when authenticated)
  List<Map<String, dynamic>> _recentListens = [];
  List<Map<String, dynamic>> _recentLoves = [];

  @override
  void initState() {
    super.initState();
    _fetch();
    // Personalized fetch can run independently after a microtask so we have context.read access.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchPersonalized());
  }

  Future<void> _fetchPersonalized() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      if (_recentListens.isNotEmpty || _recentLoves.isNotEmpty) {
        setState(() { _recentListens = []; _recentLoves = []; });
      }
      return;
    }
    final userId = auth.user?['id']?.toString();
    if (userId == null) return;
    try {
      final results = await Future.wait<Map<String, dynamic>>([
        auth.authedQuery(r'''query($id: ID!) {
          user(id: $id) {
            recentListens(first: 12, page: 1, orderBy: [{column: "id", order: DESC}]) {
              data {
                object {
                  __typename
                  ... on Song { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug } } }
                  ... on Folk { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug } } }
                  ... on Instrumental { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug } } }
                  ... on Poem { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug } } }
                  ... on Karaoke { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } users(first: 3) { data { id username } } }
                }
              }
            }
          }
        }''', {'id': userId}),
        auth.authedQuery(r'''query($id: ID!) {
          user(id: $id) {
            loves(first: 12, page: 1, orderBy: [{column: "id", order: DESC}]) {
              data {
                object {
                  __typename
                  ... on Song { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug } } }
                  ... on Folk { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug } } }
                  ... on Instrumental { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug } } }
                  ... on Poem { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug } } }
                  ... on Karaoke { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } users(first: 3) { data { id username } } }
                }
              }
            }
          }
        }''', {'id': userId}),
      ]);
      if (!mounted) return;

      List<Map<String, dynamic>> mapResult(dynamic raw) {
        final list = ((raw?['data'] ?? []) as List);
        final out = <Map<String, dynamic>>[];
        final seen = <String>{};
        for (final entry in list) {
          final obj = entry['object'];
          if (obj == null) continue;
          final m = Map<String, dynamic>.from(obj as Map);
          final id = m['id'].toString();
          if (seen.contains(id)) continue;
          seen.add(id);
          // Normalize karaoke users → artists for display
          if (m['users']?['data'] != null && m['artists'] == null) {
            m['artists'] = {'data': ((m['users']['data']) as List).map((u) => {'id': u['id'], 'title': u['username']}).toList()};
          }
          // Map __typename to file_type
          const tnMap = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem', 'Karaoke': 'karaoke'};
          m['file_type'] = tnMap[m['__typename']?.toString()] ?? 'song';
          out.add(m);
        }
        return out;
      }

      setState(() {
        _recentListens = mapResult(results[0]['user']?['recentListens']);
        _recentLoves = mapResult(results[1]['user']?['loves']);
      });
    } catch (_) {}
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      // Per-query catch so one failing section (e.g. a schema mismatch) doesn't
      // wipe the whole homepage — Future.wait rejects on first error otherwise.
      Future<Map<String, dynamic>> safe(Future<Map<String, dynamic>> f) =>
          f.catchError((_) => <String, dynamic>{});
      final queries = await Future.wait<Map<String, dynamic>>([
        safe(ApiClient.query(_stickyQuery)),
        safe(ApiClient.query(_trendingQuery)),
        safe(ApiClient.query(_artistsQuery, _artistsWhere)),
        safe(ApiClient.query(_composersQuery, _composersWhere)),
        safe(ApiClient.query(_videoQuery)),
        safe(ApiClient.query(_playlistsQuery, {'where': {'AND': [{'column': 'is_system', 'value': '1'}, {'column': 'is_public', 'value': '1'}]}})),
        safe(ApiClient.query(_rankingQuery)),
        safe(ApiClient.query(_galleryQuery, {'where': {'AND': [{'column': 'type', 'value': 'image'}]}})),
        safe(ApiClient.query(_audioQuery, {'where': {'AND': [{'column': 'type', 'value': 'audio'}]}})),
        safe(ApiClient.query(_videoDocQuery, {'where': {'AND': [{'column': 'type', 'value': 'video'}]}})),
        safe(ApiClient.query(_newsQuery, {'where': {'AND': [{'column': 'type', 'value': 'news'}]}})),
        safe(ApiClient.query(_memorialArtists, _stickyWhere)),
        safe(ApiClient.query(_memorialComposers, _stickyWhere)),
        safe(ApiClient.query(_memorialPoets, _stickyWhere)),
        safe(ApiClient.query(_memorialRecomposers, _stickyWhere)),
      ]);
      final events = await _fetchEvents();
      if (!mounted) return;

      final trendingList = ((queries[1]['statisticListen']?['data'] ?? []) as List).where((d) => d['object'] != null).toList();
      Map<String, dynamic>? trending;
      if (trendingList.isNotEmpty) {
        final pick = trendingList[DateTime.now().microsecond % trendingList.length];
        trending = Map<String, dynamic>.from(pick['object'] as Map);
        trending['weeklyListens'] = pick['total'];
      }

      final mem = <Map<String, dynamic>>[];
      void addMem(dynamic raw, String type, String songsKey) {
        for (final p in ((raw?['data'] ?? []) as List)) {
          final m = Map<String, dynamic>.from(p as Map);
          m['personType'] = type;
          m['topSongs'] = ((m[songsKey]?['data'] ?? []) as List);
          mem.add(m);
        }
      }
      addMem(queries[11]['artists'], 'artist', 'songs');
      addMem(queries[12]['composers'], 'composer', 'songs');
      addMem(queries[13]['poets'], 'poet', 'poems');
      addMem(queries[14]['recomposers'], 'recomposer', 'folks');

      setState(() {
        _hotSongs = (queries[0]['stickySongs'] ?? []) as List;
        _trendingSong = trending;
        _artists = queries[2]['artists']?['data'] ?? [];
        _composers = queries[3]['composers']?['data'] ?? [];
        _videos = queries[4]['songs']?['data'] ?? [];
        _playlists = queries[5]['playlists']?['data'] ?? [];
        _chartSongs = ((queries[6]['statisticListen']?['data'] ?? []) as List).where((d) => d['object'] != null).toList();
        _galleryDocs = queries[7]['documents']?['data'] ?? [];
        _audioDocs = queries[8]['documents']?['data'] ?? [];
        _videoDocs = queries[9]['documents']?['data'] ?? [];
        _newsDocs = queries[10]['documents']?['data'] ?? [];
        _memorial = mem;
        _events = events;
        _loading = false;
      });
      _fetchLatest(_categories[_latestTab], 1);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<dynamic>> _fetchEvents() async {
    final now = DateTime.now();
    final mmdd = '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    try {
      final data = await ApiClient.query(_eventQuery, {
        'where': {'AND': [
          {'column': 'is_system', 'value': '1'},
          {'column': 'is_public', 'value': '1'},
          {'column': 'event_start', 'operator': 'LTE', 'value': mmdd},
          {'column': 'event_end', 'operator': 'GTE', 'value': mmdd},
        ]}
      });
      return (data['playlists']?['data'] ?? []) as List;
    } catch (_) { return []; }
  }

  Future<void> _fetchLatest(_Cat cat, int page) async {
    setState(() => _latestLoading = true);
    try {
      final artistField = cat.query == 'karaokes'
          ? 'users(first: 5) { data { id slug: username title: username avatar { url } } }'
          : 'artists(first: 5) { data { id slug title avatar { url } } }';
      final q = '''query(\$page: Int) {
        ${cat.query}(first: 5, page: \$page, orderBy: [{column: "id", order: DESC}]) {
          data { id slug title subtitle views play_type thumbnail { url } file { audio_url video_url duration } $artistField }
          paginatorInfo { currentPage lastPage }
        }
      }''';
      final data = await ApiClient.query(q, {'page': page});
      final items = (data[cat.query]?['data'] ?? []) as List;
      final pi = data[cat.query]?['paginatorInfo'];
      if (!mounted) return;
      setState(() {
        _latestCat[cat.slug] = items;
        _latestPage[cat.slug] = pi?['currentPage'] ?? 1;
        _latestLastPage[cat.slug] = pi?['lastPage'] ?? 1;
        _latestLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _latestLoading = false);
    }
  }

  Future<void> _fetchRanking({String? period, String? type}) async {
    final p = period ?? _chartPeriod;
    final t = type ?? _chartType;
    setState(() { _chartLoading = true; _chartPeriod = p; _chartType = t; });
    try {
      final q = '''query(\$period: String, \$type: String!) {
        statisticListen(first: 5, page: 1, period: \$period, type: \$type) {
          data { total object {
            ... on Song { id title subtitle slug views play_type thumbnail { url } artists(first: 5) { data { id title slug } } }
            ... on Folk { id title subtitle slug views play_type thumbnail { url } artists(first: 5) { data { id title slug } } }
            ... on Instrumental { id title subtitle slug views play_type thumbnail { url } artists(first: 5) { data { id title slug } } }
            ... on Poem { id title subtitle slug views play_type thumbnail { url } artists(first: 5) { data { id title slug } } }
          } }
        }
      }''';
      final data = await ApiClient.query(q, {'period': p, 'type': t});
      final list = ((data['statisticListen']?['data'] ?? []) as List).where((d) => d['object'] != null).toList();
      if (!mounted) return;
      setState(() { _chartSongs = list; _chartLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _chartLoading = false);
    }
  }

  Future<void> _fetchMemberRank(String kind) async {
    if (_memberLoading[kind] == true) return;
    setState(() => _memberLoading[kind] = true);
    try {
      String q;
      List<Map<String, dynamic>> items = [];
      if (kind == 'listeners' || kind == 'contributors') {
        final field = kind == 'listeners' ? 'listen' : 'point';
        q = 'query { users(first: 5, orderBy: [{column: "$field", order: DESC}], where: {AND: [{column: "$field", value: 0, operator: GT}, {column: "id", value: 1, operator: NEQ}]}) { data { id username avatar { url } $field } } }';
        final data = await ApiClient.query(q);
        items = ((data['users']?['data'] ?? []) as List).map((u) => {
          'id': u['id'], 'username': u['username'], 'avatar': u['avatar']?['url'], 'value': u[field],
        }).toList();
      } else {
        final queryName = kind == 'uploaders' ? 'topUpload' : 'topCommentLove';
        q = 'query { $queryName(first: 5) { data { username avatar user_id total } } }';
        final data = await ApiClient.query(q);
        items = ((data[queryName]?['data'] ?? []) as List).map((u) => {
          'id': u['user_id'], 'username': u['username'], 'avatar': u['avatar'], 'value': u['total'],
        }).toList();
      }
      if (!mounted) return;
      setState(() {
        _memberRanks[kind] = items;
        _memberLoading[kind] = false;
      });
    } catch (_) {
      if (mounted) setState(() => _memberLoading[kind] = false);
    }
  }

  void _openSong(Map<String, dynamic> song) => context.push('/song/${song['id']}', extra: song);

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Chào buổi sáng';
    if (h < 18) return 'Chào buổi chiều';
    return 'Chào buổi tối';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: _loading
          ? KeyedSubtree(key: const ValueKey('sk'), child: _skeleton())
          : KeyedSubtree(key: const ValueKey('content'), child: _content()),
    );
  }

  Widget _content() {
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: _feedItems(),
      ),
    );
  }

  List<Widget> _feedItems() {
    return [
          // Compact hero greeting
          _StaggerFadeIn(index: 0, child: _hero()),
          const SizedBox(height: 14),

          // Quick action chips (logged-in only)
          if (context.watch<AuthProvider>().isAuthenticated) ...[
            _StaggerFadeIn(index: 1, child: _quickChips()),
            const SizedBox(height: 22),
          ] else
            const SizedBox(height: 6),

          // ─── HERO SPOTLIGHT (rotating featured) ───
          if (_spotlightItems().isNotEmpty) ...[
            _StaggerFadeIn(index: 2, child: HeroSpotlight(items: _spotlightItems(), onTap: _openSong)),
            const SizedBox(height: 28),
          ],

          // ─── DÀNH CHO BẠN (personalized — only when logged in) ───
          if (_recentListens.isNotEmpty || _recentLoves.isNotEmpty)
            const _GroupLabel('DÀNH CHO BẠN'),

          if (_recentListens.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.history,
              title: 'Nghe gần đây',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/nghe-gan-day'),
            ),
            _songCarousel(_recentListens),
            const SizedBox(height: 32),
          ],

          if (_recentLoves.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.favorite,
              title: 'Yêu thích gần đây',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/yeu-thich'),
            ),
            _shufflePlayBar(
              label: 'Phát ngẫu nhiên',
              count: _recentLoves.length,
              onPlay: () => _shufflePlay(_recentLoves),
            ),
            const SizedBox(height: 12),
            _songCarousel(_recentLoves),
            const SizedBox(height: 32),
          ],

          // ─── KHÁM PHÁ ───
          const _GroupLabel('KHÁM PHÁ'),

          SectionHeader(
            icon: Icons.access_time,
            title: 'Bài hát mới cập nhật',
            actionText: 'Xem tất cả',
            onAction: () => context.push('/the-loai/${_categories[_latestTab].slug}'),
          ),
          _latestTabsBar(),
          const SizedBox(height: 12),
          _latestList(),
          const SizedBox(height: 32),

          if (_hotSongs.isNotEmpty) ...[
            const SectionHeader(icon: Icons.trending_up, title: 'Có thể bạn muốn nghe'),
            _songCarousel(_hotSongs),
            const SizedBox(height: 32),
          ],

          if (_videos.isNotEmpty) ...[
            const SectionHeader(icon: Icons.movie_outlined, title: 'Video'),
            _videoCarousel(_videos),
            const SizedBox(height: 32),
          ],

          if (_playlists.isNotEmpty) ...[
            const SectionHeader(icon: Icons.queue_music, title: 'Playlist theo chủ đề'),
            _playlistCarousel(_playlists),
            const SizedBox(height: 32),
          ],

          const SectionHeader(icon: Icons.album_outlined, title: 'Thể loại'),
          _categoryTiles(),
          const SizedBox(height: 32),

          // ─── NGHỆ SĨ ───
          if (_artists.isNotEmpty || _composers.isNotEmpty)
            const _GroupLabel('NGHỆ SĨ'),

          if (_artists.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.mic,
              title: 'Nghệ sĩ tiêu biểu',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/nghe-si'),
            ),
            _personCarousel(_artists, '/nghe-si/'),
            const SizedBox(height: 32),
          ],

          if (_composers.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.music_note_outlined,
              title: 'Nhạc sĩ tiêu biểu',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/nhac-si'),
            ),
            _personCarousel(_composers, '/nhac-si/'),
            const SizedBox(height: 32),
          ],

          // ─── TƯỞNG NHỚ & SỰ KIỆN ───
          if (_memorial.isNotEmpty || _events.isNotEmpty)
            const _GroupLabel('TƯỞNG NHỚ & SỰ KIỆN'),

          if (_memorial.isNotEmpty) ...[
            const SectionHeader(icon: Icons.local_florist_outlined, title: 'Tưởng niệm', subtitle: 'Những nghệ sĩ đã khuất'),
            ..._memorial.take(3).map(_memorialCard),
            const SizedBox(height: 24),
          ],

          if (_events.isNotEmpty) ...[
            const SectionHeader(icon: Icons.event_outlined, title: 'Theo dòng sự kiện'),
            ..._events.map(_eventCard),
            const SizedBox(height: 24),
          ],

          // ─── THƯ VIỆN (gộp 4 mục thành 1 section + tabs) ───
          if (_galleryDocs.isNotEmpty || _audioDocs.isNotEmpty || _videoDocs.isNotEmpty || _newsDocs.isNotEmpty) ...[
            const _GroupLabel('THƯ VIỆN'),
            SectionHeader(
              icon: Icons.collections_bookmark_outlined,
              title: 'Tư liệu',
              subtitle: 'Kho ảnh, âm thanh, video và bài viết',
              actionText: 'Xem tất cả',
              onAction: () {
                const slugs = ['hinh-anh', 'am-thanh', 'video', 'bai-viet'];
                context.push('/tu-lieu/${slugs[_archiveTab]}');
              },
            ),
            _archiveTabsBar(),
            const SizedBox(height: 14),
            _archiveContent(),
            const SizedBox(height: 32),
          ],

          // ─── BẢNG XẾP HẠNG (positioned at the end of the home feed) ───
          const _GroupLabel('BẢNG XẾP HẠNG'),
          SectionHeader(
            icon: Icons.headphones,
            title: 'Top nghe nhiều',
            subtitle: 'Bài hát nhiều lượt nghe cập nhật theo giờ',
            actionText: 'Xem tất cả',
            onAction: () => context.push('/bang-xep-hang'),
          ),
          _rankingTabs(),
          const SizedBox(height: 10),
          _rankingList(_chartSongs),
          const SizedBox(height: 28),
          SectionHeader(
            icon: Icons.workspace_premium_outlined,
            title: 'Top thành viên',
            subtitle: 'Thành viên đóng góp nhiều nhất',
            actionText: 'Xem tất cả',
            onAction: () => context.push('/bang-xep-hang/${_memberSlugForTab(_rankTab)}'),
          ),
          _memberTabsBar(),
          const SizedBox(height: 10),
          _memberBody(),
          const SizedBox(height: 32),

          // Footer signature — slogan at the very bottom of the page.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Column(
                children: [
                  Text(
                    'BCĐCNT',
                    style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textMuted, letterSpacing: 4)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bài ca đi cùng năm tháng',
                    style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 60),
    ];
  }

  // --- Section builders ---

  /// Up to 5 hand-picked items for the rotating hero spotlight.
  /// Trending song first (with weeklyListens), then top sticky songs.
  List<Map<String, dynamic>> _spotlightItems() {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    if (_trendingSong != null) {
      final m = Map<String, dynamic>.from(_trendingSong!);
      out.add(m);
      seen.add(m['id'].toString());
    }
    for (final s in _hotSongs) {
      if (out.length >= 5) break;
      final m = Map<String, dynamic>.from(s as Map);
      final id = m['id'].toString();
      if (seen.contains(id)) continue;
      out.add(m);
      seen.add(id);
    }
    return out;
  }

  Widget _skeleton() {
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          const SkBox(height: 84, radius: 20),
          const SizedBox(height: 28),
          const SkBox(width: 160, height: 20),
          const SizedBox(height: 16),
          const SkBox(height: 96, radius: 16),
          const SizedBox(height: 24),
          const SkBox(height: 124, radius: 18),
          const SizedBox(height: 28),
          const SkBox(width: 200, height: 20),
          const SizedBox(height: 16),
          Column(
            children: List.generate(4, (i) => const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SkBox(width: 56, height: 56, radius: 10),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkBox(width: 220, height: 14),
                        SizedBox(height: 6),
                        SkBox(width: 140, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ),
          const SizedBox(height: 28),
          const SkBox(width: 160, height: 20),
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, __) => const SizedBox(
                width: 130,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkBox(width: 130, height: 130, radius: 14),
                    SizedBox(height: 8),
                    SkBox(width: 110, height: 12),
                    SizedBox(height: 4),
                    SkBox(width: 80, height: 10),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero() {
    final h = DateTime.now().hour;
    final icon = h < 12 ? Icons.wb_sunny_outlined : (h < 18 ? Icons.wb_twilight : Icons.nightlight_outlined);
    final auth = context.watch<AuthProvider>();
    final loggedIn = auth.isAuthenticated;
    final user = auth.user;
    final username = user?['username'] as String?;
    final avatar = user?['avatar'] as String?;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [AppColors.surfaceLight, AppColors.surface, AppColors.surfaceLight.withValues(alpha: 0.3)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.06), blurRadius: 24, spreadRadius: -6, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          // Avatar (if logged in) or sun/moon icon, with notifications dot
          GestureDetector(
            onTap: loggedIn ? () => context.push('/profile') : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.4), blurRadius: 16, spreadRadius: -2)],
                  ),
                  child: ClipOval(
                    child: loggedIn && avatar != null
                        ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, errorWidget: (_, __, ___) => Icon(icon, color: Colors.white, size: 22))
                        : Icon(icon, color: Colors.white, size: 22),
                  ),
                ),
                if (loggedIn && (user?['unread'] ?? 0) > 0) Positioned(
                  top: -2, right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      (user!['unread'] as int) > 9 ? '9+' : '${user['unread']}',
                      style: body(const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loggedIn && username != null ? '${_greeting()}, $username' : _greeting(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 0.3)),
                ),
                const SizedBox(height: 2),
                Text(
                  'Bài ca đi cùng năm tháng',
                  style: display(const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.3, height: 1.15)),
                ),
              ],
            ),
          ),
          // Search
          InkWell(
            onTap: () => context.push('/search'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
            ),
          ),
          // Login pill (when not logged in)
          if (!loggedIn) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () => showDialog(context: context, builder: (_) => const LoginDialog()).then((_) {
                if (context.read<AuthProvider>().isAuthenticated) _fetchPersonalized();
              }),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                  boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: -2, offset: const Offset(0, 3))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.login, color: Colors.white, size: 14),
                  const SizedBox(width: 5),
                  Text('Đăng nhập', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickChips() {
    final chips = <(IconData, String, Color, VoidCallback)>[
      (Icons.favorite, 'Yêu thích', const Color(0xFFE57373), () => context.push('/yeu-thich')),
      (Icons.access_time, 'Nghe gần đây', const Color(0xFF7986CB), () => context.push('/nghe-gan-day')),
      (Icons.queue_music, 'Playlist của tôi', const Color(0xFF81C784), () => context.push('/playlist-cua-toi')),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final c = chips[i];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: c.$4,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(color: c.$3.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(7)),
                      child: Icon(c.$1, size: 13, color: c.$3),
                    ),
                    const SizedBox(width: 8),
                    Text(c.$2, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _shufflePlayBar({required String label, required int count, required VoidCallback onPlay}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [AppColors.accentSoft, AppColors.accentSoft.withValues(alpha: 0.3)],
              begin: Alignment.centerLeft, end: Alignment.centerRight,
            ),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                ),
                child: const Icon(Icons.shuffle, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                    Text('$count bài • bật ngẫu nhiên', style: body(const TextStyle(fontSize: 10, color: AppColors.textMuted))),
                  ],
                ),
              ),
              const Icon(Icons.play_arrow, color: AppColors.accentLight, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  void _shufflePlay(List<dynamic> songs) {
    if (songs.isEmpty) return;
    final queue = <Map<String, dynamic>>[];
    for (final s in songs) {
      final m = Map<String, dynamic>.from(s as Map);
      m['audioUrl'] = m['file']?['audio_url'];
      if (m['audioUrl'] != null) queue.add(m);
    }
    if (queue.isEmpty) return;
    queue.shuffle();
    final player = context.read<PlayerProvider>();
    player.playSong(queue.first, queue);
    player.setFetchMore(null);
    if (!player.shuffle) player.toggleShuffle();
  }

  Widget _memorialCard(Map<String, dynamic> p) {
    final topSongs = (p['topSongs'] as List).take(3).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gold memorial stripe
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Colors.transparent, AppColors.gold, Colors.transparent]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TƯỞNG NHỚ', style: body(const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.gold, letterSpacing: 2))),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => context.push(_personRoute(p['personType'], p['slug'])),
                  child: Row(
                    children: [
                      ColorFiltered(
                        colorFilter: const ColorFilter.matrix([0.33,0.33,0.33,0,0, 0.33,0.33,0.33,0,0, 0.33,0.33,0.33,0,0, 0,0,0,1,0]),
                        child: Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.gold.withValues(alpha: 0.4), width: 2),
                          ),
                          child: ClipOval(
                            child: p['avatar']?['url'] != null
                                ? CachedNetworkImage(imageUrl: p['avatar']['url'], fit: BoxFit.cover)
                                : Container(color: AppColors.surface, child: const Icon(Icons.person, color: AppColors.textMuted)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p['title'] ?? '', style: display(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.2))),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.gold.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
                                  ),
                                  child: Text(
                                    '${p['yob'] ?? '?'} – ${p['yod'] ?? '?'}',
                                    style: body(const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
                    ],
                  ),
                ),
                if (topSongs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(height: 1, color: AppColors.borderSubtle),
                  const SizedBox(height: 6),
                  ...topSongs.asMap().entries.map((e) {
                    final s = Map<String, dynamic>.from(e.value);
                    return InkWell(
                      onTap: () => _openSong(s),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Container(
                              width: 20, height: 20,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(5)),
                              child: Text('${e.key + 1}', style: body(const TextStyle(fontSize: 10, color: AppColors.accentLight, fontWeight: FontWeight.w700))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(s['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, color: AppColors.text))),
                            ),
                            const Icon(Icons.play_arrow, color: AppColors.textMuted, size: 16),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventCard(dynamic ep) {
    final thumb = ep['thumbnail']?['url'] ?? ep['items']?['data']?[0]?['object']?['thumbnail']?['url'];
    final desc = _plainExcerpt(ep['excerpt'] ?? ep['description']);
    final now = DateTime.now();
    final evDate = _formatDate(ep['event_date']);
    return InkWell(
      onTap: () {
        final first = ep['items']?['data']?[0];
        final obj = first?['object'];
        if (obj != null) {
          context.push('/song/${obj['id']}', extra: Map<String, dynamic>.from(obj));
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight], begin: Alignment.centerLeft, end: Alignment.centerRight),
                borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ep['title'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: display(const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
                    ),
                  ),
                  if (evDate.isNotEmpty) Text(
                    '$evDate${now.year > 0 ? ' — ${now.year}' : ''}',
                    style: body(const TextStyle(fontSize: 11, color: Colors.white70)),
                  ),
                ],
              ),
            ),
            if (thumb != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppColors.surface)),
              ),
            if (desc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Text(desc, style: body(const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _trendingBanner(Map<String, dynamic> song) {
    final artists = (song['artists']?['data'] ?? song['artists'] ?? []) as List;
    final thumb = song['thumbnail']?['url'];
    final weekly = song['weeklyListens'];
    return InkWell(
      onTap: () => _openSong(song),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFF8A1717), AppColors.accent, Color(0xFFC67068)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: -4, offset: const Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              // Soft glow behind
              Positioned(
                right: -40, top: -40,
                child: Container(
                  width: 160, height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Thumbnail with play overlay
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: thumb != null
                                ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover)
                                : Container(color: Colors.white.withValues(alpha: 0.1), child: const Icon(Icons.music_note, color: Colors.white, size: 32)),
                          ),
                        ),
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)]),
                          child: const Icon(Icons.play_arrow, size: 20, color: AppColors.accent),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.local_fire_department, color: Colors.amberAccent, size: 12),
                              const SizedBox(width: 4),
                              Text('NGHE NHIỀU TRONG TUẦN', style: body(const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.8))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            song['title'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: display(const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.2)),
                          ),
                          if (artists.isNotEmpty) Text(
                            artists.map((a) => a['title'] ?? '').join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: body(const TextStyle(fontSize: 12, color: Colors.white70)),
                          ),
                          if (weekly != null) Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.headphones, size: 10, color: Colors.white),
                                const SizedBox(width: 4),
                                Text('${_formatInt(weekly is num ? weekly.toInt() : 0)} lượt nghe', style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white))),
                              ]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  Widget _latestTabsBar() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length - 1, // skip karaoke (thanh-vien-hat) in tabs
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (ctx, i) {
          final active = i == _latestTab;
          final c = _categories[i];
          return InkWell(
            onTap: () {
              setState(() => _latestTab = i);
              if (!_latestCat.containsKey(c.slug)) _fetchLatest(c, 1);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: active ? AppColors.accentLight : Colors.transparent, width: 2)),
              ),
              child: Text(c.name, style: body(TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? AppColors.accentLight : AppColors.textSecondary))),
            ),
          );
        },
      ),
    );
  }

  Widget _latestList() {
    final cat = _categories[_latestTab];
    final items = _latestCat[cat.slug] ?? [];
    if (_latestLoading && items.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    }
    if (items.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Chưa có bài', style: body(const TextStyle(color: AppColors.textMuted))));
    return Column(
      children: items.take(5).map((s) {
        final song = Map<String, dynamic>.from(s);
        song['file_type'] = cat.fileType;
        return SongRow(song: song, onTap: () => _openSong(song));
      }).toList(),
    );
  }

  Widget _categoryTiles() {
    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) {
          final c = _categories[i];
          return InkWell(
            onTap: () => context.push('/the-loai/${c.slug}'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 144,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [c.bg, Color.lerp(c.bg, Colors.black, 0.3)!],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: c.bg.withValues(alpha: 0.35), blurRadius: 16, spreadRadius: -4, offset: const Offset(0, 6)),
                ],
              ),
              child: Stack(
                children: [
                  // Subtle sheen
                  Positioned(
                    right: -18, top: -10,
                    child: Container(
                      width: 70, height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                        child: Icon(c.icon, color: Colors.white, size: 20),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.1, height: 1.15)),
                          ),
                          const SizedBox(height: 2),
                          Row(children: [
                            Text('Khám phá', style: body(const TextStyle(fontSize: 10, color: Colors.white70))),
                            const SizedBox(width: 2),
                            const Icon(Icons.arrow_forward, size: 10, color: Colors.white70),
                          ]),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _songCarousel(List<dynamic> songs, {bool showRank = false}) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: songs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final song = Map<String, dynamic>.from(songs[i]);
          final artists = (song['artists']?['data'] ?? song['artists'] ?? []) as List;
          final thumb = song['thumbnail']?['url'];
          return InkWell(
            onTap: () => _openSong(song),
            child: SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: thumb != null
                            ? CachedNetworkImage(imageUrl: thumb, width: 140, height: 140, fit: BoxFit.cover)
                            : Container(width: 140, height: 140, color: AppColors.surfaceLight, child: const Icon(Icons.music_note, size: 28, color: AppColors.textMuted)),
                      ),
                      if (showRank) Positioned(
                        bottom: 6, left: 6,
                        child: Container(
                          width: 22, height: 22,
                          decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(song['title'] ?? '', style: AppText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (artists.isNotEmpty)
                    Text(artists.map((a) => a['title'] ?? '').join(', '), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _personCarousel(List<dynamic> people, String routePrefix) {
    return SizedBox(
      height: 114,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final p = people[i];
          final avatar = p['avatar']?['url'];
          return InkWell(
            onTap: () => context.push('$routePrefix${p['slug']}'),
            child: SizedBox(
              width: 80,
              child: Column(
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight])),
                    child: ClipOval(
                      child: avatar != null
                          ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover)
                          : Center(child: Text((p['title'] ?? '?').toString().substring(0, 1).toUpperCase(), style: display(const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white70)))),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(p['title'] ?? '', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _videoCarousel(List<dynamic> videos) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) {
          final song = Map<String, dynamic>.from(videos[i]);
          final artists = (song['artists']?['data'] ?? []) as List;
          final thumb = song['thumbnail']?['url'];
          return InkWell(
            onTap: () => _openSong(song),
            child: SizedBox(
              width: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: thumb != null
                            ? CachedNetworkImage(imageUrl: thumb, width: 200, height: 112, fit: BoxFit.cover)
                            : Container(width: 200, height: 112, color: AppColors.surfaceLight, child: const Icon(Icons.movie, color: AppColors.textMuted)),
                      ),
                      Positioned(
                        bottom: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.movie, size: 11, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('Video', style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white))),
                          ]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(song['title'] ?? '', style: AppText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (artists.isNotEmpty)
                    Text(artists.map((a) => a['title'] ?? '').join(', '), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _playlistCarousel(List<dynamic> playlists) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: playlists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (ctx, i) {
          final pl = playlists[i];
          final thumb = pl['thumbnail']?['url'];
          final total = pl['items']?['paginatorInfo']?['total'] ?? 0;
          return InkWell(
            onTap: () => context.push('/playlist/${pl['id']}'),
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: thumb != null
                            ? CachedNetworkImage(imageUrl: thumb, width: 140, height: 140, fit: BoxFit.cover)
                            : Container(width: 140, height: 140, color: AppColors.surfaceLight, child: const Icon(Icons.queue_music, size: 32, color: AppColors.textMuted)),
                      ),
                      Positioned(
                        bottom: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.queue_music, size: 10, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('$total', style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
                          ]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(pl['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.title),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _memberSlugForTab(int t) {
    switch (t) {
      case 0: return 'cong-hien';
      case 1: return 'dong-gop';
      case 2: return 'binh-luan-yeu-thich';
      case 3: return 'nghe-nhieu';
      default: return 'cong-hien';
    }
  }

  Widget _memberTabsBar() {
    const tabs = [
      ('Cống hiến', 'contributors'),
      ('Bản thu', 'uploaders'),
      ('Bình luận', 'commentLoves'),
      ('Nghe nhiều', 'listeners'),
    ];
    // Lazy-load first tab on first render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cur = tabs[_rankTab].$2;
      if (_memberRanks[cur] == null && _memberLoading[cur] != true) _fetchMemberRank(cur);
    });
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final t = tabs[i];
          final active = i == _rankTab;
          return InkWell(
            onTap: active ? null : () {
              setState(() => _rankTab = i);
              if (_memberRanks[t.$2] == null) _fetchMemberRank(t.$2);
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: active ? AppColors.accentSoft : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: active ? AppColors.accent : AppColors.border),
              ),
              child: Text(t.$1, style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? AppColors.accentLight : AppColors.textSecondary))),
            ),
          );
        },
      ),
    );
  }

  Widget _memberBody() {
    switch (_rankTab) {
      case 0: return _memberList('contributors', valueLabel: 'điểm');
      case 1: return _memberList('uploaders', valueLabel: 'bản thu');
      case 2: return _memberList('commentLoves', valueLabel: 'lượt thích');
      case 3: return _memberList('listeners', valueLabel: 'lượt nghe');
      default: return const SizedBox.shrink();
    }
  }

  Widget _memberList(String kind, {required String valueLabel}) {
    final loading = _memberLoading[kind] == true;
    final items = _memberRanks[kind] ?? [];
    if (loading && items.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    if (items.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('Chưa có dữ liệu', style: body(const TextStyle(color: AppColors.textMuted)))));
    const medals = [Color(0xFFFFD54F), Color(0xFFB0BEC5), Color(0xFFA87451)];
    return Column(
      children: items.asMap().entries.map((e) {
        final i = e.key;
        final u = e.value;
        final isTop3 = i < 3;
        final value = u['value'] is num ? (u['value'] as num).toInt() : 0;
        return InkWell(
          onTap: u['id'] != null ? () => context.push('/user/${u['id']}') : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isTop3 ? medals[i].withValues(alpha: 0.4) : AppColors.border, width: isTop3 ? 1.2 : 1),
              boxShadow: isTop3 ? [BoxShadow(color: medals[i].withValues(alpha: 0.12), blurRadius: 12, spreadRadius: -2)] : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isTop3 ? LinearGradient(colors: [medals[i], medals[i].withValues(alpha: 0.6)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                    color: isTop3 ? null : AppColors.surface,
                    boxShadow: isTop3 ? [BoxShadow(color: medals[i].withValues(alpha: 0.5), blurRadius: 8, spreadRadius: -1)] : null,
                  ),
                  child: isTop3
                      ? Icon(i == 0 ? Icons.emoji_events : Icons.military_tech, color: Colors.white, size: 16)
                      : Text('${i + 1}', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 36, height: 36,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight])),
                  child: ClipOval(
                    child: u['avatar'] != null
                        ? CachedNetworkImage(imageUrl: u['avatar'], fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.person, color: Colors.white70))
                        : const Icon(Icons.person, color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    u['username'] ?? '?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_formatInt(value), style: display(const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
                    Text(valueLabel, style: body(const TextStyle(fontSize: 9, color: AppColors.textMuted))),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _rankingTabs() {
    const periods = [('week', 'Tuần'), ('month', 'Tháng'), ('year', 'Năm'), ('', 'Tất cả')];
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: periods.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final p = periods[i];
          final active = _chartPeriod == p.$1;
          return InkWell(
            onTap: active ? null : () => _fetchRanking(period: p.$1),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: active ? AppColors.accentSoft : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: active ? AppColors.accent : AppColors.border),
              ),
              child: Text(p.$2, style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? AppColors.accentLight : AppColors.textSecondary))),
            ),
          );
        },
      ),
    );
  }

  Widget _rankingList(List<dynamic> chart) {
    if (_chartLoading) return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    if (chart.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('Chưa có dữ liệu', style: body(const TextStyle(color: AppColors.textMuted)))));
    const medals = [Color(0xFFFFD54F), Color(0xFFB0BEC5), Color(0xFFA87451)]; // gold, silver, bronze
    return Column(
      children: chart.asMap().entries.map((e) {
        final i = e.key;
        final item = e.value;
        final s = Map<String, dynamic>.from(item['object']);
        final total = item['total'] ?? 0;
        final artists = (s['artists']?['data'] ?? []) as List;
        final isTop3 = i < 3;
        return InkWell(
          onTap: () => _openSong(s),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isTop3 ? medals[i].withValues(alpha: 0.4) : AppColors.border, width: isTop3 ? 1.2 : 1),
              boxShadow: isTop3 ? [BoxShadow(color: medals[i].withValues(alpha: 0.12), blurRadius: 12, spreadRadius: -2)] : null,
            ),
            child: Row(
              children: [
                // Medal or rank
                Container(
                  width: 32, height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isTop3
                        ? LinearGradient(colors: [medals[i], medals[i].withValues(alpha: 0.6)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                        : null,
                    color: isTop3 ? null : AppColors.surface,
                    boxShadow: isTop3 ? [BoxShadow(color: medals[i].withValues(alpha: 0.5), blurRadius: 8, spreadRadius: -1)] : null,
                  ),
                  child: isTop3
                      ? Icon(i == 0 ? Icons.emoji_events : Icons.military_tech, color: Colors.white, size: 16)
                      : Text('${i + 1}', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                ),
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: s['thumbnail']?['url'] != null
                      ? CachedNetworkImage(imageUrl: s['thumbnail']['url'], width: 44, height: 44, fit: BoxFit.cover)
                      : Container(width: 44, height: 44, color: AppColors.surface, child: const Icon(Icons.music_note, color: AppColors.textMuted)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                      if (artists.isNotEmpty) Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(artists.map((a) => a['title'] ?? '').join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_formatInt(total is num ? total.toInt() : 0), style: display(const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
                    Text('lượt', style: body(const TextStyle(fontSize: 9, color: AppColors.textMuted))),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _songCardGrid(List<dynamic> songs) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: songs.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 2.4,
      ),
      itemBuilder: (ctx, i) {
        final song = Map<String, dynamic>.from(songs[i] as Map);
        final artists = (song['artists']?['data'] ?? song['artists'] ?? []) as List;
        final thumb = song['thumbnail']?['url'];
        return InkWell(
          onTap: () => _openSong(song),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                  child: thumb != null
                      ? CachedNetworkImage(imageUrl: thumb, width: 64, height: 64, fit: BoxFit.cover)
                      : Container(width: 64, height: 64, color: AppColors.surface, child: const Icon(Icons.music_note, color: AppColors.textMuted)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text))),
                      if (artists.isNotEmpty) Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(artists.map((a) => a['title'] ?? '').join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 10, color: AppColors.textMuted))),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Container(
                    width: 28, height: 28,
                    decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _archiveTabsBar() {
    final tabs = <(IconData, String, int)>[
      (Icons.image_outlined, 'Ảnh', _galleryDocs.length),
      (Icons.audiotrack, 'Âm thanh', _audioDocs.length),
      (Icons.video_library_outlined, 'Video', _videoDocs.length),
      (Icons.article_outlined, 'Bài viết', _newsDocs.length),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final t = tabs[i];
          final active = i == _archiveTab;
          if (t.$3 == 0) return const SizedBox.shrink();
          return InkWell(
            onTap: active ? null : () => setState(() => _archiveTab = i),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.accentSoft : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? AppColors.accent : AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(t.$1, size: 14, color: active ? AppColors.accentLight : AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(t.$2, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? AppColors.accentLight : AppColors.textSecondary))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _archiveContent() {
    // Skip past tabs that have no items
    int idx = _archiveTab;
    final counts = [_galleryDocs.length, _audioDocs.length, _videoDocs.length, _newsDocs.length];
    if (counts[idx] == 0) {
      // Auto-jump to first non-empty tab
      idx = counts.indexWhere((c) => c > 0);
      if (idx < 0) return const SizedBox.shrink();
    }
    Widget child;
    switch (idx) {
      case 0: child = _imageGrid(_galleryDocs); break;
      case 1: child = _audioList(_audioDocs); break;
      case 2: child = _videoDocGrid(_videoDocs); break;
      case 3: child = Column(children: _newsDocs.map(_articleRow).toList()); break;
      default: child = const SizedBox.shrink();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (c, anim) => FadeTransition(opacity: anim, child: c),
      child: KeyedSubtree(key: ValueKey('archive-$idx'), child: child),
    );
  }

  Widget _imageGrid(List<dynamic> docs) {
    // More columns + more visible images on desktop so each thumbnail
    // shrinks instead of looking poster-sized.
    final w = MediaQuery.of(context).size.width;
    final cols = w >= 1280 ? 6 : (w >= 900 ? 5 : 3);
    final visibleCount = w >= 1280 ? 18 : (w >= 900 ? 15 : 6);
    final visible = docs.take(visibleCount).toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: visible.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols, crossAxisSpacing: 6, mainAxisSpacing: 6,
      ),
      itemBuilder: (ctx, i) {
        final d = visible[i];
        final thumb = d['thumbnail']?['url'];
        return InkWell(
          onTap: () => _openImageLightbox(docs, i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: thumb != null
                ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppColors.surfaceLight))
                : Container(color: AppColors.surfaceLight, child: const Icon(Icons.image, color: AppColors.textMuted)),
          ),
        );
      },
    );
  }

  Future<List<dynamic>> _loadMoreDocs(String docType) async {
    if (_docExhausted[docType] == true) return [];
    final nextPage = (_docPage[docType] ?? 1) + 1;
    String fields;
    switch (docType) {
      case 'image': fields = 'id slug title views downloads thumbnail { url } uploader { id username } comments(first: 0) { paginatorInfo { total } }'; break;
      case 'audio': fields = 'id slug title views downloads file { audio_url } uploader { id username } comments(first: 0) { paginatorInfo { total } }'; break;
      case 'video': fields = 'id slug title views downloads thumbnail { url } file { video_url } uploader { id username } comments(first: 0) { paginatorInfo { total } }'; break;
      default: return [];
    }
    final q = '''query(\$page: Int, \$where: WhereConditions) {
      documents(first: 12, page: \$page, orderBy: [{column: "id", order: DESC}], where: \$where) {
        data { $fields }
        paginatorInfo { currentPage lastPage }
      }
    }''';
    try {
      final data = await ApiClient.query(q, {'page': nextPage, 'where': {'AND': [{'column': 'type', 'value': docType}]}});
      final raw = data['documents'];
      final list = (raw?['data'] ?? []) as List;
      final pi = raw?['paginatorInfo'] ?? {};
      _docPage[docType] = nextPage;
      if ((pi['currentPage'] ?? 0) >= (pi['lastPage'] ?? 0)) {
        _docExhausted[docType] = true;
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  void _openImageLightbox(List<dynamic> docs, int index) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageLightbox(docs: docs, initialIndex: index, onLoadMore: () => _loadMoreDocs('image')),
    ));
  }

  void _openAudioLightbox(List<dynamic> docs, int index) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AudioLightbox(docs: docs, initialIndex: index, onLoadMore: () => _loadMoreDocs('audio')),
    ));
  }

  void _openVideoLightbox(List<dynamic> docs, int index) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => VideoLightbox(docs: docs, initialIndex: index, onLoadMore: () => _loadMoreDocs('video')),
    ));
  }

  Widget _audioList(List<dynamic> docs) {
    return Column(
      children: docs.asMap().entries.map((e) {
        final i = e.key;
        final d = e.value;
        return InkWell(
          onTap: () => _openAudioLightbox(docs, i),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title),
                      if (d['uploader']?['username'] != null) Text(d['uploader']['username'], style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                    ],
                  ),
                ),
                const Icon(Icons.graphic_eq, size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _videoDocGrid(List<dynamic> docs) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 12, childAspectRatio: 1.05,
      ),
      itemBuilder: (ctx, i) {
        final d = docs[i];
        final thumb = d['thumbnail']?['url'];
        final videoUrl = d['file']?['video_url'];
        return InkWell(
          onTap: () => _openVideoLightbox(docs, i),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(children: [
                    Positioned.fill(
                      child: thumb != null
                          ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppColors.surfaceLight))
                          : (videoUrl != null
                              ? VideoPoster(videoUrl: videoUrl)
                              : Container(color: AppColors.surfaceLight, child: const Icon(Icons.movie, color: AppColors.textMuted))),
                    ),
                    Center(
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 22),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  d['title'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _articleRow(dynamic d) {
    final excerpt = _plainExcerpt(d['content']);
    final thumb = d['thumbnail']?['url'];
    return InkWell(
      onTap: () => context.push('/tu-lieu/chi-tiet/${d['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: thumb != null
                  ? CachedNetworkImage(imageUrl: thumb, width: 64, height: 64, fit: BoxFit.cover)
                  : Container(width: 64, height: 64, color: AppColors.surface, child: const Icon(Icons.article, color: AppColors.textMuted)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(d['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.title),
                  if (excerpt.isNotEmpty) Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4))),
                  ),
                  if (d['uploader']?['username'] != null) Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(d['uploader']['username'], style: body(const TextStyle(fontSize: 10, color: AppColors.textMuted))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _Pager extends StatelessWidget {
  final int currentPage;
  final int lastPage;
  final bool loading;
  final void Function(int) onGoto;
  const _Pager({required this.currentPage, required this.lastPage, required this.loading, required this.onGoto});

  @override
  Widget build(BuildContext context) {
    final pages = <int>{1, lastPage};
    for (int i = -1; i <= 1; i++) {
      final p = currentPage + i;
      if (p >= 1 && p <= lastPage) pages.add(p);
    }
    final ordered = pages.toList()..sort();
    final children = <Widget>[
      _PageBtn(icon: Icons.chevron_left, enabled: currentPage > 1 && !loading, onTap: () => onGoto(currentPage - 1)),
    ];
    int prev = 0;
    for (final p in ordered) {
      if (prev != 0 && p - prev > 1) {
        children.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: AppColors.textMuted))));
      }
      children.add(_PageBtn(label: '$p', enabled: p != currentPage && !loading, active: p == currentPage, onTap: () => onGoto(p)));
      prev = p;
    }
    children.add(_PageBtn(icon: Icons.chevron_right, enabled: currentPage < lastPage && !loading, onTap: () => onGoto(currentPage + 1)));
    return Center(child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: children));
  }
}

class _PageBtn extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool enabled;
  final bool active;
  final VoidCallback onTap;
  const _PageBtn({this.label, this.icon, this.enabled = true, this.active = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.accent : AppColors.surfaceLight;
    final fg = active ? Colors.white : (enabled ? AppColors.text : AppColors.textMuted);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? AppColors.accent : AppColors.border),
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, size: 16, color: fg)
                : Text(label!, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg))),
          ),
        ),
      ),
    );
  }
}

/// Fades in + slides up by 8px, with a delay proportional to [index].
/// Use to reveal the first ~6 above-the-fold widgets in sequence.
class _StaggerFadeIn extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration step;
  const _StaggerFadeIn({required this.index, required this.child, this.step = const Duration(milliseconds: 70)});

  @override
  State<_StaggerFadeIn> createState() => _StaggerFadeInState();
}

class _StaggerFadeInState extends State<_StaggerFadeIn> with SingleTickerProviderStateMixin {
  late AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    Future.delayed(widget.step * widget.index, () {
      if (mounted) _ctl.forward();
    });
  }

  @override
  void dispose() { _ctl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _ctl, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(curve),
        child: widget.child,
      ),
    );
  }
}

/// Wrap any tappable card to add subtle scale-down on press.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  const PressScale({super.key, required this.child, this.onTap, this.borderRadius});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 18, height: 2,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.accent, Colors.transparent]),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: body(const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.accentLight,
              letterSpacing: 2.5,
            )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.border, Colors.transparent]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
