import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_html/flutter_html.dart';
import '../widgets/share_card.dart' show showPersonShareSheet;
import '../constants/theme.dart';
import '../widgets/ui.dart';
import '../services/api.dart';
import '../services/push.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import '../services/activity.dart';
import '../services/player.dart';
import '../widgets/list_search.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';
import '../widgets/comment_section.dart';
import '../widgets/shimmer.dart';
import '../widgets/gallery_lightbox.dart';

enum PersonType { artist, composer, poet, recomposer }

class _TypeConfig {
  final String label;
  final String queryName;
  final List<_SectionCfg> sections;
  final String routePrefix;
  const _TypeConfig({required this.label, required this.queryName, required this.sections, required this.routePrefix});
}

class _SectionCfg {
  final String key;
  final String label;
  final IconData icon;
  final String fields;
  final String fileType;
  const _SectionCfg({required this.key, required this.label, required this.icon, required this.fields, required this.fileType});
}

const _songFields = 'id title subtitle slug views likes downloads created_at play_type thumbnail { url } file { audio_url video_url duration } sheet { year composers(first: 20) { data { id slug title } } } artists(first: 5) { data { id title slug avatar { url } } }';
const _folkFields = 'id title subtitle slug views likes downloads created_at play_type thumbnail { url } file { audio_url video_url duration } recomposers(first: 5) { data { id slug title } } artists(first: 5) { data { id title slug avatar { url } } }';
const _instFields = 'id title subtitle slug views likes downloads created_at play_type thumbnail { url } file { audio_url video_url duration } sheet { year composers(first: 20) { data { id slug title } } } artists(first: 5) { data { id title slug avatar { url } } }';
const _poemFields = 'id title subtitle slug views likes downloads created_at play_type thumbnail { url } file { audio_url video_url duration } poets(first: 5) { data { id slug title } } artists(first: 5) { data { id title slug avatar { url } } }';

const _songSec = _SectionCfg(key: 'songs', label: 'Bài hát', icon: Icons.music_note, fields: _songFields, fileType: 'song');
const _folkSec = _SectionCfg(key: 'folks', label: 'Dân ca', icon: Icons.music_note, fields: _folkFields, fileType: 'folk');
const _instSec = _SectionCfg(key: 'instrumentals', label: 'Khí nhạc', icon: Icons.music_note, fields: _instFields, fileType: 'instrumental');
const _poemSec = _SectionCfg(key: 'poems', label: 'Ngâm thơ', icon: Icons.auto_stories_outlined, fields: _poemFields, fileType: 'poem');

// Media sub-tabs — each filters the person's `documents` relation by the
// `type` column. Hidden when count is 0 so a person with only photos
// doesn't get an empty "Video" tab.
class _MediaCfg {
  final String key;       // 'image' | 'audio' | 'video' | 'news'
  final String label;
  final IconData icon;
  const _MediaCfg(this.key, this.label, this.icon);
}

const _mediaSecs = <_MediaCfg>[
  _MediaCfg('image', 'Hình ảnh', Icons.photo_library_outlined),
  _MediaCfg('audio', 'Âm thanh', Icons.graphic_eq),
  _MediaCfg('video', 'Video', Icons.movie_outlined),
  _MediaCfg('news', 'Tư liệu', Icons.article_outlined),
];

const Map<PersonType, _TypeConfig> _config = {
  PersonType.artist: _TypeConfig(label: 'Nghệ sĩ', queryName: 'artist', sections: [_songSec, _folkSec, _instSec, _poemSec], routePrefix: '/nghe-si/'),
  PersonType.composer: _TypeConfig(label: 'Nhạc sĩ', queryName: 'composer', sections: [_songSec, _instSec, _folkSec], routePrefix: '/nhac-si/'),
  PersonType.poet: _TypeConfig(label: 'Nhà thơ', queryName: 'poet', sections: [_poemSec, _songSec], routePrefix: '/nha-tho/'),
  PersonType.recomposer: _TypeConfig(label: 'Soạn giả', queryName: 'recomposer', sections: [_folkSec], routePrefix: '/soan-gia/'),
};

class PersonDetailScreen extends StatefulWidget {
  final PersonType type;
  final String slug;
  const PersonDetailScreen({super.key, required this.type, required this.slug});

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _SectionState {
  final List<dynamic> items;
  final int currentPage;
  final int lastPage;
  final int total;
  final String sort;
  final bool loading;
  /// Last request failed: show a retry instead of fetching again by itself
  /// (offline, the lazy tab fetch otherwise looped forever).
  final bool failed;
  /// The next page is on its way (lists load more as they scroll).
  final bool loadingMore;
  /// Loading the next page failed: wait for a tap on "Thử lại".
  final bool moreFailed;
  /// Words in this tab's search box ('' = every song).
  final String query;
  /// Songs in the tab without a search: the tab label, the stats panel and
  /// whether the tab shows at all must not follow a search's count.
  final int allTotal;
  const _SectionState({this.items = const [], this.currentPage = 1, this.lastPage = 1, this.total = 0, this.sort = 'views', this.loading = false, this.failed = false, this.loadingMore = false, this.moreFailed = false, this.query = '', int? allTotal}) : allTotal = allTotal ?? total;

  _SectionState copyWith({List<dynamic>? items, int? currentPage, int? lastPage, int? total, String? sort, bool? loading, bool? failed, bool? loadingMore, bool? moreFailed, String? query}) =>
      _SectionState(
        items: items ?? this.items,
        currentPage: currentPage ?? this.currentPage,
        lastPage: lastPage ?? this.lastPage,
        total: total ?? this.total,
        sort: sort ?? this.sort,
        loading: loading ?? this.loading,
        failed: failed ?? this.failed,
        loadingMore: loadingMore ?? this.loadingMore,
        moreFailed: moreFailed ?? this.moreFailed,
        query: query ?? this.query,
        allTotal: allTotal,
      );

  /// Appends a page without repeating rows already shown.
  List<dynamic> appended(List<dynamic> more) {
    final seen = items.whereType<Map>().map((e) => e['id']?.toString()).toSet();
    return [...items, ...more.where((e) => e is! Map || seen.add(e['id']?.toString()))];
  }
}

// Standard song sorts; every section (songs/folks/instrumentals/poems)
// has views, likes and downloads columns. Labels come from kSongSorts, in
// the same order.
const _sortOptions = [
  ('views', 'views'),
  ('newest', 'id'),
  ('likes', 'likes'),
  ('downloads', 'downloads'),
  ('title', 'title'),
];
const _perPage = 10;

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  Map<String, dynamic>? _person;
  // ♥ Yêu thích (the web heart); fans also hear about new songs.
  bool _following = false;
  int _followers = 0;
  bool _followBusy = false;
  int _shares = 0;
  /// Songs per composition year for this composer/artist (desktop chart).
  Map<int, int> _yearCounts = {};
  /// The most listened songs, for the share picture.
  List<String> _topSongs = [];
  final Map<String, _SectionState> _sections = {};
  // Document tabs share the same _SectionState shape (items + total).
  // Sort is fixed (id DESC, newest first) so we don't reuse the sort field.
  final Map<String, _SectionState> _media = {};
  bool _loading = true;
  bool _bioExpanded = false;
  // Latest request per section: a response for an older sort/page that
  // lands late is dropped instead of overwriting the newer list.
  final Map<String, int> _reqIds = {};
  int _fetchReq = 0;
  final _nestedKey = GlobalKey<NestedScrollViewState>();

