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

enum PersonType { artist, composer, poet, recomposer }

class _TypeConfig {
  final String label;
  final String queryName;
  final List<_SectionCfg> sections;
  final String relatedQuery;
  final String relatedIdVar;
  final String relatedLabel;
  final String relatedRoutePrefix;
  final String routePrefix;
  const _TypeConfig({
    required this.label,
    required this.queryName,
    required this.sections,
    required this.relatedQuery,
    required this.relatedIdVar,
    required this.relatedLabel,
    required this.relatedRoutePrefix,
    required this.routePrefix,
  });
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
const _instSec = _SectionCfg(key: 'instrumentals', label: 'Hoà tấu', icon: Icons.music_note, fields: _instFields, fileType: 'instrumental');
const _poemSec = _SectionCfg(key: 'poems', label: 'Ngâm thơ', icon: Icons.auto_stories_outlined, fields: _poemFields, fileType: 'poem');

const Map<PersonType, _TypeConfig> _config = {
  PersonType.artist: _TypeConfig(
    label: 'Nghệ sĩ', queryName: 'artist',
    sections: [_songSec, _folkSec, _instSec, _poemSec],
    relatedQuery: 'relatedArtists', relatedIdVar: 'artist_id',
    relatedLabel: 'Nghệ sĩ liên quan', relatedRoutePrefix: '/nghe-si/', routePrefix: '/nghe-si/',
  ),
  PersonType.composer: _TypeConfig(
    label: 'Nhạc sĩ', queryName: 'composer',
    sections: [_songSec, _instSec, _folkSec],
    relatedQuery: 'relatedComposers', relatedIdVar: 'composer_id',
    relatedLabel: 'Nhạc sĩ liên quan', relatedRoutePrefix: '/nhac-si/', routePrefix: '/nhac-si/',
  ),
  PersonType.poet: _TypeConfig(
    label: 'Nhà thơ', queryName: 'poet',
    sections: [_poemSec, _songSec],
    relatedQuery: 'relatedPoets', relatedIdVar: 'poet_id',
    relatedLabel: 'Nhà thơ liên quan', relatedRoutePrefix: '/nha-tho/', routePrefix: '/nha-tho/',
  ),
  PersonType.recomposer: _TypeConfig(
    label: 'Soạn giả', queryName: 'recomposer',
    sections: [_folkSec],
    relatedQuery: 'relatedRecomposers', relatedIdVar: 'recomposer_id',
    relatedLabel: 'Soạn giả liên quan', relatedRoutePrefix: '/soan-gia/', routePrefix: '/soan-gia/',
  ),
};

class PersonDetailScreen extends StatefulWidget {
  final PersonType type;
  final String slug;
  const PersonDetailScreen({super.key, required this.type, required this.slug});

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _SectionState {
  List<dynamic> items;
  int currentPage;
  int lastPage;
  int total;
  String sort; // views | newest | likes | downloads
  bool loading;
  _SectionState({this.items = const [], this.currentPage = 1, this.lastPage = 1, this.total = 0, this.sort = 'views', this.loading = false});
}

const _sortOptions = [
  ('views', 'Nghe nhiều', 'views'),
  ('newest', 'Mới nhất', 'id'),
  ('likes', 'Yêu thích', 'likes'),
];

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  Map<String, dynamic>? _person;
  final Map<String, _SectionState> _sections = {};
  List<dynamic> _relatedPeople = [];
  bool _loading = true;
  bool _bioExpanded = false;

  _TypeConfig get _cfg => _config[widget.type]!;

  @override
  void initState() {
    super.initState();
    for (final c in _cfg.sections) {
      _sections[c.key] = _SectionState();
    }
    _fetch();
  }

