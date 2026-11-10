import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/lunar.dart';
import '../services/occasions.dart';
import '../widgets/anniversary_rail.dart';
import '../widgets/auth_dialogs.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';

// Trang chủ desktop (canvas "Desktop · Trang chủ"): Lời chào + Phát nhanh ·
// Gợi ý ngày lễ (only near one) · Của bạn (Nghe tiếp | Mới thích | Nghe đi
// nghe lại) · Nghe nhiều hôm nay | Đang nghe cùng bạn · Kỷ niệm tuần này ·
// Mới cập nhật · Câu chuyện bài hát · Có thể bạn thích · Nhạc sĩ tiêu biểu ·
// Nghệ sĩ tiêu biểu. Guests get a login invite in place of "Của bạn".
// Showcase rows stay always visible; only what the member picks has tabs.

const _songFields = 'id slug title subtitle views created_at play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id slug title } } sheet { year composers(first: 2) { data { id slug title } } }';
const _personal = 'id title slug play_type thumbnail { url } file { audio_url video_url } artists(first: 2) { data { id title slug } }';

const _mainQuery = '''query DesktopHomeMain {
  stickySongs(first: 30) { data { $_songFields } }
  featuredComments(limit: 6) { id snippet likes username user_avatar song_id song_title song_image audio_url video_url play_type file_type }
}''';
const _liveQuery = '''query DesktopHomeLive {
  nowListening(limit: 8) { listeners song { $_songFields } }
  topSongsToday(limit: 8) { $_songFields }
}''';
const _peopleQuery = '''query HomePeople {
  topComposersToday(limit: 12) { id slug title avatar { url } }
  topArtistsToday(limit: 12) { id slug title avatar { url } }
}''';

const _cats = [
  ('Tân nhạc', 'songs'),
  ('Dân ca', 'folks'),
  ('Khí nhạc', 'instrumentals'),
  ('Tiếng thơ', 'poems'),
  ('Thành viên hát', 'karaokes'),
];
const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
const _tn = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem'};

List<Map<String, dynamic>> _maps(dynamic list) => ((list ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
bool _playable(Map s) => s['file']?['audio_url'] != null || s['file']?['video_url'] != null;
String _key(Map s) => '${s['file_type'] ?? 'song'}-${s['id']}';

String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 11) return 'Chào buổi sáng';
  if (h < 14) return 'Chào buổi trưa';
  if (h < 18) return 'Chào buổi chiều';
  return 'Chào buổi tối';
}

