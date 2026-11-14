import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/events.dart';
import '../services/lunar.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';
import '../main.dart' show TabReselect;
import '../widgets/voice_search_sheet.dart';
import '../widgets/new_documents_rail.dart';

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

  final _browseScroll = ScrollController();

  // Tapping "Tìm kiếm" again: back to the top of the browse grid, or put
  // the cursor in the search box when already there.
  void _onReselect() {
    if (TabReselect.tick.value.$1 != 1) return;
    if (_browseScroll.hasClients && _browseScroll.offset > 0) {
      _browseScroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    } else {
      _focus.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    TabReselect.tick.addListener(_onReselect);
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
      // Desktop: arriving from the sidebar means "I want to type".
      if (q.isEmpty && mounted && MediaQuery.sizeOf(context).width >= 900) _focus.requestFocus();
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
    if (mounted) setState(() => _localRecent = next);
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
    TabReselect.tick.removeListener(_onReselect);
    _browseScroll.dispose();
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
      _searchSeq++; // a search still in flight must not refill the cleared box
      setState(() { _groups = []; _loading = false; _searchFailed = false; });
      return;
    }
    // 200ms feels noticeably snappier than 400ms — autocomplete-grade
     // responsiveness without spamming the GraphQL endpoint.
    _debounce = Timer(const Duration(milliseconds: 200), () => _runSearch(v.trim()));
  }

  // Each search gets a number; only the latest one may write results.
  // Typing "bac", "bac ho" fires two requests and the slower first one
  // used to land last and replace the right results.
  int _searchSeq = 0;

  Future<void> _runSearch(String q) async {
    if (q.isEmpty) return;
    final seq = ++_searchSeq;
    setState(() => _loading = true);
    try {
      // Desktop shows more per group: recordings of one song fold into a row.
      final desk = MediaQuery.sizeOf(context).width >= 900;
      final limit = _filter == 'all' ? (desk ? 12 : 5) : 50;
      // "Lời bài hát": the same search over song lyrics (people often
      // remember a line, not the title). Needs the API's `lyric` flag.
      final byLyric = _filter == 'lyric';
      final data = await ApiClient.query(
        byLyric
            ? r'query($q: String!, $limit: Int) { search(q: $q, limit: $limit, type: "song", lyric: true) }'
            : r'query($q: String!, $limit: Int, $type: String!) { search(q: $q, limit: $limit, type: $type) }',
        byLyric ? {'q': q, 'limit': 30} : {'q': q, 'limit': limit, 'type': _filter},
      );
      if (seq != _searchSeq) return;
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
      // Desktop has a column for it, so two words are enough there.
      if (_filter == 'all' && q.split(' ').length >= (desk ? 2 : 3)) {
        try {
          final wide = mounted && MediaQuery.sizeOf(context).width >= 1100;
          final ld = await ApiClient.query(r'query($q: String!, $limit: Int) { search(q: $q, limit: $limit, type: "song", lyric: true) }', {'q': q, 'limit': wide ? 12 : 5});
          final hits = _lyricHits(((ld['search'] ?? []) as List).expand((g) => ((g['hits'] as List?) ?? [])).toList()).take(wide ? 8 : 3).toList();
          if (hits.isNotEmpty) filtered.add({'type': 'lyric', 'name': 'Lời bài hát', 'hits': hits});
        } catch (_) {}
      }
      if (!mounted || seq != _searchSeq) return;
      // Recent keywords are recorded on submit / result tap, not here: a
      // debounce fires on half-typed words ("bá", "bác h").
      setState(() { _groups = filtered; _loading = false; _searchFailed = false; });
      if (desk) _loadPersonTop();
    } catch (_) {
      if (mounted && seq == _searchSeq) setState(() { _groups = []; _loading = false; _searchFailed = true; });
    }
  }

  // Search failed (network), so "không tìm thấy" would be a lie.
  bool _searchFailed = false;

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

  String? _trackedQuery;

  Future<void> _trackKeyword(String q) async {
    q = q.trim();
    // Several result taps for one search record it once.
    if (q.isEmpty || q == _trackedQuery) return;
    _trackedQuery = q;
    // Always remember locally — works for both authed and unauthed. The
    // server-side recent (below) is the cross-device version for authed
    // users; both lists merge in the empty state UI.
    final auth = context.read<AuthProvider>();
    await _saveLocalRecent(q);
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
    // Picking a chip is a deliberate search, like pressing Search.
    _trackKeyword(kw);
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
      case 'tag':
        context.push('/tag/$slug');
        break;
      default: break;
    }
    _trackKeyword(_query);
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
    if (MediaQuery.sizeOf(context).width >= 900) return _buildDesktop(auth.isAuthenticated);

    return ColoredBox(
      color: AppColors.bg,
      child: Column(
        children: [
          if (!hasQuery && !_focus.hasFocus) const PageTitle('Tìm kiếm'),
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
                            // With a query the user came for the results; the
                            // keyboard would cover them.
                            // The tab doubles as the browse page: no keyboard popping over it.
                            autofocus: false,
                            textInputAction: TextInputAction.search,
                            style: body(TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600)),
                            decoration: InputDecoration(
                              hintText: 'Bài hát, nhạc sĩ, nghệ sĩ, lời…',
                              hintStyle: body(TextStyle(color: AppColors.textMuted, fontSize: 16, fontWeight: FontWeight.w600)),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onTap: () => setState(() {}),
                            onTapOutside: (_) {
                              _focus.unfocus();
                              setState(() {});
                            },
                            onSubmitted: (v) {
                              _debounce?.cancel();
                              _runSearch(v.trim());
                              _trackKeyword(v);
                            },
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

  List<Map<String, dynamic>> _dedupedRecent() {
    String norm(Object? v) => (v ?? '').toString().trim().toLowerCase();
    final objTitles = {
      for (final r in _recent)
        if (r['object'] is Map) norm((r['object'] as Map)['title']),
    };
    final seen = <String>{};
    return [
      for (final r in _recent.whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
        if (r['object'] is Map
            ? seen.add('o:${(r['object'] as Map)['__typename']}:${(r['object'] as Map)['id']}')
            : (!objTitles.contains(norm(r['q'])) && seen.add('q:${norm(r['q'])}')))
          r,
    ];
  }

  Widget _buildEmpty(bool authed) {
    final serverRecent = authed && _recentLoaded && _recent.isNotEmpty;
    return ListView(
      controller: _browseScroll,
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (serverRecent) ...[
          SectionTitle('Tìm gần đây', action: 'Xoá', onAction: _clearAllRecent, padding: const EdgeInsets.fromLTRB(20, 20, 12, 6)),
          // A search that ended in a click is logged twice (the typed words,
          // then the song opened); show the song once, not both.
          ..._dedupedRecent().take(5).map((r) {
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
                  BrandChip(label: kw['name']?.toString() ?? '', onTap: () => _useKeyword(kw['name']?.toString() ?? '')),
              ],
            ),
          ),
        ],
        const _BrowseBlocks(),
      ],
    );
  }

  // ------------------------------------------------------------ Desktop
  // Canvas "Desktop · Tìm kiếm": one big box (the top bar hides its own),
  // no "Huỷ"; results in two columns with recordings of one song folded
  // into a row; a person on top brings their most played songs.

  static const _personTypes = ['composer', 'artist', 'poet', 'recomposer'];
  static const _personRoute = {'composer': '/nhac-si/', 'artist': '/nghe-si/', 'poet': '/nha-tho/', 'recomposer': '/soan-gia/'};
  static const _personRole = {'composer': 'Nhạc sĩ', 'artist': 'Nghệ sĩ', 'poet': 'Nhà thơ', 'recomposer': 'Soạn giả'};
  static const _mainFilters = ['all', 'lyric', 'song', 'folk', 'instrumental', 'document'];
  final Set<String> _openRec = {};
  Map<String, dynamic>? _personTop;

  static String _norm(Object? v) => (v ?? '').toString().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// One entry per name: "Phạm Tuyên" as Nhạc sĩ, Nghệ sĩ and Nhà thơ is
  /// one person with three roles (and the photo any of them has).
  List<Map<String, dynamic>> _mergedPeople() {
    final byName = <String, Map<String, dynamic>>{};
    for (final t in _personTypes) {
      for (final g in _groups.where((g) => g['type'] == t)) {
        for (final h in ((g['hits'] as List?) ?? const []).whereType<Map>()) {
          final e = byName.putIfAbsent(_norm(h['title']), () => {...Map<String, dynamic>.from(h), 'types': <String>[], '_score': 0.0});
          (e['types'] as List<String>).add(t);
          if ('${e['image'] ?? ''}'.isEmpty && '${h['image'] ?? ''}'.isNotEmpty) e['image'] = h['image'];
          final sc = (h['_score'] as num?)?.toDouble() ?? 0;
          if (sc > (e['_score'] as double)) e['_score'] = sc;
        }
      }
    }
    return byName.values.toList()..sort((a, b) => (b['_score'] as double).compareTo(a['_score'] as double));
  }

  Map<String, dynamic>? _deskTopHit() {
    final top = _findTopHit();
    if (top == null || !_personTypes.contains(top['_search_type'])) return top;
    return _mergedPeople().firstWhere((p) => _norm(p['title']) == _norm(top['title']), orElse: () => top);
  }

  /// Songs of the person on top, most played first.
  Future<void> _loadPersonTop() async {
    final top = _filter == 'all' ? _deskTopHit() : null;
    final types = (top?['types'] as List?)?.cast<String>() ?? const <String>[];
    if (top == null || types.isEmpty) {
      if (_personTop != null) setState(() => _personTop = null);
      return;
    }
    final type = _personTypes.firstWhere(types.contains);
    final key = '$type:${top['slug']}';
    if (_personTop?['key'] == key) return;
    _personTop = {'key': key, 'type': type, 'songs': null};
    final field = type == 'recomposer' ? 'folks' : 'songs';
    try {
      final d = await ApiClient.query('query(\$s: String!) { $type(slug: \$s) { yob yod $field(first: 12, orderBy: [{column: "views", order: DESC}]) { paginatorInfo { total } data { id title slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug } } } } } }', {'s': top['slug']});
      final p = d[type];
      if (!mounted || _personTop?['key'] != key || p is! Map) return;
      final ft = field == 'folks' ? 'folk' : 'song';
      setState(() => _personTop = {
            'key': key, 'type': type, 'yob': p['yob'], 'yod': p['yod'],
            'total': p[field]?['paginatorInfo']?['total'],
            'songs': [for (final s in ((p[field]?['data'] ?? const []) as List).whereType<Map>()) {...Map<String, dynamic>.from(s), 'file_type': ft}],
          });
    } catch (_) {
      if (mounted && _personTop?['key'] == key) setState(() => _personTop = {..._personTop!, 'songs': const []});
    }
  }

  Map<String, dynamic> _hitSong(Map h) {
    final t = h['_search_type']?.toString() ?? 'song';
    return {
      'id': h['id'], 'title': h['title'], 'slug': h['slug'], 'file_type': t,
      if ('${h['image'] ?? ''}'.isNotEmpty) 'thumbnail': {'url': h['image']},
      if (h['artist'] != null) 'artists': {'data': [{'title': h['artist']}]},
      if (h['audio_url'] != null || h['video_url'] != null) 'file': {'audio_url': h['audio_url'], 'video_url': h['video_url']},
      'play_type': h['play_type'] ?? 'audio',
    };
  }

  void _queue(Map<String, dynamic> song) {
    final player = context.read<PlayerProvider>();
    if (player.currentSong == null) {
      player.playSong(song, [song], 'manual');
      return;
    }
    if (!player.queue.any((s) => sameSong(s, song))) player.setQueue([...player.queue, song]);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Đã thêm "${song['title']}" vào danh sách phát'), duration: const Duration(seconds: 2)));
  }

  Widget _buildDesktop(bool authed) {
    final hasQuery = _query.trim().isNotEmpty;
    return ColoredBox(
      color: AppColors.bg,
      child: LayoutBuilder(builder: (context, c) {
        final pad = c.maxWidth < 1000 ? 28.0 : 40.0;
        Widget frame(Widget child) => Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 1240 + pad * 2), child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: child)),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 24),
          frame(_deskBox(hasQuery)),
          if (hasQuery) frame(_deskFilters()),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 1240 + pad * 2),
                child: hasQuery ? _deskResults(pad, c.maxWidth) : _deskEmpty(authed, pad),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _deskBox(bool hasQuery) {
    final ring = !hasQuery || _focus.hasFocus;
    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: 20, right: 8),
      decoration: BoxDecoration(
        color: ring ? AppColors.bg : AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: ring ? AppColors.wine : Colors.transparent, width: 2),
      ),
      child: Row(children: [
        Icon(Icons.search_rounded, size: 24, color: AppColors.textMuted),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            style: body(TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
            decoration: InputDecoration(
              hintText: 'Tìm bài, nhạc sĩ, nghệ sĩ, hoặc một câu hát…',
              hintStyle: body(TextStyle(color: AppColors.textMuted, fontSize: 18, fontWeight: FontWeight.w600)),
              border: InputBorder.none,
              isDense: true,
            ),
            onTap: () => setState(() {}),
            onTapOutside: (_) => setState(() {}),
            onSubmitted: (v) {
              _debounce?.cancel();
              _runSearch(v.trim());
              _trackKeyword(v);
            },
            onChanged: _onChanged,
          ),
        ),
        if (hasQuery)
          IconButton(
            tooltip: keyTip(context, 'Xoá', 'Esc'),
            icon: Icon(Icons.cancel_rounded, size: 22, color: AppColors.textMuted),
            onPressed: () {
              _ctrl.clear();
              _onChanged('');
              _focus.requestFocus();
            },
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
      ]),
    );
  }

  Widget _deskFilters() {
    final more = _filterOptions.where((o) => !_mainFilters.contains(o.$1)).toList();
    final inMore = more.where((o) => o.$1 == _filter).firstOrNull;
    final total = _groups.fold<int>(0, (s, g) => s + ((g['hits'] as List?)?.length ?? 0));
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(children: [
        Expanded(
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in _filterOptions.where((o) => _mainFilters.contains(o.$1))) _DeskChip(label: o.$2, on: o.$1 == _filter, onTap: () => _setFilter(o.$1)),
            PopupMenuButton<String>(
              tooltip: 'Thêm bộ lọc',
              position: PopupMenuPosition.under,
              onSelected: _setFilter,
              itemBuilder: (_) => [for (final o in more) PopupMenuItem(value: o.$1, child: Text(o.$2, style: body(TextStyle(fontSize: 15, fontWeight: o.$1 == _filter ? FontWeight.w800 : FontWeight.w600, color: AppColors.text))))],
              child: _DeskChip(label: inMore?.$2 ?? 'Thêm', on: inMore != null, trailing: Icons.expand_more_rounded),
            ),
          ]),
        ),
        if (_groups.isNotEmpty) Text('$total kết quả', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
      ]),
    );
  }

  Widget _deskEmpty(bool authed, double pad) {
    final serverRecent = authed && _recentLoaded && _recent.isNotEmpty;
    final recent = <Widget>[
      if (serverRecent) ...[
        _DeskTitle('Tìm gần đây', action: 'Xoá', onAction: _clearAllRecent, top: 0),
        for (final r in _dedupedRecent().take(5))
          if (r['object'] is Map)
            _RecentObjectRow(
              obj: Map<String, dynamic>.from(r['object'] as Map),
              onTap: () => _openRecentObject(Map<String, dynamic>.from(r['object'] as Map)),
              onDelete: () => _deleteRecent(r['id'].toString()),
              iconFor: _typeIcon,
              typeLabel: _objTypeLabel((r['object'] as Map)['__typename']?.toString()),
              inset: 0,
            )
          else if ('${r['q'] ?? ''}'.isNotEmpty)
            _RecentRow(keyword: '${r['q']}', onTap: () => _useKeyword('${r['q']}'), onDelete: () => _deleteRecent(r['id'].toString()), inset: 0),
      ] else if (_localRecent.isNotEmpty) ...[
        _DeskTitle('Tìm gần đây', action: 'Xoá', onAction: _clearLocalRecent, top: 0),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final q in _localRecent.take(8)) BrandChip(label: q, icon: Icons.history_rounded, onTap: () => _useKeyword(q))]),
      ],
    ];
    final trending = <Widget>[
      if (_trendingLoaded && _trending.isNotEmpty) ...[
        _DeskTitle('Đang được tìm', top: 0),
        Wrap(spacing: 10, runSpacing: 10, children: [for (final kw in _trending.take(10)) BrandChip(label: kw['name']?.toString() ?? '', onTap: () => _useKeyword(kw['name']?.toString() ?? ''))]),
      ],
    ];
    return ListView(
      controller: _browseScroll,
      padding: EdgeInsets.fromLTRB(pad, 32, pad, 56),
      children: [
        if (recent.isNotEmpty || trending.isNotEmpty)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: recent.isNotEmpty ? recent : trending)),
            const SizedBox(width: 48),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: recent.isNotEmpty ? trending : const [])),
          ]),
        const _BrowseBlocks(desktop: true),
      ],
    );
  }

  Widget _deskResults(double pad, double width) {
    if (_groups.isEmpty) return _buildResults();
    final songTypes = ['song', 'folk', 'instrumental', 'poem', 'karaoke'];
    Widget list(List<Widget> children) => ListView(padding: EdgeInsets.fromLTRB(pad, 24, pad, 56), children: children);
    List hitsOf(String t) => _groups.where((g) => g['type'] == t).expand((g) => (g['hits'] as List?) ?? const []).toList();

    if (_filter != 'all') {
      if (songTypes.contains(_filter)) return list([_deskSongTable(hitsOf(_filter), max: 60)]);
      if (_filter == 'lyric') return list([for (final g in _groups) ...((g['hits'] as List?) ?? const []).whereType<Map>().map((h) => _lyricRow(Map<String, dynamic>.from(h)))]);
      return list([for (final g in _groups) ...((g['hits'] as List?) ?? const []).whereType<Map>().map((h) => _deskMini(Map<String, dynamic>.from(h)))]);
    }

    final top = _deskTopHit();
    final topTypes = (top?['types'] as List?)?.cast<String>();
    final personTop = topTypes != null;
    bool isTop(Map h) => top != null && !personTop && h['id'].toString() == top['id'].toString() && h['_search_type'] == top['_search_type'];

    final left = <Widget>[
      if (top != null && !personTop) _DeskTopSong(hit: top, typeLabel: _typeLabel(top['_search_type']?.toString()), onPlay: () => _openHit(top), onQueue: () => _queue(_hitSong(top))),
      if (personTop) ..._personSongsTable(top!),
      for (final t in songTypes)
        if (hitsOf(t).where((h) => !isTop(h as Map)).isNotEmpty) ...[
          _DeskTitle(_typeLabel(t), action: 'Xem tất cả', onAction: () => _setFilter(t)),
          _deskSongTable(hitsOf(t).where((h) => !isTop(h as Map)).toList()),
        ],
    ];
    final people = _mergedPeople().where((p) => !personTop || _norm(p['title']) != _norm(top!['title'])).toList();
    final lyric = hitsOf('lyric');
    final right = <Widget>[
      if (lyric.isNotEmpty) ...[
        _DeskTitle('Khớp lời bài hát', action: 'Xem tất cả', onAction: () => _setFilter('lyric'), top: 0),
        Text('Bài có câu hát chứa chữ bạn gõ', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
        for (final h in lyric.whereType<Map>()) _lyricRow(Map<String, dynamic>.from(h)),
      ],
      if (people.isNotEmpty) ...[_DeskTitle('Người', top: lyric.isEmpty ? 0 : 32), for (final p in people.take(6)) _deskMini(p)],
      for (final (t, label) in const [('tag', 'Chủ đề'), ('document', 'Tư liệu'), ('user', 'Thành viên')])
        if (hitsOf(t).isNotEmpty) ...[
          _DeskTitle(label, action: t == 'tag' ? null : 'Xem tất cả', onAction: () => _setFilter(t), top: 32),
          for (final h in hitsOf(t).take(5).whereType<Map>()) _deskMini(Map<String, dynamic>.from(h)),
        ],
    ];
    // The first title on the right sits level with the first on the left.
    if (right.isNotEmpty && right.first is _DeskTitle) right[0] = (right.first as _DeskTitle).withTop(0);
    final head = personTop ? <Widget>[_personCard(top!), const SizedBox(height: 8)] : const <Widget>[];
    if (left.isEmpty) return list([...head, ...right]);
    if (right.isEmpty || width < 1100) return list([...head, ...left, if (right.isNotEmpty) const SizedBox(height: 32), ...right]);
    return list([
      ...head,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 7, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
        const SizedBox(width: 40),
        Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
      ]),
    ]);
  }

  /// Song table: recordings of one song (same title and composer) are one
  /// row with "N bản thu"; the row plays the most relevant one.
  Widget _deskSongTable(List hits, {int max = 6}) {
    final order = <String>[];
    final byKey = <String, List<Map<String, dynamic>>>{};
    for (final h in hits.whereType<Map>()) {
      final k = '${h['_search_type']}|${_norm(h['title'])}|${_norm(h['composer'])}';
      byKey.putIfAbsent(k, () {
        order.add(k);
        return [];
      }).add(Map<String, dynamic>.from(h));
    }
    final rows = <Widget>[const _DeskTableHead()];
    for (final k in order.take(max)) {
      final g = byKey[k]!;
      final first = g.first;
      final open = _openRec.contains(k);
      final artists = <String>{for (final h in g) if ('${h['artist'] ?? ''}'.isNotEmpty && h['artist'] != 'Đang cập nhật') '${h['artist']}'};
      rows.add(_DeskSongRow(
        song: _hitSong(first),
        title: '${first['title'] ?? ''}',
        sub: artists.join(', '),
        composer: '${first['composer'] ?? ''}',
        views: g.fold<int>(0, (s, h) => s + ((h['views'] as num?)?.toInt() ?? 0)),
        recordings: g.length,
        open: open,
        onToggle: () => setState(() => open ? _openRec.remove(k) : _openRec.add(k)),
        onTap: () => _openHit(first),
      ));
      if (open && g.length > 1) {
        for (final h in g) {
          rows.add(_DeskSongRow(song: _hitSong(h), title: '${h['artist'] ?? 'Bản thu'}', sub: '', composer: '', views: (h['views'] as num?)?.toInt() ?? 0, nested: true, onTap: () => _openHit(h)));
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  List<Widget> _personSongsTable(Map<String, dynamic> p) {
    final songs = ((_personTop?['songs'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (songs.length <= 5) return const [];
    final route = '${_personRoute[_personTop?['type']] ?? '/nhac-si/'}${p['slug']}';
    return [
      _DeskTitle('Bài hát của ${p['title']}', action: 'Xem tất cả', onAction: () => context.push(route), top: 24),
      const _DeskTableHead(),
      for (var i = 5; i < songs.length; i++)
        _DeskSongRow(
          song: songs[i],
          title: '${songs[i]['title'] ?? ''}',
          sub: songByline(songs[i]),
          composer: _personTop?['type'] == 'composer' ? '${p['title']}' : '',
          views: (songs[i]['views'] as num?)?.toInt() ?? 0,
          onTap: () => playOrOpen(context, songs[i], songs, '${_personRole[_personTop?['type']] ?? ''} ${p['title']}'),
        ),
    ];
  }

  Widget _personCard(Map<String, dynamic> p) {
    final types = (p['types'] as List).cast<String>();
    final songs = (_personTop?['songs'] as List?)?.cast<Map<String, dynamic>>();
    final label = '${_personRole[_personTop?['type'] ?? types.first]} ${p['title']}';
    final route = '${_personRoute[types.first]}${p['slug']}';
    final life = [
      if (_personTop?['yob'] != null && '${_personTop?['yob']}' != '0') '${_personTop!['yob']}${_personTop?['yod'] != null && '${_personTop?['yod']}' != '0' ? ' – ${_personTop!['yod']}' : ''}',
      if (_personTop?['total'] != null) '${_personTop!['total']} bài trong kho',
    ].join(' · ');
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      NetImage(url: '${p['image'] ?? ''}'.isEmpty ? null : '${p['image']}', width: 132, height: 132, circle: true, tint: true, fallback: GeneratedCover(title: '${p['title']}', size: 132, radius: 66)),
      const SizedBox(height: 14),
      Text('KẾT QUẢ HÀNG ĐẦU', style: AppText.eyebrow),
      const SizedBox(height: 4),
      Text('${p['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 32, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.text))),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in types)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14)),
            child: Text(_personRole[t] ?? t, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textSecondary))),
          ),
      ]),
      if (life.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(life, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [
        if (songs != null && songs.isNotEmpty) PillButton(label: 'Phát toàn bộ', icon: Icons.play_arrow_rounded, height: 44, onTap: () => playOrOpen(context, songs.first, songs, label)),
        PillButton(label: 'Xem trang', height: 44, primary: false, onTap: () => context.push(route)),
      ]),
    ]);
    final top5 = songs == null
        ? Column(children: [for (var i = 0; i < 5; i++) const SkeletonSongRow()])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('NGHE NHIỀU NHẤT', style: body(TextStyle(fontSize: 13, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted))),
            const SizedBox(height: 4),
            for (var i = 0; i < songs.length && i < 5; i++)
              draggableSong(context, songs[i], InkWell(
                onTap: () => playOrOpen(context, songs[i], songs, label),
                onSecondaryTap: () => showSongActions(context, songs[i]),
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
                  child: Row(children: [
                    SizedBox(width: 28, child: Text('${i + 1}', style: display(TextStyle(fontSize: 17, fontWeight: FontWeight.w300, color: AppColors.textMuted)))),
                    SongCover(song: songs[i], size: 40, radius: 8),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${songs[i]['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text))),
                        Text(songByline(songs[i]), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                      ]),
                    ),
                    Text(formatViews((songs[i]['views'] as num?)?.toInt()), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                    const SizedBox(width: 8),
                  ]),
                ),
              )),
          ]);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 300, child: info),
          if (songs == null || songs.isNotEmpty) ...[const SizedBox(width: 28), Expanded(child: top5)],
        ]),
      ),
    );
  }

  Widget _lyricRow(Map<String, dynamic> h) {
    final snippet = '${h['lyric_snippet'] ?? ''}';
    final meta = [if ('${h['composer'] ?? ''}'.isNotEmpty) '${h['composer']}', if ('${h['artist'] ?? ''}'.isNotEmpty) '${h['artist']}'].join(' · ');
    return InkWell(
      onTap: () => _openHit(h),
      onSecondaryTap: () => showSongActions(context, _hitSong(h)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${h['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
              if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
              if (snippet.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text.rich(_highlight('…$snippet…', _query.trim()), maxLines: 3, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.45, fontStyle: FontStyle.italic, color: AppColors.textSecondary))),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          Icon(Icons.play_arrow_rounded, size: 26, color: AppColors.accentFg),
        ]),
      ),
    );
  }

  /// The typed words in bold inside a lyric line.
  TextSpan _highlight(String text, String q) {
    final words = q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    if (words.isEmpty) return TextSpan(text: text);
    final re = RegExp(words.map(RegExp.escape).join('|'), caseSensitive: false);
    final spans = <TextSpan>[];
    var at = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(TextSpan(text: m.group(0), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.text)));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(children: spans);
  }

  /// A person, document, topic or member: picture, name, what it is.
  Widget _deskMini(Map<String, dynamic> h) {
    final t = h['_search_type']?.toString();
    final types = (h['types'] as List?)?.cast<String>();
    final person = types != null || _personTypes.contains(t) || t == 'user';
    const docKinds = {'news': 'Tư liệu bài viết', 'image': 'Ảnh tư liệu', 'video': 'Video tư liệu', 'audio': 'Tư liệu âm thanh'};
    final sub = types != null
        ? types.map((x) => _personRole[x]).join(' · ')
        : t == 'document'
            ? (docKinds[h['type']] ?? 'Tư liệu')
            : _typeLabel(t);
    final image = '${h['image'] ?? ''}';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => types != null ? context.push('${_personRoute[types.first]}${h['slug']}') : _openHit(h),
      child: SizedBox(
        height: 60,
        child: Row(children: [
          NetImage(url: image.isEmpty ? null : image, width: 44, height: 44, circle: person, radius: person ? 0 : 8, tint: person, fallback: GeneratedCover(title: '${h['title'] ?? ''}', size: 44, radius: person ? 22 : 8)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${h['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text))),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ]),
      ),
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
    if (t == 'tag') return 'Chủ đề';
    final found = _filterOptions.firstWhere((o) => o.$1 == t, orElse: () => ('', '', null));
    return found.$2.isNotEmpty ? found.$2 : (t ?? '');
  }

  Widget _buildResults() {
    if (_loading && _groups.isEmpty) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_groups.isEmpty && _searchFailed) {
      return ListView(children: [OfflineBlock(onRetry: () => _runSearch(_query.trim()))]);
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
                children: [for (final kw in _trending.take(8)) BrandChip(label: kw['name']?.toString() ?? '', onTap: () => _useKeyword(kw['name']?.toString() ?? ''))],
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

    Widget groupBlock(Map g) {
      final hits = (g['hits'] as List? ?? []);
      final type = g['type']?.toString();
      final label = _typeLabel(type);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 0, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentLight, letterSpacing: 1.2)),
                  ),
                ),
                if (_filter == 'all' && type != null && type.isNotEmpty)
                  InkWell(
                    onTap: () => _setFilter(type),
                    borderRadius: BorderRadius.circular(8),
                    // 48pt target; the text itself is small.
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('Xem tất cả', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accentLight))),
                          Icon(Icons.chevron_right, size: 18, color: AppColors.accentLight),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...hits.map((h) => _HitRow(hit: Map<String, dynamic>.from(h as Map), onTap: () => _openHit(Map<String, dynamic>.from(h)), iconFor: _typeIcon, isSongLike: _isSongLike)),
        ],
      );
    }

    // Desktop, "Tất cả": what matched the lyrics gets its own column beside
    // the title matches (people remember a line, not the name).
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final lyricGroup = wide && _filter == 'all' ? displayGroups.cast<Map>().where((g) => g['type'] == 'lyric').firstOrNull : null;
    final mainGroups = lyricGroup == null ? displayGroups.cast<Map>().toList() : displayGroups.cast<Map>().where((g) => g['type'] != 'lyric').toList();
    final left = ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      itemCount: mainGroups.length + (topHit != null ? 2 : 1), // +1 result count, +1 if topHit
      itemBuilder: (ctx, idx) {
        if (idx == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text('Tìm thấy $totalHits kết quả', style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary))),
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
        return groupBlock(mainGroups[idx - (topHit != null ? 2 : 1)]);
      },
    );
    if (lyricGroup == null) return left;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 6, child: left),
      VerticalDivider(width: 1, color: AppColors.borderSubtle),
      Expanded(
        flex: 5,
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 40), children: [
          Text('KHỚP LỜI BÀI HÁT · ${(lyricGroup['hits'] as List).length}', style: AppText.eyebrow),
          const SizedBox(height: 4),
          Text('Những bài có câu hát giống chữ bạn gõ', style: body(TextStyle(fontSize: 14, color: AppColors.textMuted))),
          const SizedBox(height: 8),
          ...((lyricGroup['hits'] as List).map((h) => _HitRow(hit: Map<String, dynamic>.from(h as Map), onTap: () => _openHit(Map<String, dynamic>.from(h)), iconFor: _typeIcon, isSongLike: _isSongLike))),
          if (_filter == 'all')
            Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => _setFilter('lyric'), child: Text('Xem tất cả bài khớp lời', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg))))),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------ Desktop parts