  _TypeConfig get _cfg => _config[widget.type]!;

  @override
  void initState() {
    super.initState();
    for (final c in _cfg.sections) {
      _sections[c.key] = const _SectionState();
    }
    _fetch();
  }

  @override
  void didUpdateWidget(PersonDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug || oldWidget.type != widget.type) {
      _sections.clear();
      _media.clear();
      for (final c in _cfg.sections) {
        _sections[c.key] = const _SectionState();
      }
      setState(() { _person = null; _loading = true; _bioExpanded = false; });
      _fetch();
    }
  }

  Future<void> _fetchMedia(String type, {int page = 1}) async {
    final personId = _person?['id']?.toString();
    if (personId == null) return;
    final prev = _media[type] ?? const _SectionState();
    if (prev.loading) return;
    setState(() { _media[type] = prev.copyWith(loading: true, failed: false); });
    try {
      // Field set varies per media type — match the document_archive_screen
      // shape so the existing image/audio/video/news renderers + lightbox
      // chrome (which shows the uploader badge) work as-is.
      String fields;
      switch (type) {
        case 'image':
          fields = 'id slug title views thumbnail { url } uploader { id username avatar { url } }';
          break;
        case 'audio':
          fields = 'id slug title views file { audio_url } uploader { id username avatar { url } }';
          break;
        case 'video':
          fields = 'id slug title views thumbnail { url } file { video_url } uploader { id username avatar { url } }';
          break;
        case 'news':
        default:
          fields = 'id slug title thumbnail { url } content created_at uploader { id username avatar { url } }';
      }
      final queryById = '${_cfg.queryName}ByID';
      final q = '''query(\$id: ID!, \$page: Int) {
        $queryById(id: \$id) {
          documents(first: 12, page: \$page, where: {column: "type", value: "$type"}, orderBy: [{column: "id", order: DESC}]) {
            data { $fields }
            paginatorInfo { total currentPage lastPage }
          }
        }
      }''';
      final data = await ApiClient.query(q, {'id': personId, 'page': page});
      final raw = data[queryById]?['documents'];
      if (!mounted) return;
      final newItems = (raw?['data'] ?? []) as List;
      setState(() {
        _media[type] = _SectionState(
          items: page == 1 ? newItems : prev.appended(newItems),
          currentPage: raw?['paginatorInfo']?['currentPage'] ?? page,
          lastPage: raw?['paginatorInfo']?['lastPage'] ?? 1,
          total: raw?['paginatorInfo']?['total'] ?? prev.total,
        );
      });
    } catch (_) {
      if (mounted) setState(() { _media[type] = prev.copyWith(loading: false, failed: true); });
    }
  }

  /// [fresh]: reload after a CTV change (e.g. a comment picture made the
  /// avatar) — authed POST so the CDN's cached copy is skipped.
  Future<void> _fetch({bool fresh = false}) async {
    final sectionsQuery = _cfg.sections.map((c) =>
      '${c.key}(first: 10, page: 1, orderBy: [{ column: "views", order: DESC }]) { data { ${c.fields} } paginatorInfo { total currentPage lastPage } }'
    ).join('\n');
    // Per-doc-type counts so the media tabs can render with totals before
    // their content has been fetched. Aliased so all 4 share the same
    // `documents` relation under the person.
    final mediaCountsQuery = _mediaSecs.map((m) =>
      '${m.key}Docs: documents(first: 1, page: 1, where: {column: "type", value: "${m.key}"}) { paginatorInfo { total } }'
    ).join('\n');
    final q = 'query(\$slug: String!) { ${_cfg.queryName}(slug: \$slug) { id title slug content rank real_name avatar { url user { id username } } dob mob yob dod mod yod born_address views total_listens total_downloads shares loves(first: 1) { paginatorInfo { total } } $sectionsQuery $mediaCountsQuery } }';
    final req = ++_fetchReq;
    try {
      final data = fresh
          ? await context.read<AuthProvider>().authedQuery(q, {'slug': widget.slug})
          : await ApiClient.query(q, {'slug': widget.slug});
      final p = data[_cfg.queryName];
      if (req != _fetchReq || !mounted) return;
      if (p == null) { setState(() => _loading = false); return; }
      setState(() {
        _person = Map<String, dynamic>.from(p);
        _yearCounts = {};
        _following = false;
        _followers = (p['loves']?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0;
        _shares = (p['shares'] as num?)?.toInt() ?? 0;
        _topSongs = [
          for (final c in _cfg.sections)
            for (final x in ((p[c.key]?['data'] ?? []) as List).take(3)) '${x['title'] ?? ''}'.trim(),
        ].where((t) => t.isNotEmpty).take(3).toList();
        for (final c in _cfg.sections) {
          final raw = p[c.key];
          _sections[c.key] = _SectionState(
            items: (raw?['data'] ?? []) as List,
            total: raw?['paginatorInfo']?['total'] ?? 0,
            currentPage: raw?['paginatorInfo']?['currentPage'] ?? 1,
            lastPage: raw?['paginatorInfo']?['lastPage'] ?? 1,
          );
        }
        for (final m in _mediaSecs) {
          final raw = p['${m.key}Docs'];
          _media[m.key] = _SectionState(
            total: raw?['paginatorInfo']?['total'] ?? 0,
          );
        }
        _loading = false;
      });
      if (!fresh) logActivity(context.read<AuthProvider>(), 'view', _cfg.queryName, p['id']);
      _fetchFollowing(p['id']);
    } catch (_) {
      if (req == _fetchReq && mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  /// Whether I follow this person, asked directly (a user_id filter)
  /// instead of scanning the first 500 followers.
  Future<void> _fetchFollowing(dynamic personId) async {
    final me = int.tryParse('${context.read<AuthProvider>().user?['id'] ?? ''}');
    if (me == null || personId == null) return;
    final queryById = '${_cfg.queryName}ByID';
    try {
      final d = await ApiClient.query(
        'query(\$id: ID!) { $queryById(id: \$id) { loves(first: 1, where: {column: "user_id", value: $me}) { paginatorInfo { total } } } }',
        {'id': personId.toString()},
      );
      final n = ((d[queryById]?['loves']?['paginatorInfo']?['total'] ?? 0) as num).toInt();
      if (mounted && !_followBusy && _person?['id']?.toString() == personId.toString()) setState(() => _following = n > 0);
    } catch (_) {}
  }

  bool _failed = false;

  /// [append]: the next page, added under the rows already shown (the
  /// lists load more as they scroll; a person has few songs).
  Future<void> _fetchPage(String key, int page, {String? sort, bool append = false, String? query}) async {
    final cfg = _cfg.sections.firstWhere((c) => c.key == key);
    final personId = _person?['id']?.toString();
    if (personId == null) return;
    final prev = _sections[key]!;
    final useSort = sort ?? prev.sort;
    final useQuery = query ?? prev.query;
    final sortCol = _sortOptions.firstWhere((o) => o.$1 == useSort, orElse: () => _sortOptions.first).$2;
    final order = useSort == 'title' ? 'ASC' : 'DESC';
    final req = (_reqIds[key] ?? 0) + 1;
    _reqIds[key] = req;
    setState(() {
      // Skeleton while a new list loads; the old one stays in [items] so a
      // failed request can fall back to it.
      _sections[key] = append ? prev.copyWith(loadingMore: true, moreFailed: false) : prev.copyWith(loading: true, sort: useSort, failed: false, query: useQuery);
    });
    try {
      final queryById = '${_cfg.queryName}ByID';
      final q = 'query(\$id: ID!, \$page: Int, \$q: String) { $queryById(id: \$id) { $key(first: $_perPage, page: \$page, q: \$q, orderBy: [{ column: "$sortCol", order: $order }]) { data { ${cfg.fields} } paginatorInfo { total currentPage lastPage } } } }';
      final data = await ApiClient.query(q, {'id': personId, 'page': page, 'q': useQuery});
      final raw = data[queryById]?[key];
      if (req != _reqIds[key] || !mounted) return;
      final newItems = (raw?['data'] ?? []) as List;
      setState(() {
        _sections[key] = _SectionState(
          items: append ? prev.appended(newItems) : newItems,
          total: raw?['paginatorInfo']?['total'] ?? prev.total,
          currentPage: raw?['paginatorInfo']?['currentPage'] ?? page,
          lastPage: raw?['paginatorInfo']?['lastPage'] ?? prev.lastPage,
          sort: useSort,
          loading: false,
          query: useQuery,
          allTotal: useQuery.isEmpty ? (raw?['paginatorInfo']?['total'] ?? prev.allTotal) : prev.allTotal,
        );
      });
      if (!append) _scrollListToTop();
    } catch (e) {
      if (req != _reqIds[key] || !mounted) return;
      if (append) {
        setState(() => _sections[key] = prev.copyWith(loadingMore: false, moreFailed: true));
        return;
      }
      final kept = prev.items.isNotEmpty;
      setState(() {
        // Keep the page already on screen (and its sort tab) when there is one.
        _sections[key] = kept ? prev.copyWith(loading: false, failed: false) : prev.copyWith(loading: false, sort: useSort, failed: true);
      });
      if (kept) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          action: SnackBarAction(label: 'Thử lại', onPressed: () => _fetchPage(key, page, sort: useSort)),
        ));
      }
    }
  }

  /// New page / sort: back to the top of the list (header collapsed, tab
  /// bar and sort chips in view) instead of staying at the pager.
  void _scrollListToTop() {
    final inner = _nestedKey.currentState?.innerController;
    if (inner == null || !inner.hasClients) return;
    for (final pos in inner.positions) {
      if (pos.pixels > 0) pos.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
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

  String? _formatLifeDate(Map<String, dynamic> p, String suffix) {
    int? norm(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt() == 0 ? null : v.toInt();
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      final n = int.tryParse(s);
      if (n == null) return null;
      return n == 0 ? null : n;
    }
    final d = norm(p['d$suffix']);
    final m = norm(p['m$suffix']);
    final y = norm(p['y$suffix']);
    if (d != null && m != null && y != null) return '$d/$m/$y';
    if (m != null && y != null) return '$m/$y';
    if (y != null) return y.toString();
    return null;
  }

  void _showAvatarZoom(Map<String, dynamic> p) {
    final url = p['avatar']?['url'];
    if (url == null) return;
    final creditUser = p['avatar']?['user'];
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
              ),
              Flexible(
                child: GestureDetector(
                  onTap: () {},
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: InteractiveViewer(
                      minScale: 1, maxScale: 4,
                      child: CachedNetworkImage(
                        imageUrl: url  /* full size: zoomable viewer */,
                        fit: BoxFit.contain,
                        placeholder: (_, _) => const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.white70)),
                        errorWidget: (_, _, _) => const Padding(padding: EdgeInsets.all(40), child: Icon(Icons.broken_image, color: Colors.white38, size: 48)),
                      ),
                    ),
                  ),
                ),
              ),
              if (creditUser != null) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.camera_alt_outlined, size: 14, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(creditUser['username'] ?? '', style: body(const TextStyle(fontSize: 13, color: Colors.white70))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      await askLogin(context);
      return;
    }
    if (_followBusy || _person == null) return;
    final next = !_following;
    setState(() {
      _followBusy = true;
      _following = next;
      _followers = (_followers + (next ? 1 : -1)).clamp(0, 1 << 30);
    });
    try {
      await auth.authedMutate(
        'mutation(\$id: ID!) { ${next ? 'love' : 'unlove'}(lovable_id: \$id, lovable_type: "${_cfg.queryName}") { id } }',
        {'id': _person!['id'].toString()},
      );
      if (mounted && next) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã yêu thích ${_person!['title']} — bạn sẽ được báo khi có bài mới'), duration: const Duration(seconds: 3)));
        PushService.instance.maybeAsk(context, reason: 'Nhận thông báo khi ${_person!['title']} có bài mới.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _following = !next;
          _followers = (_followers + (next ? -1 : 1)).clamp(0, 1 << 30);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${next ? 'Chưa yêu thích được' : 'Chưa bỏ yêu thích được'}. ${friendlyError(e)}'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  String? _yearCountsFor;

  /// "Tác phẩm theo năm" (desktop side column): songYearCounts for a
  /// composer or an artist; stays empty until the API has it.
  void _loadYearCounts() {
    final p = _person;
    final arg = switch (_cfg.queryName) { 'composer' => 'composer_id', 'artist' => 'artist_id', _ => null };
    if (p == null || arg == null || _yearCountsFor == '${p['id']}') return;
    _yearCountsFor = '${p['id']}';
    ApiClient.query('query(\$id: ID) { songYearCounts($arg: \$id) { year total } }', {'id': '${p['id']}'}).then((d) {
      final m = <int, int>{};
      for (final e in ((d['songYearCounts'] ?? []) as List).whereType<Map>()) {
        m[(e['year'] as num).toInt()] = (e['total'] as num).toInt();
      }
      if (mounted) setState(() => _yearCounts = m);
    }).catchError((_) {});
  }

  bool get _canEdit => context.read<AuthProvider>().hasPermission('manage_people') && _person?['id'] != null;

  /// BQT: Sửa thông tin (canvas Desktop_NgheSi_BQT, chốt 18/11).
  Future<void> _edit() async {
    final saved = await context.push<bool>('/sua-nguoi/${_cfg.queryName}/${_person!['id']}');
    if (saved == true && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Đã lưu thông tin')));
      _fetch(fresh: true);
    }
  }

  Future<void> _share() async {
    final p = _person;
    if (p == null) return;
    final first = _cfg.sections.firstWhere((c) => (_sections[c.key]?.allTotal ?? 0) > 0, orElse: () => _cfg.sections.first);
    await showPersonShareSheet(
      context,
      person: p,
      type: _cfg.queryName,
      label: _cfg.label,
      path: '${_cfg.routePrefix}${p['slug']}',
      topSongs: _topSongs,
      songCount: _sections[first.key]?.allTotal ?? 0,
      listens: ((p['total_listens'] ?? 0) as num).toInt(),
      onCount: (n) {
        if (mounted) setState(() => _shares = n);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg, elevation: 0,
          leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          title: Text(_cfg.label),
          centerTitle: true,
        ),
        body: const SingleChildScrollView(child: Column(children: [
          HeroSkeleton(circular: true),
          Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SongListSkeleton(rows: 6, showIndex: true)),
        ])),
      );
    }
    if (_person == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context))),
        body: Center(
          child: _failed
              ? OfflineBlock(onRetry: () { setState(() { _loading = true; _failed = false; }); _fetch(); })
              : const EmptyBlock(icon: Icons.person_off_outlined, title: 'Không tìm thấy', message: 'Trang này có thể đã được gộp hoặc đổi tên.'),
        ),
      );
    }

    final p = _person!;
    final player = context.watch<PlayerProvider>();
    // Hide section tabs that have no data — keeps the bar tight for niche
    // people types (e.g. recomposers usually only have folks).
    final visibleSections = _cfg.sections.where((c) => (_sections[c.key]?.allTotal ?? 0) > 0).toList();
    final visibleMedia = _mediaSecs.where((m) => (_media[m.key]?.total ?? 0) > 0).toList();

    // Tiểu sử is the first tab and the page always opens on it (18/11).
    return DefaultTabController(
      length: visibleSections.length + visibleMedia.length + 1, // +1 for Tiểu sử
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(
          children: [
            NestedScrollView(
              key: _nestedKey,
              headerSliverBuilder: (ctx, _) => [
                if (MediaQuery.sizeOf(context).width >= 900)
                  SliverAppBar(
                    pinned: true,
                    backgroundColor: AppColors.bg,
                    leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
                    title: Text(_cfg.label),
                    centerTitle: true,
                    actions: [IconButton(icon: Icon(Icons.share, color: AppColors.textSecondary), onPressed: _share)],
                  )
                else
                  _mobileHero(p),
                SliverToBoxAdapter(child: _buildHeader(p)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    tabs: [
                      const Tab(text: 'Tiểu sử'),
                      ...visibleSections.map((c) => Tab(text: '${c.label} · ${_formatInt(_sections[c.key]!.allTotal)}')),
                      ...visibleMedia.map((m) => Tab(text: '${m.label} · ${_formatInt(_media[m.key]!.total)}')),
                    ],
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  _buildBioTab(p, player.currentSong != null),
                  ...visibleSections.map((c) => _buildSectionTab(c)),
                  ...visibleMedia.map((m) => _buildMediaTab(m)),
                ],
              ),
            ),
            if (player.currentSong != null)
              const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaTab(_MediaCfg cfg) {
    final state = _media[cfg.key]!;
    // Lazy fetch on first reveal — schedule outside build to avoid setState
    // during build.
    if (state.items.isEmpty && !state.loading && !state.failed && state.total > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchMedia(cfg.key);
      });
    }
    final hasMore = state.currentPage < state.lastPage;
    if (state.loading && state.items.isEmpty) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (state.failed && state.items.isEmpty) {
      return Center(child: SingleChildScrollView(child: OfflineBlock(onRetry: () => _fetchMedia(cfg.key))));
    }
    if (state.items.isEmpty) {
      return Center(child: Text('Chưa có ${cfg.label.toLowerCase()}', style: body(TextStyle(fontSize: 16, color: AppColors.textMuted))));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        if (!state.loading && !state.failed && hasMore && n.metrics.pixels > n.metrics.maxScrollExtent - 400) {
          _fetchMedia(cfg.key, page: state.currentPage + 1);
        }
        return false;
      },
      child: ListView(
        key: PageStorageKey('person-media-${cfg.key}'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          _buildMediaContent(cfg, state.items),
          if (state.loading) Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
          if (state.failed && !state.loading) Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(child: PillButton(label: 'Chưa tải được · Thử lại', icon: Icons.refresh_rounded, primary: false, onTap: () => _fetchMedia(cfg.key, page: state.currentPage + 1))),
          ),
          if (!hasMore && state.items.isNotEmpty) Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('Đã hết', style: body(TextStyle(fontSize: 14, color: AppColors.textMuted)))),
          ),
        ],
      ),
    );
  }

  // News tab still routes to detail screen — there's no dedicated lightbox
  // for long-form articles. Image/audio/video open the same lightboxes that
  // the home page archive box uses, so navigation feels consistent.
  void _openMediaLightbox(String type, List<dynamic> items, int index) {
    final cb = () async {
      await _fetchMedia(type, page: (_media[type]?.currentPage ?? 1) + 1);
      return _media[type]?.items ?? [];
    };
    Widget lb;
    switch (type) {
      case 'image': lb = ImageLightbox(docs: items, initialIndex: index, onLoadMore: cb); break;
      case 'audio': lb = AudioLightbox(docs: items, initialIndex: index, onLoadMore: cb); break;
      case 'video': lb = VideoLightbox(docs: items, initialIndex: index, onLoadMore: cb); break;
      default: return;
    }
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => lb));
  }

  Widget _buildMediaContent(_MediaCfg cfg, List<dynamic> items) {
    switch (cfg.key) {
      case 'image':
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, crossAxisSpacing: 6, mainAxisSpacing: 6),
          itemBuilder: (ctx, i) {
            final d = Map<String, dynamic>.from(items[i] as Map);
            final thumb = d['thumbnail']?['url'];
            return InkWell(
              onTap: () => _openMediaLightbox('image', items, i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: thumb != null
                    ? CachedNetworkImage(imageUrl: cdnImg((thumb).toString(), 640), fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: AppColors.surfaceLight))
                    : Container(color: AppColors.surfaceLight, child: Icon(Icons.image, color: AppColors.textMuted)),
              ),
            );
          },
        );
      case 'video':
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 320, crossAxisSpacing: 10, mainAxisSpacing: 14, childAspectRatio: 1.05),
          itemBuilder: (ctx, i) {
            final d = Map<String, dynamic>.from(items[i] as Map);
            final thumb = d['thumbnail']?['url'];
            return InkWell(
              onTap: () => _openMediaLightbox('video', items, i),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(children: [
                        Positioned.fill(
                          child: thumb != null
                              ? CachedNetworkImage(imageUrl: cdnImg((thumb).toString(), 640), fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: AppColors.surfaceLight))
                              : Container(color: AppColors.surfaceLight, child: Icon(Icons.movie, color: AppColors.textMuted)),
                        ),
                        Center(child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle), child: const Icon(Icons.play_arrow, color: Colors.white, size: 24))),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: Text(d['title']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.35)))),
                ],
              ),
            );
          },
        );
      case 'audio':
        return Column(
          children: items.asMap().entries.map((e) {
            final i = e.key;
            final d = Map<String, dynamic>.from(e.value as Map);
            return InkWell(
              onTap: () => _openMediaLightbox('audio', items, i),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle), child: const Icon(Icons.play_arrow, color: Colors.white)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(d['title']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text))),
                      if (d['uploader']?['username'] != null) Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(d['uploader']['username'].toString(), style: body(TextStyle(fontSize: 12, color: AppColors.textMuted))),
                      ),
                    ]),
                  ),
                  Icon(Icons.graphic_eq, size: 18, color: AppColors.textMuted),
                ]),
              ),
            );
          }).toList(),
        );
      case 'news':
      default:
        return Column(
          children: items.map((it) {
            final d = Map<String, dynamic>.from(it as Map);
            final thumb = d['thumbnail']?['url'];
            final excerpt = (d['content']?.toString() ?? '').replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
            final shortExcerpt = excerpt.length > 140 ? '${excerpt.substring(0, 140)}…' : excerpt;
            return InkWell(
              onTap: () => context.push('/tu-lieu/chi-tiet/${d['id']}'),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (thumb != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(imageUrl: cdnImg((thumb).toString(), 200), width: 80, height: 60, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(width: 80, height: 60, color: AppColors.bg)),
                    )
                  else
                    Container(width: 80, height: 60, decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.article_outlined, color: AppColors.textMuted)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(d['title']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                      if (shortExcerpt.isNotEmpty) Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(shortExcerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4))),
                      ),
                    ]),
                  ),
                ]),
              ),
            );
          }).toList(),
        );
    }
  }

  Widget _buildHeader(Map<String, dynamic> p) {
    final bornDate = _formatLifeDate(p, 'ob');
    final deathDate = _formatLifeDate(p, 'od');
    final w = MediaQuery.of(context).size.width;
    final isDesktop = w >= 900;
    if (isDesktop) {
      return _buildDesktopHeader(p, bornDate, deathDate);
    }
    return _buildMobileHeader(p, bornDate, deathDate);
  }

  /// Desktop hero (canvas "Desktop · Nhạc sĩ"): a dark band with the
  /// tinted photo on the right, the round portrait, name, life line, the
  /// "Phát toàn bộ" action and the two totals.
  Widget _buildDesktopHeader(Map<String, dynamic> p, String? bornDate, String? deathDate) {
    _loadYearCounts();
    final first = _cfg.sections.firstWhere((c) => (_sections[c.key]?.allTotal ?? 0) > 0, orElse: () => _cfg.sections.first);
    final total = _sections[first.key]?.allTotal ?? 0;
    final canPlay = _sections[first.key]?.items.isNotEmpty ?? false;
    final avatar = p['avatar']?['url']?.toString();
    final rank = (p['rank'] ?? '').toString().trim();
    final life = [
      if (bornDate != null) bornDate,
      if (deathDate != null) deathDate,
      if ((p['born_address'] ?? '').toString().trim().isNotEmpty) p['born_address'].toString().trim(),
    ].join(' · ');
    Widget ghost(String label, IconData icon, VoidCallback? onTap, {bool on = false}) => Material(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(26),
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: onTap,
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 22, color: on ? AppColors.love : Colors.white),
                const SizedBox(width: 8),
                Text(label, style: body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
              ]),
            ),
          ),
        );
    Widget stat(String v, String k) => Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text(v, style: display(const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white))),
          Text(k, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xCCFFFFFF)))),
        ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: 300,
          child: Stack(fit: StackFit.expand, children: [
            Container(color: AppColors.band),
            if (avatar != null)
              Positioned(
                right: 0, top: 0, bottom: 0, width: 620,
                child: Opacity(opacity: 0.55, child: BrandTint(child: CachedNetworkImage(imageUrl: cdnImg(avatar, 1000), fit: BoxFit.cover, alignment: const Alignment(0, -0.4)))),
              ),
            DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.band, AppColors.band.withValues(alpha: 0.70), AppColors.band.withValues(alpha: 0.20)], stops: [0.3, 0.6, 1]))),
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 28, 36, 28),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                InkWell(
                  onTap: avatar != null ? () => _showAvatarZoom(p) : null,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 184, height: 184,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 4)),
                    child: ClipOval(child: avatar != null ? BrandTint(child: CachedNetworkImage(imageUrl: cdnImg(avatar, 480), fit: BoxFit.cover, errorWidget: (_, _, _) => _initialsFallback(p))) : _initialsFallback(p)),
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text([_cfg.label, if (rank.isNotEmpty) rank].join(' · ').toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, letterSpacing: 1, fontWeight: FontWeight.w800, color: Color(0xFFF6E8DE)))),
                    const SizedBox(height: 6),
                    Text(p['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 50, height: 1.05, letterSpacing: -1.1, fontWeight: FontWeight.w800, color: Colors.white))),
                    if (life.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(life, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xE6FFFFFF)))),
                    ],
                    const SizedBox(height: 18),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      Material(
                        color: AppColors.wine,
                        borderRadius: BorderRadius.circular(26),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(26),
                          onTap: canPlay ? () => _playSection(first, shuffle: false) : null,
                          child: Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.play_arrow_rounded, size: 26, color: Colors.white),
                              const SizedBox(width: 8),
                              Text('Phát toàn bộ ${_formatInt(total)} bài', style: body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
                            ]),
                          ),
                        ),
                      ),
                      ghost('Trộn bài', Icons.shuffle_rounded, canPlay ? () => _playSection(first, shuffle: true) : null),
                      ghost(_followers > 0 ? '$_followers yêu thích' : 'Yêu thích', _following ? Icons.favorite_rounded : Icons.favorite_border_rounded, _toggleFollow, on: _following),
                      ghost('Chia sẻ', Icons.ios_share_rounded, _share),
                      if (_canEdit) ghost('Sửa thông tin', Icons.edit_outlined, _edit),
                    ]),
                  ]),
                ),
                const SizedBox(width: 20),
                Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  stat(_formatInt(p['total_listens']), 'lượt nghe'),
                  const SizedBox(height: 12),
                  stat(_formatInt(p['total_downloads']), 'lượt tải'),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// Desktop side column next to the song table: songs per year, the
  /// people this one works with most, the start of the bio.
  Widget _desktopSide(Map<String, dynamic> p) {
    final eyebrow = AppText.eyebrow;
    // Collaborators: singers on a composer's songs, composers on a singer's.
    final counts = <String, (Map, int)>{};
    for (final x in (_sections['songs']?.items ?? const []).whereType<Map>()) {
      final people = _cfg.queryName == 'artist' ? (x['sheet']?['composers']?['data'] ?? const []) : (x['artists']?['data'] ?? const []);
      for (final a in (people as List).whereType<Map>()) {
        if ('${a['id']}' == '${p['id']}' && _cfg.queryName == 'artist') continue;
        final k = '${a['slug']}';
        counts[k] = (a, (counts[k]?.$2 ?? 0) + 1);
      }
    }
    final top = counts.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    final bio = (p['content'] ?? '').toString().replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'&nbsp;|\s+'), ' ').trim();
    final years = _yearCounts.keys.toList()..sort();
    final peak = _yearCounts.values.fold<int>(1, (a, b) => b > a ? b : a);
    var best = (0, 0);
    for (final y in years) {
      final five = [for (var i = 0; i < 5; i++) _yearCounts[y + i] ?? 0].fold<int>(0, (a, b) => a + b);
      if (five > best.$2) best = (y, five);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 16, 32, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (years.length > 1) ...[
          Text('TÁC PHẨM THEO NĂM', style: eyebrow),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var y = years.first; y <= years.last; y++)
                Expanded(
                  child: Tooltip(
                    message: '$y · ${_yearCounts[y] ?? 0} bài',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.5),
                      child: FractionallySizedBox(
                        heightFactor: ((_yearCounts[y] ?? 0) / peak).clamp(0.02, 1.0),
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: y >= best.$1 && y < best.$1 + 5 ? AppColors.wine : AppColors.rose.withValues(alpha: 0.45),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text('${years.first}', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
            Expanded(child: Text(best.$2 > 0 ? '${best.$1}–${best.$1 + 4} · ${best.$2} bài' : '', textAlign: TextAlign.center, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
            Text('${years.last}', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
          ]),
          const SizedBox(height: 28),
        ],
        if (top.isNotEmpty) ...[
          Text('CỘNG TÁC THƯỜNG XUYÊN', style: eyebrow),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 12, children: [
            for (final (a, _) in top.take(4))
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push('${_cfg.queryName == 'artist' ? '/nhac-si/' : '/nghe-si/'}${a['slug']}'),
                child: SizedBox(
                  width: 64,
                  child: Column(children: [
                    UserAvatar(url: a['avatar']?['url']?.toString(), name: '${a['title'] ?? ''}', size: 52),
                    const SizedBox(height: 6),
                    Text('${a['title'] ?? ''}', maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, height: 1.25, fontWeight: FontWeight.w800, color: AppColors.text))),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 28),
        ],
        if (bio.isNotEmpty) ...[
          Text('TIỂU SỬ', style: eyebrow),
          const SizedBox(height: 8),
          Text(bio, maxLines: 5, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.65, color: AppColors.textSecondary))),
          Builder(builder: (ctx) => TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                onPressed: () {
                  DefaultTabController.maybeOf(ctx)?.animateTo(0); // Tiểu sử
                },
                child: Text('Đọc tiếp', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
              )),
        ],
      ]),
    );
  }

  // Phone header (2026-11 redesign): avatar beside name, one meta line
  // (years · quê), a single stats strip, and "Phát" as the main action.
  /// Phone hero: the person's photo fills the top (brand-tinted), name and
  /// life line on it; collapses into a wine bar with the name.
  Widget _mobileHero(Map<String, dynamic> p) {
    String year(String k) => (p[k] ?? '').toString();
    final years = [year('yob'), year('yod')].where((y) => y.isNotEmpty && y != '0').join(' – ');
    final meta = [years, (p['born_address'] ?? '').toString()].where((s) => s.isNotEmpty).join(' · ');
    final rank = (p['rank'] ?? '').toString();
    final avatar = p['avatar']?['url']?.toString();
    final top = MediaQuery.paddingOf(context).top;
    Widget circle(IconData icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: Material(
            color: Colors.white.withValues(alpha: 0.9),
            shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20, color: AppColors.wine))),
          ),
        );
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 340 + top,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: avatar != null ? () => _showAvatarZoom(p) : null,
              child: avatar != null
                  ? BrandTint(child: CachedNetworkImage(imageUrl: cdnImg((avatar).toString(), 1000), fit: BoxFit.cover, alignment: const Alignment(0, -0.4), memCacheWidth: 1000))
                  : Container(decoration: BoxDecoration(gradient: LinearGradient(colors: AppColors.heroGradient))),
            ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.3, 1],
                    colors: [Color(0x400E0A0A), Color(0x000E0A0A), Color(0xE00E0A0A)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: top + 8,
              left: 12,
              right: 12,
              child: Row(children: [
                circle(Icons.arrow_back_ios_new_rounded, 'Quay lại', () => goBack(context)),
              ]),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_cfg.label, style: body(const TextStyle(fontSize: 12, letterSpacing: 0.9, fontWeight: FontWeight.w800, color: Color(0xD9FFFFFF)))),
                  const SizedBox(height: 6),
                  Text(p['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 34, height: 1.1, fontWeight: FontWeight.w800, color: Colors.white))),
                  if (meta.isNotEmpty || rank.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text([meta, rank].where((s) => s.isNotEmpty).join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w600, color: Color(0xD9FFFFFF)))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileHeader(Map<String, dynamic> p, String? bornDate, String? deathDate) {
    final first = _cfg.sections.firstWhere((c) => (_sections[c.key]?.allTotal ?? 0) > 0, orElse: () => _cfg.sections.first);
    final firstState = _sections[first.key];
    final canPlay = (firstState?.items.isNotEmpty ?? false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _StatCell(label: 'lượt nghe', value: formatViews(((p['total_listens'] ?? 0) as num).toInt())),
                  Container(width: 1, color: AppColors.border),
                  _StatCell(label: first.label.toLowerCase(), value: _formatInt(firstState?.allTotal ?? 0)),
                  Container(width: 1, color: AppColors.border),
                  _StatCell(label: 'lượt tải', value: formatViews(((p['total_downloads'] ?? 0) as num).toInt())),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // One row of controls: play, shuffle, follow (was three stacked
          // rows pushing the songs below the fold).
          Row(
            children: [
              Expanded(child: PillButton(label: 'Phát', icon: Icons.play_arrow_rounded, onTap: canPlay ? () => _playSection(first, shuffle: false) : null)),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: 'Phát ngẫu nhiên',
                excludeSemantics: true,
                child: Material(
                  color: AppColors.surface,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: canPlay ? () => _playSection(first, shuffle: true) : null,
                    child: SizedBox(width: 50, height: 50, child: Icon(Icons.shuffle_rounded, size: 22, color: AppColors.text)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _CountPill(
                icon: _following ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                count: _followers,
                active: _following,
                semantics: '${_following ? 'Đã yêu thích' : 'Yêu thích'}, $_followers người yêu thích',
                onTap: _toggleFollow,
              ),
              const SizedBox(width: 10),
              _CountPill(
                icon: Icons.ios_share_rounded,
                count: _shares,
                semantics: 'Chia sẻ, $_shares lượt chia sẻ',
                onTap: _share,
              ),
              if (_canEdit) ...[
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: 'Sửa thông tin',
                  child: Material(
                    color: AppColors.surface,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _edit,
                      child: SizedBox(width: 50, height: 50, child: Icon(Icons.edit_outlined, size: 22, color: AppColors.text)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Queue the loaded songs of [cfg] (first page, as sorted) and start.
  void _playSection(_SectionCfg cfg, {required bool shuffle}) {
    final items = (_sections[cfg.key]?.items ?? [])
        .whereType<Map>()
        .map((s) => {...Map<String, dynamic>.from(s), 'file_type': cfg.fileType})
        .where((s) => s['file']?['audio_url'] != null)
        .toList();
    if (items.isEmpty) return;
    if (shuffle) items.shuffle();
    context.read<PlayerProvider>().playSong(items.first, items, 'manual', '${_person?['title'] ?? ''} · ${cfg.label}');
  }

  Widget _buildSectionTab(_SectionCfg cfg) {
    final state = _sections[cfg.key]!;
    final queue = state.items.whereType<Map>().map((x) => {...Map<String, dynamic>.from(x), 'file_type': cfg.fileType}).toList();
    final metric = state.sort == 'newest' ? 'time' : state.sort;
    final Widget content;
    if (state.loading) {
      content = const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SongListSkeleton(rows: 8, showIndex: true));
    } else if (state.failed && state.items.isEmpty) {
      content = OfflineBlock(onRetry: () => _fetchPage(cfg.key, state.currentPage));
    } else if (state.items.isEmpty) {
      content = state.query.isNotEmpty
          ? ListSearchEmpty(query: state.query)
          : Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('Chưa có bài', style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)))));
    } else if (MediaQuery.sizeOf(context).width >= 900) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [
          _DeskSongHeader(),
          for (var i = 0; i < queue.length; i++)
            Builder(
              builder: (rowCtx) => _DeskSongRow(
                song: queue[i],
                index: i,
                byline: songByline(queue[i]),
                playing: rowCtx.select<PlayerProvider, bool>((pl) => sameSong(pl.currentSong, queue[i])),
                onTap: () => playOrOpen(context, queue[i], queue, '${_person?['title'] ?? ''} · ${cfg.label}'),
              ),
            ),
          if (state.loadingMore) const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2.4)),
        ]),
      );
    } else {
      content = Column(children: [
        for (var i = 0; i < queue.length; i++)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Builder(
            builder: (rowCtx) => SongRow(
              song: queue[i],
              highlight: state.query,
              index: i,
              showIndex: true,
              metricKey: metric,
              // Same id *and* kind: song 12 and folk 12 are different rows.
              isPlaying: rowCtx.select<PlayerProvider, bool>((pl) => sameSong(pl.currentSong, queue[i])),
              onTap: () => playOrOpen(context, queue[i], queue, '${_person?['title'] ?? ''} · ${cfg.label}'),
            ),
          )),
        if (state.loadingMore)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.accent)),
              const SizedBox(width: 10),
              Text('Đang tải thêm…', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            ]),
          )
        else if (state.moreFailed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(child: TextButton(onPressed: () => _fetchPage(cfg.key, state.currentPage + 1, append: true), child: const Text('Chưa tải được thêm · Thử lại'))),
          ),
      ]);
    }
    final list = NotificationListener<ScrollNotification>(
      // Near the bottom: fetch the next page under the rows already shown.
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600 && !state.loading && !state.loadingMore && !state.moreFailed && state.currentPage < state.lastPage && state.items.isNotEmpty) {
          _fetchPage(cfg.key, state.currentPage + 1, append: true);
        }
        return false;
      },
      child: ListView(
      key: PageStorageKey('person-${cfg.key}'),
      // No side padding on the list: the sort chips run edge to edge,
      // rows add their own 20px.
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListSearchField(
              initial: state.query,
              hint: 'Tìm trong ${_formatInt(state.allTotal)} bài${cfg.key == 'songs' ? '' : ' ${cfg.label.toLowerCase()}'} của ${_person?['title'] ?? ''}',
              onChanged: (q) => _fetchPage(cfg.key, 1, query: q),
            ),
            ListSearchSummary(query: state.query, total: state.total, loading: state.loading),
          ]),
        ),
        _buildSortBar(cfg.key, state),
        content,
      ],
    ),
    );
    if (MediaQuery.sizeOf(context).width < 1100 || _person == null) return list;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: list),
      const SizedBox(width: 8),
      SizedBox(width: 300, child: _desktopSide(_person!)),
    ]);
  }

  Widget _buildSortBar(String key, _SectionState state) {
    final selected = _sortOptions.indexWhere((o) => o.$1 == state.sort);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SortTabs(
        labels: kSongSorts,
        selected: selected < 0 ? 0 : selected,
        onSelect: (i) => _fetchPage(key, 1, sort: _sortOptions[i].$1),
      ),
    );
  }

  Widget _buildBioTab(Map<String, dynamic> p, bool hasPlayer) {
    final bio = p['content'];
    final bioPlain = bio == null ? '' : (bio as String).replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'&nbsp;|\s+'), ' ').trim();
    final hasBio = bioPlain.isNotEmpty;
    // Only a long bio gets folded behind "Xem thêm"; short ones show whole.
    final longBio = bioPlain.length > 420;
    final bioCollapsed = longBio && !_bioExpanded;
    return ListView(
      key: const PageStorageKey('person-bio'),
      padding: EdgeInsets.fromLTRB(20, 12, 20, hasPlayer ? 100 : 24),
      children: [
        if (hasBio) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: bioCollapsed ? 260 : double.infinity),
                  child: ShaderMask(
                    // Fade the cut-off edge so it reads as "there's more".
                    shaderCallback: (r) => LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0.75, 1],
                      colors: [Colors.white, bioCollapsed ? Colors.transparent : Colors.white],
                    ).createShader(r),
                    blendMode: BlendMode.dstIn,
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Html(
                        data: bio,
                        style: {'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero, fontSize: FontSize(16), lineHeight: const LineHeight(1.65), color: AppColors.text)},
                      ),
                    ),
                  ),
                ),
                if (longBio)
                  Semantics(
                    button: true,
                    child: InkWell(
                      onTap: () => setState(() => _bioExpanded = !_bioExpanded),
                      borderRadius: BorderRadius.circular(10),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_bioExpanded ? 'Thu gọn' : 'Xem thêm', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
                            const SizedBox(width: 4),
                            Icon(_bioExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 22, color: AppColors.accentLight),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Chưa có tiểu sử', style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)))),
          ),
        CommentSection(type: _cfg.queryName, id: p['id'].toString(), subjectTitle: p['title']?.toString(), onPageChanged: () => _fetch(fresh: true)),
      ],
    );
  }

  String _initial(Object? title) {
    final t = (title ?? '').toString().trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }

  Widget _initialsFallback(Map<String, dynamic> p) {
    return Container(
      color: AppColors.surfaceLight,
      alignment: Alignment.center,
      child: Text(
        _initial(p['title']),
        style: display(const TextStyle(fontSize: 42, color: Colors.white70, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final List<Tab> tabs;
  _TabBarDelegate({required this.tabs});

  @override
  double get minExtent => 50;
  @override
  double get maxExtent => 50;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: maxExtent,
      color: AppColors.bg,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: AppColors.text,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.wine,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.border,
        labelPadding: const EdgeInsets.symmetric(horizontal: 11),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        labelStyle: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        unselectedLabelStyle: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        tabs: tabs,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate old) => old.tabs.length != tabs.length;
}

class _StatInline extends StatelessWidget {
  final String label;
  final String value;
  const _StatInline({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
        textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(
        children: [
          TextSpan(text: value, style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
          TextSpan(text: ' $label', style: body(TextStyle(fontSize: 14, color: AppColors.textMuted))),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String value;
  const _MetaChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text(value, style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary))),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: display(TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text))),
          const SizedBox(height: 2),
          Text(label, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
        ],
      ),
    );
  }
}


/// ♥ / share button on the person page: icon plus the count, as on the
/// song page ("42 thích", "12 chia sẻ").
class _CountPill extends StatelessWidget {
  final IconData icon;
  final int count;
  final bool active;
  final String semantics;
  final VoidCallback onTap;
  const _CountPill({required this.icon, required this.count, this.active = false, required this.semantics, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentLight : AppColors.text;
    return Semantics(
      button: true,
      selected: active,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: active ? AppColors.accentSoft : AppColors.surface,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 50,
            constraints: const BoxConstraints(minWidth: 50),
            padding: EdgeInsets.symmetric(horizontal: count > 0 ? 16 : 13),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: active ? AppColors.love : color),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text(formatViews(count), style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color))),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Desktop song table: column titles.
class _DeskSongHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final st = body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted));
    return Container(
      height: 40,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        SizedBox(width: 36, child: Text('#', textAlign: TextAlign.right, style: st)),
        const SizedBox(width: 16),
        Expanded(flex: 5, child: Text('TÊN BÀI', style: st)),
        Expanded(flex: 3, child: Text('TRÌNH BÀY', style: st)),
        SizedBox(width: 64, child: Text('NĂM', style: st)),
        SizedBox(width: 90, child: Text('LƯỢT NGHE', textAlign: TextAlign.right, style: st)),
        const SizedBox(width: 48),
      ]),
    );
  }
}