String _postedAgo(String? createdAt) {
  final at = DateTime.tryParse((createdAt ?? '').replaceFirst(' ', 'T'));
  if (at == null) return '';
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return 'Hôm nay';
  if (days == 1) return 'Hôm qua';
  if (days < 7) return '$days ngày trước';
  return timeago(createdAt);
}

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});
  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  List<Map<String, dynamic>> _sticky = [], _comments = [], _top = [], _live = [], _composers = [], _artists = [];
  List<Map<String, dynamic>> _recent = [], _loved = [], _again = [], _forYou = [];
  List<Anniv> _anniv = [];
  Occasion? _occasion;
  String? _occasionId;
  List<Map<String, dynamic>> _occasionSongs = [];
  int? _topDecade;
  Map<String, dynamic>? _topComposer;
  String? _personalFor;
  bool _loading = true;
  /// 0 Nghe tiếp · 1 Mới thích · 2 Nghe đi nghe lại (remembered).
  int _yours = 0;
  int _cat = 0;
  final Map<String, List<Map<String, dynamic>>> _latest = {};
  String? _starting;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _fetchLatest(0);
    loadAnniversaries(window: 7).then((a) {
      if (mounted) setState(() => _anniv = a.take(6).toList());
    });
    _fetchOccasion(nextOccasion(DateTime.now()));
    SharedPreferences.getInstance().then((p) {
      final v = p.getInt('desktop_home_yours');
      if (v != null && mounted) setState(() => _yours = v.clamp(0, 2));
    });
    _liveTimer = Timer.periodic(const Duration(minutes: 2), (_) => _fetchLive());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final uid = auth.user?['id']?.toString();
    if (!auth.loading && uid != _personalFor) {
      _personalFor = uid;
      _recent = []; _loved = []; _again = []; _forYou = []; _topDecade = null; _topComposer = null;
      if (uid != null) _fetchPersonal(auth, uid);
    }
  }

  Future<void> _fetch() async {
    await Future.wait([
      ApiClient.query(_mainQuery).then((d) {
        if (!mounted) return;
        setState(() {
          _sticky = _maps(d['stickySongs']?['data']).map((s) => {...s, 'file_type': 'song'}).where(_playable).toList();
          _comments = _maps(d['featuredComments']).where((c) => '${c['snippet'] ?? ''}'.trim().isNotEmpty).take(2).toList();
        });
      }).catchError((_) {}),
      ApiClient.query(_peopleQuery).then((d) {
        bool photo(Map p) => (p['avatar']?['url']?.toString() ?? '').isNotEmpty;
        if (mounted) setState(() { _composers = _maps(d['topComposersToday']).where(photo).toList(); _artists = _maps(d['topArtistsToday']).where(photo).toList(); });
      }).catchError((_) {}),
      _fetchLive(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchLive() async {
    try {
      final d = await ApiClient.query(_liveQuery);
      if (!mounted) return;
      setState(() {
        _live = _maps(d['nowListening']).where((x) => x['song'] is Map).map((x) => {...Map<String, dynamic>.from(x['song'] as Map), 'file_type': 'song', 'listeners': x['listeners']}).toList();
        _top = _maps(d['topSongsToday']).map((s) => {...s, 'file_type': 'song'}).toList();
      });
    } catch (_) {}
  }

  List<Map<String, dynamic>> _objects(dynamic data) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final e in _maps(data)) {
      if (e['object'] is! Map) continue;
      final m = Map<String, dynamic>.from(e['object']);
      m['file_type'] = _tn[m['__typename']] ?? 'song';
      if (e['total'] != null) m['plays'] = e['total'];
      if (_playable(m) && seen.add(_key(m))) out.add(m);
    }
    return out;
  }

  void _fetchPersonal(AuthProvider auth, String uid) {
    const objs = '__typename ... on Song { $_personal } ... on Folk { $_personal } ... on Instrumental { $_personal } ... on Poem { $_personal }';
    auth.authedQuery('''query(\$id: ID!) { user(id: \$id) {
      recentListens(first: 30, page: 1, orderBy: [{column: "id", order: DESC}]) { data { object { $objs } } }
      loves(first: 30, page: 1, orderBy: [{column: "id", order: DESC}]) { data { object { $objs } } }
    } }''', {'id': uid}).then((d) {
      if (mounted && _personalFor == uid) setState(() { _recent = _objects(d['user']?['recentListens']?['data']); _loved = _objects(d['user']?['loves']?['data']); });
    }).catchError((_) {});
    ApiClient.query('query(\$w: WhereConditions) { mostListens(first: 20, where: \$w, orderBy: [{column: "total", order: DESC}]) { data { total object { $objs } } } }', {'w': {'column': 'user_id', 'value': uid}}).then((d) {
      if (mounted && _personalFor == uid) setState(() => _again = _objects(d['mostListens']?['data']).where((s) => ((s['plays'] as num?) ?? 0) >= 3).toList());
    }).catchError((_) {});
    auth.authedQuery(r'''query($id: ID) { recommendedSongs(user_id: $id, limit: 30) { id title slug image audio_url video_url play_type file_type artists { id title slug } } }''', {'id': uid}).then((d) {
      final out = <Map<String, dynamic>>[];
      for (final m in _maps(d['recommendedSongs'])) {
        if ((m['audio_url'] == null && m['video_url'] == null) || '${m['image'] ?? ''}'.isEmpty) continue;
        out.add({
          'id': m['id'], 'title': m['title'], 'slug': m['slug'], 'thumbnail': {'url': m['image']},
          'file': {'audio_url': m['audio_url'], 'video_url': m['video_url']}, 'play_type': m['play_type'],
          'file_type': const {'audio': 'song', 'video': 'song'}[m['file_type']] ?? m['file_type'] ?? 'song',
          'artists': {'data': m['artists'] ?? []},
        });
      }
      if (mounted && _personalFor == uid) setState(() => _forYou = out);
    }).catchError((_) {});
    auth.authedQuery('query { myListeningProfile { top_decade top_composers { id slug title } } }').then((d) {
      final p = d['myListeningProfile'];
      if (!mounted || _personalFor != uid || p is! Map) return;
      setState(() {
        _topDecade = (p['top_decade'] as num?)?.toInt();
        final c = _maps(p['top_composers']);
        _topComposer = c.isEmpty ? null : c.first;
      });
    }).catchError((_) {});
  }

  Future<void> _fetchOccasion(Occasion? o) async {
    if (o == null) return;
    final mmdd = '${o.month.toString().padLeft(2, '0')}-${o.day.toString().padLeft(2, '0')}';
    try {
      final ev = await ApiClient.query(r'''query($w: WhereConditions) { playlists(first: 1, orderBy: [{column: "id", order: DESC}], where: $w) { data { id } } }''', {
        'w': {'AND': [
          {'column': 'is_system', 'value': '1'},
          {'column': 'is_public', 'value': '1'},
          {'column': 'event_start', 'operator': 'LTE', 'value': mmdd},
          {'column': 'event_end', 'operator': 'GTE', 'value': mmdd},
        ]},
      });
      final id = (ev['playlists']?['data'] as List?)?.firstOrNull?['id']?.toString() ?? kOccasionPlaylist[o.label]?.toString();
      if (id == null) return;
      final d = await ApiClient.query('query(\$id: ID!) { playlist(id: \$id) { songs(first: 30) { data { $_songFields } } } }', {'id': id});
      final songs = _maps(d['playlist']?['songs']?['data']).where((s) => s['thumbnail']?['url'] != null && _playable(s)).map((s) => {...s, 'file_type': 'song'}).toList();
      if (mounted && songs.isNotEmpty) setState(() { _occasion = o; _occasionId = id; _occasionSongs = songs; });
    } catch (_) {}
  }

  Future<void> _fetchLatest(int i) async {
    final (_, q) = _cats[i];
    if (_latest[q] != null) return;
    final people = q == 'karaokes' ? 'users(first: 3) { data { id slug: username title: username avatar { url } } }' : 'artists(first: 3) { data { id slug title avatar { url } } }${q == 'songs' ? ' sheet { composers(first: 1) { data { avatar { url } } } }' : ''}';
    try {
      final d = await ApiClient.query('query { $q(first: 8, orderBy: [{column: "id", order: DESC}]) { data { id slug title subtitle views created_at play_type thumbnail { url } file { audio_url video_url duration } $people } } }');
      if (!mounted) return;
      setState(() => _latest[q] = _maps(d[q]?['data']).map((s) {
            if (q == 'karaokes' && s['users'] != null) s['artists'] = s['users'];
            s['file_type'] = q.substring(0, q.length - 1);
            return s;
          }).toList());
    } catch (_) {
      if (mounted) setState(() => _latest[q] = []);
    }
  }

  void _play(List<Map<String, dynamic>> list, String label, [int at = 0]) {
    if (list.isEmpty) return;
    playOrOpen(context, list[at], list, label);
  }

  /// Phát nhanh: fetch a list, then play it.
  Future<void> _quick(String key, String label, Future<List<Map<String, dynamic>>> Function() load) async {
    if (_starting != null) return;
    setState(() => _starting = key);
    try {
      final list = await load();
      if (mounted) _play(list, label);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _starting = null);
    }
  }

  Future<List<Map<String, dynamic>>> _songsWhere(Map<String, dynamic>? where) async {
    final d = await ApiClient.query('query(\$w: WhereConditions) { songs(first: 40, random: true, where: \$w) { data { $_songFields } } }', {'w': where});
    return _maps(d['songs']?['data']).map((s) => {...s, 'file_type': 'song'}).where(_playable).toList();
  }

  Future<List<Map<String, dynamic>>> _decadeSongs(int decade) => _songsWhere({'AND': [
        {'column': 'year', 'operator': 'GTE', 'value': '$decade'},
        {'column': 'year', 'operator': 'LT', 'value': '${decade + 10}'},
        {'column': 'views', 'operator': 'GT', 'value': 1000},
      ]});

  Future<List<Map<String, dynamic>>> _composerSongs(String slug) async {
    final d = await ApiClient.query('query(\$s: String!) { composer(slug: \$s) { songs(first: 40, orderBy: [{column: "views", order: DESC}]) { data { $_songFields } } } }', {'s': slug});
    final l = _maps(d['composer']?['songs']?['data']).map((s) => {...s, 'file_type': 'song'}).where(_playable).toList()..shuffle();
    return l;
  }

  Future<void> _playAnniv(Anniv a) async {
    setState(() => _starting = 'anniv-${a.person['slug']}');
    final songs = await annivSongs(a);
    if (!mounted) return;
    setState(() => _starting = null);
    songs.isEmpty ? context.push('${a.route}${a.person['slug']}') : _play(songs, '${a.role} ${a.person['title'] ?? ''}');
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final authed = context.select<AuthProvider, bool>((a) => a.isAuthenticated);
    final name = context.select<AuthProvider, String?>((a) => a.user?['username']?.toString());
    final now = DateTime.now();
    // Each song once on the page: rails further down skip what is above.
    final yoursList = [_recent, _loved, _again][_yours];
    final seen = <String>{for (final s in [...yoursList, ..._top, ..._live]) _key(s)};
    final forYou = [for (final s in _forYou) if (seen.add(_key(s))) s];
    return Material(
      color: AppColors.bg,
      child: LayoutBuilder(builder: (context, c) {
        final pad = c.maxWidth < 900 ? 28.0 : 40.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 28, pad, 56),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(authed ? '${_greeting(now)}${name != null ? ', $name' : ''}' : 'Chào bạn', style: display(TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: AppColors.text))),
                const SizedBox(height: 6),
                Text('${_weekdays[now.weekday - 1]}, ${now.day}/${now.month} · ${LunarDate.fromSolar(now).label} âm lịch', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                const SizedBox(height: 18),
                _quickRow(authed),
                if (_occasion != null) ...[
                  _head('Gợi ý cho ${_occasion!.day}/${_occasion!.month}', top: 36, action: 'Mở playlist', onAction: () => context.push('/playlist/$_occasionId')),
                  _occasionBlock(),
                ],
                ..._yoursBlock(authed),
                const SizedBox(height: 44),
                LayoutBuilder(builder: (context, cc) {
                  final top = _section('Nghe nhiều hôm nay', _loading && _top.isEmpty ? _skeletonRows() : _rankList(), action: 'Xem tất cả', onAction: () => context.push('/bang-xep-hang'));
                  final live = _section('Đang nghe cùng bạn', _liveList(), dot: true);
                  if (cc.maxWidth < 760) return Column(children: [top, const SizedBox(height: 40), live]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 7, child: top), const SizedBox(width: 40), Expanded(flex: 5, child: live)]);
                }),
                if (_anniv.isNotEmpty) ...[_head('Kỷ niệm tuần này'), _annivGrid()],
                _head('Mới cập nhật', tabs: [for (final (l, _) in _cats) l], tab: _cat, onTab: (i) { setState(() => _cat = i); _fetchLatest(i); }, action: 'Xem tất cả', onAction: () => context.push('/the-loai/${const ['tan-nhac', 'dan-ca', 'khi-nhac', 'tieng-tho', 'thanh-vien-hat'][_cat]}')),
                _latestBlock(),
                if (_comments.isNotEmpty) ...[_head('Câu chuyện bài hát', action: 'Xem thêm', onAction: () => context.go('/cong-dong')), _stories()],
                if (authed && forYou.isNotEmpty) ...[_head('Có thể bạn thích'), _cards(forYou, 'Có thể bạn thích')],
                if (_composers.isNotEmpty) ...[_head('Nhạc sĩ tiêu biểu', action: 'Xem tất cả', onAction: () => context.push('/nhac-si')), _people(_composers, '/nhac-si/')],
                if (_artists.isNotEmpty) ...[_head('Nghệ sĩ tiêu biểu', action: 'Xem tất cả', onAction: () => context.push('/nghe-si')), _people(_artists, '/nghe-si/')],
              ]),
            ),
          ),
        );
      }),
    );
  }

  /// Title row: optional tabs right after the title, action at the end.
  Widget _head(String title, {double top = 44, String? action, VoidCallback? onAction, List<String>? tabs, int tab = 0, ValueChanged<int>? onTab, bool dot = false}) => Padding(
        padding: EdgeInsets.only(top: top, bottom: 14),
        child: Row(children: [
          if (dot) ...[
            Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFFC62828), shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFC62828).withValues(alpha: 0.18), spreadRadius: 4)])),
            const SizedBox(width: 12),
          ],
          Text(title, style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text))),
          if (tabs != null) ...[
            const SizedBox(width: 18),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var i = 0; i < tabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Material(
                        color: i == tab ? AppColors.text : AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => onTab?.call(i),
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            child: Text(tabs[i], style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: i == tab ? AppColors.bg : AppColors.textSecondary))),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ] else
            const Spacer(),
          if (action != null) TextButton(onPressed: onAction, child: Text(action, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
        ]),
      );

  Widget _section(String title, Widget child, {String? action, VoidCallback? onAction, bool dot = false}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _head(title, top: 0, action: action, onAction: onAction, dot: dot),
        child,
      ]);

  // ---------- Phát nhanh ----------
  Widget _quickRow(bool authed) {
    final items = <(String, IconData, String, VoidCallback)>[
      ('random', Icons.shuffle_rounded, 'Ngẫu nhiên kho nhạc', () => _quick('random', 'Ngẫu nhiên kho nhạc', () => _songsWhere({'column': 'views', 'operator': 'GT', 'value': 2000}))),
      if (authed && _topDecade != null)
        ('decade', Icons.play_arrow_rounded, 'Thập niên ${_topDecade! % 100} · bạn hay nghe', () => _quick('decade', 'Thập niên $_topDecade', () => _decadeSongs(_topDecade!))),
      if (authed && _topComposer != null)
        ('composer', Icons.play_arrow_rounded, 'Theo ${_topComposer!['title']}', () => _quick('composer', 'Nhạc sĩ ${_topComposer!['title']}', () => _composerSongs('${_topComposer!['slug']}'))),
      if (_sticky.isNotEmpty) ('sticky', Icons.play_arrow_rounded, 'Hôm qua nghe nhiều', () => _play(_sticky, 'Hôm qua nghe nhiều')),
      if (!authed) ('d70', Icons.play_arrow_rounded, 'Thập niên 70', () => _quick('d70', 'Thập niên 70', () => _decadeSongs(1970))),
    ];
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final (k, icon, label, onTap) in items)
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 18, 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: AppColors.wine, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: _starting == k
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : Icon(icon, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text(label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text))),
              ]),
            ),
          ),
        ),
    ]);
  }

  // ---------- Gợi ý ngày lễ ----------
  Widget _occasionBlock() {
    final o = _occasion!;
    final songs = _occasionSongs;
    final band = [for (var i = 0; i < songs.length; i++) if (i == 0 || i > 4) songs[i]].take(4).toList();
    final when = o.days == 0 ? 'HÔM NAY' : 'CÒN ${o.days} NGÀY';
    return SizedBox(
      height: 240,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          flex: 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(fit: StackFit.expand, children: [
              Container(color: const Color(0xFF2E080A)),
              // Four songs' pictures, like the playlist covers in lists — not
              // the four already shown in the tiles beside it.
              if (band.length >= 4)
                Column(children: [
                  for (final r in [0, 2])
                    Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final i in [r, r + 1]) Expanded(child: NetImage(url: band[i]['thumbnail']?['url']?.toString(), tint: true)),
                    ])),
                ])
              else
                NetImage(url: songs.first['thumbnail']?['url']?.toString(), tint: true),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xE62E080A), Color(0x332E080A)]))),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('$when · PLAYLIST NGÀY LỄ', style: body(const TextStyle(fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w800, color: Color(0xFFF6E8DE)))),
                  const SizedBox(height: 6),
                  Text('${o.label} ${o.day}/${o.month}', maxLines: 2, style: display(const TextStyle(fontSize: 30, height: 1.1, letterSpacing: -0.6, fontWeight: FontWeight.w800, color: Colors.white))),
                  const SizedBox(height: 4),
                  Text('${songs.length} bài', style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xD9FFFFFF)))),
                  const SizedBox(height: 14),
                  Row(children: [
                    _bandButton('Phát tất cả', Icons.play_arrow_rounded, () => _play(songs, o.label)),
                    const SizedBox(width: 10),
                    _bandButton('Xem playlist', null, () => context.push('/playlist/$_occasionId'), ghost: true),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 4,
          child: Column(children: [
            for (var r = 0; r < 2; r++) ...[
              if (r == 1) const SizedBox(height: 14),
              Expanded(
                child: Row(children: [
                  for (var k = 0; k < 2; k++) ...[
                    if (k == 1) const SizedBox(width: 14),
                    Expanded(child: songs.length > 1 + r * 2 + k ? _tile(songs, 1 + r * 2 + k, o.label) : const SizedBox.shrink()),
                  ],
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _tile(List<Map<String, dynamic>> list, int i, String label) => Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        color: AppColors.surfaceLight,
        child: InkWell(
          onTap: () => _play(list, label, i),
          child: Stack(fit: StackFit.expand, children: [
            NetImage(url: list[i]['thumbnail']?['url']?.toString()),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.4, 1], colors: [Color(0x002E080A), Color(0xD92E080A)]))),
            Positioned(left: 12, right: 12, bottom: 10, child: Text('${list[i]['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 14, height: 1.25, fontWeight: FontWeight.w800, color: Colors.white)))),
          ]),
        ),
      );

  Widget _bandButton(String label, IconData? icon, VoidCallback onTap, {bool ghost = false}) => Material(
        color: ghost ? Colors.white.withValues(alpha: 0.16) : AppColors.wine,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 22, color: Colors.white), const SizedBox(width: 6)],
              Text(label, style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white))),
            ]),
          ),
        ),
      );

  // ---------- Của bạn ----------
  List<Widget> _yoursBlock(bool authed) {
    if (!authed) {
      return [
        _head('Của bạn'),
        Container(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            Container(width: 64, height: 64, decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle), child: Icon(Icons.favorite_rounded, size: 30, color: AppColors.accentFg)),
            const SizedBox(width: 22),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Đăng nhập để nghe tiếp bài đang dở', style: body(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
                const SizedBox(height: 4),
                Text('Lưu bài yêu thích, tạo playlist, nhận gợi ý theo gu nghe của bạn. Nghe nhạc thì không cần đăng nhập.', style: body(TextStyle(fontSize: 15, height: 1.5, color: AppColors.textSecondary))),
              ]),
            ),
            const SizedBox(width: 16),
            PillButton(label: 'Đăng nhập', height: 48, onTap: () => showDialog(context: context, useRootNavigator: true, builder: (_) => const LoginDialog())),
            const SizedBox(width: 10),
            PillButton(label: 'Đăng ký', height: 48, primary: false, onTap: () => showDialog(context: context, useRootNavigator: true, builder: (_) => const RegisterDialog())),
          ]),
        ),
      ];
    }
    final lists = [_recent, _loved, _again];
    final labels = ['Nghe gần đây', 'Yêu thích', 'Nghe đi nghe lại'];
    final routes = ['/nghe-gan-day', '/yeu-thich', '/thong-ke'];
    final list = lists[_yours];
    return [
      _head('Của bạn',
          tabs: const ['Nghe tiếp', 'Mới thích', 'Nghe đi nghe lại'],
          tab: _yours,
          onTab: (i) {
            setState(() => _yours = i);
            SharedPreferences.getInstance().then((p) => p.setInt('desktop_home_yours', i));
          },
          action: 'Xem tất cả',
          onAction: () => context.push(routes[_yours])),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(const ['Bài bạn nghe sẽ hiện ở đây để nghe tiếp.', 'Thả tim một bài để giữ nó ở đây.', 'Bài bạn nghe từ 3 lần trở lên sẽ hiện ở đây.'][_yours], style: AppText.bodyText),
        )
      else
        _cards(list, labels[_yours], badge: (s) => _yours == 1 ? _heartBadge() : (_yours == 2 && s['plays'] != null ? _textBadge('${s['plays']} lần') : null)),
    ];
  }

  Widget _heartBadge() => Container(
        width: 28, height: 28,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), shape: BoxShape.circle),
        child: Icon(Icons.favorite_rounded, size: 16, color: AppColors.accentLight),
      );
  Widget _textBadge(String t) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(13)),
        child: Text(t, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF161112)))),
      );

  /// One row of song cards: ~160px each, more columns on wider windows.
  Widget _cards(List<Map<String, dynamic>> list, String label, {Widget? Function(Map<String, dynamic>)? badge}) => LayoutBuilder(builder: (context, c) {
        final cols = ((c.maxWidth + 18) / 178).floor().clamp(4, 9);
        final w = (c.maxWidth - (cols - 1) * 18) / cols;
        final shown = list.take(cols).toList();
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 18),
            SizedBox(
              width: w,
              child: draggableSong(context, shown[i], InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _play(list, label, i),
                onSecondaryTap: () => showSongActions(context, shown[i]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Stack(children: [
                    SongCover(song: shown[i], size: w, radius: 16),
                    if (badge?.call(shown[i]) case final b?) Positioned(right: 8, top: 8, child: b),
                  ]),
                  const SizedBox(height: 8),
                  Text('${shown[i]['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w800, color: AppColors.text))),
                  Text(songByline(shown[i]), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                ]),
              )),
            ),
          ],
        ]);
      });

  // ---------- Lists ----------
  Widget _row(Map<String, dynamic> s, List<Map<String, dynamic>> list, int i, String label, {Widget? lead, Widget? trail, String? sub, String? stand}) => draggableSong(context, s, InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _play(list, label, i),
        onSecondaryTap: () => showSongActions(context, s),
        child: Container(
          height: 64,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
          child: Row(children: [
            ?lead,
            stand != null
                ? NetImage(url: stand, width: 46, height: 46, radius: 10, tint: true, fallback: SongCover(song: s, size: 46, radius: 10))
                : SongCover(song: s, size: 46, radius: 10),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
                Text(sub ?? songByline(s, withComposer: true), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
              ]),
            ),
            ?trail,
            // Rows with a badge ("● 3 người") keep it alone; right-click still opens the menu.
            if (trail == null) IconButton(tooltip: 'Tuỳ chọn', onPressed: () => showSongActions(context, s), icon: Icon(Icons.more_horiz_rounded, color: AppColors.textMuted)),
          ]),
        ),
      ));

  Widget _rankList() => Column(children: [
        for (var i = 0; i < _top.length && i < 7; i++)
          _row(_top[i], _top, i, 'Nghe nhiều hôm nay',
              lead: SizedBox(width: 46, child: Text('${i + 1}', textAlign: TextAlign.center, style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w300, color: i < 3 ? AppColors.accentFg : AppColors.textMuted))))),
      ]);

  Widget _liveList() => Column(children: [
        for (var i = 0; i < _live.length && i < 7; i++)
          _row(_live[i], _live, i, 'Mọi người đang nghe',
              trail: ((_live[i]['listeners'] as num?) ?? 0) > 0
                  ? Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(14)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFC62828), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('${_live[i]['listeners']} người', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
                      ]),
                    )
                  : null),
        if (_live.isEmpty && !_loading) Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Chưa có ai đang nghe lúc này.', style: AppText.bodyText)),
      ]);

  Widget _skeletonRows() => Column(children: [for (var i = 0; i < 6; i++) const SkeletonSongRow()]);

  // ---------- Kỷ niệm ----------
  Widget _annivGrid() => LayoutBuilder(builder: (context, c) {
        const cols = 3;
        final w = (c.maxWidth - (cols - 1) * 16) / cols;
        return Wrap(spacing: 16, runSpacing: 16, children: [
          for (final a in _anniv.take(6))
            SizedBox(
              width: w,
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.push('${a.route}${a.person['slug']}'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(children: [
                      NetImage(url: a.person['avatar']?['url']?.toString(), width: 60, height: 60, circle: true, tint: true),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(annivWhen(a).toUpperCase(), style: body(TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: AppColors.textMuted))),
                          Text('${a.person['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text))),
                          Text(annivYears(a), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        ]),
                      ),
                      IconButton.filled(
                        tooltip: 'Nghe các bài của ${a.person['title'] ?? ''}',
                        style: IconButton.styleFrom(backgroundColor: AppColors.wine, fixedSize: const Size(44, 44)),
                        onPressed: () => _playAnniv(a),
                        icon: _starting == 'anniv-${a.person['slug']}'
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                            : const Icon(Icons.play_arrow_rounded, color: Colors.white),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]);
      });

  // ---------- Mới cập nhật ----------
  /// A new song often has no picture yet: its singer's, else its composer's.
  String? _standIn(Map s) {
    final own = s['thumbnail']?['url']?.toString();
    if (own != null && own.isNotEmpty) return null;
    for (final p in [...((s['artists']?['data'] ?? const []) as List), ...((s['sheet']?['composers']?['data'] ?? const []) as List)]) {
      final u = (p as Map?)?['avatar']?['url']?.toString();
      if (u != null && u.isNotEmpty) return u;
    }
    return null;
  }

  Widget _latestBlock() {
    final list = _latest[_cats[_cat].$2];
    if (list == null) return _skeletonRows();
    if (list.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Chưa tải được, thử lại sau.', style: AppText.bodyText));
    final label = 'Mới cập nhật · ${_cats[_cat].$1}';
    Widget col(int from) => Column(children: [
          for (var i = from; i < list.length && i < from + 4; i++)
            _row(list[i], list, i, label, sub: [songByline(list[i]), _postedAgo(list[i]['created_at']?.toString())].where((x) => x.isNotEmpty).join(' · '), stand: _standIn(list[i])),
        ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: col(0)), const SizedBox(width: 36), Expanded(child: col(4))]);
  }

  // ---------- Câu chuyện bài hát ----------
  Widget _stories() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < _comments.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(child: _story(_comments[i])),
        ],
      ]);

  Widget _story(Map<String, dynamic> c) {
    final song = <String, dynamic>{
      'id': c['song_id'], 'title': c['song_title'],
      if (c['song_image'] != null) 'thumbnail': {'url': c['song_image']},
      'file': {'audio_url': c['audio_url'], 'video_url': c['video_url']},
      'play_type': c['play_type'], 'file_type': c['file_type'] ?? 'song',
    };
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/song/${c['song_id']}', extra: song),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.format_quote_rounded, size: 34, color: AppColors.rose),
            const SizedBox(height: 8),
            Text('${c['snippet'] ?? ''}'.trim(), maxLines: 3, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, height: 1.6, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500, color: AppColors.text))),
            const SizedBox(height: 16),
            Row(children: [
              UserAvatar(url: c['user_avatar']?.toString(), name: '${c['username'] ?? ''}', size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c['username'] ?? ''}', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text))),
                  Text.rich(TextSpan(children: [const TextSpan(text: 'về bài '), TextSpan(text: '${c['song_title'] ?? ''}', style: TextStyle(color: AppColors.accentFg, fontWeight: FontWeight.w700))]),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                ]),
              ),
              if (_playable(song)) PillButton(label: 'Nghe bài', icon: Icons.play_arrow_rounded, height: 44, onTap: () => playOrOpen(context, song, [song], 'Câu chuyện bài hát')),
            ]),
          ]),
        ),
      ),
    );
  }

  // ---------- Người tiêu biểu ----------
  Widget _people(List<Map<String, dynamic>> list, String route) => LayoutBuilder(builder: (context, c) {
        final cols = ((c.maxWidth + 16) / 136).floor().clamp(5, 10);
        final w = (c.maxWidth - (cols - 1) * 16) / cols;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < cols && i < list.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            SizedBox(width: w, child: _Person(person: list[i], size: w, onTap: () => context.push('$route${list[i]['slug']}'))),
          ],
        ]);
      });
}

/// A round portrait: on hover a wine ring hugs the picture and the name
/// turns wine — no square plate behind a round photo.
class _Person extends StatefulWidget {
  final Map<String, dynamic> person;
  final double size;
  final VoidCallback onTap;
  const _Person({required this.person, required this.size, required this.onTap});
  @override
  State<_Person> createState() => _PersonState();
}

class _PersonState extends State<_Person> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final w = widget.size;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _hover ? AppColors.accentFg : Colors.transparent, width: 2)),
            child: NetImage(url: widget.person['avatar']?['url']?.toString(), width: w - 10, height: w - 10, circle: true, tint: true),
          ),
          const SizedBox(height: 6),
          Text('${widget.person['title'] ?? ''}', maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w800, color: _hover ? AppColors.accentFg : AppColors.text))),
        ]),
      ),
    );
  }
}
