import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_html/flutter_html.dart';
import '../services/share.dart';
import '../constants/theme.dart';
import '../widgets/ui.dart';
import '../widgets/auth_dialogs.dart';
import '../services/api.dart';
import '../services/push.dart';
import '../services/auth.dart';
import '../services/activity.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import 'home_mobile_screen.dart' show playOrOpen;
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
  const _SectionState({this.items = const [], this.currentPage = 1, this.lastPage = 1, this.total = 0, this.sort = 'views', this.loading = false});

  _SectionState copyWith({List<dynamic>? items, int? currentPage, int? lastPage, int? total, String? sort, bool? loading}) =>
      _SectionState(
        items: items ?? this.items,
        currentPage: currentPage ?? this.currentPage,
        lastPage: lastPage ?? this.lastPage,
        total: total ?? this.total,
        sort: sort ?? this.sort,
        loading: loading ?? this.loading,
      );
}

const _sortOptions = [
  ('views', 'Nghe nhiều', 'views'),
  ('newest', 'Mới nhất', 'id'),
  ('likes', 'Yêu thích', 'likes'),
];

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  Map<String, dynamic>? _person;
  // Theo dõi = ♥ on the person page (same `like` data as the web heart).
  bool _following = false;
  int _followers = 0;
  bool _followBusy = false;
  final Map<String, _SectionState> _sections = {};
  // Document tabs share the same _SectionState shape (items + total).
  // Sort is fixed (id DESC, newest first) so we don't reuse the sort field.
  final Map<String, _SectionState> _media = {};
  bool _loading = true;
  bool _bioExpanded = false;

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
    setState(() { _media[type] = prev.copyWith(loading: true); });
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
          items: page == 1 ? newItems : [...prev.items, ...newItems],
          currentPage: raw?['paginatorInfo']?['currentPage'] ?? page,
          lastPage: raw?['paginatorInfo']?['lastPage'] ?? 1,
          total: raw?['paginatorInfo']?['total'] ?? prev.total,
        );
      });
    } catch (_) {
      if (mounted) setState(() { _media[type] = prev.copyWith(loading: false); });
    }
  }

  Future<void> _fetch() async {
    final sectionsQuery = _cfg.sections.map((c) =>
      '${c.key}(first: 10, page: 1, orderBy: [{ column: "views", order: DESC }]) { data { ${c.fields} } paginatorInfo { total currentPage lastPage } }'
    ).join('\n');
    // Per-doc-type counts so the media tabs can render with totals before
    // their content has been fetched. Aliased so all 4 share the same
    // `documents` relation under the person.
    final mediaCountsQuery = _mediaSecs.map((m) =>
      '${m.key}Docs: documents(first: 1, page: 1, where: {column: "type", value: "${m.key}"}) { paginatorInfo { total } }'
    ).join('\n');
    final q = 'query(\$slug: String!) { ${_cfg.queryName}(slug: \$slug) { id title slug content rank real_name avatar { url user { id username } } dob mob yob dod mod yod born_address views total_listens total_downloads loves(first: 500) { data { user_id } paginatorInfo { total } } $sectionsQuery $mediaCountsQuery } }';
    try {
      final data = await ApiClient.query(q, {'slug': widget.slug});
      final p = data[_cfg.queryName];
      if (!mounted) return;
      if (p == null) { setState(() => _loading = false); return; }
      setState(() {
        _person = Map<String, dynamic>.from(p);
        final lovers = ((p['loves']?['data'] ?? []) as List).whereType<Map>();
        final me = context.read<AuthProvider>().user?['id']?.toString();
        _following = me != null && lovers.any((l) => l['user_id']?.toString() == me);
        _followers = (p['loves']?['paginatorInfo']?['total'] as num?)?.toInt() ?? lovers.length;
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
      logActivity(context.read<AuthProvider>(), 'view', _cfg.queryName, p['id']);
    } catch (_) {
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  bool _failed = false;

  Future<void> _fetchPage(String key, int page, {String? sort}) async {
    final cfg = _cfg.sections.firstWhere((c) => c.key == key);
    final personId = _person?['id']?.toString();
    if (personId == null) return;
    final prev = _sections[key]!;
    final useSort = sort ?? prev.sort;
    final sortCol = _sortOptions.firstWhere((o) => o.$1 == useSort, orElse: () => _sortOptions.first).$3;
    setState(() {
      _sections[key] = prev.copyWith(loading: true, sort: useSort);
    });
    try {
      final queryById = '${_cfg.queryName}ByID';
      final q = 'query(\$id: ID!, \$page: Int) { $queryById(id: \$id) { $key(first: 10, page: \$page, orderBy: [{ column: "$sortCol", order: DESC }]) { data { ${cfg.fields} } paginatorInfo { total currentPage lastPage } } } }';
      final data = await ApiClient.query(q, {'id': personId, 'page': page});
      final raw = data[queryById]?[key];
      if (!mounted) return;
      final newItems = (raw?['data'] ?? []) as List;
      setState(() {
        _sections[key] = _SectionState(
          // page=1 is either initial sort/refresh — replace. page>1 — append.
          items: page == 1 ? newItems : [...prev.items, ...newItems],
          total: raw?['paginatorInfo']?['total'] ?? prev.total,
          currentPage: raw?['paginatorInfo']?['currentPage'] ?? page,
          lastPage: raw?['paginatorInfo']?['lastPage'] ?? prev.lastPage,
          sort: useSort,
          loading: false,
        );
      });
    } catch (_) {
      if (mounted) setState(() {
        _sections[key] = prev.copyWith(loading: false, sort: useSort);
      });
    }
  }

  void _loadMore(String key) {
    final s = _sections[key]!;
    if (s.loading || s.currentPage >= s.lastPage) return;
    _fetchPage(key, s.currentPage + 1);
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
      showDialog(context: context, builder: (_) => const LoginDialog());
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đang theo dõi ${_person!['title']} — bạn sẽ được báo khi có bài mới'), duration: const Duration(seconds: 3)));
        PushService.instance.maybeAsk(context, reason: 'Nhận thông báo khi ${_person!['title']} có bài mới.');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _following = !next;
          _followers = (_followers + (next ? -1 : 1)).clamp(0, 1 << 30);
        });
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _share() async {
    if (_person == null) return;
    final url = '$siteUrl${_cfg.routePrefix}${_person!['slug']}';
    await shareText(context, text: '🎵 ${_person!['title']} — các bài hát trên Bài ca đi cùng năm tháng: $url', subject: _person!['title']?.toString());
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
    final visibleSections = _cfg.sections.where((c) => (_sections[c.key]?.total ?? 0) > 0).toList();
    final visibleMedia = _mediaSecs.where((m) => (_media[m.key]?.total ?? 0) > 0).toList();

    return DefaultTabController(
      length: visibleSections.length + visibleMedia.length + 1, // +1 for Tiểu sử
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(
          children: [
            NestedScrollView(
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
                      ...visibleSections.map((c) => Tab(text: '${c.label} · ${_formatInt(_sections[c.key]!.total)}')),
                      const Tab(text: 'Tiểu sử'),
                      ...visibleMedia.map((m) => Tab(text: '${m.label} · ${_formatInt(_media[m.key]!.total)}')),
                    ],
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  ...visibleSections.map((c) => _buildSectionTab(c)),
                  _buildBioTab(p, player.currentSong != null),
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
    if (state.items.isEmpty && !state.loading && state.total > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchMedia(cfg.key);
      });
    }
    final hasMore = state.currentPage < state.lastPage;
    if (state.loading && state.items.isEmpty) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (state.items.isEmpty) {
      return Center(child: Text('Chưa có ${cfg.label.toLowerCase()}', style: body(TextStyle(color: AppColors.textMuted))));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        if (!state.loading && hasMore && n.metrics.pixels > n.metrics.maxScrollExtent - 400) {
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
          if (!hasMore && state.items.isNotEmpty) Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('Đã hết', style: body(TextStyle(fontSize: 12, color: AppColors.textMuted)))),
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

  /// Spotify-style horizontal artist hero: left avatar + right column with
  /// big title, role/rank, stats inline, life dates.
  Widget _buildDesktopHeader(Map<String, dynamic> p, String? bornDate, String? deathDate) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar always circular — square treatment for creators was
          // reverted per user feedback (looked inconsistent across the app).
          InkWell(
            onTap: p['avatar']?['url'] != null ? () => _showAvatarZoom(p) : null,
            borderRadius: BorderRadius.circular(100),
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)]),
                boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.45 * AppColors.shadowMul), blurRadius: 36, spreadRadius: -4)],
                border: Border.all(color: AppColors.border, width: 3),
              ),
              child: ClipOval(
                child: p['avatar']?['url'] != null
                    ? CachedNetworkImage(imageUrl: cdnImg((p['avatar']['url']).toString(), 480), fit: BoxFit.cover, errorWidget: (_, _, _) => _initialsFallback(p))
                    : _initialsFallback(p),
              ),
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Vertical rhythm — golden ratio (φ ≈ 1.618):
                //   font tier  32 → 14 → 11 (anchor = title)
                //   space tier  6 → 14 → 6 → 22 (within / between groups)
                Text(
                  _cfg.label.toUpperCase(),
                  style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.textMuted)),
                ),
                const SizedBox(height: 6),
                Text(p['title'] ?? '', style: AppText.hero),
                if (p['rank'] != null && (p['rank'] as String).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(p['rank'], style: body(TextStyle(fontSize: 14, color: AppColors.accentLight, fontWeight: FontWeight.w500))),
                ],
                const SizedBox(height: 14),
                // Inline stat row — Spotify-style.
                Wrap(
                  spacing: 18, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatInline(label: 'lượt nghe', value: _formatInt(p['total_listens'])),
                    _StatInline(label: 'lượt tải', value: _formatInt(p['total_downloads'])),
                    _StatInline(label: 'lượt xem', value: _formatInt(p['views'])),
                  ],
                ),
                if (p['real_name'] != null && (p['real_name'] as String).isNotEmpty
                    || bornDate != null || deathDate != null
                    || (p['born_address'] != null && (p['born_address'] as String).isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 22),
                    child: Wrap(
                      spacing: 18, runSpacing: 4,
                      children: [
                        if (p['real_name'] != null && (p['real_name'] as String).isNotEmpty)
                          _MetaChip(icon: Icons.badge_outlined, value: p['real_name']),
                        if (bornDate != null) _MetaChip(icon: Icons.cake_outlined, value: bornDate),
                        if (deathDate != null) _MetaChip(icon: Icons.whatshot_outlined, value: deathDate),
                        if (p['born_address'] != null && (p['born_address'] as String).isNotEmpty)
                          _MetaChip(icon: Icons.place_outlined, value: p['born_address']),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Phone header (2026-11 redesign): avatar beside name, one meta line
  // (years · quê), a single stats strip, and "Phát tất cả" as the main action.
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
                  : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)]))),
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
                const Spacer(),
                circle(Icons.ios_share_rounded, 'Chia sẻ', _share),
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
                  Text(_cfg.label.toUpperCase(), style: body(const TextStyle(fontSize: 12, letterSpacing: 0.9, fontWeight: FontWeight.w800, color: Color(0xD9FFFFFF)))),
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
    final first = _cfg.sections.firstWhere((c) => (_sections[c.key]?.total ?? 0) > 0, orElse: () => _cfg.sections.first);
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
                  _StatCell(label: first.label.toLowerCase(), value: _formatInt(firstState?.total ?? 0)),
                  Container(width: 1, color: AppColors.border),
                  _StatCell(label: 'lượt tải', value: formatViews(((p['total_downloads'] ?? 0) as num).toInt())),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: PillButton(label: 'Phát tất cả', icon: Icons.play_arrow_rounded, onTap: canPlay ? () => _playSection(first, shuffle: false) : null)),
              const SizedBox(width: 10),
              Expanded(child: PillButton(label: 'Ngẫu nhiên', icon: Icons.shuffle_rounded, primary: false, onTap: canPlay ? () => _playSection(first, shuffle: true) : null)),
            ],
          ),
          const SizedBox(height: 10),
          Material(
            color: _following ? AppColors.accentSoft : Colors.transparent,
            shape: StadiumBorder(side: BorderSide(color: _following ? Colors.transparent : AppColors.border, width: 1.5)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: _toggleFollow,
              child: SizedBox(
                height: 46,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_following ? Icons.check_rounded : Icons.person_add_alt_1_rounded, size: 20, color: _following ? AppColors.accentLight : AppColors.text),
                  const SizedBox(width: 8),
                  Text(
                    [_following ? 'Đang theo dõi' : 'Theo dõi', if (_followers >= 20) '$_followers người'].join(' · '),
                    style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _following ? AppColors.accentLight : AppColors.text)),
                  ),
                ]),
              ),
            ),
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
    final hasMore = state.currentPage < state.lastPage;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        if (!state.loading && hasMore && n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
          _loadMore(cfg.key);
        }
        return false;
      },
      child: ListView.builder(
        key: PageStorageKey('person-${cfg.key}'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        itemCount: state.items.length + 2, // [sort bar, ...items, footer]
        itemBuilder: (ctx, i) {
          if (i == 0) return _buildSortBar(cfg.key, state);
          if (i == state.items.length + 1) {
            if (state.loading) {
              return Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(color: AppColors.accent)));
            }
            if (!hasMore && state.items.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('Đã hết', style: body(TextStyle(fontSize: 12, color: AppColors.textMuted)))),
              );
            }
            return const SizedBox(height: 16);
          }
          final s = state.items[i - 1];
          final sg = Map<String, dynamic>.from(s as Map);
          sg['file_type'] = cfg.fileType;
          final queue = state.items.whereType<Map>().map((x) => {...Map<String, dynamic>.from(x), 'file_type': cfg.fileType}).toList();
          return Builder(
            builder: (rowCtx) => SongRow(
              song: sg,
              metricKey: state.sort == 'newest' ? 'time' : state.sort,
              isPlaying: rowCtx.select<PlayerProvider, String?>((pl) => pl.currentSong?['id']?.toString()) == sg['id']?.toString(),
              onTap: () => playOrOpen(context, sg, queue, '${_person?['title'] ?? ''} · ${cfg.label}'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSortBar(String key, _SectionState state) {
    final selected = _sortOptions.indexWhere((o) => o.$1 == state.sort);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ChipStrip(
        labels: const ['Nghe nhiều nhất', 'Mới cập nhật', 'Yêu thích nhất'],
        selected: selected < 0 ? 0 : selected,
        padding: EdgeInsets.zero,
        onSelect: (i) {
          if (_sortOptions[i].$1 != state.sort) _fetchPage(key, 1, sort: _sortOptions[i].$1);
        },
      ),
    );
  }

  Widget _buildBioTab(Map<String, dynamic> p, bool hasPlayer) {
    final bio = p['content'];
    final hasBio = bio != null && (bio as String).replaceAll(RegExp(r'<[^>]+>'), '').trim().isNotEmpty;
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
                  constraints: BoxConstraints(maxHeight: _bioExpanded ? double.infinity : 200),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Html(
                      data: bio,
                      style: {'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero, fontSize: FontSize(14), lineHeight: const LineHeight(1.8), color: AppColors.textSecondary)},
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _bioExpanded = !_bioExpanded),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_bioExpanded ? 'Thu gọn' : 'Xem thêm', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
                        Icon(_bioExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: AppColors.accentLight),
                      ],
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
            child: Center(child: Text('Chưa có tiểu sử', style: body(TextStyle(color: AppColors.textMuted)))),
          ),
        CommentSection(type: _cfg.queryName, id: p['id'].toString()),
      ],
    );
  }

  Widget _initialsFallback(Map<String, dynamic> p) {
    return Container(
      color: AppColors.surfaceLight,
      alignment: Alignment.center,
      child: Text(
        (p['title'] ?? '?').toString().substring(0, 1).toUpperCase(),
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