class _DeskChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  final IconData? trailing;
  const _DeskChip({required this.label, this.on = false, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      height: 38,
      padding: EdgeInsets.only(left: 16, right: trailing != null ? 10 : 16),
      decoration: BoxDecoration(color: on ? AppColors.text : AppColors.surface, borderRadius: BorderRadius.circular(19)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: on ? AppColors.bg : AppColors.text))),
        if (trailing != null) Icon(trailing, size: 20, color: on ? AppColors.bg : AppColors.text),
      ]),
    );
    if (onTap == null) return chip;
    return InkWell(borderRadius: BorderRadius.circular(19), onTap: onTap, child: chip);
  }
}

class _DeskTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final double top;
  const _DeskTitle(this.title, {this.action, this.onAction, this.top = 32});
  _DeskTitle withTop(double t) => _DeskTitle(title, action: action, onAction: onAction, top: t);

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top, bottom: 10),
        child: Row(children: [
          Expanded(child: Text(title, style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text)))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
        ]),
      );
}

class _DeskTableHead extends StatelessWidget {
  const _DeskTableHead();
  @override
  Widget build(BuildContext context) {
    final st = body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted));
    return Container(
      height: 34,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        const SizedBox(width: 62),
        Expanded(child: Text('BÀI HÁT · TRÌNH BÀY', style: st)),
        SizedBox(width: 170, child: Text('SÁNG TÁC', style: st)),
        SizedBox(width: 90, child: Text('LƯỢT NGHE', textAlign: TextAlign.right, style: st)),
        const SizedBox(width: 48),
      ]),
    );
  }
}

