import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  String _filter = 'all';
  List<dynamic> _groups = [];
  bool _loading = false;

  // Empty state
  List<Map<String, dynamic>> _trending = [];
  List<Map<String, dynamic>> _recent = [];
  bool _trendingLoaded = false;
  bool _recentLoaded = false;

  static const _filterOptions = [
    ('all', 'Tất cả', null),
    ('song', 'Tân nhạc', null),
    ('folk', 'Dân ca', null),
    ('instrumental', 'Khí nhạc', null),
    ('poem', 'Tiếng thơ', null),
    ('karaoke', 'Thành viên hát', null),
    ('artist', 'Nghệ sĩ', null),
    ('composer', 'Nhạc sĩ', null),
    ('poet', 'Nhà thơ', null),
    ('recomposer', 'Soạn giả', null),
    ('document', 'Tư liệu', null),
    ('user', 'Thành viên', null),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchTrending();
      if (context.read<AuthProvider>().isAuthenticated) _fetchRecent();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchTrending() async {
    try {
      final data = await ApiClient.query(
        r'query($limit: Int) { trendingKeywords(limit: $limit) { name object_type object_id search_count } }',
        {'limit': 12},
      );
      final list = ((data['trendingKeywords'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() { _trending = list; _trendingLoaded = true; });
    } catch (_) { if (mounted) setState(() => _trendingLoaded = true); }
  }

  Future<void> _fetchRecent() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    try {
      final data = await auth.authedQuery(
        r'''query { me { recentSearches(first: 15, orderBy: [{column: "created_at", order: DESC}]) {
          data {
            id q object_type object_id
            object {
              __typename
              ... on Song { id title slug thumbnail { url } }
              ... on Folk { id title slug thumbnail { url } }
              ... on Instrumental { id title slug thumbnail { url } }
              ... on Poem { id title slug thumbnail { url } }
              ... on Karaoke { id title slug thumbnail { url } }
              ... on Artist { id title slug avatar { url } }
              ... on Composer { id title slug avatar { url } }
              ... on Poet { id title slug avatar { url } }
              ... on Recomposer { id title slug avatar { url } }
              ... on Document { id title slug thumbnail { url } }
            }
          }
        } } }''',
      );
      final list = ((data['me']?['recentSearches']?['data'] ?? []) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) => (r['q'] != null && (r['q'] as String).isNotEmpty) || r['object'] != null)
          .toList();
      if (mounted) setState(() { _recent = list; _recentLoaded = true; });
    } catch (_) { if (mounted) setState(() => _recentLoaded = true); }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    setState(() => _query = v);
    if (v.trim().isEmpty) {
      setState(() { _groups = []; _loading = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(v.trim()));
  }

  Future<void> _runSearch(String q) async {
    if (q.isEmpty) return;
    setState(() => _loading = true);
    try {
      final limit = _filter == 'all' ? 5 : 50;
      final data = await ApiClient.query(
        r'query($q: String!, $limit: Int, $type: String!) { search(q: $q, limit: $limit, type: $type) }',
        {'q': q, 'limit': limit, 'type': _filter},
      );
      final raw = (data['search'] ?? []) as List;
      final filtered = raw.where((g) => (g['hits'] as List?)?.isNotEmpty ?? false).toList();
      if (!mounted) return;
      setState(() { _groups = filtered; _loading = false; });
      _trackKeyword(q);
    } catch (_) {
      if (mounted) setState(() { _groups = []; _loading = false; });
    }
  }

  Future<void> _trackKeyword(String q) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    try {
      await auth.authedMutate(r'mutation($q: String!) { addRecentSearch(q: $q) { id } }', {'q': q});
    } catch (_) {}
  }

  Future<void> _deleteRecent(String id) async {
    final auth = context.read<AuthProvider>();
    setState(() => _recent = _recent.where((r) => r['id'].toString() != id).toList());
    try {
      await auth.authedMutate(r'mutation($id: ID!) { deleteRecentSearch(id: $id) }', {'id': id});
    } catch (_) {}
  }

  Future<void> _clearAllRecent() async {
    final auth = context.read<AuthProvider>();
    setState(() => _recent = []);
    try {
      await auth.authedMutate(r'mutation { deleteAllRecentSearches }', null);
    } catch (_) {}
  }

  void _setFilter(String f) {
    if (f == _filter) return;
    setState(() => _filter = f);
    if (_query.trim().isNotEmpty) _runSearch(_query.trim());
  }

  void _useKeyword(String kw) {
    _ctrl.text = kw;
    _onChanged(kw);
    _focus.unfocus();
  }

  void _openHit(Map<String, dynamic> hit) {
    final t = hit['_search_type']?.toString();
    final id = hit['id']?.toString();
    final slug = hit['slug']?.toString();
    if (id == null) return;
    switch (t) {
      case 'song':
      case 'folk':
      case 'instrumental':
      case 'poem':
      case 'karaoke':
        // Build minimal song map for player
        final song = <String, dynamic>{
          'id': id, 'title': hit['title'], 'slug': slug, 'file_type': t,
          if (hit['image'] != null) 'thumbnail': {'url': hit['image']},
          if (hit['artist'] != null) 'artists': {'data': [{'title': hit['artist']}]},
          if (hit['audio_url'] != null || hit['video_url'] != null) 'file': {'audio_url': hit['audio_url'], 'video_url': hit['video_url']},
          'play_type': hit['play_type'] ?? 'audio',
        };
        context.push('/song/$id', extra: song);
        break;
      case 'artist': context.push('/nghe-si/$slug'); break;
      case 'composer': context.push('/nhac-si/$slug'); break;
      case 'poet': context.push('/nha-tho/$slug'); break;
      case 'recomposer': context.push('/soan-gia/$slug'); break;
      case 'document':
        context.push('/tu-lieu/chi-tiet/$id');
        break;
      case 'user':
        context.push('/user/$id');
        break;
      default: break;
    }
    _trackHit(t, id);
  }

  Future<void> _trackHit(String? type, String id) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated || type == null) return;
    try {
      await auth.authedMutate(
        r'mutation($object_type: String!, $object_id: ID!) { addRecentSearch(object_type: $object_type, object_id: $object_id) { id } }',
        {'object_type': type, 'object_id': id},
      );
    } catch (_) {}
  }

  String _objTypeLabel(String? typename) {
    const map = {
      'Song': 'Tân nhạc', 'Folk': 'Dân ca', 'Instrumental': 'Khí nhạc',
      'Poem': 'Tiếng thơ', 'Karaoke': 'Thành viên hát',
      'Artist': 'Nghệ sĩ', 'Composer': 'Nhạc sĩ', 'Poet': 'Nhà thơ',
      'Recomposer': 'Soạn giả', 'Document': 'Tư liệu', 'Tag': 'Tag',
    };
    return map[typename] ?? '';
  }

  void _openRecentObject(Map<String, dynamic> obj) {
    final tn = obj['__typename']?.toString();
    final id = obj['id']?.toString();
    final slug = obj['slug']?.toString();
    if (id == null) return;
    const fileTypeMap = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem', 'Karaoke': 'karaoke'};
    if (fileTypeMap.containsKey(tn)) {
      final song = <String, dynamic>{
        'id': id, 'title': obj['title'], 'slug': slug, 'file_type': fileTypeMap[tn],
        if (obj['thumbnail'] != null) 'thumbnail': obj['thumbnail'],
      };
      context.push('/song/$id', extra: song);
      return;
    }
    switch (tn) {
      case 'Artist': context.push('/nghe-si/$slug'); break;
      case 'Composer': context.push('/nhac-si/$slug'); break;
      case 'Poet': context.push('/nha-tho/$slug'); break;
      case 'Recomposer': context.push('/soan-gia/$slug'); break;
      case 'Document':
        context.push('/tu-lieu/chi-tiet/$id');
        break;
      case 'Tag':
        context.push('/tag/$slug');
        break;
    }
  }

  IconData _typeIcon(String? t) {
    switch (t) {
      case 'song': case 'folk': case 'instrumental': case 'karaoke': return Icons.music_note;
      case 'poem': return Icons.auto_stories_outlined;
      case 'artist': return Icons.mic;
      case 'composer': return Icons.music_note_outlined;
      case 'poet': return Icons.auto_stories_outlined;
      case 'recomposer': return Icons.edit_outlined;
      case 'document': return Icons.collections_bookmark_outlined;
      case 'user': return Icons.person_outline;
      default: return Icons.search;
    }
  }

  bool _isSongLike(String? t) => t == 'song' || t == 'folk' || t == 'instrumental' || t == 'poem' || t == 'karaoke';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final hasQuery = _query.trim().isNotEmpty;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, size: 20, color: AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    autofocus: true,
                    style: body(const TextStyle(color: AppColors.text, fontSize: 14)),
                    decoration: InputDecoration(
                      hintText: 'Tìm bài hát, nghệ sĩ, nhạc sĩ, tư liệu...',
                      hintStyle: body(const TextStyle(color: AppColors.textMuted, fontSize: 14)),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: _onChanged,
                  ),
                ),
                if (hasQuery)
                  GestureDetector(
                    onTap: () { _ctrl.clear(); _onChanged(''); },
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.cancel, size: 18, color: AppColors.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Filter pills — only when there's a query to narrow.
        // Mobile: horizontal-scroll pills (compact). Desktop: wrap so all
        // categories are visible without scrolling.
        if (hasQuery) Builder(builder: (ctx) {
          final isDesktop = MediaQuery.of(ctx).size.width >= 900;
          final pill = (
            String f,
            String label,
          ) {
            final active = _filter == f;
            return InkWell(
              onTap: active ? null : () => _setFilter(f),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? AppColors.accentSoft : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: active ? AppColors.accent : AppColors.border),
                ),
                child: Text(label, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? AppColors.accentLight : AppColors.textSecondary))),
              ),
            );
          };
          if (isDesktop) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final opt in _filterOptions) pill(opt.$1, opt.$2)],
              ),
            );
          }
          return SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filterOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => pill(_filterOptions[i].$1, _filterOptions[i].$2),
            ),
          );
        }),

        Expanded(
          child: hasQuery ? _buildResults() : _buildEmpty(auth.isAuthenticated),
        ),
      ],
    );
  }

  Widget _buildEmpty(bool authed) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        if (authed && _recentLoaded && _recent.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.history, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(child: Text('Tìm kiếm gần đây', style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)))),
              TextButton(
                onPressed: _clearAllRecent,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text('Xoá tất cả', style: body(const TextStyle(fontSize: 11, color: AppColors.accentLight))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._recent.map((r) {
            final q = r['q']?.toString();
            final obj = r['object'];
            if (obj != null) {
              final objMap = Map<String, dynamic>.from(obj as Map);
              return _RecentObjectRow(
                obj: objMap,
                onTap: () => _openRecentObject(objMap),
                onDelete: () => _deleteRecent(r['id'].toString()),
                iconFor: _typeIcon,
                typeLabel: _objTypeLabel(objMap['__typename']?.toString()),
              );
            }
            if (q != null && q.isNotEmpty) {
              return _RecentRow(
                keyword: q,
                onTap: () => _useKeyword(q),
                onDelete: () => _deleteRecent(r['id'].toString()),
              );
            }
            return const SizedBox.shrink();
          }),
          const SizedBox(height: 22),
        ],
        if (_trendingLoaded && _trending.isNotEmpty) ...[
          Row(children: [
            const Icon(Icons.local_fire_department, size: 16, color: AppColors.accentLight),
            const SizedBox(width: 8),
            Text('Xu hướng tìm kiếm', style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _trending.map((kw) {
              final name = kw['name']?.toString() ?? '';
              return InkWell(
                onTap: () => _useKeyword(name),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(name, style: body(const TextStyle(fontSize: 12, color: AppColors.text))),
                ),
              );
            }).toList(),
          ),
        ],
        if (!_trendingLoaded && (!authed || _recent.isEmpty))
          const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: AppColors.accent))),
      ],
    );
  }

  Map<String, dynamic>? _findTopHit() {
    if (_filter != 'all' || _groups.isEmpty) return null;
    Map<String, dynamic>? best;
    double bestScore = -1;
    for (final g in _groups) {
      for (final h in ((g['hits'] as List?) ?? [])) {
        final score = (h['_score'] is num) ? (h['_score'] as num).toDouble() : 0.0;
        if (score > bestScore) { bestScore = score; best = Map<String, dynamic>.from(h as Map); }
      }
    }
    return best;
  }

  String _typeLabel(String? t) {
    final found = _filterOptions.firstWhere((o) => o.$1 == t, orElse: () => ('', '', null));
    return found.$2.isNotEmpty ? found.$2 : (t ?? '');
  }

  Widget _buildResults() {
    if (_loading && _groups.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text('Không tìm thấy kết quả', style: body(const TextStyle(color: AppColors.textMuted))),
            ],
          ),
        ),
      );
    }

    final topHit = _findTopHit();
    // Strip top hit from groups so it doesn't appear twice (only in 'all' mode)
    final displayGroups = _filter == 'all' && topHit != null
        ? _groups.map((g) {
            final hits = ((g['hits'] as List?) ?? [])
                .where((h) => !(h['id'].toString() == topHit['id'].toString() && h['_search_type'] == topHit['_search_type']))
                .toList();
            return {'type': g['type'], 'name': g['name'], 'hits': hits};
          }).where((g) => (g['hits'] as List).isNotEmpty).toList()
        : _groups;
    final totalHits = _groups.fold<int>(0, (s, g) => s + ((g['hits'] as List?)?.length ?? 0));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: displayGroups.length + (topHit != null ? 2 : 1), // +1 result count, +1 if topHit
      itemBuilder: (ctx, idx) {
        if (idx == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text('Tìm thấy $totalHits kết quả', style: body(const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
          );
        }
        if (topHit != null && idx == 1) {
          return _TopResultCard(
            hit: topHit,
            typeLabel: _typeLabel(topHit['_search_type']?.toString()),
            onTap: () => _openHit(topHit),
            iconFor: _typeIcon,
            isSongLike: _isSongLike,
          );
        }
        final gi = idx - (topHit != null ? 2 : 1);
        final g = displayGroups[gi];
        final hits = (g['hits'] as List? ?? []);
        final type = g['type']?.toString();
        final label = _typeLabel(type);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accentLight, letterSpacing: 1.5)),
                    ),
                  ),
                  if (_filter == 'all' && type != null && type.isNotEmpty)
                    InkWell(
                      onTap: () => _setFilter(type),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(children: [
                          Text('Xem tất cả', style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                          const Icon(Icons.chevron_right, size: 13, color: AppColors.textMuted),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
            ...hits.map((h) => _HitRow(hit: Map<String, dynamic>.from(h as Map), onTap: () => _openHit(Map<String, dynamic>.from(h)), iconFor: _typeIcon, isSongLike: _isSongLike)),
          ],
        );
      },
    );
  }
}

