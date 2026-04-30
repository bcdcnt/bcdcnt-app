import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_html/flutter_html.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';
import '../widgets/comment_section.dart';
import '../widgets/shimmer.dart';

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

const _songFields = 'id title subtitle slug views downloads play_type thumbnail { url } file { audio_url video_url duration } sheet { year composers(first: 20) { data { id slug title } } } artists(first: 5) { data { id title slug avatar { url } } }';
const _folkFields = 'id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } recomposers(first: 5) { data { id slug title } } artists(first: 5) { data { id title slug avatar { url } } }';
const _instFields = 'id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } sheet { year composers(first: 20) { data { id slug title } } } artists(first: 5) { data { id title slug avatar { url } } }';
const _poemFields = 'id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } poets(first: 5) { data { id slug title } } artists(first: 5) { data { id title slug avatar { url } } }';

const _songSec = _SectionCfg(key: 'songs', label: 'Bài hát', icon: Icons.music_note, fields: _songFields, fileType: 'song');
const _folkSec = _SectionCfg(key: 'folks', label: 'Dân ca', icon: Icons.music_note, fields: _folkFields, fileType: 'folk');
const _instSec = _SectionCfg(key: 'instrumentals', label: 'Khí nhạc', icon: Icons.music_note, fields: _instFields, fileType: 'instrumental');
const _poemSec = _SectionCfg(key: 'poems', label: 'Ngâm thơ', icon: Icons.auto_stories_outlined, fields: _poemFields, fileType: 'poem');

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
  final Map<String, _SectionState> _sections = {};
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
      for (final c in _cfg.sections) {
        _sections[c.key] = const _SectionState();
      }
      setState(() { _person = null; _loading = true; _bioExpanded = false; });
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final sectionsQuery = _cfg.sections.map((c) =>
      '${c.key}(first: 10, page: 1, orderBy: [{ column: "views", order: DESC }]) { data { ${c.fields} } paginatorInfo { total currentPage lastPage } }'
    ).join('\n');
    final q = 'query(\$slug: String!) { ${_cfg.queryName}(slug: \$slug) { id title slug content rank real_name avatar { url user { id username } } dob mob yob dod mod yod born_address views total_listens total_downloads $sectionsQuery } }';
    try {
      final data = await ApiClient.query(q, {'slug': widget.slug});
      final p = data[_cfg.queryName];
      if (!mounted) return;
      if (p == null) { setState(() => _loading = false); return; }
      setState(() {
        _person = Map<String, dynamic>.from(p);
        for (final c in _cfg.sections) {
          final raw = p[c.key];
          _sections[c.key] = _SectionState(
            items: (raw?['data'] ?? []) as List,
            total: raw?['paginatorInfo']?['total'] ?? 0,
            currentPage: raw?['paginatorInfo']?['currentPage'] ?? 1,
            lastPage: raw?['paginatorInfo']?['lastPage'] ?? 1,
          );
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

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
                        imageUrl: url,
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

  Future<void> _share() async {
    if (_person == null) return;
    final url = '$siteUrl${_cfg.routePrefix}${_person!['slug']}';
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã sao chép link: $url'), backgroundColor: AppColors.success, duration: const Duration(seconds: 2)));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          title: Text(_cfg.label.toUpperCase(), style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
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
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
        body: Center(child: Text('Không tìm thấy', style: AppText.bodyText)),
      );
    }

    final p = _person!;
    final player = context.watch<PlayerProvider>();
    // Hide section tabs that have no data — keeps the bar tight for niche
    // people types (e.g. recomposers usually only have folks).
    final visibleSections = _cfg.sections.where((c) => (_sections[c.key]?.total ?? 0) > 0).toList();

    return DefaultTabController(
      length: visibleSections.length + 1, // +1 for Tiểu sử
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(
          children: [
            NestedScrollView(
              headerSliverBuilder: (ctx, _) => [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: AppColors.bg.withValues(alpha: 0.88),
                  leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
                  title: Text(_cfg.label.toUpperCase(), style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
                  centerTitle: true,
                  actions: [IconButton(icon: const Icon(Icons.share, color: AppColors.textSecondary), onPressed: _share)],
                ),
                SliverToBoxAdapter(child: _buildHeader(p)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    tabs: [
                      const Tab(text: 'Tiểu sử'),
                      ...visibleSections.map((c) => Tab(text: '${c.label} (${_formatInt(_sections[c.key]!.total)})')),
                    ],
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  _buildBioTab(p, player.currentSong != null),
                  ...visibleSections.map((c) => _buildSectionTab(c)),
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
          InkWell(
            onTap: p['avatar']?['url'] != null ? () => _showAvatarZoom(p) : null,
            borderRadius: BorderRadius.circular(110),
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.45), blurRadius: 36, spreadRadius: -4)],
                border: Border.all(color: AppColors.border, width: 3),
              ),
              child: ClipOval(
                child: p['avatar']?['url'] != null
                    ? CachedNetworkImage(imageUrl: p['avatar']['url'], fit: BoxFit.cover, errorWidget: (_, _, _) => _initialsFallback(p))
                    : _initialsFallback(p),
              ),
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _cfg.label.toUpperCase(),
                  style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.textMuted)),
                ),
                const SizedBox(height: 8),
                Text(
                  p['title'] ?? '',
                  style: AppText.hero,
                ),
                if (p['rank'] != null && (p['rank'] as String).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(p['rank'], style: body(const TextStyle(fontSize: 15, color: AppColors.accentLight, fontWeight: FontWeight.w500))),
                ],
                const SizedBox(height: 18),
                // Inline stat row — comma-separated, Spotify-style.
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
                    padding: const EdgeInsets.only(top: 14),
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

  Widget _buildMobileHeader(Map<String, dynamic> p, String? bornDate, String? deathDate) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Center(
            child: InkWell(
              onTap: p['avatar']?['url'] != null ? () => _showAvatarZoom(p) : null,
              borderRadius: BorderRadius.circular(80),
              child: Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                  boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: -5)],
                  border: Border.all(color: AppColors.border, width: 3),
                ),
                child: ClipOval(
                  child: p['avatar']?['url'] != null
                      ? CachedNetworkImage(imageUrl: p['avatar']['url'], fit: BoxFit.cover, errorWidget: (_, _, _) => _initialsFallback(p))
                      : _initialsFallback(p),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            p['title'] ?? '',
            textAlign: TextAlign.center,
            style: display(const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text)),
          ),
          if (p['rank'] != null && (p['rank'] as String).isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(p['rank'], textAlign: TextAlign.center, style: body(const TextStyle(fontSize: 14, color: AppColors.accentLight, fontWeight: FontWeight.w500))),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border), bottom: BorderSide(color: AppColors.border)),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _StatCell(label: 'Lượt nghe', value: _formatInt(p['total_listens'])),
                  Container(width: 1, color: AppColors.border),
                  _StatCell(label: 'Lượt tải', value: _formatInt(p['total_downloads'])),
                  Container(width: 1, color: AppColors.border),
                  _StatCell(label: 'Lượt xem', value: _formatInt(p['views'])),
                ],
              ),
            ),
          ),
          if (p['real_name'] != null && (p['real_name'] as String).isNotEmpty)
            _InfoRow(icon: Icons.badge_outlined, label: 'Tên thật', value: p['real_name']),
          if (bornDate != null) _InfoRow(icon: Icons.cake_outlined, label: 'Ngày sinh', value: bornDate),
          if (deathDate != null) _InfoRow(icon: Icons.whatshot_outlined, label: 'Ngày mất', value: deathDate),
          if (p['born_address'] != null && (p['born_address'] as String).isNotEmpty)
            _InfoRow(icon: Icons.place_outlined, label: 'Quê quán', value: p['born_address']),
        ],
      ),
    );
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
              return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(color: AppColors.accent)));
            }
            if (!hasMore && state.items.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('Đã hết', style: body(const TextStyle(fontSize: 12, color: AppColors.textMuted)))),
              );
            }
            return const SizedBox(height: 16);
          }
          final s = state.items[i - 1];
          final sg = Map<String, dynamic>.from(s as Map);
          sg['file_type'] = cfg.fileType;
          return SongRow(song: sg, onTap: () => context.push('/song/${sg['id']}', extra: sg));
        },
      ),
    );
  }

  Widget _buildSortBar(String key, _SectionState state) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _sortOptions.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final opt = _sortOptions[i];
            final active = state.sort == opt.$1;
            return InkWell(
              onTap: active ? null : () => _fetchPage(key, 1, sort: opt.$1),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? AppColors.accentSoft : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: active ? AppColors.accent : AppColors.border),
                ),
                child: Text(
                  opt.$2,
                  style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? AppColors.accentLight : AppColors.textSecondary)),
                ),
              ),
            );
          },
        ),
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
                        Text(_bioExpanded ? 'Thu gọn' : 'Xem thêm', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
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
            child: Center(child: Text('Chưa có tiểu sử', style: body(const TextStyle(color: AppColors.textMuted)))),
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
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.bg,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: AppColors.accentLight,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.accent,
        indicatorWeight: 2,
        dividerColor: AppColors.borderSubtle,
        labelStyle: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        unselectedLabelStyle: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
      text: TextSpan(
        children: [
          TextSpan(text: value, style: display(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
          TextSpan(text: ' $label', style: body(const TextStyle(fontSize: 13, color: AppColors.textMuted))),
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
        Text(value, style: body(const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
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
          Text(value, style: display(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
          const SizedBox(height: 2),
          Text(label, style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text('$label: ', style: body(const TextStyle(fontSize: 13, color: AppColors.textMuted))),
          Expanded(child: Text(value, style: body(const TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w500)))),
        ],
      ),
    );
  }
}
