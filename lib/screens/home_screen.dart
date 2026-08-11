import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../constants/theme.dart';
import 'package:provider/provider.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/section_header.dart';
import '../widgets/hover_effects.dart';
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
  songs: catSongs(category: \$cat, first: 10, page: \$page, orderBy: [{column: "id", order: DESC}]) {
    data { id slug title subtitle views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } }
    paginatorInfo { currentPage lastPage }
  }
}''';

// Bio fields fetched alongside the avatar so the home Featured hero
// can render bio chips (honour, real name, lifespan, hometown)
// underneath the title — gives the card editorial substance instead
// of leaving the lower half empty.
// Khám phá nghệ sĩ/nhạc sĩ — khớp query web: random, ngưỡng lượt nghe 10k,
// và lấy thêm `likes` để hiện badge lượt yêu thích trên card.
const _artistsQuery = '''query(\$where: WhereConditions) {
  artists(first: 60, random: true, where: \$where) {
    data {
      id slug title avatar { url } total_listens likes
      rank real_name yob yod born_address
    }
  }
}''';

const _composersQuery = '''query(\$where: WhereConditions) {
  composers(first: 60, random: true, where: \$where) {
    data {
      id slug title avatar { url } total_listens likes
      rank real_name yob yod born_address
    }
  }
}''';

const _artistsWhere = {
  'where': {'AND': [
    {'column': 'type', 'value': 'domestic'},
    {'column': 'is_group', 'value': '0'},
    {'column': 'total_listens', 'operator': 'GT', 'value': '10000'},
    {'column': 'image_id', 'operator': 'GT', 'value': '0'},
  ]}
};
const _composersWhere = {
  'where': {'AND': [
    {'column': 'type', 'value': 'domestic'},
    {'column': 'total_listens', 'operator': 'GT', 'value': '10000'},
    {'column': 'image_id', 'operator': 'GT', 'value': '0'},
  ]}
};

const _videoQuery = '''query {
  songs(first: 15, where: {AND: [{column: "play_type", value: "video"}]}, orderBy: [{column: "id", order: DESC}]) {
    data { id slug title subtitle views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } }
  }
}''';

const _trendingQuery = '''query {
  statisticListen(first: 10, type: "song", period: "week") {
    data { total object { ... on Song { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id title slug } } } } }
  }
}''';

const _rankingQuery = '''query {
  statisticListen(first: 10, type: "song", period: "week") {
    data { total object { ... on Song { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id title slug } } } } }
  }
}''';

const _playlistsQuery = '''query(\$where: WhereConditions) {
  playlists(first: 30, orderBy: [{column: "event_date", order: DESC}], where: \$where) {
    data { id slug title event_start event_date thumbnail { url } user { id username } }
  }
}''';

// Nhạc nhẹ nhàng — bài trong tag "Nhạc nhẹ", thứ tự ngẫu nhiên (BE random),
// giống section cùng tên trên web.
const _easyQuery = '''query {
  songsByTag(tag: "Nhạc nhẹ", random: true, first: 18) {
    data { id slug title subtitle views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } }
  }
}''';

// Đánh giá bài gửi — bài mới nhất ở forum 28 (status=1) có file + poll, khớp
// section cùng tên trên web.
const _reviewQuery = '''query(\$forumId: ID!) {
  forum(id: \$forumId) {
    discussions(first: 30, orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: 1}]}) {
      data { id title slug file { id audio_url waveform } polls(first: 1) { data { id title status options(orderBy: [{column: "position", order: ASC}]) { id name total_answer percent position } } } }
    }
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
  // Full trending list — kept around so the hero spotlight can fall
  // back to it when sticky songs are empty (otherwise spotlight
  // collapses to a single banner with no slider feel).
  List<Map<String, dynamic>> _trendingList = [];
  // Trending search keywords (chip strip above "Bài hát mới cập nhật").
  // Populated in _fetch alongside the other above-fold queries.
  List<Map<String, dynamic>> _trendingKeywords = [];
  List<dynamic> _artists = [];
  // Persisted index into `_artists` for the standalone discovery hero
  // card. -1 = pick a fresh random the next render. Reset whenever the
  // artists pool rebuilds so we don't index past the new length.
  int _featuredArtistIndex = -1;
  List<dynamic> _composers = [];
  List<dynamic> _videos = [];
  List<dynamic> _playlists = [];
  // _videos / _playlists are shuffled in `_fetch` after they land so
  // each visit to home shows a different ordering — keeps the
  // "Video nổi bật" / "Playlist nổi bật" sections feeling fresh
  // without an extra random API param.
  List<dynamic> _chartSongs = [];
  String _chartPeriod = 'week';
  String _chartType = 'song';
  bool _chartLoading = false;

  // Outer BXH tab: 0 = song chart, 1 = member chart. Lets us collapse two
  /// True once we've fired the below-fold queries (BXH chart, document
  /// archives, memorial people, events). Triggered by scroll past 600px
  /// so users who only browse the top of the home don't pay for those
  /// 9 extra round-trips on first paint.
  bool _belowFoldFetched = false;
  // ĐẶC BIỆT (Tưởng niệm + Sự kiện) outer tab.
  int _specialTab = 0;
  // Top-level member ranking tab: 0=listens 1=contributors 2=uploaders 3=commentLoves
  int _rankTab = 0;
  final Map<String, List<Map<String, dynamic>>> _memberRanks = {};
  final Map<String, bool> _memberLoading = {};
  // Which member from the loaded ranking list gets the hero spotlight — picked
  // at random per load so it isn't always the same #1 (which felt stale).
  final Map<String, int> _heroPick = {};
  // Detail card (yob, points, uploads count, comments count) for the
  // user shown in `_topMemberHero` — fetched on demand once we know
  // the current top user's id, then cached so tab switching doesn't
  // re-fire the same query.
  final Map<String, Map<String, dynamic>> _memberDetails = {};
  List<dynamic> _galleryDocs = [];
  List<dynamic> _audioDocs = [];
  List<dynamic> _videoDocs = [];
  List<dynamic> _newsDocs = [];
  // Nhạc nhẹ nhàng — bài trong tag "Nhạc nhẹ" (ngẫu nhiên), khớp section
  // cùng tên trên web. Fetch cùng nhóm above-fold vì payload nhỏ.
  List<dynamic> _easySongs = [];
  // Đánh giá bài gửi — bài forum 28 có file + poll (fetch below-fold).
  List<dynamic> _reviewUploads = [];
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
  // Personalised recommendations from `recommendedSongs` resolver. Each
  // row carries a `reason` chip ("Vì bạn nghe X") used by the carousel.
  List<Map<String, dynamic>> _recommendedSongs = [];

  // Cảm nhận hay — slider of featured comments from the top-loved
  // pool. Stable within a day, rotates daily.
  List<Map<String, dynamic>> _featuredComments = [];
  late final PageController _featuredCommentsCtrl = PageController();
  int _featuredCommentIndex = 0;
  Timer? _featuredCommentsTimer;

  // Shared rotation cadence for the auto-cycling discovery surfaces
  // (Featured artist/composer hero + Top member hero) so they feel in sync.
  static const Duration _kHeroRotate = Duration(seconds: 5);

  // Featured Person hero auto-rotate timer — re-picks `_featuredArtistIndex`
  // every few seconds so the discovery card feels alive without an
  // explicit slider.
  Timer? _featuredArtistTimer;

  // Top member hero auto-rotate timer — re-rolls `_heroPick` for the active
  // ranking tab on the same cadence as the artist hero.
  Timer? _memberHeroTimer;

  // Auto-scroll ngang cho "Nghe nhiều trong tuần" + "Khám phá nghệ sĩ" (khớp
  // web): mỗi ~4s trượt sang ~1 card, quay về đầu khi hết. Tạm dừng khi đang
  // có thao tác cuộn (auto lẫn tay) để không giật.
  final ScrollController _spotlightCtrl = ScrollController();
  final ScrollController _discoverCtrl = ScrollController();
  Timer? _autoScrollTimer;

  // Khám phá thể loại — top tags with sample thumbnails for the mosaic.
  List<Map<String, dynamic>> _popularTags = [];

  // Total song count per category (keyed by `_Cat.query`) for the "Thể loại"
  // banners — shows the size instead of a generic "Khám phá X" line.
  Map<String, int> _categoryCounts = {};

  // Tracks whether we've successfully fetched personalized data for the
  // currently logged-in user. Reset on logout so a re-login re-fetches.
  String? _personalizedUserId;

  @override
  void initState() {
    super.initState();
    _fetch();
    // AuthProvider restores from prefs asynchronously, so on first frame the
    // user may still be null — listen for the eventual notify and (re)fetch
    // once auth lands. Also fire once immediately in case auth was already
    // ready when we mounted.
    final auth = context.read<AuthProvider>();
    auth.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAuthChanged());
    _restartMemberHeroTimer();
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      _advanceScroll(_spotlightCtrl);
      _advanceScroll(_discoverCtrl);
    });
  }

  void _advanceScroll(ScrollController c) {
    if (!c.hasClients) return;
    final pos = c.position;
    // Bỏ qua nếu đang cuộn (tay hoặc animate trước chưa xong) để tránh giật.
    if (pos.isScrollingNotifier.value) return;
    final max = pos.maxScrollExtent;
    if (max <= 8) return;
    final step = pos.viewportDimension / 3; // ~1 card ở spotlight
    final target = c.offset + step >= max - 8 ? 0.0 : (c.offset + step).clamp(0.0, max);
    c.animateTo(target, duration: const Duration(milliseconds: 650), curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    context.read<AuthProvider>().removeListener(_onAuthChanged);
    _featuredCommentsTimer?.cancel();
    _featuredCommentsCtrl.dispose();
    _featuredArtistTimer?.cancel();
    _memberHeroTimer?.cancel();
    _autoScrollTimer?.cancel();
    _spotlightCtrl.dispose();
    _discoverCtrl.dispose();
    super.dispose();
  }

  /// Re-pick the Featured Person hero on a slow rotation so the
  /// discovery card cycles through the artist/composer pool without
  /// a visible slider/dots indicator. The user can still hit shuffle
  /// any time to advance manually.
  void _restartFeaturedArtistTimer() {
    _featuredArtistTimer?.cancel();
    final poolSize = _artists.length + _composers.length;
    if (poolSize < 2) return;
    _featuredArtistTimer = Timer.periodic(_kHeroRotate, (_) {
      if (!mounted) return;
      final pool = _artists.length + _composers.length;
      if (pool < 2) return;
      setState(() {
        // Force a different index than current — re-roll until we get
        // a fresh pick (avoids the rare "same person twice in a row"
        // case on small pools).
        var next = _featuredArtistIndex;
        for (var i = 0; i < 5 && next == _featuredArtistIndex; i++) {
          next = math.Random().nextInt(pool);
        }
        _featuredArtistIndex = next;
      });
    });
  }

  /// Re-roll the Top-member hero on the same cadence as the artist hero, for
  /// whichever ranking tab is currently active. Reads the live `_rankTab` each
  /// tick so it follows tab switches without needing a restart.
  void _restartMemberHeroTimer() {
    _memberHeroTimer?.cancel();
    _memberHeroTimer = Timer.periodic(_kHeroRotate, (_) {
      if (!mounted) return;
      final kind = switch (_rankTab) {
        0 => 'contributors', 1 => 'uploaders', 2 => 'commentLoves', 3 => 'listeners',
        _ => 'contributors',
      };
      final items = _memberRanks[kind];
      if (items == null || items.length < 2) return;
      setState(() {
        final cur = _heroPick[kind] ?? 0;
        var next = cur;
        for (var i = 0; i < 5 && next == cur; i++) {
          next = math.Random().nextInt(items.length);
        }
        _heroPick[kind] = next;
      });
    });
  }

  /// Auto-advance the featured-comments slider every 6s. Cancels the
  /// previous timer when re-fetched (e.g. on pull-to-refresh) so the
  /// page index stays in sync with the freshly populated list.
  void _restartFeaturedCommentsTimer() {
    _featuredCommentsTimer?.cancel();
    if (_featuredComments.length < 2) return;
    _featuredCommentsTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || _featuredComments.length < 2) return;
      final next = (_featuredCommentIndex + 1) % _featuredComments.length;
      if (_featuredCommentsCtrl.hasClients) {
        _featuredCommentsCtrl.animateToPage(
          next,
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }


  void _onAuthChanged() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final uid = auth.user?['id']?.toString();
    if (auth.isAuthenticated && uid != null && uid != _personalizedUserId) {
      _personalizedUserId = uid;
      _fetchPersonalized();
    } else if (!auth.isAuthenticated && _personalizedUserId != null) {
      _personalizedUserId = null;
      if (_recentListens.isNotEmpty || _recentLoves.isNotEmpty) {
        setState(() { _recentListens = []; _recentLoves = []; _recommendedSongs = []; });
      }
    }
  }

  Future<void> _fetchPersonalized() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.user?['id']?.toString();
    if (userId == null) return;
    try {
      // Per-query catch so a schema hiccup in one (e.g. recentListens) doesn't
      // also blank out the other (e.g. loves). Mirrors the safety net in
      // _fetch() for the public home queries.
      Future<Map<String, dynamic>> safe(Future<Map<String, dynamic>> f) =>
          f.catchError((e) {
            // ignore: avoid_print
            print('[home] personalized query failed: $e');
            return <String, dynamic>{};
          });
      final results = await Future.wait<Map<String, dynamic>>([
        safe(auth.authedQuery(r'''query($id: ID!) {
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
        }''', {'id': userId})),
        safe(auth.authedQuery(r'''query($id: ID!) {
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
        }''', {'id': userId})),
        // Personalised recommendations — flat shape with `reason` chip.
        // Doesn't need auth because the resolver takes user_id explicitly.
        safe(ApiClient.query(r'''query($id: ID!) {
          recommendedSongs(user_id: $id, limit: 30) {
            id title subtitle slug image audio_url video_url play_type file_type score reason
            artists { id title slug }
          }
        }''', {'id': userId})),
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

      // Map recommendedSongs (flat shape from RecommendedSong type) into
      // the same shape recentListens / recentLoves use, so `_songCarousel`
      // and `_shufflePlay` work on it without special casing.
      final recsRaw = ((results[2]['recommendedSongs'] ?? []) as List);
      final recs = recsRaw.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        // Wrap the flat artists list in the same `data` envelope the
        // rest of the home uses, so player/mini-player can extract
        // performers without special-casing recommendation rows.
        final artistList = ((m['artists'] as List?) ?? const [])
            .map((a) => Map<String, dynamic>.from(a as Map))
            .toList();
        return <String, dynamic>{
          'id': m['id'],
          'title': m['title'],
          'subtitle': m['subtitle'],
          'slug': m['slug'],
          'thumbnail': {'url': m['image']},
          'file': {'audio_url': m['audio_url'], 'video_url': m['video_url']},
          'play_type': m['play_type'],
          'file_type': m['file_type'] ?? 'song',
          'reason': m['reason'],
          'artists': {'data': artistList},
        };
      }).toList();

      setState(() {
        _recentListens = mapResult(results[0]['user']?['recentListens']);
        _recentLoves = mapResult(results[1]['user']?['loves']);
        _recommendedSongs = recs;
      });
    } catch (_) {}
  }

  Future<void> _fetch() async {
    // Reset below-fold guard so pull-to-refresh re-fetches everything,
    // not just the above-fold slice.
    _belowFoldFetched = false;
    // Force personalized re-fetch on pull-to-refresh too — without this,
    // a transient failure (e.g. backend timeout) sticks until the user
    // logs out and back in, because `_personalizedUserId` is already
    // pinned to the current uid.
    if (mounted && context.read<AuthProvider>().isAuthenticated) {
      _personalizedUserId = null;
      _fetchPersonalized();
    }
    setState(() => _loading = true);
    try {
      // Per-query catch so one failing section (e.g. a schema mismatch) doesn't
      // wipe the whole homepage — Future.wait rejects on first error otherwise.
      Future<Map<String, dynamic>> safe(Future<Map<String, dynamic>> f) =>
          f.catchError((_) => <String, dynamic>{});
      // Above-fold only — spotlight + KHÁM PHÁ + NGHỆ SĨ. Below-fold
      // (BXH, ĐẶC BIỆT, THƯ VIỆN) loads on scroll via [_fetchBelowFold].
      final queries = await Future.wait<Map<String, dynamic>>([
        safe(ApiClient.query(_stickyQuery)),
        safe(ApiClient.query(_trendingQuery)),
        safe(ApiClient.query(_artistsQuery, _artistsWhere)),
        safe(ApiClient.query(_composersQuery, _composersWhere)),
        safe(ApiClient.query(_videoQuery)),
        safe(ApiClient.query(_playlistsQuery, {'where': {'AND': [{'column': 'event_date', 'operator': 'IS_NOT_NULL'}, {'column': 'is_public', 'value': '1'}]}})),
        // Trending search keywords for the chip strip — small response,
        // batches with the existing above-fold queries to avoid an extra
        // round-trip on first paint.
        safe(ApiClient.query(r'query { trendingKeywords(limit: 12) { name object_type object_id } }')),
        // Cảm nhận hay — typography slider showing a few top-loved
        // comments. Tiny payload, daily-stable server side so it
        // caches well.
        safe(ApiClient.query(r'query { featuredComments(limit: 10) { id snippet likes created_at username user_avatar song_id song_title song_subtitle song_slug song_image audio_url video_url play_type file_type } }')),
        // Khám phá thể loại — top tags + sample thumbs for the mosaic.
        safe(ApiClient.query(r'query { popularTags(limit: 8) { id name slug song_count sample_images } }')),
        // Per-category totals for the "Thể loại" banners — first:1 keeps it tiny.
        safe(ApiClient.query(r'query { songs(first: 1) { paginatorInfo { total } } folks(first: 1) { paginatorInfo { total } } instrumentals(first: 1) { paginatorInfo { total } } poems(first: 1) { paginatorInfo { total } } karaokes(first: 1) { paginatorInfo { total } } }')),
        // Nhạc nhẹ nhàng — bài tag "Nhạc nhẹ" ngẫu nhiên (queries[10]).
        safe(ApiClient.query(_easyQuery)),
      ]);
      if (!mounted) return;

      final trendingList = ((queries[1]['statisticListen']?['data'] ?? []) as List).where((d) => d['object'] != null).toList();
      Map<String, dynamic>? trending;
      if (trendingList.isNotEmpty) {
        final pick = trendingList[DateTime.now().microsecond % trendingList.length];
        trending = Map<String, dynamic>.from(pick['object'] as Map);
        trending['weeklyListens'] = pick['total'];
      }

      setState(() {
        _hotSongs = (queries[0]['stickySongs'] ?? []) as List;
        _trendingSong = trending;
        _trendingList = trendingList
            .map((d) {
              final m = Map<String, dynamic>.from(d['object'] as Map);
              m['weeklyListens'] = d['total'];
              return m;
            })
            .toList();
        _artists = queries[2]['artists']?['data'] ?? [];
        // Reset random pick when the pool rebuilds.
        _featuredArtistIndex = -1;
        _composers = queries[3]['composers']?['data'] ?? [];
        _restartFeaturedArtistTimer();
        _videos = List.of(queries[4]['songs']?['data'] ?? [])..shuffle();
        // Event playlists — drop ones without a thumbnail (placeholder grey
        // tiles look broken). Keep the event_date DESC order (most recent
        // events first); no shuffle so the chronology reads.
        _playlists = List.of(queries[5]['playlists']?['data'] ?? [])
          ..removeWhere((p) {
            final t = (p as Map?)?['thumbnail'];
            final url = t is Map ? t['url']?.toString() : null;
            return url == null || url.isEmpty;
          });
        _trendingKeywords = ((queries[6]['trendingKeywords'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _featuredComments = ((queries[7]['featuredComments'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _featuredCommentIndex = 0;
        _restartFeaturedCommentsTimer();
        _popularTags = ((queries[8]['popularTags'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        int catTotal(String k) => ((queries[9][k]?['paginatorInfo']?['total']) as num?)?.toInt() ?? 0;
        _categoryCounts = {
          'songs': catTotal('songs'),
          'folks': catTotal('folks'),
          'instrumentals': catTotal('instrumentals'),
          'poems': catTotal('poems'),
          'karaokes': catTotal('karaokes'),
        };
        _easySongs = (queries[10]['songsByTag']?['data'] ?? []) as List;
        _loading = false;
      });
      _fetchLatest(_categories[_latestTab], 1);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fire the heavier below-fold queries — BXH chart, document archive,
  /// memorial people, calendar events. Triggered by [_content]'s scroll
  /// listener once the user has actually scrolled near these sections.
  /// Idempotent — guarded by [_belowFoldFetched].
  Future<void> _fetchBelowFold() async {
    if (_belowFoldFetched) return;
    _belowFoldFetched = true;
    try {
      Future<Map<String, dynamic>> safe(Future<Map<String, dynamic>> f) =>
          f.catchError((_) => <String, dynamic>{});
      final results = await Future.wait<Map<String, dynamic>>([
        safe(ApiClient.query(_rankingQuery)),
        safe(ApiClient.query(_galleryQuery, {'where': {'AND': [{'column': 'type', 'value': 'image'}]}})),
        safe(ApiClient.query(_audioQuery, {'where': {'AND': [{'column': 'type', 'value': 'audio'}]}})),
        safe(ApiClient.query(_videoDocQuery, {'where': {'AND': [{'column': 'type', 'value': 'video'}]}})),
        safe(ApiClient.query(_newsQuery, {'where': {'AND': [{'column': 'type', 'value': 'news'}]}})),
        safe(ApiClient.query(_memorialArtists, _stickyWhere)),
        safe(ApiClient.query(_memorialComposers, _stickyWhere)),
        safe(ApiClient.query(_memorialPoets, _stickyWhere)),
        safe(ApiClient.query(_memorialRecomposers, _stickyWhere)),
        safe(ApiClient.query(_reviewQuery, {'forumId': 28})),
      ]);
      final events = await _fetchEvents();
      if (!mounted) return;

      final mem = <Map<String, dynamic>>[];
      void addMem(dynamic raw, String type, String songsKey) {
        for (final p in ((raw?['data'] ?? []) as List)) {
          final m = Map<String, dynamic>.from(p as Map);
          m['personType'] = type;
          m['topSongs'] = ((m[songsKey]?['data'] ?? []) as List);
          mem.add(m);
        }
      }
      addMem(results[5]['artists'], 'artist', 'songs');
      addMem(results[6]['composers'], 'composer', 'songs');
      addMem(results[7]['poets'], 'poet', 'poems');
      addMem(results[8]['recomposers'], 'recomposer', 'folks');

      setState(() {
        _chartSongs = ((results[0]['statisticListen']?['data'] ?? []) as List).where((d) => d['object'] != null).toList();
        _galleryDocs = results[1]['documents']?['data'] ?? [];
        _audioDocs = results[2]['documents']?['data'] ?? [];
        _videoDocs = results[3]['documents']?['data'] ?? [];
        _newsDocs = results[4]['documents']?['data'] ?? [];
        _reviewUploads = ((results[9]['forum']?['discussions']?['data'] ?? []) as List)
            .where((d) => (d['file']?['audio_url']?.toString().isNotEmpty ?? false) && ((d['polls']?['data'] as List?)?.isNotEmpty ?? false))
            .take(10)
            .toList();
        _memorial = mem;
        _events = events;
      });
    } catch (_) {
      // Allow retry on next scroll if this round failed entirely.
      _belowFoldFetched = false;
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
        ${cat.query}(first: 10, page: \$page, orderBy: [{column: "id", order: DESC}]) {
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
        statisticListen(first: 10, page: 1, period: \$period, type: \$type) {
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
        q = 'query { users(first: 10, orderBy: [{column: "$field", order: DESC}], where: {AND: [{column: "$field", value: 0, operator: GT}, {column: "id", value: 1, operator: NEQ}]}) { data { id username avatar { url } $field } } }';
        final data = await ApiClient.query(q);
        items = ((data['users']?['data'] ?? []) as List).map((u) => {
          'id': u['id'], 'username': u['username'], 'avatar': u['avatar']?['url'], 'value': u[field],
        }).toList();
      } else {
        final queryName = kind == 'uploaders' ? 'topUpload' : 'topCommentLove';
        q = 'query { $queryName(first: 10) { data { username avatar user_id total } } }';
        final data = await ApiClient.query(q);
        items = ((data[queryName]?['data'] ?? []) as List).map((u) => {
          'id': u['user_id'], 'username': u['username'], 'avatar': u['avatar'], 'value': u['total'],
        }).toList();
      }
      if (!mounted) return;
      setState(() {
        _memberRanks[kind] = items;
        _heroPick[kind] = items.length <= 1 ? 0 : math.Random().nextInt(items.length);
        _memberLoading[kind] = false;
      });
    } catch (_) {
      if (mounted) setState(() => _memberLoading[kind] = false);
    }
  }

  /// Fetch bio + counters for one user — fuels the stat row inside
  /// `_topMemberHero`. paginatorInfo.total gives counts cheaply
  /// without enumerating the lists. Idempotent per user id.
  Future<void> _fetchMemberDetails(String userId) async {
    if (_memberDetails.containsKey(userId)) return;
    try {
      final data = await ApiClient.query(
        r'''query($id: ID!) {
          user(id: $id) {
            id yob point
            comments(first: 1) { paginatorInfo { total } }
            uploads(first: 1) { paginatorInfo { total } }
          }
        }''',
        {'id': userId},
      );
      final u = data['user'];
      if (u == null || !mounted) return;
      setState(() {
        _memberDetails[userId] = {
          'yob': u['yob'],
          'point': u['point'],
          'comments': u['comments']?['paginatorInfo']?['total'] ?? 0,
          'uploads': u['uploads']?['paginatorInfo']?['total'] ?? 0,
        };
      });
    } catch (_) {}
  }

  void _openSong(Map<String, dynamic> song) => context.push('/song/${song['id']}', extra: song);

  /// Play the spotlight song immediately without navigating away. Used by
  /// the inline "Phát" CTA on hero spotlight cards.
  void _playSpotlight(Map<String, dynamic> song) {
    final player = context.read<PlayerProvider>();
    player.playSong(Map<String, dynamic>.from(song));
  }

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
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          // Trigger below-fold fetch once user scrolls past the spotlight
          // (~600px). Saves ~9 GraphQL requests on first paint when the
          // user only stays on top of the page.
          if (!_belowFoldFetched && n.metrics.pixels > 600) {
            _fetchBelowFold();
          }
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: _feedItems(),
        ),
      ),
    );
  }

  List<Widget> _feedItems() {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return [
          // Quick action chips (Yêu thích / Nghe gần đây / Playlist của tôi)
          // — mobile only (desktop có sidebar). Bỏ lời chào để trang phẳng,
          // liền mạch giống web.
          if (!isDesktop && context.watch<AuthProvider>().isAuthenticated) ...[
            _quickChips(),
            const SizedBox(height: 18),
          ] else
            const SizedBox(height: 4),

          // Onboarding login CTA cho khách chưa đăng nhập.
          if (!context.watch<AuthProvider>().isAuthenticated) ...[
            _WelcomeBanner(
              onLogin: () => showDialog(context: context, builder: (_) => const LoginDialog()).then((_) {
                if (context.read<AuthProvider>().isAuthenticated) _fetchPersonalized();
              }),
            ),
            const SizedBox(height: 18),
          ],

          // Gợi ý cho bạn (chỉ khi đăng nhập) — section phẳng, bỏ nhãn nhóm.
          if (_recommendedSongs.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.auto_awesome,
              title: 'Gợi ý cho bạn',
              subtitle: 'Dựa trên nghệ sĩ, nhạc sĩ và chủ đề bạn nghe',
              count: '${_recommendedSongs.length} bài',
              onPlayAll: () => _shufflePlay(_recommendedSongs, sourceLabel: 'Gợi ý cho bạn'),
              playAllIcon: Icons.shuffle,
              playAllLabel: 'Ngẫu nhiên',
            ),
            _recommendedCarousel(_recommendedSongs),
            const SizedBox(height: 14),
          ],

          // Nghe gần đây (web đăng nhập có) — card cuộn ngang lịch sử nghe.
          if (_recentListens.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.history,
              title: 'Nghe gần đây',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/nghe-gan-day'),
            ),
            _recommendedCarousel(_recentListens),
            const SizedBox(height: 14),
          ],

          // Yêu thích gần đây (web đăng nhập có).
          if (_recentLoves.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.favorite,
              title: 'Yêu thích gần đây',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/yeu-thich'),
            ),
            _recommendedCarousel(_recentLoves),
            const SizedBox(height: 14),
          ],

          // Nghe nhiều trong tuần — dải banner nhiều màu. Web đặt SAU cụm
          // cá nhân hoá (Gợi ý/Nghe gần đây/Yêu thích), nên để ở đây.
          if (_spotlightItems().isNotEmpty) ...[
            SectionHeader(
              icon: Icons.headphones,
              title: 'Nghe nhiều trong tuần',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/bang-xep-hang'),
            ),
            _spotlightBanners(_spotlightItems()),
            const SizedBox(height: 18),
          ],

          // Bài hát mới cập nhật — bám thứ tự web.
          SectionHeader(
            icon: Icons.access_time,
            title: 'Bài hát mới cập nhật',
            onRefresh: () => _fetchLatest(_categories[_latestTab], 1),
            actionText: 'Xem tất cả',
            onAction: () => context.push('/the-loai/${_categories[_latestTab].slug}'),
          ),
          _latestTabsBar(),
          const SizedBox(height: 12),
          _latestList(),
          const SizedBox(height: 20),

          // Khám phá nghệ sĩ/nhạc sĩ — dải card cuộn ngang (khớp web).
          if (_artists.isNotEmpty || _composers.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.auto_awesome,
              title: 'Khám phá nghệ sĩ',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/nghe-si'),
            ),
            _discoverPersonStrip(),
            const SizedBox(height: 20),
          ],

          // Cảm nhận hay — dải card bình luận nổi bật (có tiêu đề như web).
          if (_featuredComments.isNotEmpty) ...[
            const SectionHeader(
              icon: Icons.chat_bubble_outline,
              title: 'Cảm nhận hay',
            ),
            _featuredCommentsSlider(_featuredComments),
            const SizedBox(height: 14),
          ],

          // Trending search keywords.
          if (_trendingKeywords.isNotEmpty) ...[
            const SectionHeader(
              icon: Icons.trending_up,
              title: 'Đang được tìm kiếm',
              subtitle: 'Từ khoá thịnh hành tuần qua',
            ),
            _trendingChipsStrip(),
            const SizedBox(height: 24),
          ],

          // Khám phá chủ đề — top tags strip.
          if (_popularTags.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.tag,
              title: 'Khám phá chủ đề',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/tag'),
            ),
            _popularTagsStrip(_popularTags),
            const SizedBox(height: 20),
          ],

          // Playlist sự kiện.
          if (_playlists.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.event_outlined,
              title: 'Playlist sự kiện',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/playlist'),
            ),
            _playlistCarousel(_playlists),
            const SizedBox(height: 20),
          ],

          // Nhạc nhẹ nhàng — lưới thẻ bài trong tag "Nhạc nhẹ" (ngẫu nhiên),
          // khớp section cùng tên trên web.
          if (_easySongs.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.spa_outlined,
              title: 'Nhạc nhẹ nhàng',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/tag/nhac-nhe'),
            ),
            _easySongGrid(_easySongs.take(18).toList()),
            const SizedBox(height: 20),
          ],

          // Thể loại.
          SectionHeader(
            icon: Icons.album_outlined,
            title: 'Thể loại',
            actionText: 'Xem tất cả',
            onAction: () => context.push('/the-loai'),
          ),
          _categoryTiles(),
          const SizedBox(height: 20),

          // Nghe nhạc theo thập niên.
          const SectionHeader(
            icon: Icons.history_edu_outlined,
            title: 'Nghe theo thập niên',
            subtitle: 'Bài hát theo năm sáng tác',
          ),
          _decadeStrip(),
          const SizedBox(height: 20),

          // Đánh giá bài gửi — bài mới cần cộng đồng nghe & bình chọn (khớp web).
          if (_reviewUploads.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.star_border,
              title: 'Đánh giá bài gửi',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/thao-luan'),
            ),
            _reviewUploadsStrip(),
            const SizedBox(height: 20),
          ],

          // Tư liệu mới — bài viết/tư liệu mới nhất, khớp "Tư liệu mới" web.
          if (_newsDocs.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.article_outlined,
              title: 'Tư liệu mới',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/tu-lieu/bai-viet'),
            ),
            _articleStrip(),
            const SizedBox(height: 20),
          ],

          // Tưởng niệm + Sự kiện gộp 1 section với outer tabs (section phẳng,
          // bỏ nhãn nhóm to cho giống web).
          if (_memorial.isNotEmpty || _events.isNotEmpty) ...[
            SectionHeader(
              icon: _specialTab == 0 ? Icons.local_florist_outlined : Icons.event_outlined,
              title: _specialTab == 0 ? 'Tưởng niệm' : 'Theo dòng sự kiện',
              subtitle: _specialTab == 0 ? 'Những nghệ sĩ đã khuất' : null,
            ),
            if (_memorial.isNotEmpty && _events.isNotEmpty) ...[
              _specialTabsBar(),
              const SizedBox(height: 14),
            ],
            if (_specialTab == 0 && _memorial.isNotEmpty)
              ..._memorial.take(3).map(_memorialCard)
            else if (_specialTab == 1 && _events.isNotEmpty)
              ..._events.map(_eventCard)
            else if (_memorial.isNotEmpty)
              ..._memorial.take(3).map(_memorialCard)
            else
              ..._events.map(_eventCard),
            const SizedBox(height: 24),
          ],

          // Top nghe nhiều + Top thành viên đặt CUỐI trang theo yêu cầu
          // (section phẳng, bỏ nhãn nhóm).
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
          const SizedBox(height: 20),

          SectionHeader(
            icon: Icons.workspace_premium_outlined,
            title: 'Top thành viên',
            subtitle: 'Thành viên đóng góp nhiều nhất cho cộng đồng',
            actionText: 'Xem tất cả',
            onAction: () => context.push('/bang-xep-hang/${_memberSlugForTab(_rankTab)}'),
          ),
          _topMemberHero(),
          _memberTabsBar(),
          const SizedBox(height: 10),
          _memberBody(),
          const SizedBox(height: 20),

          // Footer signature — slogan at the very bottom of the page.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Column(
                children: [
                  Text(
                    'BCĐCNT',
                    style: display(TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textMuted, letterSpacing: 4)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bài ca đi cùng năm tháng',
                    style: body(TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
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
  // Bảng màu gradient xoay vòng cho banner "Nghe nhiều trong tuần" (khớp web).
  static const List<List<Color>> _spotlightPalette = [
    [Color(0xFF8A1C1C), Color(0xFFC0392B)],
    [Color(0xFF1558B0), Color(0xFF2E86DE)],
    [Color(0xFF1F7A4D), Color(0xFF2ECC71)],
    [Color(0xFF6A3DA8), Color(0xFF9B59B6)],
    [Color(0xFFB9770E), Color(0xFFF0932B)],
    [Color(0xFF0E7C86), Color(0xFF16C2A3)],
  ];

  // Nghe nhiều trong tuần — dải banner ngang nhiều màu (khớp web
  // HomeSpotlight), thay HeroSpotlight xoay. Mỗi banner: gradient + thumbnail
  // + tên + nghệ sĩ/lượt nghe + nút "Nghe ngay". Bấm banner = phát ngay.
  Widget _spotlightBanners(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (ctx, c) {
      final wide = c.maxWidth >= 720;
      final cardW = wide ? (c.maxWidth - 28) / 3 : (c.maxWidth * 0.84).clamp(240.0, 400.0);
      return SizedBox(
        height: 124,
        child: ListView.separated(
          controller: _spotlightCtrl,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: items.length > 9 ? 9 : items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, i) {
            final s = items[i];
            final pal = _spotlightPalette[i % _spotlightPalette.length];
            final thumb = s['thumbnail']?['url']?.toString();
            final artists = (s['artists']?['data'] ?? s['artists'] ?? []) as List;
            final artistNames = artists.map((a) => a['title'] ?? '').where((x) => '$x'.isNotEmpty).join(', ');
            final listens = s['weeklyListens'] ?? s['views'];
            final listensN = listens is num ? listens.toInt() : null;
            final meta = [
              if (artistNames.isNotEmpty) artistNames,
              if (listensN != null) '${formatViews(listensN)} lượt nghe',
            ].join(' · ');
            return InkWell(
              onTap: () => _playSpotlight(s),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: cardW,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: pal, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: thumb != null && thumb.isNotEmpty
                        ? CachedNetworkImage(imageUrl: thumb, width: 72, height: 72, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(width: 72, height: 72, color: Colors.white24, child: const Icon(Icons.music_note, color: Colors.white70)))
                        : Container(width: 72, height: 72, color: Colors.white24, child: const Icon(Icons.music_note, color: Colors.white70)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
                      if (meta.isNotEmpty) Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75)))),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                          const SizedBox(width: 5),
                          Text('Nghe ngay', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
                        ]),
                      ),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      );
    });
  }

  List<Map<String, dynamic>> _spotlightItems() {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    void add(Map<String, dynamic> m) {
      if (out.length >= 5) return;
      final id = m['id']?.toString();
      if (id == null || seen.contains(id)) return;
      out.add(m);
      seen.add(id);
    }
    if (_trendingSong != null) add(Map<String, dynamic>.from(_trendingSong!));
    for (final s in _hotSongs) {
      if (out.length >= 5) break;
      add(Map<String, dynamic>.from(s as Map));
    }
    // Fall back to the rest of the trending list when sticky songs
    // didn't return enough — keeps the spotlight a real slider with
    // 3-5 items even on a slim above-fold dataset.
    for (final s in _trendingList) {
      if (out.length >= 5) break;
      add(Map<String, dynamic>.from(s));
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
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.06 * AppColors.shadowMul), blurRadius: 24, spreadRadius: -6, offset: const Offset(0, 4)),
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
                    gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.4 * AppColors.shadowMul), blurRadius: 16, spreadRadius: -2)],
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
                  style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 0.3)),
                ),
                const SizedBox(height: 2),
                Text(
                  'Bài ca đi cùng năm tháng',
                  style: display(TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.3, height: 1.15)),
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
              child: Icon(Icons.search, color: AppColors.textSecondary, size: 20),
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
                  gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                  boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.4 * AppColors.shadowMul), blurRadius: 12, spreadRadius: -2, offset: const Offset(0, 3))],
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

  // Carousel of personalised recommendations — same visual rhythm as
  // _songCarousel, plus a small "reason" chip below the title (Vì bạn
  // nghe X / Cùng nhạc sĩ Y / Cùng chủ đề #Z) so the rec feels
  // intentional, not random.
  /// Soft-fade the right edge of a horizontal carousel so a partially scrolled
  /// "peek" card — and its hover play button revealed near the edge — melts
  /// into the background instead of showing as a hard-clipped, broken-looking
  /// sliver. Left edge stays crisp so the first card aligns with the header.
  Widget _fadeRightEdge(double height, Widget listView) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final stop = (1 - 34 / rect.width).clamp(0.0, 1.0);
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, stop, 1.0],
        ).createShader(rect);
      },
      child: SizedBox(height: height, child: listView),
    );
  }

  Widget _recommendedCarousel(List<Map<String, dynamic>> songs) {
    return _fadeRightEdge(
      232,
      ListView.separated(
        scrollDirection: Axis.horizontal,
        // Hover zoom happens INSIDE each card's fixed frame (artwork only), so
        // cards never overflow → clip at the content edge with minimal padding.
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
        itemCount: songs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 2),
        itemBuilder: (_, i) {
          final s = songs[i];
          final thumb = s['thumbnail']?['url']?.toString();
          final reason = s['reason']?.toString() ?? '';
          return HoverCard(
            child: InkWell(
              onTap: () => _openSong(s),
              borderRadius: BorderRadius.circular(12),
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: SizedBox(
                width: 140,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  HoverRevealPlay(
                    size: 140,
                    onPlay: () => context.read<PlayerProvider>().playSong(Map<String, dynamic>.from(s)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: thumb != null
                          ? CachedNetworkImage(imageUrl: thumb, width: 140, height: 140, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(width: 140, height: 140, color: AppColors.surfaceLight))
                          : Container(width: 140, height: 140, color: AppColors.surfaceLight, child: Icon(Icons.music_note, size: 28, color: AppColors.textMuted)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(s['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 11, color: AppColors.accentLight, fontWeight: FontWeight.w500, height: 1.25))),
                  ],
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  // Cảm nhận hay — dải card cuộn ngang (khớp trang chủ web): mỗi card 1
  // bình luận nổi bật gồm avatar + tên + lượt thích, trích 3 dòng, và tên
  // bài hát ở chân. Bấm mở bài hát (deep-link tới bình luận).
  Widget _featuredCommentsSlider(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return const SizedBox.shrink();
    return _fadeRightEdge(
      160,
      ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
        itemCount: data.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _featuredCommentStripCard(data[i]),
      ),
    );
  }

  Widget _featuredCommentStripCard(Map<String, dynamic> data) {
    final snippet = (data['snippet'] ?? '').toString();
    final username = (data['username'] ?? '').toString();
    final userAvatar = data['user_avatar']?.toString();
    final songTitle = (data['song_title'] ?? '').toString();
    final likes = data['likes'] is int ? data['likes'] as int : int.tryParse('${data['likes']}') ?? 0;
    final song = <String, dynamic>{
      'id': data['song_id'],
      'title': data['song_title'],
      'subtitle': data['song_subtitle'],
      'slug': data['song_slug'],
      'thumbnail': {'url': data['song_image']},
      'file': {'audio_url': data['audio_url'], 'video_url': data['video_url']},
      'play_type': data['play_type'],
      'file_type': data['file_type'] ?? 'song',
      'highlightCommentId': data['id']?.toString(),
    };
    return InkWell(
      onTap: () => _openSong(song),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 270,
        height: 148,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ClipOval(
              child: userAvatar != null && userAvatar.isNotEmpty
                  ? CachedNetworkImage(imageUrl: userAvatar, width: 28, height: 28, fit: BoxFit.cover, errorWidget: (_, _, _) => _avatarFallback(28))
                  : _avatarFallback(28),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(username, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text)))),
            if (likes > 0) ...[
              Icon(Icons.favorite, size: 12, color: AppColors.accent),
              const SizedBox(width: 3),
              Text('$likes', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent))),
            ],
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Text(snippet, maxLines: 3, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.textSecondary))),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.music_note, size: 13, color: AppColors.accentLight),
            const SizedBox(width: 5),
            Expanded(child: Text(songTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accentLight)))),
          ]),
        ]),
      ),
    );
  }

  Widget _avatarFallback(double size) => Container(
        width: size,
        height: size,
        color: AppColors.surfaceLight,
        child: Icon(Icons.person, size: size * 0.6, color: AppColors.textMuted),
      );

  // Khám phá nghệ sĩ/nhạc sĩ — dải card cuộn ngang (khớp web): avatar tròn
  // lớn + badge lượt thích + nhãn loại + tên + lượt nghe. Trộn xen kẽ nghệ
  // sĩ & nhạc sĩ, tối đa 18 người.
  Widget _discoverPersonStrip() {
    final mixed = <Map<String, dynamic>>[];
    final maxLen = math.max(_artists.length, _composers.length);
    for (var i = 0; i < maxLen; i++) {
      if (i < _artists.length) mixed.add({...(_artists[i] as Map).cast<String, dynamic>(), '_kind': 'artist'});
      if (i < _composers.length) mixed.add({...(_composers[i] as Map).cast<String, dynamic>(), '_kind': 'composer'});
    }
    final list = mixed.take(18).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return _fadeRightEdge(
      184,
      ListView.separated(
        controller: _discoverCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final p = list[i];
          final kind = p['_kind'] as String;
          final label = kind == 'artist' ? 'NGHỆ SĨ' : 'NHẠC SĨ';
          final route = kind == 'artist' ? '/nghe-si/' : '/nhac-si/';
          final avatar = p['avatar']?['url']?.toString();
          final listens = p['total_listens'] is num ? (p['total_listens'] as num).toInt() : null;
          final likes = p['likes'] is int ? p['likes'] as int : int.tryParse('${p['likes']}') ?? 0;
          return InkWell(
            onTap: () => context.push('$route${p['slug']}'),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 120,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(clipBehavior: Clip.none, children: [
                  ClipOval(
                    child: avatar != null && avatar.isNotEmpty
                        ? CachedNetworkImage(imageUrl: avatar, width: 96, height: 96, fit: BoxFit.cover, errorWidget: (_, _, _) => _avatarFallback(96))
                        : _avatarFallback(96),
                  ),
                  if (likes > 0) Positioned(
                    top: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
                      child: Text('♥ ${formatViews(likes)}', style: body(TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white))),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(label, style: body(TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.accentLight, letterSpacing: 1))),
                const SizedBox(height: 2),
                Text(p['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                if (listens != null) ...[
                  const SizedBox(height: 2),
                  Text('${formatViews(listens)} lượt nghe', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 10.5, color: AppColors.textSecondary))),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  // Đánh giá bài gửi — dải card cuộn ngang (khớp web): tiêu đề + waveform
  // nghe thử + poll bình chọn gọn (thanh phần trăm).
  Widget _reviewUploadsStrip() {
    final items = _reviewUploads.take(10).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _reviewCard(items[i]),
      ),
    );
  }

  Widget _reviewCard(dynamic d) {
    final title = d['title']?.toString() ?? '';
    final id = d['id'];
    final audioUrl = d['file']?['audio_url']?.toString();
    final waveform = d['file']?['waveform']?.toString();
    final pollList = (d['polls']?['data'] as List?) ?? const [];
    final options = pollList.isNotEmpty ? ((pollList[0]['options'] as List?) ?? const []) : const [];
    final seed = int.tryParse('${d['id']}') ?? 0;
    // Poll 2 lựa chọn: option[0] = tán thành (👍), option[1] = phản đối (👎).
    int cnt(dynamic o) => (o is Map && o['total_answer'] is num) ? (o['total_answer'] as num).toInt() : 0;
    final upCount = options.isNotEmpty ? cnt(options[0]) : 0;
    final downCount = options.length > 1 ? cnt(options[1]) : 0;
    final total = upCount + downCount;
    final upPct = total > 0 ? (upCount / total * 100).round() : 50;
    const green = Color(0xFF4CAF50);
    const red = Color(0xFFF44336);
    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: () => context.push('/thao-luan/$id'),
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
        ),
        const SizedBox(height: 12),
        // Chừa thêm lề phải để sóng nhạc không chạm viền card.
        if (audioUrl != null && audioUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: WaveformPlayer(audioUrl: audioUrl, seed: seed, waveform: waveform, height: 56, showTimestamp: false),
          ),
        if (options.isNotEmpty) ...[
          const SizedBox(height: 14),
          // Poll gọn giống web: 👍 số | thanh xanh(up%)+đỏ | up% | 👎 số.
          Row(children: [
            Icon(Icons.thumb_up_outlined, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('$upCount', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: total > 0
                      ? Stack(children: [
                          Positioned.fill(child: Container(color: red)),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (upPct / 100).clamp(0.0, 1.0),
                            child: Container(color: green),
                          ),
                        ])
                      : Container(color: AppColors.surfaceLight),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (total > 0) ...[
              Text('$upPct%', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: green))),
              const SizedBox(width: 8),
            ],
            Icon(Icons.thumb_down_outlined, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('$downCount', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
          ]),
        ],
      ]),
    );
  }

  // Tư liệu mới — dải card cuộn ngang (khớp web): ảnh 16:9 trên, tiêu đề
  // 2 dòng + người đăng phía dưới.
  Widget _articleStrip() {
    final items = _newsDocs.take(12).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return _fadeRightEdge(
      234,
      ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _articleCard(items[i]),
      ),
    );
  }

  Widget _articleCard(dynamic d) {
    final thumb = d['thumbnail']?['url']?.toString();
    final uploader = d['uploader']?['username']?.toString();
    return InkWell(
      onTap: () => context.push('/tu-lieu/chi-tiet/${d['id']}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: thumb != null && thumb.isNotEmpty
                ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: AppColors.surfaceLight, child: Icon(Icons.article, color: AppColors.textMuted)))
                : Container(color: AppColors.surfaceLight, child: Center(child: Icon(Icons.article, size: 32, color: AppColors.textMuted))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(d['title']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.35))),
              if (uploader != null) ...[
                const SizedBox(height: 8),
                Text(uploader, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  // Cảm nhận hay — full-width typography card showing a top-loved
  // user comment on a song. Layout: gradient surface, big italic
  // quote, then a footer row with the commenter avatar/name on the
  // left and the song reference on the right. Tap opens the song.
  Widget _featuredCommentCard(Map<String, dynamic> data) {
    final snippet = (data['snippet'] ?? '').toString();
    if (snippet.trim().isEmpty) return const SizedBox.shrink();
    final username = (data['username'] ?? '').toString();
    final userAvatar = data['user_avatar']?.toString();
    final songTitle = (data['song_title'] ?? '').toString();
    final songImage = data['song_image']?.toString();
    final likes = data['likes'] is int
        ? data['likes'] as int
        : int.tryParse('${data['likes']}') ?? 0;
    final relTime = _formatRelative(data['created_at']?.toString());

    final song = <String, dynamic>{
      'id': data['song_id'],
      'title': data['song_title'],
      'subtitle': data['song_subtitle'],
      'slug': data['song_slug'],
      'thumbnail': {'url': data['song_image']},
      'file': {'audio_url': data['audio_url'], 'video_url': data['video_url']},
      'play_type': data['play_type'],
      'file_type': data['file_type'] ?? 'song',
      // Deep-link the comment so song detail scrolls to + flashes it
      // instead of dropping the user on page 1 of the comment list
      // (where the highlighted comment may not be visible).
      'highlightCommentId': data['id']?.toString(),
    };

    return InkWell(
      onTap: () => _openSong(song),
      borderRadius: BorderRadius.circular(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.accentLight.withValues(alpha: 0.35), width: 1.2),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.22 * AppColors.shadowMul), blurRadius: 22, spreadRadius: -6, offset: const Offset(0, 6))],
          ),
        child: Stack(fit: StackFit.expand, children: [
          // Song thumbnail full-bleed background — gives each comment
          // its own visual identity tied to the song it's about.
          if (songImage != null && songImage.isNotEmpty)
            CachedNetworkImage(
              imageUrl: songImage,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Container(color: AppColors.surfaceLight),
            )
          else
            Container(color: AppColors.surfaceLight),
          // Heavy dark + accent overlay so the comment text stays
          // legible no matter what's on the thumbnail. Bumped up
          // (~0.78 / ~0.92) so the typography really pops; the
          // thumbnail is still visible as a moody backdrop, not a
          // background image competing with the text.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accent.withValues(alpha: 0.78),
                  Colors.black.withValues(alpha: 0.92),
                ],
              ),
            ),
          ),
          // Big decorative quote glyph in the top-right corner —
          // editorial feel, signals "this is a quote" at a glance.
          Positioned(
            top: -6, right: -2,
            child: Icon(Icons.format_quote, size: 56, color: Colors.white.withValues(alpha: 0.18)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 26, 18),
            // spaceBetween pins header to top + footer to bottom and
            // lets the snippet sit in the middle. Shorter quotes feel
            // centred instead of bunched at the top with empty space
            // under them.
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'CẢM NHẬN HAY',
                  style: body(TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  )),
                ),
              ),
              const Spacer(),
              if (likes > 0) ...[
                Icon(Icons.favorite, size: 12, color: Colors.white.withValues(alpha: 0.85)),
                const SizedBox(width: 4),
                Text(
                  '$likes',
                  style: body(TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.9),
                  )),
                ),
              ],
              if (relTime.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '· $relTime',
                  style: body(TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                  )),
                ),
              ],
              const SizedBox(width: 32),
            ]),
            // Snippet keeps its natural height — Column's
            // spaceBetween distributes any leftover space between
            // header/footer instead of bunching it under the text.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                snippet,
                maxLines: 11,
                overflow: TextOverflow.ellipsis,
                style: brand(TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.95),
                  height: 1.55,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 0.1,
                )),
              ),
            ),
            Row(children: [
              // Commenter avatar — small circle. Falls back to a tinted
              // initial when no image is set.
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: ClipOval(
                  child: userAvatar != null && userAvatar.isNotEmpty
                      ? CachedNetworkImage(imageUrl: userAvatar, fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.person, size: 14, color: Colors.white54))
                      : Center(child: Text(
                          username.isNotEmpty ? username.characters.first.toUpperCase() : '?',
                          style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                        )),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 10),
              // Song reference — tiny thumb + title — on the right.
              // Indicates this comment is *about* a specific song.
              if (songTitle.isNotEmpty) ...[
                Icon(Icons.subdirectory_arrow_right, size: 12, color: Colors.white.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    songTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85), fontStyle: FontStyle.italic)),
                  ),
                ),
              ],
            ]),
          ]),
        ),
        ]),
      ),
      ),
    );
  }

  // Khám phá chủ đề — compact horizontal scroll strip of top tags.
  // 130×130 tiles, free flick — different rhythm to the auto-rotating
  // comment slider above so the two sliders don't compete.
  Widget _popularTagsStrip(List<Map<String, dynamic>> tags) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => HoverGlow(child: SizedBox(width: 130, child: _popularTagTile(tags[i]))),
      ),
    );
  }

  Widget _popularTagTile(Map<String, dynamic> tag) {
    final name = (tag['name'] ?? '').toString();
    final slug = (tag['slug'] ?? '').toString();
    final count = tag['song_count'] is int ? tag['song_count'] as int : int.tryParse('${tag['song_count']}') ?? 0;
    final samples = ((tag['sample_images'] as List?) ?? const [])
        .map((e) => e?.toString())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
    final thumb = samples.isNotEmpty ? samples.first : null;
    return InkWell(
      onTap: () => slug.isNotEmpty ? context.push('/tag/$slug') : null,
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(fit: StackFit.expand, children: [
          // Single representative thumbnail.
          if (thumb == null)
            Container(color: AppColors.surfaceLight)
          else
            CachedNetworkImage(
              imageUrl: thumb,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Container(color: AppColors.surfaceLight),
            ),
          // Diagonal dark + accent gradient — title sits in the
          // bottom-left corner over the heaviest part of the overlay.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Colors.black.withValues(alpha: 0.25),
                  Colors.black.withValues(alpha: 0.82),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: display(TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  )),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count bài',
                  style: body(TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.78),
                  )),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // Đang được tìm kiếm — pill tự xuống dòng (Wrap) khớp web, thay cho dải
  // cuộn ngang 1 hàng trước đây.
  Widget _trendingChipsStrip() {
    final kws = _trendingKeywords.where((k) => (k['name']?.toString() ?? '').isNotEmpty).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(kws.length, (i) {
        final name = kws[i]['name'].toString();
        return HoverGlow(
          radius: 18,
          child: InkWell(
            // Pass the keyword as `extra` so the search screen can
            // pre-fill its input + auto-run the search on first build.
            onTap: () => context.push('/search', extra: name),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (i == 0) ...[
                  Icon(Icons.local_fire_department, size: 13, color: AppColors.accentLight),
                  const SizedBox(width: 5),
                ],
                Text(name, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text))),
              ]),
            ),
          ),
        );
      }),
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
                    Text(c.$2, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _shufflePlay(List<dynamic> songs, {String? sourceLabel}) {
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
    player.playSong(queue.first, queue, 'manual', sourceLabel);
    player.setFetchMore(null);
    if (!player.shuffle) player.toggleShuffle();
  }

  /// Play the whole list in given order from the first song. Shuffle is
  /// turned off so the user gets the curated/intended sequence.
  void _playAll(List<dynamic> songs, {String? sourceLabel}) {
    if (songs.isEmpty) return;
    final queue = <Map<String, dynamic>>[];
    for (final s in songs) {
      final m = Map<String, dynamic>.from(s as Map);
      m['audioUrl'] = m['file']?['audio_url'];
      if (m['audioUrl'] != null) queue.add(m);
    }
    if (queue.isEmpty) return;
    final player = context.read<PlayerProvider>();
    player.playSong(queue.first, queue, 'manual', sourceLabel);
    player.setFetchMore(null);
    if (player.shuffle) player.toggleShuffle();
  }

  Widget _memorialCard(Map<String, dynamic> p) {
    final topSongs = (p['topSongs'] as List).take(3).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15 * AppColors.shadowMul), blurRadius: 8, offset: const Offset(0, 2))],
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
                                : Container(color: AppColors.surface, child: Icon(Icons.person, color: AppColors.textMuted)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p['title'] ?? '', style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.2))),
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
                      Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
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
                              child: Text('${e.key + 1}', style: body(TextStyle(fontSize: 10, color: AppColors.accentLight, fontWeight: FontWeight.w700))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(s['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, color: AppColors.text))),
                            ),
                            Icon(Icons.play_arrow, color: AppColors.textMuted, size: 16),
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
              decoration: BoxDecoration(
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
                child: Text(desc, style: body(TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5))),
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
          gradient: LinearGradient(
            colors: [Color(0xFF8A1717), AppColors.accent, Color(0xFFC67068)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.45 * AppColors.shadowMul), blurRadius: 24, spreadRadius: -4, offset: const Offset(0, 10))],
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
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 12, offset: const Offset(0, 4))],
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
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 8)]),
                          child: Icon(Icons.play_arrow, size: 20, color: AppColors.accent),
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
        itemCount: _categories.length, // gồm cả Thành viên hát (khớp web)
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
      return Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    }
    if (items.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Chưa có bài', style: body(TextStyle(color: AppColors.textMuted))));
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    // 10 on desktop (split 5+5) to match BXH chart density and avoid the
    // big empty space on the right of single-column rows. 5 on mobile.
    final take = items.take(isDesktop ? 10 : 5).toList();
    Widget rowFor(int i, dynamic s) {
      final song = Map<String, dynamic>.from(s);
      song['file_type'] = cat.fileType;
      // No rank highlight on "Bài hát mới cập nhật" — newly uploaded
      // songs aren't a ranking, so emphasising slots 1-3 misled the
      // reader. Index suppressed; thumbnail leads the row instead.
      return SongRow(song: song, index: i, showIndex: false, onTap: () => _openSong(song));
    }
    if (isDesktop && take.length > 1) {
      final half = (take.length / 2).ceil();
      final left = <Widget>[];
      final right = <Widget>[];
      for (var i = 0; i < take.length; i++) {
        (i < half ? left : right).add(rowFor(i, take[i]));
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: left)),
          const SizedBox(width: 24),
          Expanded(child: Column(children: right)),
        ],
      );
    }
    return Column(children: [for (var i = 0; i < take.length; i++) rowFor(i, take[i])]);
  }

  Widget _categoryTiles() {
    // Lưới 2 cột gồm cả 5 danh mục (kể cả "Thành viên hát") để khớp web.
    // Item lẻ cuối cùng chiếm trọn 1 hàng. LayoutBuilder đo theo bề rộng nội
    // dung thực (không phải bề rộng cửa sổ) để sidebar desktop không ép wrap.
    final cats = _categories;
    return LayoutBuilder(builder: (ctx, c) {
      final tileW = (c.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: List.generate(cats.length, (i) {
          final cat = cats[i];
          // Danh mục cuối (lẻ) chiếm trọn hàng cho cân đối.
          final fullRow = i == cats.length - 1 && cats.length.isOdd;
          return SizedBox(
            width: fullRow ? c.maxWidth : tileW,
            child: _categoryBanner(cat),
          );
        }),
      );
    });
  }

  Widget _categoryBanner(_Cat c) {
    return HoverScale(
      child: InkWell(
      onTap: () => context.push('/the-loai/${c.slug}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c.bg, Color.lerp(c.bg, Colors.black, 0.3)!],
            begin: Alignment.centerLeft, end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: c.bg.withValues(alpha: 0.35 * AppColors.shadowMul), blurRadius: 16, spreadRadius: -4, offset: const Offset(0, 6)),
          ],
        ),
        child: Row(children: [
          // Sheen accent — soft circle on the right side.
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: Icon(c.icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: display(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.2)),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatInt(_categoryCounts[c.query] ?? 0)} bài',
                  style: body(const TextStyle(fontSize: 11, color: Colors.white70)),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward, color: Colors.white70, size: 18),
        ]),
      ),
      ),
    );
  }

  // Decade quick-links — horizontal strip into /bai-hat/thap-nien/{d}.
  // Older decades come first (chronological reading) since BCĐCNT's
  // identity is tied to older eras anyway.
  Widget _decadeStrip() {
    final now = DateTime.now().year;
    final decades = <int>[];
    for (var d = 1940; d <= now; d += 10) {
      decades.add(d);
    }
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: decades.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final d = decades[i];
          final tint = HSLColor.fromAHSL(
            1,
            (i * 38) % 360,
            0.45,
            0.32,
          ).toColor();
          return HoverGlow(
            child: InkWell(
            onTap: () => context.push('/bai-hat/thap-nien/$d'),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 124,
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [tint, Color.lerp(tint, Colors.black, 0.35)!],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.35 * AppColors.shadowMul), blurRadius: 14, spreadRadius: -4, offset: const Offset(0, 4))],
              ),
              child: Stack(clipBehavior: Clip.hardEdge, children: [
                // Decorative 2-digit year stamp — clipped by the
                // outer ClipRRect so it never bleeds past the rounded
                // corners.
                Positioned(
                  right: -4, top: -6,
                  child: Text(
                    '${d % 100}',
                    style: display(TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withValues(alpha: 0.12),
                      height: 1,
                    )),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.album, size: 18, color: Colors.white.withValues(alpha: 0.85)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'THẬP NIÊN',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: body(TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.white.withValues(alpha: 0.7))),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '$d',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: display(const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ]),
            ),
          ),
          );
        },
      ),
    );
  }

  /// Combine artists + composers into one alternating list, tagging each
  /// with `_kind` so the unified carousel can route to the right detail.
  List<dynamic> _mixPeople() {
    final out = <dynamic>[];
    final maxLen = _artists.length > _composers.length ? _artists.length : _composers.length;
    for (var i = 0; i < maxLen; i++) {
      if (i < _artists.length) out.add({...(_artists[i] as Map), '_kind': 'artist'});
      if (i < _composers.length) out.add({...(_composers[i] as Map), '_kind': 'composer'});
    }
    return out;
  }

  /// [routePrefix] null → each item carries its own `_kind` and routes to
  /// the matching detail page (`/nghe-si/<slug>` for artist,
  /// `/nhac-si/<slug>` for composer).
  Widget _personCarousel(List<dynamic> people, String? routePrefix) {
    final w = MediaQuery.of(context).size.width;
    final av = w >= 1280 ? 110.0 : (w >= 900 ? 96.0 : 80.0);
    return SizedBox(
      height: av + 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final p = people[i];
          final avatar = p['avatar']?['url'];
          final route = routePrefix != null
              ? '$routePrefix${p['slug']}'
              : (p['_kind'] == 'composer' ? '/nhac-si/${p['slug']}' : '/nghe-si/${p['slug']}');
          return HoverScale(
            child: InkWell(
              onTap: () => context.push(route),
              borderRadius: BorderRadius.circular(av / 2),
              child: SizedBox(
                width: av,
                child: Column(
                  children: [
                    Container(
                      width: av, height: av,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                      ),
                      child: ClipOval(
                        child: avatar != null
                            ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover)
                            : Center(child: Text((p['title'] ?? '?').toString().substring(0, 1).toUpperCase(), style: display(const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white70)))),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(p['title'] ?? '', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Format an event date for the playlist badge. `event_start` is a recurring
  /// day in "MM-DD" form (no year) → shown as "DD/MM"; `event_date` is a full
  /// "yyyy-MM-dd" → shown as "DD/MM/yyyy". Returns '' when null/unparseable so
  /// the badge stays hidden.
  String _fmtEventDate(String? s) {
    if (s == null) return '';
    s = s.trim();
    if (s.isEmpty) return '';
    final mmdd = RegExp(r'^(\d{1,2})-(\d{1,2})$').firstMatch(s);
    if (mmdd != null) {
      final mm = mmdd.group(1)!.padLeft(2, '0');
      final dd = mmdd.group(2)!.padLeft(2, '0');
      return '$dd/$mm';
    }
    final d = DateTime.tryParse(s);
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Widget _playlistCarousel(List<dynamic> playlists) {
    final w = MediaQuery.of(context).size.width;
    final card = w >= 1280 ? 180.0 : (w >= 900 ? 160.0 : 140.0);
    return SizedBox(
      // +76 (not +60): HoverCard's 6px padding + the 2-line title need the
      // extra room, same as the song carousels.
      height: card + 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: playlists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (ctx, i) {
          final pl = playlists[i];
          final thumb = pl['thumbnail']?['url'];
          final eventDate = _fmtEventDate((pl['event_date'] ?? pl['event_start'])?.toString());
          return HoverCard(
            child: InkWell(
              onTap: () => context.push('/playlist/${pl['id']}'),
              borderRadius: BorderRadius.circular(12),
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: SizedBox(
                width: card,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      children: [
                        // Same hover as song cards: artwork zooms in its frame
                        // + a reveal play button, inside the HoverCard fill.
                        HoverRevealPlay(
                          size: card,
                          onPlay: () => context.push('/playlist/${pl['id']}'),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: thumb != null
                                ? CachedNetworkImage(imageUrl: thumb, width: card, height: card, fit: BoxFit.cover)
                                : Container(width: card, height: card, color: AppColors.surfaceLight, child: Icon(Icons.queue_music, size: 32, color: AppColors.textMuted)),
                          ),
                        ),
                        // Event start date badge (top-left, clear of the
                        // bottom-right reveal play button).
                        if (eventDate.isNotEmpty) Positioned(
                          top: 6, left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.event, size: 10, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(eventDate, style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
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

  /// ĐẶC BIỆT outer tabs — switch between Tưởng niệm and Sự kiện cards.
  Widget _specialTabsBar() {
    const tabs = [
      (Icons.local_florist_outlined, 'Tưởng niệm'),
      (Icons.event_outlined, 'Sự kiện'),
    ];
    return Row(
      children: List.generate(tabs.length, (i) {
        final t = tabs[i];
        final active = i == _specialTab;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InkWell(
            onTap: active ? null : () => setState(() => _specialTab = i),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? AppColors.accent : AppColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(t.$1, size: 14, color: active ? AppColors.accentLight : AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(t.$2, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? AppColors.accentLight : AppColors.textSecondary))),
              ]),
            ),
          ),
        );
      }),
    );
  }


  Widget _memberTabsBar() {
    // Unified underline style — matches `_latestTabsBar` + `_rankingTabs`.
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
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (ctx, i) {
          final t = tabs[i];
          final active = i == _rankTab;
          return InkWell(
            onTap: active ? null : () {
              setState(() => _rankTab = i);
              if (_memberRanks[t.$2] == null) _fetchMemberRank(t.$2);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: active ? AppColors.accentLight : Colors.transparent, width: 2)),
              ),
              child: Text(t.$1, style: body(TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? AppColors.accentLight : AppColors.textSecondary))),
            ),
          );
        },
      ),
    );
  }

  // Spotlight card for the #1 member of the currently-selected ranking
  // tab. Sits above the tab bar so the leading contributor gets a hero
  // moment regardless of which leaderboard the user is browsing.
  // Header copy follows the active tab (Top Cống hiến / Top Bản thu /
  // Top Bình luận / Top Nghe nhiều) — tab strip below already lets the
  // user switch, so we don't need a separate stats strip inside the
  // hero.
  Widget _topMemberHero() {
    const labels = {
      0: ('Cống hiến', 'điểm'),
      1: ('Bản thu', 'bản thu'),
      2: ('Bình luận', 'lượt thích'),
      3: ('Nghe nhiều', 'lượt nghe'),
    };
    final kind = switch (_rankTab) {
      0 => 'contributors', 1 => 'uploaders', 2 => 'commentLoves', 3 => 'listeners',
      _ => 'contributors',
    };
    final items = _memberRanks[kind] ?? [];
    if (items.isEmpty) return const SizedBox.shrink();
    final heroIdx = (_heroPick[kind] ?? 0).clamp(0, items.length - 1);
    final top = Map<String, dynamic>.from(items[heroIdx] as Map);
    final username = top['username']?.toString() ?? '?';
    final value = top['value'] is num ? (top['value'] as num).toInt() : 0;
    final avatar = top['avatar']?.toString();
    final userId = top['id']?.toString();
    final activeLabel = labels[_rankTab] ?? labels[0]!;
    const gold = Color(0xFFFFD700);
    // Bright gold glows nicely on dark, but as text/border on near-white it's
    // almost illegible. Use a deep goldenrod for ink on the light theme.
    final isLight = AppColors.bg.computeLuminance() > 0.5;
    final goldInk = isLight ? const Color(0xFFA9791C) : gold;

    // Lazy-fetch the bio + counter detail block for this user.
    if (userId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_memberDetails.containsKey(userId)) _fetchMemberDetails(userId);
      });
    }
    final details = userId != null ? _memberDetails[userId] : null;
    final age = _ageFromYob(details?['yob']?.toString());
    final cmtCount = details?['comments'] is num ? (details!['comments'] as num).toInt() : null;
    final uploadCount = details?['uploads'] is num ? (details!['uploads'] as num).toInt() : null;
    final point = details?['point'] is num ? (details!['point'] as num).toInt() : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: userId != null ? () => context.push('/user/$userId') : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: isLight
                  ? [gold.withValues(alpha: 0.42), gold.withValues(alpha: 0.14)]
                  : [gold.withValues(alpha: 0.22), AppColors.surfaceLight.withValues(alpha: 0.6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: goldInk.withValues(alpha: isLight ? 0.55 : 0.45), width: 1.2),
            boxShadow: [BoxShadow(color: gold.withValues(alpha: 0.18 * AppColors.shadowMul), blurRadius: 18, spreadRadius: -4, offset: const Offset(0, 6))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 68, height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                    border: Border.all(color: gold, width: 2),
                  ),
                  child: ClipOval(
                    child: avatar != null
                        ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.person, color: Colors.white70, size: 32))
                        : const Icon(Icons.person, color: Colors.white70, size: 32),
                  ),
                ),
                Positioned(
                  top: -10, right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: gold.withValues(alpha: 0.5 * AppColors.shadowMul), blurRadius: 8)]),
                    child: const Icon(Icons.workspace_premium, size: 16, color: Colors.black87),
                  ),
                ),
              ]),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    'TOP ${activeLabel.$1.toUpperCase()}',
                    style: body(TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: goldInk)),
                  ),
                  const SizedBox(height: 4),
                  Text(username, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text))),
                  const SizedBox(height: 3),
                  Text('${_formatInt(value)} ${activeLabel.$2}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500))),
                ]),
              ),
              const SizedBox(width: 10),
              if (userId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: goldInk.withValues(alpha: 0.65)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person_outline, size: 13, color: goldInk),
                    const SizedBox(width: 5),
                    Text('Hồ sơ', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: goldInk))),
                  ]),
                ),
            ]),
            // Stat strip — secondary numbers about the spotlit user.
            // Each chip falls out when its value is unknown (e.g. the
            // user has no DOB on file).
            () {
              final chips = <Widget>[];
              if (age != null) chips.add(_topMemberStatChip(Icons.cake_outlined, '$age tuổi'));
              if (point != null && point > 0) chips.add(_topMemberStatChip(Icons.workspace_premium_outlined, '${_formatInt(point)} điểm'));
              if (uploadCount != null && uploadCount > 0) chips.add(_topMemberStatChip(Icons.upload_outlined, '${_formatInt(uploadCount)} bản thu'));
              if (cmtCount != null && cmtCount > 0) chips.add(_topMemberStatChip(Icons.chat_bubble_outline, '${_formatInt(cmtCount)} bình luận'));
              if (chips.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(spacing: 8, runSpacing: 6, children: chips),
              );
            }(),
          ]),
        ),
      ),
    );
  }

  Widget _topMemberStatChip(IconData icon, String text) {
    // Dark scrim chip on dark themes; on the light theme a translucent-white
    // chip keeps the dark label readable on the pale card.
    final isLight = AppColors.bg.computeLuminance() > 0.5;
    final goldInk = isLight ? const Color(0xFFA9791C) : const Color(0xFFFFD700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isLight ? Colors.white.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: goldInk),
        const SizedBox(width: 5),
        Text(
          text,
          style: body(TextStyle(fontSize: 12, color: AppColors.text, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  /// Years between yob (4-digit) and the current year. Null when yob
  /// is empty / unparseable / clearly nonsense.
  /// "2 năm trước" / "3 ngày trước" — Vietnamese relative time. Null
  /// when the input doesn't parse as a date.
  String _formatRelative(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inDays >= 365) return '${diff.inDays ~/ 365} năm trước';
    if (diff.inDays >= 30) return '${diff.inDays ~/ 30} tháng trước';
    if (diff.inDays >= 1) return '${diff.inDays} ngày trước';
    if (diff.inHours >= 1) return '${diff.inHours} giờ trước';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} phút trước';
    return 'vừa xong';
  }

  int? _ageFromYob(String? yob) {
    if (yob == null || yob.isEmpty) return null;
    final n = int.tryParse(yob);
    if (n == null) return null;
    final now = DateTime.now().year;
    if (n < 1900 || n > now) return null;
    return now - n;
  }

  // Discovery hero — picks a RANDOM person (artist OR composer) so each
  // refresh surfaces a different face from either pool. The card now
  // also previews the person's top 3 songs underneath the header so
  // it feels substantive rather than a single avatar floating in
  // gradient space. Shuffle button re-rolls.
  Widget _featuredArtistHero() {
    final pool = <Map<String, dynamic>>[
      for (final a in _artists) {...Map<String, dynamic>.from(a as Map), '_kind': 'artist'},
      for (final c in _composers) {...Map<String, dynamic>.from(c as Map), '_kind': 'composer'},
    ];
    if (pool.isEmpty) return const SizedBox.shrink();
    if (_featuredArtistIndex < 0 || _featuredArtistIndex >= pool.length) {
      _featuredArtistIndex = math.Random().nextInt(pool.length);
    }
    final top = pool[_featuredArtistIndex];
    final isComposer = top['_kind'] == 'composer';
    final name = top['title']?.toString() ?? '?';
    final slug = top['slug']?.toString();
    final avatar = top['avatar']?['url']?.toString();
    final listens = top['total_listens'] is num ? (top['total_listens'] as num).toInt() : 0;
    final realName = top['real_name']?.toString().trim() ?? '';
    final rank = top['rank']?.toString().trim() ?? '';
    final yob = top['yob']?.toString().trim() ?? '';
    final yod = top['yod']?.toString().trim() ?? '';
    final bornAt = top['born_address']?.toString().trim() ?? '';
    final route = isComposer ? '/nhac-si/' : '/nghe-si/';
    final label = isComposer ? 'KHÁM PHÁ NHẠC SĨ' : 'KHÁM PHÁ NGHỆ SĨ';
    // Light theme: a low-alpha dark-red accent over near-white desaturates into
    // a washed-out pink. Use a stronger, warmer accent tint so the card keeps
    // its identity colour.
    final isLight = AppColors.bg.computeLuminance() > 0.5;
    return MouseRegion(
      onEnter: (_) => _featuredArtistTimer?.cancel(),
      onExit: (_) => _restartFeaturedArtistTimer(),
      child: InkWell(
      onTap: slug != null ? () => context.push('$route$slug') : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: isLight
                ? [AppColors.accentLight.withValues(alpha: 0.46), AppColors.accentLight.withValues(alpha: 0.18)]
                : [AppColors.accent.withValues(alpha: 0.32), AppColors.surfaceLight.withValues(alpha: 0.6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: AppColors.accent.withValues(alpha: isLight ? 0.40 : 0.45), width: 1.2),
          boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.22 * AppColors.shadowMul), blurRadius: 18, spreadRadius: -4, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                border: Border.all(color: AppColors.accentLight, width: 2),
              ),
              child: ClipOval(
                child: avatar != null
                    ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.person, color: Colors.white70, size: 30))
                    : const Icon(Icons.person, color: Colors.white70, size: 30),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Icon(isComposer ? Icons.music_note_outlined : Icons.mic, size: 12, color: AppColors.accentLight),
                  const SizedBox(width: 5),
                  Text(label, style: body(TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: AppColors.accentLight))),
                ]),
                const SizedBox(height: 4),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text))),
                if (listens > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${_formatInt(listens)} lượt nghe',
                    style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            // Shuffle CTA — re-pick a different person from the pool.
            InkWell(
              onTap: () => setState(() => _featuredArtistIndex = math.Random().nextInt(pool.length)),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.surfaceLight, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
                child: Icon(Icons.shuffle, size: 16, color: AppColors.textSecondary),
              ),
            ),
          ]),
          // Bio row — real name, lifespan, hometown. Each fact is a
          // small icon-prefixed chip so the row reads as "encyclopaedia
          // entry" not as a paragraph. Skips facts that are empty so
          // we never render a chip with nothing inside.
          () {
            final chips = <Widget>[];
            // Award/honour first (NSƯT / NSND / Giải thưởng …) —
            // visually heaviest and most newsworthy, so it leads.
            if (rank.isNotEmpty) {
              chips.add(_featuredArtistBioChip(Icons.workspace_premium_outlined, rank, accent: true));
            }
            if (realName.isNotEmpty && realName.toLowerCase() != name.toLowerCase()) {
              chips.add(_featuredArtistBioChip(Icons.badge_outlined, realName));
            }
            final lifespan = _formatLifespan(yob, yod);
            if (lifespan.isNotEmpty) {
              chips.add(_featuredArtistBioChip(Icons.cake_outlined, lifespan));
            }
            if (bornAt.isNotEmpty) {
              chips.add(_featuredArtistBioChip(Icons.location_on_outlined, bornAt));
            }
            if (chips.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: chips,
              ),
            );
          }(),
        ]),
      ),
      ),
    );
  }

  Widget _featuredArtistBioChip(IconData icon, String text, {bool accent = false}) {
    final isLight = AppColors.bg.computeLuminance() > 0.5;
    final bg = accent
        ? AppColors.accent.withValues(alpha: 0.45)
        : (isLight ? Colors.white.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.22));
    final border = accent
        ? AppColors.accentLight.withValues(alpha: 0.6)
        : AppColors.border;
    final iconColor = accent ? Colors.white : AppColors.accentLight;
    final textColor = accent ? Colors.white : AppColors.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: iconColor),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: body(TextStyle(fontSize: 12, color: textColor, fontWeight: accent ? FontWeight.w700 : FontWeight.w500)),
          ),
        ),
      ]),
    );
  }

  /// Render `yob`–`yod` as "1925 - 1985", "1925 - " (still alive
  /// missing yod), or "1985†" (missing yob), filtering null/empty.
  String _formatLifespan(String yob, String yod) {
    if (yob.isEmpty && yod.isEmpty) return '';
    if (yob.isEmpty) return '$yod †';
    if (yod.isEmpty) return 'Sinh $yob';
    return '$yob - $yod';
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
    if (loading && items.isEmpty) return Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    if (items.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('Chưa có dữ liệu', style: body(TextStyle(color: AppColors.textMuted)))));
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final rows = items.asMap().entries.map((e) => _memberRow(e.key, e.value as Map<String, dynamic>, valueLabel)).toList();
    if (isDesktop && rows.length > 1) {
      // Match BXH song chart: 2-col grid, fills wide column instead of
      // leaving a sparse single-column list.
      final half = (rows.length / 2).ceil();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: rows.sublist(0, half))),
          const SizedBox(width: 24),
          Expanded(child: Column(children: rows.sublist(half))),
        ],
      );
    }
    return Column(children: rows);
  }

  Widget _memberRow(int i, Map<String, dynamic> u, String valueLabel) {
    final isTop3 = i < 3;
    final value = u['value'] is num ? (u['value'] as num).toInt() : 0;
    return HoverHighlight(
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: u['id'] != null ? () => context.push('/user/${u['id']}') : null,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          // No bottom divider — it cut across the rounded hover highlight.
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${i + 1}',
                  textAlign: TextAlign.center,
                  style: body(TextStyle(
                    fontSize: isTop3 ? 18 : 13,
                    fontWeight: isTop3 ? FontWeight.w900 : FontWeight.w600,
                    color: isTop3 ? AppColors.accentLight : AppColors.textMuted,
                    letterSpacing: -0.5,
                  )),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight])),
                child: ClipOval(
                  child: u['avatar'] != null
                      ? CachedNetworkImage(imageUrl: u['avatar'], fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.person, color: Colors.white70))
                      : const Icon(Icons.person, color: Colors.white70),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  u['username'] ?? '?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                ),
              ),
              const SizedBox(width: 8),
              Text('${_formatInt(value)} $valueLabel', style: AppText.caption),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rankingTabs() {
    // Unified underline style — matches `_latestTabsBar` so the page reads
    // with one tab idiom instead of mixing pill + underline.
    const periods = [('week', 'Tuần'), ('month', 'Tháng'), ('year', 'Năm'), ('', 'Tất cả')];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: periods.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (ctx, i) {
          final p = periods[i];
          final active = _chartPeriod == p.$1;
          return InkWell(
            onTap: active ? null : () => _fetchRanking(period: p.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: active ? AppColors.accentLight : Colors.transparent, width: 2)),
              ),
              child: Text(p.$2, style: body(TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? AppColors.accentLight : AppColors.textSecondary))),
            ),
          );
        },
      ),
    );
  }

  Widget _rankingList(List<dynamic> chart) {
    if (_chartLoading) return Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    if (chart.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('Chưa có dữ liệu', style: body(TextStyle(color: AppColors.textMuted)))));
    // Editorial chart row — same visual rhythm as SongRow elsewhere on the
    // page (no boxed cards, no medal gradients). Top-3 rank is bold accent
    // type; everyone else is muted. Listen count reads as "1.2K lượt
    // nghe" inline next to the row.
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final rows = chart.asMap().entries.map(_chartRow).toList();
    if (isDesktop && rows.length > 1) {
      // Split 10 into 2 cols of 5 — fills the wide main column instead of
      // leaving big empty whitespace right of the listen count.
      final half = (rows.length / 2).ceil();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: rows.sublist(0, half))),
          const SizedBox(width: 24),
          Expanded(child: Column(children: rows.sublist(half))),
        ],
      );
    }
    return Column(children: rows);
  }

  Widget _chartRow(MapEntry<int, dynamic> e) {
    final i = e.key;
    final item = e.value;
    final s = Map<String, dynamic>.from(item['object']);
    // Stuff the period total into `weeklyListens` so SongRow surfaces it
    // with the headphones icon (otherwise it would fall back to lifetime
    // `views`). SongRow with showIndex already handles top-3 highlight.
    if (item['total'] != null) s['weeklyListens'] = item['total'];
    return SongRow(song: s, index: i, showIndex: true, onTap: () => _openSong(s));
  }

  /// Compact integer formatter — 1234 → "1.2K", 1234567 → "1.2M". Returns
  /// `_formatInt(n)` (full grouping) for values < 1K so small numbers stay
  /// exact.

  // Nhạc nhẹ nhàng — lưới thẻ cover VUÔNG (khớp web): 3 cột (mobile) / 6
  // cột (desktop), ảnh 1:1 + nút phát góc dưới-phải, tên 2 dòng + nghệ sĩ.
  Widget _easySongGrid(List<dynamic> songs) {
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth >= 900 ? 6 : 3;
      const gap = 10.0;
      final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: 14,
        children: songs.map((raw) {
          final s = Map<String, dynamic>.from(raw as Map);
          final thumb = s['thumbnail']?['url']?.toString();
          final artists = (s['artists']?['data'] ?? s['artists'] ?? []) as List;
          final artistNames = artists.map((a) => a['title'] ?? '').where((x) => '$x'.isNotEmpty).join(', ');
          return SizedBox(
            width: tileW,
            child: InkWell(
              onTap: () => _openSong(s),
              borderRadius: BorderRadius.circular(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: thumb != null && thumb.isNotEmpty
                        ? CachedNetworkImage(imageUrl: thumb, width: tileW, height: tileW, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(width: tileW, height: tileW, color: AppColors.surfaceLight, child: Icon(Icons.music_note, color: AppColors.textMuted)))
                        : Container(width: tileW, height: tileW, color: AppColors.surfaceLight, child: Icon(Icons.music_note, color: AppColors.textMuted)),
                  ),
                  Positioned(
                    right: 6, bottom: 6,
                    child: GestureDetector(
                      onTap: () => context.read<PlayerProvider>().playSong(s),
                      child: Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.accent, shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(s['title']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3))),
                if (artistNames.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 1), child: Text(artistNames, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 11, color: AppColors.textMuted)))),
              ]),
            ),
          );
        }).toList(),
      );
    });
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
                      : Container(width: 64, height: 64, color: AppColors.surface, child: Icon(Icons.music_note, color: AppColors.textMuted)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text))),
                      if (artists.isNotEmpty) Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(artists.map((a) => a['title'] ?? '').join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 10, color: AppColors.textMuted))),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
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
    // Filter out empty tabs so the bar collapses naturally; keep original
    // index so tap dispatch still maps correctly.
    final visible = tabs.asMap().entries.where((e) => e.value.$3 > 0).toList();
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(width: 18),
          itemBuilder: (ctx, i) {
            final originalIndex = visible[i].key;
            final t = visible[i].value;
            final active = originalIndex == _archiveTab;
            return InkWell(
              onTap: active ? null : () => setState(() => _archiveTab = originalIndex),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: active ? AppColors.accentLight : Colors.transparent, width: 2)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(t.$1, size: 14, color: active ? AppColors.accentLight : AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(t.$2, style: body(TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? AppColors.accentLight : AppColors.textSecondary))),
                ]),
              ),
            );
          },
        ),
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
                : Container(color: AppColors.surfaceLight, child: Icon(Icons.image, color: AppColors.textMuted)),
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
                  decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title),
                      if (d['uploader']?['username'] != null) Text(d['uploader']['username'], style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
                    ],
                  ),
                ),
                Icon(Icons.graphic_eq, size: 18, color: AppColors.textMuted),
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
                              : Container(color: AppColors.surfaceLight, child: Icon(Icons.movie, color: AppColors.textMuted))),
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
                  style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3)),
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
                  : Container(width: 64, height: 64, color: AppColors.surface, child: Icon(Icons.article, color: AppColors.textMuted)),
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
                    child: Text(excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4))),
                  ),
                  if (d['uploader']?['username'] != null) Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(d['uploader']['username'], style: body(TextStyle(fontSize: 10, color: AppColors.textMuted))),
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
        children.add(Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: AppColors.textMuted))));
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