class _TopResultCard extends StatelessWidget {
  final Map<String, dynamic> hit;
  final String typeLabel;
  final VoidCallback onTap;
  final IconData Function(String?) iconFor;
  final bool Function(String?) isSongLike;
  const _TopResultCard({required this.hit, required this.typeLabel, required this.onTap, required this.iconFor, required this.isSongLike});

  @override
  Widget build(BuildContext context) {
    final t = hit['_search_type']?.toString();
    final image = hit['image']?.toString();
    final title = hit['title']?.toString() ?? '';
    final subtitle = isSongLike(t) ? hit['artist']?.toString() : null;
    final isPerson = t == 'artist' || t == 'composer' || t == 'poet' || t == 'recomposer' || t == 'user';

    // Desktop: larger artwork + hero-tier title (Apple Music / Spotify scale).
    // Mobile keeps the compact original sizing.
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final imgSize = isDesktop ? 140.0 : 84.0;
    final titleSize = isDesktop ? 24.0 : 16.0;
    final subSize = isDesktop ? 14.0 : 12.0;
    final cardPadding = isDesktop ? 22.0 : 14.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_outlined, size: 14, color: AppColors.accentLight),
                const SizedBox(width: 6),
                Text(
                  'KẾT QUẢ HÀNG ĐẦU',
                  style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accentLight, letterSpacing: 1.5)),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: EdgeInsets.all(cardPadding),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.12), blurRadius: 16, spreadRadius: -4, offset: const Offset(0, 6))],
              ),
              child: Row(
                children: [
                  Container(
                    width: imgSize, height: imgSize,
                    decoration: BoxDecoration(
                      shape: isPerson ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: isPerson ? null : BorderRadius.circular(12),
                      color: AppColors.surface,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: image != null
                        ? CachedNetworkImage(imageUrl: image, fit: BoxFit.cover, errorWidget: (_, _, _) => Icon(iconFor(t), color: AppColors.textMuted))
                        : Icon(iconFor(t), color: AppColors.textMuted, size: imgSize * 0.4),
                  ),
                  SizedBox(width: isDesktop ? 22 : 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(4)),
                          child: Text(typeLabel.toUpperCase(), style: body(const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.accentLight, letterSpacing: 1))),
                        ),
                        SizedBox(height: isDesktop ? 10 : 6),
                        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: titleSize, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.15, letterSpacing: -0.3))),
                        if (subtitle != null && subtitle.isNotEmpty) Padding(
                          padding: EdgeInsets.only(top: isDesktop ? 6 : 4),
                          child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: subSize, color: AppColors.textSecondary))),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentObjectRow extends StatelessWidget {
  final Map<String, dynamic> obj;
  final String typeLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final IconData Function(String?) iconFor;
  const _RecentObjectRow({required this.obj, required this.typeLabel, required this.onTap, required this.onDelete, required this.iconFor});

  @override
  Widget build(BuildContext context) {
    final tn = obj['__typename']?.toString();
    final image = (obj['thumbnail']?['url'] ?? obj['avatar']?['url'])?.toString();
    final title = (obj['title'] ?? obj['name'] ?? '').toString();
    final isPerson = tn == 'Artist' || tn == 'Composer' || tn == 'Poet' || tn == 'Recomposer';
    const typeKeyMap = {
      'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem',
      'Karaoke': 'karaoke', 'Artist': 'artist', 'Composer': 'composer',
      'Poet': 'poet', 'Recomposer': 'recomposer', 'Document': 'document',
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.history, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: isPerson ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: isPerson ? null : BorderRadius.circular(6),
                color: AppColors.surfaceLight,
              ),
              clipBehavior: Clip.hardEdge,
              child: image != null
                  ? CachedNetworkImage(imageUrl: image, fit: BoxFit.cover, errorWidget: (_, __, ___) => Icon(iconFor(typeKeyMap[tn]), color: AppColors.textMuted, size: 16))
                  : Icon(iconFor(typeKeyMap[tn]), color: AppColors.textMuted, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text))),
                  if (typeLabel.isNotEmpty) Text(typeLabel, style: body(const TextStyle(fontSize: 10, color: AppColors.textMuted))),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final String keyword;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _RecentRow({required this.keyword, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.history, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(child: Text(keyword, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, color: AppColors.text)))),
            IconButton(
              icon: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  final Map<String, dynamic> hit;
  final VoidCallback onTap;
  final IconData Function(String?) iconFor;
  final bool Function(String?) isSongLike;
  const _HitRow({required this.hit, required this.onTap, required this.iconFor, required this.isSongLike});

  @override
  Widget build(BuildContext context) {
    final t = hit['_search_type']?.toString();
    final image = hit['image']?.toString();
    final title = hit['title']?.toString() ?? '';
    final subtitle = isSongLike(t) ? hit['artist']?.toString() : null;
    final isPerson = t == 'artist' || t == 'composer' || t == 'poet' || t == 'recomposer' || t == 'user';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: isPerson ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: isPerson ? null : BorderRadius.circular(8),
                color: AppColors.surface,
              ),
              clipBehavior: Clip.hardEdge,
              child: image != null
                  ? CachedNetworkImage(imageUrl: image, fit: BoxFit.cover, errorWidget: (_, __, ___) => Icon(iconFor(t), color: AppColors.textMuted, size: 18))
                  : Icon(iconFor(t), color: AppColors.textMuted, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                  if (subtitle != null && subtitle.isNotEmpty) Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}
