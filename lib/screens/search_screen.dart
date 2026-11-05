import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';
import '../widgets/voice_search_sheet.dart';

class SearchScreen extends StatefulWidget {
  /// Pre-fill the search box + auto-run on first build. Used by the home
  /// page trending chip strip so taps land directly on results.
  final String? initialQuery;
  const SearchScreen({super.key, this.initialQuery});
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
  // Local recent — works for unauthed users (server-side recent requires
  // login). Stored as a JSON list of plain query strings, max 10 entries.
  List<String> _localRecent = [];
  static const _localRecentKey = 'search_local_recent';

  static const _filterOptions = [
    ('all', 'Tất cả', null),
    ('lyric', 'Lời bài hát', null),
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
    _loadLocalRecent();
    // Pre-fill from initialQuery (e.g. trending chip click) so the user
    // lands on results instead of an empty input.
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _ctrl.text = q;
      _query = q;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchTrending();
      if (context.read<AuthProvider>().isAuthenticated) _fetchRecent();
      if (q.isNotEmpty) _runSearch(q);
    });
  }

  Future<void> _loadLocalRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_localRecentKey) ?? const [];
      if (mounted) setState(() => _localRecent = List<String>.from(saved));
    } catch (_) {}
  }

  Future<void> _saveLocalRecent(String q) async {
    if (q.trim().isEmpty) return;
    final query = q.trim();
    // Move-to-front + dedupe + cap at 10. Mirrors how Spotify / browsers
    // surface "recent" — most-recent-first, no repeats.
    final next = [query, ..._localRecent.where((r) => r.toLowerCase() != query.toLowerCase())].take(10).toList();
    setState(() => _localRecent = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_localRecentKey, next);
    } catch (_) {}
  }

  Future<void> _clearLocalRecent() async {
    setState(() => _localRecent = []);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localRecentKey);
    } catch (_) {}
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
    // 200ms feels noticeably snappier than 400ms — autocomplete-grade
     // responsiveness without spamming the GraphQL endpoint.
    _debounce = Timer(const Duration(milliseconds: 200), () => _runSearch(v.trim()));
  }

  Future<void> _runSearch(String q) async {
    if (q.isEmpty) return;
    setState(() => _loading = true);
    try {
      final limit = _filter == 'all' ? 5 : 50;
      // "Lời bài hát": the same search over song lyrics (people often
      // remember a line, not the title). Needs the API's `lyric` flag.
      final byLyric = _filter == 'lyric';
      final data = await ApiClient.query(
        byLyric
            ? r'query($q: String!, $limit: Int) { search(q: $q, limit: $limit, type: "song", lyric: true) }'
            : r'query($q: String!, $limit: Int, $type: String!) { search(q: $q, limit: $limit, type: $type) }',
        byLyric ? {'q': q, 'limit': 30} : {'q': q, 'limit': limit, 'type': _filter},
      );
      final raw = (data['search'] ?? []) as List;
      final filtered = raw.where((g) => (g['hits'] as List?)?.isNotEmpty ?? false).toList();
      if (byLyric) {
        for (final g in filtered) {
          (g as Map)['type'] = 'lyric';
          g['hits'] = _lyricHits((g['hits'] as List?) ?? const []);
        }
      }
      // In "Tất cả", also look the words up inside lyrics and add the songs
      // whose lyrics match as a "Lời bài hát" group (silently skipped if
      // the server doesn't support it yet).
      if (_filter == 'all' && q.split(' ').length >= 3) {
        try {
          final ld = await ApiClient.query(r'query($q: String!) { search(q: $q, limit: 5, type: "song", lyric: true) }', {'q': q});
          final hits = _lyricHits(((ld['search'] ?? []) as List).expand((g) => ((g['hits'] as List?) ?? [])).toList()).take(3).toList();
          if (hits.isNotEmpty) filtered.add({'type': 'lyric', 'name': 'Lời bài hát', 'hits': hits});
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() { _groups = filtered; _loading = false; });
      _trackKeyword(q);
    } catch (_) {
      if (mounted) setState(() { _groups = []; _loading = false; });
    }
  }

  /// Lyric matches: one row per song title (several recordings of a song
  /// share the same lyrics) and a clean snippet without verse markers
  /// ("1, 3-") or photo captions ("(Ảnh …)").
  List<dynamic> _lyricHits(List hits) {
    final seen = <String>{};
    final out = [];
    for (final h in hits.whereType<Map>()) {
      var s = (h['lyric_snippet'] ?? '').toString();
      if (s.isEmpty) continue;
      if (!seen.add((h['title'] ?? '').toString().toLowerCase().trim())) continue;
      s = s
          .replaceAll(RegExp(r'\((Ảnh|ảnh|Nguồn|nguồn)[^)]*\)?'), ' ')
          .replaceAll(RegExp(r'(^|\s)(\d+(\s*[,&]\s*\d+)*\s*[-–.:)]|ĐK\s*:?|Đk\s*:?)\s', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      out.add({...Map<String, dynamic>.from(h), 'lyric_snippet': s});
    }
    return out;
  }

  Future<void> _trackKeyword(String q) async {
    // Always remember locally — works for both authed and unauthed. The
    // server-side recent (below) is the cross-device version for authed
    // users; both lists merge in the empty state UI.
    await _saveLocalRecent(q);
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
        // Build minimal song map for player. Source defaults to 'manual'
        // — even though navigation came from a search result, the user
        // who clicks AND lets the song play 30s+ is genuinely listening,
        // so it should count (web tracker does the same).
        final song = <String, dynamic>{
          'id': id, 'title': hit['title'], 'slug': slug, 'file_type': t,
          if (hit['image'] != null) 'thumbnail': {'url': hit['image']},
          if (hit['artist'] != null) 'artists': {'data': [{'title': hit['artist']}]},
          if (hit['audio_url'] != null || hit['video_url'] != null) 'file': {'audio_url': hit['audio_url'], 'video_url': hit['video_url']},
          'play_type': hit['play_type'] ?? 'audio',
        };
        // Tap = play (app-wide rule); the group's songs become the queue.
        final group = _groups.firstWhere((g) => g['type'] == t, orElse: () => {'hits': [hit]});
        final queue = ((group['hits'] as List?) ?? [hit]).whereType<Map>().map((h) => <String, dynamic>{
              'id': h['id'], 'title': h['title'], 'slug': h['slug'], 'file_type': t,
              if (h['image'] != null) 'thumbnail': {'url': h['image']},
              if (h['artist'] != null) 'artists': {'data': [{'title': h['artist']}]},
              if (h['audio_url'] != null) 'file': {'audio_url': h['audio_url'], 'video_url': h['video_url']},
            }).toList();
        playOrOpen(context, song, queue, 'Tìm kiếm: ${_query.trim()}');
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

    return ColoredBox(
      color: AppColors.bg,
      child: Column(
        children: [
          if (!hasQuery && !_focus.hasFocus) const PageTitle('Khám phá'),
          Padding(
            padding: EdgeInsets.fromLTRB(20, hasQuery || _focus.hasFocus ? 10 : 16, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 50,
                    padding: const EdgeInsets.only(left: 18, right: 8),
                    decoration: BoxDecoration(
                      color: _focus.hasFocus ? AppColors.bg : AppColors.surface,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: _focus.hasFocus ? AppColors.wine : Colors.transparent, width: 2),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 22, color: AppColors.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            focusNode: _focus,
                            autofocus: widget.initialQuery != null,
                            textInputAction: TextInputAction.search,
                            style: body(TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600)),
                            decoration: InputDecoration(
                              hintText: 'Bài hát, nhạc sĩ, ca sĩ, lời…',
                              hintStyle: body(TextStyle(color: AppColors.textMuted, fontSize: 16, fontWeight: FontWeight.w600)),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onTap: () => setState(() {}),
                            onTapOutside: (_) {
                              _focus.unfocus();
                              setState(() {});
                            },
                            onSubmitted: (v) => _runSearch(v.trim()),
                            onChanged: _onChanged,
                          ),
                        ),
                        if (hasQuery)
                          IconButton(
                            tooltip: 'Xoá',
                            icon: Icon(Icons.cancel_rounded, size: 20, color: AppColors.textMuted),
                            onPressed: () { _ctrl.clear(); _onChanged(''); },
                          )
                        else
                          IconButton(
                            tooltip: 'Tìm bằng giọng nói',
                            icon: Icon(Icons.mic_none_rounded, size: 24, color: AppColors.accentLight),
                            onPressed: () async {
                              final heard = await showVoiceSearch(context);
                              if (heard == null || heard.isEmpty || !mounted) return;
                              _ctrl.text = heard;
                              setState(() => _query = heard);
                              _runSearch(heard);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                if (hasQuery || _focus.hasFocus)
                  TextButton(
                    onPressed: () {
                      _ctrl.clear();
                      _onChanged('');
                      _focus.unfocus();
                      setState(() {});
                    },
                    style: TextButton.styleFrom(minimumSize: const Size(56, 44)),
                    child: Text('Huỷ', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.accentLight))),
                  ),
              ],
            ),
          ),
          if (hasQuery)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: ChipStrip(
                labels: [for (final o in _filterOptions) o.$2],
                selected: _filterOptions.indexWhere((o) => o.$1 == _filter),
                onSelect: (i) => _setFilter(_filterOptions[i].$1),
              ),
            ),
          Expanded(
            child: hasQuery ? _buildResults() : _buildEmpty(auth.isAuthenticated),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool authed) {
    final serverRecent = authed && _recentLoaded && _recent.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (serverRecent) ...[
          SectionTitle('Tìm gần đây', action: 'Xoá', onAction: _clearAllRecent, padding: const EdgeInsets.fromLTRB(20, 20, 12, 6)),
          ..._recent.take(5).map((r) {
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
              return _RecentRow(keyword: q, onTap: () => _useKeyword(q), onDelete: () => _deleteRecent(r['id'].toString()));
            }
            return const SizedBox.shrink();
          }),
        ] else if (_localRecent.isNotEmpty) ...[
          SectionTitle('Tìm gần đây', action: 'Xoá', onAction: _clearLocalRecent, padding: const EdgeInsets.fromLTRB(20, 20, 12, 6)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final q in _localRecent.take(5)) BrandChip(label: q, icon: Icons.history_rounded, onTap: () => _useKeyword(q))],
            ),
          ),
        ],
        if (_trendingLoaded && _trending.isNotEmpty) ...[
          SectionTitle('Đang được tìm', action: null, padding: const EdgeInsets.fromLTRB(20, 24, 12, 10)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kw in _trending.take(8))
                  BrandChip(label: kw['name']?.toString() ?? '', soft: true, onTap: () => _useKeyword(kw['name']?.toString() ?? '')),
              ],
            ),
          ),
        ],
        const _BrowseBlocks(),
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
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_groups.isEmpty) {
      // No results — surface trending keywords as alternatives so the
      // user has somewhere to go instead of bouncing.
      return ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          EmptyBlock(
            icon: Icons.search_off_rounded,
            title: 'Không tìm thấy kết quả',
            message: _filter == 'lyric'
                ? 'Thử gõ đúng một câu hát bạn nhớ, có dấu càng tốt.'
                : 'Thử từ khoá khác, hoặc tìm theo một câu trong lời bài hát.',
            action: _filter == 'all' ? 'Tìm trong lời bài hát' : 'Tìm trong "Tất cả"',
            onAction: () => _setFilter(_filter == 'all' ? 'lyric' : 'all'),
          ),
          if (_trending.isNotEmpty) ...[
            SectionTitle('Đang được tìm', action: null),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final kw in _trending.take(8)) BrandChip(label: kw['name']?.toString() ?? '', soft: true, onTap: () => _useKeyword(kw['name']?.toString() ?? ''))],
              ),
            ),
          ],
        ],
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      itemCount: displayGroups.length + (topHit != null ? 2 : 1), // +1 result count, +1 if topHit
      itemBuilder: (ctx, idx) {
        if (idx == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text('Tìm thấy $totalHits kết quả', style: body(TextStyle(fontSize: 13, color: AppColors.textSecondary))),
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
                      style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accentLight, letterSpacing: 1.5)),
                    ),
                  ),
                  if (_filter == 'all' && type != null && type.isNotEmpty)
                    InkWell(
                      onTap: () => _setFilter(type),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(children: [
                          Text('Xem tất cả', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                          Icon(Icons.chevron_right, size: 13, color: AppColors.textMuted),
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
    final isPerson = t == 'artist' || t == 'composer' || t == 'poet' || t == 'recomposer' || t == 'user';
    final views = hit['views'] is num ? (hit['views'] as num).toInt() : 0;
    final sub = [
      typeLabel,
      if (isSongLike(t) && (hit['artist']?.toString() ?? '').isNotEmpty) hit['artist'].toString(),
      if (views > 0) '${formatViews(views)} lượt nghe',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('Kết quả hàng đầu', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
        ),
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                NetImage(
                  url: image,
                  width: 76,
                  height: 76,
                  circle: isPerson,
                  radius: isPerson ? 0 : 14,
                  fallback: GeneratedCover(title: title, size: 76, radius: isPerson ? 38 : 14),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 20, height: 1.2, fontWeight: FontWeight.w800, color: AppColors.text))),
                    const SizedBox(height: 4),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta),
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(color: AppColors.wine, shape: BoxShape.circle),
                  child: Icon(isSongLike(t) ? Icons.play_arrow_rounded : Icons.arrow_forward_rounded, color: Colors.white, size: 28),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
        child: Row(
          children: [
            NetImage(url: image, width: 48, height: 48, circle: isPerson, radius: isPerson ? 0 : 10, fallback: GeneratedCover(title: title, size: 48, radius: isPerson ? 24 : 10)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title),
                  if (typeLabel.isNotEmpty) Text(typeLabel, style: AppText.meta),
                ],
              ),
            ),
            IconButton(tooltip: 'Xoá khỏi lịch sử', icon: Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted), onPressed: onDelete),
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
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.search_rounded, size: 22, color: AppColors.textMuted),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(keyword, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title)),
              IconButton(tooltip: 'Xoá khỏi lịch sử', icon: Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted), onPressed: onDelete),
            ],
          ),
        ),
      );
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
    final isPerson = t == 'artist' || t == 'composer' || t == 'poet' || t == 'recomposer' || t == 'user';
    final views = hit['views'] is num ? (hit['views'] as num).toInt() : 0;
    final snippet = (hit['lyric_snippet'] ?? '').toString();
    final sub = snippet.isNotEmpty
        ? '“…$snippet…”'
        : [
            if (isSongLike(t) && (hit['artist']?.toString() ?? '').isNotEmpty && hit['artist'] != 'Đang cập nhật') hit['artist'].toString(),
            if (views > 0) '${formatViews(views)} lượt nghe',
          ].join(' · ');
    final song = isSongLike(t)
        ? <String, dynamic>{
            'id': hit['id'], 'title': title, 'slug': hit['slug'], 'file_type': t,
            if (image != null) 'thumbnail': {'url': image},
            if (hit['artist'] != null) 'artists': {'data': [{'title': hit['artist']}]},
            if (hit['audio_url'] != null) 'file': {'audio_url': hit['audio_url'], 'video_url': hit['video_url']},
          }
        : null;
    return InkWell(
      onTap: onTap,
      onLongPress: song == null ? null : () => showSongActions(context, song),
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              NetImage(url: image, width: 52, height: 52, circle: isPerson, radius: isPerson ? 0 : 12, fallback: GeneratedCover(title: title, size: 52, radius: isPerson ? 26 : 12)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title),
                    if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(sub, maxLines: snippet.isNotEmpty ? 2 : 1, overflow: TextOverflow.ellipsis, style: snippet.isNotEmpty ? AppText.meta.copyWith(fontStyle: FontStyle.italic) : AppText.meta)),
                  ],
                ),
              ),
              if (song != null)
                IconButton(tooltip: 'Tuỳ chọn', icon: Icon(Icons.more_vert_rounded, color: AppColors.textMuted), onPressed: () => showSongActions(context, song))
              else
                Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Browse shortcuts under the empty search box: kinds, decades, popular