class _DeskSongRow extends StatelessWidget {
  final Map<String, dynamic> song;
  final String title;
  final String sub;
  final String composer;
  final int views;
  final int recordings;
  final bool open;
  final bool nested;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  const _DeskSongRow({required this.song, required this.title, required this.sub, required this.composer, required this.views, required this.onTap, this.recordings = 1, this.open = false, this.nested = false, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final size = nested ? 36.0 : 48.0;
    final badge = recordings > 1
        ? InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onToggle,
            child: Container(
              height: 24,
              padding: const EdgeInsets.only(left: 9, right: 4),
              decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('$recordings bản thu', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: AppColors.accentFg),
              ]),
            ),
          )
        : null;
    return draggableSong(context, song, InkWell(
      onTap: onTap,
      onSecondaryTap: () => showSongActions(context, song),
      child: Container(
        height: nested ? 52 : 66,
        padding: EdgeInsets.only(left: nested ? 62 : 0),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
        child: Row(children: [
          SongCover(song: song, size: size, radius: nested ? 8 : 10),
          const SizedBox(width: 14),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: nested ? 15 : 16, fontWeight: FontWeight.w800, color: AppColors.text))),
              if (badge != null || sub.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    if (badge != null) ...[badge, const SizedBox(width: 8)],
                    Expanded(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)))),
                  ]),
                ),
            ]),
          ),
          SizedBox(width: 170, child: Text(composer, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
          SizedBox(width: 90, child: Text(views > 0 ? formatViews(views) : '', textAlign: TextAlign.right, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)))),
          IconButton(tooltip: 'Tuỳ chọn', onPressed: () => showSongActions(context, song), icon: Icon(Icons.more_horiz_rounded, color: AppColors.textMuted)),
        ]),
      ),
    ));
  }
}