/// Soft-sell login banner shown to non-authed users on home, right
/// after the spotlight. Frames sign-in as the path to personalised
/// content (yêu thích, lịch sử, playlist) without hard-blocking the
/// editorial content below.
class _WelcomeBanner extends StatelessWidget {
  final VoidCallback onLogin;
  const _WelcomeBanner({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [AppColors.accent.withValues(alpha: 0.18), AppColors.surface],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
          ),
          child: const Icon(Icons.favorite_outline, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Trải nghiệm cá nhân hoá', style: display(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text))),
              const SizedBox(height: 2),
              Text('Đăng nhập để lưu bài yêu thích, lịch sử nghe và tạo playlist riêng.', style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4))),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: onLogin,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: Text('Đăng nhập', style: body(const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        ),
      ]),
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
              gradient: LinearGradient(colors: [AppColors.accent, Colors.transparent]),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: body(TextStyle(
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
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.border, Colors.transparent]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a square thumbnail and reveals an inline "play" CTA in the
/// bottom-right corner. On desktop the CTA only appears while the
/// pointer is over the card — keeps the carousel uncluttered. On
/// touch (no hover) the CTA stays visible since there's no other way
/// to surface it without adding a long-press affordance.
/// Renders the first frame of a video as a static thumbnail. Used for
/// the home video carousel when a song lacks a manual thumbnail. The
/// VideoPlayer is created paused at offset 0 — no audio, no playback,
/// just the frame. Falls back to a tinted placeholder while loading
/// or on error so the carousel never shows a flicker of black.
class _VideoFrameThumbnail extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  const _VideoFrameThumbnail({required this.url, required this.width, required this.height});

  @override
  State<_VideoFrameThumbnail> createState() => _VideoFrameThumbnailState();
}

class _VideoFrameThumbnailState extends State<_VideoFrameThumbnail> {
  VideoPlayerController? _ctl;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final ctl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await ctl.initialize();
      await ctl.setVolume(0);
      // Already at offset 0 after initialize(); keep paused so the
      // first frame is what's painted.
      if (!mounted) { ctl.dispose(); return; }
      setState(() { _ctl = ctl; _ready = true; });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || (_ctl != null && !_ctl!.value.isInitialized)) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: AppColors.surfaceLight,
        child: Icon(Icons.movie, color: AppColors.textMuted),
      );
    }
    if (!_ready || _ctl == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: AppColors.surfaceLight,
      );
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _ctl!.value.size.width,
          height: _ctl!.value.size.height,
          child: VideoPlayer(_ctl!),
        ),
      ),
    );
  }
}