/// One row of the desktop song table: # · cover + title · singers · year ·
/// listens · ⋯. Right click opens the same menu as ⋯.
class _DeskSongRow extends StatelessWidget {
  final Map<String, dynamic> song;
  final int index;
  final String byline;
  final bool playing;
  final VoidCallback onTap;
  const _DeskSongRow({required this.song, required this.index, required this.byline, required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final year = '${song['sheet']?['year'] ?? ''}'.trim();
    final txt = body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary));
    return draggableSong(context, song, Material(
      color: playing ? AppColors.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: AppColors.surfaceHover,
        onTap: onTap,
        onSecondaryTap: () => showSongActions(context, song),
        child: Container(
          height: 60,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
          child: Row(children: [
            SizedBox(
              width: 36,
              child: playing
                  ? Icon(Icons.graphic_eq_rounded, size: 22, color: AppColors.accentFg)
                  : Text('${index + 1}', textAlign: TextAlign.right, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: Row(children: [
                SongCover(song: song, size: 40, radius: 8),
                const SizedBox(width: 12),
                Expanded(child: Text('${song['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: playing ? AppColors.accentFg : AppColors.text)))),
              ]),
            ),
            Expanded(flex: 3, child: Text(byline, maxLines: 1, overflow: TextOverflow.ellipsis, style: txt)),
            SizedBox(width: 64, child: Text(year.isEmpty || year == '0' ? '' : year, style: txt)),
            SizedBox(width: 90, child: Text(formatViews(((song['views'] ?? 0) as num).toInt()), textAlign: TextAlign.right, style: txt)),
            SizedBox(width: 48, child: IconButton(tooltip: 'Tuỳ chọn', onPressed: () => showSongActions(context, song), icon: Icon(Icons.more_horiz_rounded, color: AppColors.textMuted))),
          ]),
        ),
      ),
    ));
  }
}