class _DeskTopSong extends StatelessWidget {
  final Map<String, dynamic> hit;
  final String typeLabel;
  final VoidCallback onPlay;
  final VoidCallback onQueue;
  const _DeskTopSong({required this.hit, required this.typeLabel, required this.onPlay, required this.onQueue});

  @override
  Widget build(BuildContext context) {
    final t = hit['_search_type']?.toString();
    final song = t == 'song' || t == 'folk' || t == 'instrumental' || t == 'poem' || t == 'karaoke';
    final image = '${hit['image'] ?? ''}';
    final title = '${hit['title'] ?? ''}';
    final views = (hit['views'] as num?)?.toInt() ?? 0;
    final meta = [
      if (song && '${hit['artist'] ?? ''}'.isNotEmpty) '${hit['artist']}',
      if (song && '${hit['composer'] ?? ''}'.isNotEmpty) 'Nhạc: ${hit['composer']}',
      if (views > 0) '${formatViews(views)} lượt nghe',
    ].join(' · ');
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            NetImage(url: image.isEmpty ? null : image, width: 112, height: 112, radius: 14, fallback: GeneratedCover(title: title, size: 112, radius: 14)),
            const SizedBox(width: 20),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('KẾT QUẢ HÀNG ĐẦU · ${typeLabel.toUpperCase()}', style: AppText.eyebrow),
                const SizedBox(height: 6),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 30, height: 1.15, letterSpacing: -0.6, fontWeight: FontWeight.w800, color: AppColors.text))),
                if (meta.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  PillButton(label: song ? 'Phát' : 'Mở', icon: song ? Icons.play_arrow_rounded : Icons.arrow_forward_rounded, height: 44, onTap: onPlay),
                  if (song) PillButton(label: 'Thêm vào danh sách phát', icon: Icons.queue_music_rounded, height: 44, primary: false, onTap: onQueue),
                ]),
              ]),
            ),
          ]),
        ),
      ),
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
  final double inset;
  const _RecentObjectRow({required this.obj, required this.typeLabel, required this.onTap, required this.onDelete, required this.iconFor, this.inset = 20});

  @override
  Widget build(BuildContext context) {
    final tn = obj['__typename']?.toString();
    final image = (obj['thumbnail']?['url'] ?? obj['avatar']?['url'])?.toString();
    final title = (obj['title'] ?? obj['name'] ?? '').toString();
    final isPerson = tn == 'Artist' || tn == 'Composer' || tn == 'Poet' || tn == 'Recomposer';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset, 6, 8, 6),
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
  final double inset;
  const _RecentRow({required this.keyword, required this.onTap, required this.onDelete, this.inset = 20});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(inset, 4, 8, 4),
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