  @override
  void didUpdateWidget(PersonDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug || oldWidget.type != widget.type) {
      _sections.clear();
      for (final c in _cfg.sections) {
        _sections[c.key] = _SectionState();
      }
      setState(() { _person = null; _relatedPeople = []; _loading = true; _bioExpanded = false; });
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
            sort: 'views',
          );
        }
        _loading = false;
      });
      _fetchRelated(p['id']);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchPage(String key, int page, {String? sort}) async {
    final cfg = _cfg.sections.firstWhere((c) => c.key == key);
    final personId = _person?['id']?.toString();
    if (personId == null) return;
    final useSort = sort ?? _sections[key]!.sort;
    final sortCol = _sortOptions.firstWhere((o) => o.$1 == useSort, orElse: () => _sortOptions.first).$3;
    setState(() {
      final s = _sections[key]!;
      _sections[key] = _SectionState(items: s.items, total: s.total, currentPage: s.currentPage, lastPage: s.lastPage, sort: useSort, loading: true);
    });
    try {
      final queryById = '${_cfg.queryName}ByID';
      final q = 'query(\$id: ID!, \$page: Int) { $queryById(id: \$id) { $key(first: 10, page: \$page, orderBy: [{ column: "$sortCol", order: DESC }]) { data { ${cfg.fields} } paginatorInfo { total currentPage lastPage } } } }';
      final data = await ApiClient.query(q, {'id': personId, 'page': page});
      final raw = data[queryById]?[key];
      if (!mounted) return;
      setState(() {
        _sections[key] = _SectionState(
          items: (raw?['data'] ?? []) as List,
          total: raw?['paginatorInfo']?['total'] ?? _sections[key]!.total,
          currentPage: raw?['paginatorInfo']?['currentPage'] ?? page,
          lastPage: raw?['paginatorInfo']?['lastPage'] ?? _sections[key]!.lastPage,
          sort: useSort,
          loading: false,
        );
      });
    } catch (_) {
      if (mounted) setState(() {
        final s = _sections[key]!;
        _sections[key] = _SectionState(items: s.items, total: s.total, currentPage: s.currentPage, lastPage: s.lastPage, sort: useSort, loading: false);
      });
    }
  }

  Future<void> _fetchRelated(dynamic id) async {
    try {
      final q = 'query(\$id: ID!) { ${_cfg.relatedQuery}(${_cfg.relatedIdVar}: \$id, first: 10) { data { id title slug avatar { url } } } }';
      final data = await ApiClient.query(q, {'id': id.toString()});
      final list = (data[_cfg.relatedQuery]?['data'] ?? []) as List;
      if (mounted) setState(() => _relatedPeople = list);
    } catch (_) {}
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
    final d = p['d$suffix'], m = p['m$suffix'], y = p['y$suffix'];
    if (d == null && m == null && y == null) return null;
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
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              Flexible(
                child: GestureDetector(
                  onTap: () {},
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.white70)),
                        errorWidget: (_, __, ___) => const Padding(padding: EdgeInsets.all(40), child: Icon(Icons.broken_image, color: Colors.white38, size: 48)),
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
                    Text(
                      creditUser['username'] ?? '',
                      style: body(const TextStyle(fontSize: 13, color: Colors.white70)),
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
      return const Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    }
    if (_person == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
        body: Center(child: Text('Không tìm thấy', style: AppText.bodyText)),
      );
    }
    final p = _person!;
    final bio = p['content'];
    final bornDate = _formatLifeDate(p, 'ob');
    final deathDate = _formatLifeDate(p, 'od');
    final player = context.watch<PlayerProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.bg.withValues(alpha: 0.88),
                title: Text(_cfg.label.toUpperCase(), style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
                centerTitle: true,
                leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
                actions: [IconButton(icon: const Icon(Icons.share, color: AppColors.textSecondary), onPressed: _share)],
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 8),
                    // Avatar — tap to zoom
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
                                ? CachedNetworkImage(imageUrl: p['avatar']['url'], fit: BoxFit.cover, errorWidget: (_, __, ___) => _initialsFallback(p))
                                : _initialsFallback(p),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        p['title'] ?? '',
                        textAlign: TextAlign.center,
                        style: display(const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text)),
                      ),
                    ),
                    if (p['rank'] != null && (p['rank'] as String).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          p['rank'],
                          textAlign: TextAlign.center,
                          style: body(const TextStyle(fontSize: 14, color: AppColors.accentLight, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    // Stats bar
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

                    const SizedBox(height: 16),
                    if (p['real_name'] != null && (p['real_name'] as String).isNotEmpty)
                      _InfoRow(icon: Icons.badge_outlined, label: 'Tên thật', value: p['real_name']),
                    if (bornDate != null)
                      _InfoRow(icon: Icons.cake_outlined, label: 'Ngày sinh', value: bornDate),
                    if (deathDate != null)
                      _InfoRow(icon: Icons.whatshot_outlined, label: 'Ngày mất', value: deathDate),
                    if (p['born_address'] != null && (p['born_address'] as String).isNotEmpty)
                      _InfoRow(icon: Icons.place_outlined, label: 'Quê quán', value: p['born_address']),

                    // Bio
                    if (bio != null && (bio as String).replaceAll(RegExp(r'<[^>]+>'), '').trim().isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _SectionHeader(icon: Icons.description_outlined, title: 'Tiểu sử'),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: _bioExpanded ? double.infinity : 120),
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
                    ],

                    // Song sections
                    ..._cfg.sections.map((c) {
                      final state = _sections[c.key]!;
                      if (state.items.isEmpty && !state.loading) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionHeader(icon: c.icon, title: '${c.label}${state.total > 0 ? ' (${_formatInt(state.total)})' : ''}'),
                            // Sort tabs
                            if (state.total > 3)
                              SizedBox(
                                height: 32,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _sortOptions.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                                  itemBuilder: (_, i) {
                                    final opt = _sortOptions[i];
                                    final active = state.sort == opt.$1;
                                    return InkWell(
                                      onTap: active ? null : () => _fetchPage(c.key, 1, sort: opt.$1),
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
                            const SizedBox(height: 8),
                            if (state.loading)
                              const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
                            else
                              ...state.items.map((s) {
                                final sg = Map<String, dynamic>.from(s as Map);
                                sg['file_type'] = c.fileType;
                                return SongRow(
                                  song: sg,
                                  onTap: () => context.push('/song/${sg['id']}', extra: sg),
                                );
                              }),
                            if (state.lastPage > 1)
                              _Pager(
                                currentPage: state.currentPage,
                                lastPage: state.lastPage,
                                loading: state.loading,
                                onGoto: (p) => _fetchPage(c.key, p),
                              ),
                          ],
                        ),
                      );
                    }),

                    // Related people
                    if (_relatedPeople.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _SectionHeader(icon: Icons.people_outline, title: _cfg.relatedLabel),
                      SizedBox(
                        height: 112,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _relatedPeople.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (ctx, i) {
                            final r = _relatedPeople[i];
                            return InkWell(
                              onTap: () => context.push('${_cfg.relatedRoutePrefix}${r['slug']}'),
                              child: SizedBox(
                                width: 72,
                                child: Column(
                                  children: [
                                    Container(
                                      width: 64, height: 64,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                                        border: Border.all(color: AppColors.border, width: 2),
                                      ),
                                      child: ClipOval(
                                        child: r['avatar']?['url'] != null
                                            ? CachedNetworkImage(imageUrl: r['avatar']['url'], fit: BoxFit.cover)
                                            : Center(child: Text((r['title'] ?? '?').toString().substring(0, 1).toUpperCase(), style: display(const TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.w800)))),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      r['title'] ?? '',
                                      maxLines: 2,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: body(const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    // Comments
                    const SizedBox(height: 24),
                    CommentSection(type: _cfg.queryName, id: p['id'].toString()),

                    SizedBox(height: player.currentSong != null ? 80 : 20),
                  ]),
                ),
              ),
            ],
          ),
          if (player.currentSong != null)
            const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
        ],
      ),
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

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(title, style: display(const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text))),
        ],
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
    // Compute a compact window of page numbers around current
    final pages = <int>{};
    pages.add(1);
    pages.add(lastPage);
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
      children.add(_PageBtn(
        label: '$p',
        enabled: p != currentPage && !loading,
        active: p == currentPage,
        onTap: () => onGoto(p),
      ));
      prev = p;
    }
    children.add(_PageBtn(icon: Icons.chevron_right, enabled: currentPage < lastPage && !loading, onTap: () => onGoto(currentPage + 1)));

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ),
    );
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