/// topics and the archive — an empty search still leads somewhere.
class _BrowseBlocks extends StatefulWidget {
  const _BrowseBlocks();
  @override
  State<_BrowseBlocks> createState() => _BrowseBlocksState();
}

class _BrowseBlocksState extends State<_BrowseBlocks> {
  static const _kinds = [
    ('Tân nhạc', '/the-loai/tan-nhac', Color(0xFF711313)),
    ('Dân ca', '/the-loai/dan-ca', Color(0xFF8C3B3A)),
    ('Khí nhạc', '/the-loai/khi-nhac', Color(0xFF3B0F0F)),
    ('Tiếng thơ', '/the-loai/tieng-tho', Color(0xFF9C5E5C)),
    ('Thành viên hát', '/the-loai/thanh-vien-hat', Color(0xFF5A1D1D)),
    ('Bản nhạc', '/sheet', Color(0xFFB48988)),
  ];
  static const _decades = [1940, 1950, 1960, 1970, 1980, 1990];

  List<Map<String, dynamic>> _tags = [];

  @override
  void initState() {
    super.initState();
    ApiClient.query(r'query { popularTags(limit: 12) { id name slug song_count sample_images } }').then((d) {
      if (!mounted) return;
      setState(() => _tags = ((d['popularTags'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
    }).catchError((_) {});
  }

  List<String> get _images => [
        for (final t in _tags)
          ...((t['sample_images'] is List) ? (t['sample_images'] as List).whereType<String>() : const <String>[]),
      ];

  @override
  Widget build(BuildContext context) {
    final imgs = _images;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('Thể loại', action: null),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              for (var i = 0; i < _kinds.length; i++)
                Material(
                  color: _kinds[i].$3,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push(_kinds[i].$2),
                    child: Stack(children: [
                      if (i < imgs.length)
                        Positioned(
                          right: -16,
                          bottom: -12,
                          child: Transform.rotate(
                            angle: 0.3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 16, offset: Offset(0, 6))]),
                              child: NetImage(url: imgs[i], width: 84, height: 84, radius: 12, tint: true),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(_kinds[i].$1, style: display(const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white))),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
        SectionTitle('Thập niên', action: null),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _decades.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => BrandChip(label: 'Thập niên ${_decades[i] % 100 == 0 ? '00' : _decades[i] % 100}', onTap: () => context.push('/bai-hat/thap-nien/${_decades[i]}')),
          ),
        ),
        if (_tags.isNotEmpty) ...[
          SectionTitle('Chủ đề', action: 'Tất cả', onAction: () => context.push('/tag')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final t in _tags) BrandChip(label: '#${t['name']}', onTap: () => context.push('/tag/${t['slug']}'))],
            ),
          ),
        ],
        SectionTitle('Kho tư liệu', action: null),
        ListItem(icon: Icons.photo_outlined, title: 'Ảnh tư liệu', onTap: () => context.push('/tu-lieu/hinh-anh')),
        ListItem(icon: Icons.videocam_outlined, title: 'Video tư liệu', onTap: () => context.push('/tu-lieu/video')),
        ListItem(icon: Icons.graphic_eq_rounded, title: 'Tư liệu âm thanh', onTap: () => context.push('/tu-lieu/am-thanh')),
        ListItem(icon: Icons.emoji_events_outlined, title: 'Bảng xếp hạng', onTap: () => context.push('/bang-xep-hang')),
        ListItem(icon: Icons.person_search_outlined, title: 'Nhạc sĩ', onTap: () => context.push('/nhac-si')),
        ListItem(icon: Icons.mic_none_rounded, title: 'Ca sĩ', onTap: () => context.push('/nghe-si')),
        ListItem(icon: Icons.queue_music_rounded, title: 'Playlist cộng đồng', onTap: () => context.push('/playlist')),
      ],
    );
  }
}