/// Browse shortcuts under the empty search box: kinds, decades, community
/// playlists, popular topics, newest archive photos and the archive — an
/// empty search still leads somewhere.

const _plItemObj = '... on Song { id thumbnail { url } } ... on Folk { id thumbnail { url } } ... on Instrumental { id thumbnail { url } } ... on Poem { id thumbnail { url } }';

List<String> _plThumbs(Map p) => (((p['items']?['data']) ?? const []) as List)
    .whereType<Map>()
    .map((i) => i['object']?['thumbnail']?['url']?.toString())
    .whereType<String>()
    .toList();
class _BrowseBlocks extends StatefulWidget {
  /// Desktop: grids instead of rails, no decades (Dòng thời gian has them).
  final bool desktop;
  const _BrowseBlocks({this.desktop = false});
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
  List<Map<String, dynamic>> _playlists = [];
  /// "Tuyển tập": BQT's themed system playlists.
  List<Map<String, dynamic>> _collections = [];
  /// "Sự kiện": what runs now, what comes next, the two just gone.
  List<(SiteEvent, DateTime, _EventState)> _events = [];

  @override
  void initState() {
    super.initState();
    _fetchPlaylists();
    _fetchCollections();
    _fetchEvents();
    ApiClient.query(r'query { popularTags(limit: 12) { id name slug song_count sample_images } }').then((d) {
      if (!mounted) return;
      setState(() => _tags = ((d['popularTags'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
    }).catchError((_) {});
  }

  /// Public playlists worth showing: a real title, at least 10 songs, a cover.
  static List<Map<String, dynamic>> _goodPlaylists(dynamic data) => ((data ?? const []) as List)
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((p) => p['thumbnail']?['url'] != null || _plThumbs(p).isNotEmpty)
      .where((p) => ((p['items']?['paginatorInfo']?['total'] as num?) ?? 0) >= 10 && RegExp(r'[^\d\s]{3,}').hasMatch('${p['title'] ?? ''}'))
      .toList();

  /// "Tuyển tập": BQT's themed system playlists (Mùa xuân, Bác Hồ kính
  /// yêu…). Most new system playlists are one-song anniversary picks, so
  /// only the 10+ song ones, in a new order on every visit.
  Future<void> _fetchCollections() async {
    try {
      final d = await ApiClient.query('''query(\$w: WhereConditions) {
        playlists(first: 80, orderBy: [{column: "id", order: DESC}], where: \$w) {
          data { id slug title thumbnail { url } items(first: 4) { paginatorInfo { total } data { object { $_plItemObj } } } }
        }
      }''', {'w': {'AND': [{'column': 'is_public', 'value': '1'}, {'column': 'is_system', 'value': '1'}]}});
      final list = _goodPlaylists(d['playlists']?['data'])..shuffle();
      if (mounted) setState(() => _collections = list.take(12).toList());
    } catch (_) {}
  }

  Future<void> _fetchEvents() async {
    try {
      final all = await loadSiteEvents();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final running = [for (final e in all) if (e.runningOn(now)) (e, e.nextDate(now), _EventState.now)];
      final ahead = [for (final e in all) if (!e.runningOn(now)) (e, e.nextDate(now), _EventState.next)]..sort((a, b) => a.$2.compareTo(b.$2));
      final gone = [
        for (final e in all)
          if (!e.runningOn(now)) (e, DateTime(e.nextDate(now).year - 1, e.month, e.day), _EventState.past),
      ].where((x) => !x.$2.isBefore(today.subtract(const Duration(days: 90)))).toList()..sort((a, b) => b.$2.compareTo(a.$2));
      final list = [...running, ...ahead.take((6 - running.length - 2).clamp(2, 6)), ...gone.take(2)];
      if (mounted) setState(() => _events = list);
    } catch (_) {}
  }

  /// One tear-off sheet per event; a tap opens it on the Sự kiện page.
  Widget _eventCard((SiteEvent, DateTime, _EventState) x, double w) {
    final (e, date, state) = x;
    final (label, color) = switch (state) {
      _EventState.now => ('Đang diễn ra', const Color(0xFF2F8A5E)),
      _EventState.next => ('Sắp tới', AppColors.accentFg),
      _EventState.past => ('Đã qua', AppColors.textMuted),
    };
    return SizedBox(
      width: w,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/su-kien?id=${e.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _EventSheet(day: date.day, month: date.month, under: e.year != null ? 'Năm ${e.year}' : LunarDate.fromSolar(date).label, size: w, faded: state == _EventState.past),
          const SizedBox(height: 10),
          Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w800, color: AppColors.text))),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: label, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              if (e.songCount > 0) TextSpan(text: ' · ${e.songCount} bài'),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
          ),
        ]),
      ),
    );
  }

  /// "Playlist cộng đồng" (moved here from Trang chủ): members' own public
  /// playlists.
  Future<void> _fetchPlaylists() async {
    try {
      final d = await ApiClient.query('''query(\$w: WhereConditions) {
        playlists(first: 24, orderBy: [{column: "id", order: DESC}], where: \$w) {
          data { id slug title thumbnail { url } user { id username } items(first: 4) { paginatorInfo { total } data { object { $_plItemObj } } } }
        }
      }''', {'w': {'AND': [{'column': 'is_public', 'value': '1'}, {'column': 'is_system', 'value': '0'}]}});
      final list = _goodPlaylists(d['playlists']?['data']);
      if (mounted) setState(() => _playlists = list);
    } catch (_) {}
  }

  List<String> get _images => [
        for (final t in _tags)
          ...((t['sample_images'] is List) ? (t['sample_images'] as List).whereType<String>() : const <String>[]),
      ];

  static const _subKinds = [
    ('Nhạc thiếu nhi', '/tag/nhac-thieu-nhi', Icons.star_outline_rounded, Color(0xFF8B6914)),
    ('Nhạc nước ngoài', '/tag/nhac-nuoc-ngoai', Icons.public_rounded, Color(0xFF2D5E3A)),
    ('Nhạc nhẹ', '/tag/nhac-nhe', Icons.music_note_outlined, Color(0xFF6B5210)),
    ('Nhạc tiền chiến', '/tag/nhac-tien-chien', Icons.schedule_rounded, Color(0xFFA89060)),
    ('Nhạc phim', '/tag/nhac-phim', Icons.movie_outlined, Color(0xFF7A3B3A)),
    ('Video', '/bai-hat/video', Icons.play_arrow_rounded, Color(0xFF4A0D0D)),
    ('Thể loại dân ca', '/the-loai-dan-ca', Icons.layers_outlined, Color(0xFF8B6914)),
    ('Làn điệu dân ca', '/lan-dieu', Icons.headphones_outlined, Color(0xFFA89060)),
  ];

  Widget _kindTile(int i, List<String> imgs) => Material(
        color: _kinds[i].$3,
        borderRadius: BorderRadius.circular(widget.desktop ? 16 : 18),
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
              padding: EdgeInsets.all(widget.desktop ? 16 : 14),
              child: Text(_kinds[i].$1, style: display(TextStyle(fontSize: widget.desktop ? 18 : 17, fontWeight: FontWeight.w800, color: Colors.white))),
            ),
          ]),
        ),
      );

  /// Desktop playlist row: as many ~170px cards as fit, one line.
  Widget _cardRow(List<Map<String, dynamic>> list, {bool owner = false}) => LayoutBuilder(builder: (context, c) {
        final cols = ((c.maxWidth + 18) / 188).floor().clamp(4, 8);
        final w = (c.maxWidth - (cols - 1) * 18) / cols;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < cols && i < list.length; i++) ...[
            if (i > 0) const SizedBox(width: 18),
            SizedBox(
              width: w,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/playlist/${list[i]['id']}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox(width: w, height: w, child: _PlaylistCover(playlist: list[i]))),
                  const SizedBox(height: 8),
                  Text('${list[i]['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w800, color: AppColors.text))),
                  Text(
                    [
                      if (list[i]['items']?['paginatorInfo']?['total'] != null) '${list[i]['items']['paginatorInfo']['total']} bài',
                      if (owner && list[i]['user']?['username'] != null) '${list[i]['user']['username']}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  ),
                ]),
              ),
            ),
          ],
        ]);
      });

  static const _archive = [
    (Icons.photo_outlined, 'Ảnh tư liệu', '/tu-lieu/hinh-anh'),
    (Icons.videocam_outlined, 'Video tư liệu', '/tu-lieu/video'),
    (Icons.graphic_eq_rounded, 'Tư liệu âm thanh', '/tu-lieu/am-thanh'),
    (Icons.article_outlined, 'Tư liệu bài viết', '/tu-lieu/bai-viet'),
    (Icons.emoji_events_outlined, 'Bảng xếp hạng', '/bang-xep-hang'),
    (Icons.person_search_outlined, 'Nhạc sĩ', '/nhac-si'),
    (Icons.mic_none_rounded, 'Nghệ sĩ', '/nghe-si'),
    (Icons.edit_note_rounded, 'Soạn giả', '/soan-gia'),
    (Icons.menu_book_outlined, 'Nhà thơ', '/nha-tho'),
  ];

  Widget _desktop() {
    final imgs = _images;
    Widget title(String t, {String? action, VoidCallback? onAction}) => _DeskTitle(t, action: action, onAction: onAction, top: 40);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title('Thể loại'),
      GridView.count(
        crossAxisCount: 6,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        mainAxisExtent: 112,
        children: [for (var i = 0; i < _kinds.length; i++) _kindTile(i, imgs)],
      ),
      const SizedBox(height: 14),
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        mainAxisExtent: 56,
        children: [for (final k in _subKinds) _SubKindTile(label: k.$1, route: k.$2, icon: k.$3, color: k.$4)],
      ),
      if (_collections.isNotEmpty) ...[title('Tuyển tập', action: 'Xem tất cả', onAction: () => context.push('/playlist')), _cardRow(_collections)],
      if (_tags.isNotEmpty) ...[
        title('Chủ đề', action: 'Tất cả', onAction: () => context.push('/tag')),
        Wrap(spacing: 10, runSpacing: 10, children: [for (final t in _tags) BrandChip(label: '${t['name']}', onTap: () => context.push('/tag/${t['slug']}'))]),
      ],
      if (_events.isNotEmpty) ...[
        title('Sự kiện', action: 'Xem lịch sự kiện', onAction: () => context.push('/su-kien')),
        LayoutBuilder(builder: (context, c) {
          final cols = ((c.maxWidth + 18) / 188).floor().clamp(4, 8);
          final w = (c.maxWidth - (cols - 1) * 18) / cols;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < cols && i < _events.length; i++) ...[if (i > 0) const SizedBox(width: 18), _eventCard(_events[i], w)],
          ]);
        }),
      ],
      if (_playlists.isNotEmpty) ...[title('Playlist cộng đồng', action: 'Xem tất cả', onAction: () => context.push('/playlist')), _cardRow(_playlists, owner: true)],
      title('Kho tư liệu'),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        mainAxisExtent: 72,
        children: [
          for (final (icon, label, route) in _archive)
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push(route),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, size: 22, color: AppColors.accentFg),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Text(label, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text)))),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  ]),
                ),
              ),
            ),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.desktop) return _desktop();
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
        // Smaller kinds under the big tiles, coloured as on the web's Thư viện page.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 56,
            children: [for (final k in _subKinds) _SubKindTile(label: k.$1, route: k.$2, icon: k.$3, color: k.$4)],
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
            // "40s": short labels, more of them on one line.
            itemBuilder: (_, i) => BrandChip(label: '${_decades[i] % 100 == 0 ? '00' : _decades[i] % 100}s', onTap: () => context.push('/bai-hat/thap-nien/${_decades[i]}')),
          ),
        ),
        if (_collections.isNotEmpty) ...[
          SectionTitle('Tuyển tập', onAction: () => context.push('/playlist')),
          Rail(
            height: 226,
            count: _collections.length,
            builder: (_, i) {
              final p = _collections[i];
              final total = p['items']?['paginatorInfo']?['total'];
              return RailCard(
                cover: _PlaylistCover(playlist: p),
                title: p['title']?.toString() ?? '',
                subtitle: total != null ? '$total bài' : null,
                onTap: () => context.push('/playlist/${p['id']}'),
              );
            },
          ),
        ],
        if (_tags.isNotEmpty) ...[
          SectionTitle('Chủ đề', action: 'Tất cả', onAction: () => context.push('/tag')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final t in _tags) BrandChip(label: '${t['name']}', onTap: () => context.push('/tag/${t['slug']}'))],
            ),
          ),
        ],
        const NewDocumentsRail(),
        if (_events.isNotEmpty) ...[
          SectionTitle('Sự kiện', action: 'Xem lịch', onAction: () => context.push('/su-kien')),
          Rail(height: 246, count: _events.length, builder: (_, i) => Padding(padding: const EdgeInsets.only(top: 6), child: _eventCard(_events[i], 148))),
        ],
        // Below "Tư liệu mới": shown, not tucked into a list, so it gets taps.
        if (_playlists.isNotEmpty) ...[
          SectionTitle('Playlist cộng đồng', onAction: () => context.push('/playlist')),
          Rail(
            height: 226,
            count: _playlists.length,
            builder: (_, i) {
              final p = _playlists[i];
              final total = p['items']?['paginatorInfo']?['total'];
              return RailCard(
                cover: _PlaylistCover(playlist: p),
                title: p['title']?.toString() ?? '',
                subtitle: [if (total != null) '$total bài', if (p['user']?['username'] != null) p['user']['username']].join(' · '),
                onTap: () => context.push('/playlist/${p['id']}'),
              );
            },
          ),
        ],
        SectionTitle('Kho tư liệu', action: null),
        ListItem(icon: Icons.photo_outlined, title: 'Ảnh tư liệu', onTap: () => context.push('/tu-lieu/hinh-anh')),
        ListItem(icon: Icons.videocam_outlined, title: 'Video tư liệu', onTap: () => context.push('/tu-lieu/video')),
        ListItem(icon: Icons.graphic_eq_rounded, title: 'Tư liệu âm thanh', onTap: () => context.push('/tu-lieu/am-thanh')),
        ListItem(icon: Icons.article_outlined, title: 'Tư liệu bài viết', onTap: () => context.push('/tu-lieu/bai-viet')),
        ListItem(icon: Icons.emoji_events_outlined, title: 'Bảng xếp hạng', onTap: () => context.push('/bang-xep-hang')),
        ListItem(icon: Icons.person_search_outlined, title: 'Nhạc sĩ', onTap: () => context.push('/nhac-si')),
        ListItem(icon: Icons.mic_none_rounded, title: 'Nghệ sĩ', onTap: () => context.push('/nghe-si')),
        ListItem(icon: Icons.edit_note_rounded, title: 'Soạn giả', onTap: () => context.push('/soan-gia')),
        ListItem(icon: Icons.menu_book_outlined, title: 'Nhà thơ', onTap: () => context.push('/nha-tho')),
        // The rail above already links there; keep a way in if it didn't load.
        if (_playlists.isEmpty) ListItem(icon: Icons.queue_music_rounded, title: 'Playlist cộng đồng', onTap: () => context.push('/playlist')),
      ],
    );
  }
}

enum _EventState { now, next, past }

/// A tear-off calendar sheet like Trang chủ's: two rings, the month on a
/// wine band, the day large, and under it the year it happened (or, for a
/// feast with no year, its lunar date).
class _EventSheet extends StatelessWidget {
  final int day, month;
  final String under;
  final double size;
  final bool faded;
  const _EventSheet({required this.day, required this.month, required this.under, required this.size, this.faded = false});

  @override
  Widget build(BuildContext context) {
    final r = size > 150 ? 14.0 : 12.0;
    Widget ring() => Container(width: 8, height: 14, decoration: BoxDecoration(color: const Color(0xFF4A2A2A), borderRadius: BorderRadius.circular(4)));
    return Opacity(
      opacity: faded ? 0.55 : 1,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.isLight ? Colors.white : AppColors.surface,
                borderRadius: BorderRadius.circular(r),
                border: Border.all(color: AppColors.isLight ? const Color(0xFFEFE6E4) : AppColors.border),
                boxShadow: [BoxShadow(color: const Color(0xFF3C1414).withValues(alpha: AppColors.isLight ? 0.12 : 0.4), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: Column(children: [
                Container(
                  height: size * 0.24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFF6E1B17), borderRadius: BorderRadius.vertical(top: Radius.circular(r - 1))),
                  child: Text('THÁNG $month', style: body(TextStyle(fontSize: size > 150 ? 13 : 12, letterSpacing: 1, fontWeight: FontWeight.w800, color: Colors.white))),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('$day', style: display(TextStyle(fontSize: size * 0.42, height: 1, letterSpacing: -2, fontWeight: FontWeight.w800, color: AppColors.text))),
                      const SizedBox(height: 6),
                      FittedBox(fit: BoxFit.scaleDown, child: Text(under, maxLines: 1, style: body(TextStyle(fontSize: size > 150 ? 13 : 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)))),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          Positioned(top: -6, left: size * 0.28 - 4, child: ring()),
          Positioned(top: -6, right: size * 0.28 - 4, child: ring()),
        ]),
      ),
    );
  }
}

class _PlaylistCover extends StatelessWidget {
  final Map<String, dynamic> playlist;
  const _PlaylistCover({required this.playlist});
  @override
  Widget build(BuildContext context) {
    final own = playlist['thumbnail']?['url']?.toString();
    final t = _plThumbs(playlist);
    if (t.length < 4) return NetImage(url: own ?? t.first);
    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [for (final u in t.take(4)) NetImage(url: u)],
    );
  }
}

/// One of the smaller kinds under Thể loại: colour, icon, name on one line.
class _SubKindTile extends StatelessWidget {
  final String label;
  final String route;
  final IconData icon;
  final Color color;
  const _SubKindTile({required this.label, required this.route, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)], begin: Alignment.centerLeft, end: Alignment.centerRight),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12 * AppColors.shadowMul), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 10),
            child: Row(children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 8),
              // Long names shrink a little instead of losing letters.
              Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(label, maxLines: 1, style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))))),
            ]),
          ),
        ),
      ),
    );
  }
}
