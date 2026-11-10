import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/lunar.dart';
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


  Future<void> _fetchLatest(int i) async {
    final (_, q) = _cats[i];
    if (_latest[q] != null) return;
    final people = q == 'karaokes' ? 'users(first: 3) { data { id slug: username title: username } }' : 'artists(first: 3) { data { id slug title } }';
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
                // Hôm nay: today's event playlists, if any.
                const _TodayEvents(),
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
  Widget _row(Map<String, dynamic> s, List<Map<String, dynamic>> list, int i, String label, {Widget? lead, Widget? trail, String? sub}) => draggableSong(context, s, InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _play(list, label, i),
        onSecondaryTap: () => showSongActions(context, s),
        child: Container(
          height: 64,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
          child: Row(children: [
            ?lead,
            SongCover(song: s, size: 46, radius: 10),
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
  Widget _latestBlock() {
    final list = _latest[_cats[_cat].$2];
    if (list == null) return _skeletonRows();
    if (list.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Chưa tải được, thử lại sau.', style: AppText.bodyText));
    final label = 'Mới cập nhật · ${_cats[_cat].$1}';
    Widget col(int from) => Column(children: [
          for (var i = from; i < list.length && i < from + 4; i++)
            _row(list[i], list, i, label, sub: [songByline(list[i]), _postedAgo(list[i]['created_at']?.toString())].where((x) => x.isNotEmpty).join(' · ')),
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

/// "Hôm nay": the event playlists running today (event_start ≤ today ≤
/// event_end, set in the playlist's settings) as a tear-off calendar page —
/// canvas "Desktop · Trang chủ — khối Sự kiện B". Several at once: the
/// pages stack and chips / ‹ › / ←→ flip between them; never on its own.
/// Nothing running → nothing shown.
class _TodayEvents extends StatefulWidget {
  const _TodayEvents();
  @override
  State<_TodayEvents> createState() => _TodayEventsState();
}

class _TodayEventsState extends State<_TodayEvents> {
  List<Map<String, dynamic>> _events = [];
  final Map<String, List<Map<String, dynamic>>> _songs = {};
  int _at = 0;
  bool _hover = false;

  static String _mmdd(DateTime d) => '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _load();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (!_hover || _events.length < 2 || e is! KeyDownEvent || typingInField()) return false;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft && _at > 0) { _go(_at - 1); return true; }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight && _at < _events.length - 1) { _go(_at + 1); return true; }
    return false;
  }

  Future<void> _load() async {
    final today = _mmdd(DateTime.now());
    try {
      final d = await ApiClient.query(r'''query($w: WhereConditions) { playlists(first: 20, orderBy: [{column: "id", order: DESC}], where: $w) { data { id title description excerpt event_start event_end event_date items(first: 1) { paginatorInfo { total } } } } }''', {
        'w': {'AND': [
          {'column': 'is_system', 'value': '1'},
          {'column': 'is_public', 'value': '1'},
          {'column': 'event_start', 'operator': 'LTE', 'value': today},
          {'column': 'event_end', 'operator': 'GTE', 'value': today},
        ]},
      });
      int total(Map p) => ((p['items']?['paginatorInfo']?['total'] as num?) ?? 0).toInt();
      bool oneDay(Map p) => p['event_start'] == p['event_end'];
      final list = _maps(d['playlists']?['data']).where((p) => total(p) > 0).toList()
        // One-day events first, then the longer ones; within each, more songs first.
        ..sort((a, b) => oneDay(a) != oneDay(b) ? (oneDay(a) ? -1 : 1) : total(b).compareTo(total(a)));
      if (!mounted || list.isEmpty) return;
      setState(() => _events = list);
      _fetchSongs(list.first);
    } catch (_) {}
  }

  Future<void> _fetchSongs(Map<String, dynamic> pl) async {
    final id = '${pl['id']}';
    if (_songs.containsKey(id)) return;
    try {
      // items, not songs: playlist.songs comes back empty for some event playlists.
      final d = await ApiClient.query('query(\$id: ID!) { playlist(id: \$id) { items(first: 12, orderBy: [{column: "position", order: ASC}]) { data { object { ... on Song { $_songFields } } } } } }', {'id': id});
      final songs = [for (final it in _maps(d['playlist']?['items']?['data'])) if (it['object'] is Map && (it['object'] as Map).isNotEmpty) Map<String, dynamic>.from(it['object'] as Map)]
          .where(_playable).map((s) => {...s, 'file_type': 'song'}).toList();
      if (mounted) setState(() => _songs[id] = songs);
    } catch (_) {}
  }

  void _go(int i) {
    setState(() => _at = i);
    _fetchSongs(_events[i]);
  }

  String _plain(dynamic html) => '${html ?? ''}'.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty) return const SizedBox.shrink();
    final ev = _events[_at];
    final id = '${ev['id']}';
    final songs = _songs[id] ?? const <Map<String, dynamic>>[];
    final title = '${ev['title'] ?? ''}';
    final date = DateTime.tryParse('${ev['event_date'] ?? ''}');
    final parts = '${ev['event_start'] ?? ''}'.split('-');
    final day = date?.day ?? int.tryParse(parts.last) ?? DateTime.now().day;
    final month = date?.month ?? int.tryParse(parts.first) ?? DateTime.now().month;
    final today = _mmdd(DateTime.now());
    final onDay = date != null && _mmdd(date) == today;
    final ago = date != null ? DateTime.now().year - date.year : 0;
    final end = '${ev['event_end'] ?? ''}'.split('-');
    final eyebrow = onDay && ago > 0
        ? '$ago NĂM TRƯỚC, NGÀY NÀY'
        : ev['event_start'] != ev['event_end'] && end.length == 2 ? 'ĐẾN ${end[1]}/${end[0]}' : 'HÔM NAY';
    final desc = _plain(ev['excerpt']).isNotEmpty ? _plain(ev['excerpt']) : _plain(ev['description']);
    final many = _events.length > 1;
    Widget circle(IconData icon, VoidCallback? onTap) => Material(
          color: AppColors.surface,
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 22, color: onTap == null ? AppColors.textMuted.withValues(alpha: 0.45) : AppColors.text))),
        );
    return MouseRegion(
      onEnter: (_) => _hover = true,
      onExit: (_) => _hover = false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(top: 36, bottom: 14),
          child: Row(children: [
            Text('Hôm nay', style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text))),
            const Spacer(),
            if (many) ...[
              Text('${_at + 1} / ${_events.length}', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textMuted))),
              const SizedBox(width: 10),
              circle(Icons.chevron_left_rounded, _at > 0 ? () => _go(_at - 1) : null),
              const SizedBox(width: 8),
              circle(Icons.chevron_right_rounded, _at < _events.length - 1 ? () => _go(_at + 1) : null),
            ] else
              TextButton(onPressed: () => context.push('/playlist/$id'), child: Text('Mở playlist', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            _Calendar(day: day, month: month, year: date?.year, behind: (_events.length - 1).clamp(0, 2)),
            const SizedBox(width: 28),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(eyebrow, style: body(TextStyle(fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
                const SizedBox(height: 6),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 28, height: 1.15, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: AppColors.text))),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.5, color: AppColors.textSecondary))),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  PillButton(label: songs.length > 1 ? 'Phát tất cả' : 'Phát', icon: Icons.play_arrow_rounded, height: 44, onTap: songs.isEmpty ? null : () => playOrOpen(context, songs.first, songs, title)),
                  const SizedBox(width: 10),
                  Material(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => context.push('/playlist/$id'),
                      child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 18), alignment: Alignment.center, child: Text('Xem playlist', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)))),
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 20),
            // Song cards: as many as the playlist has, up to three.
            for (var i = 0; i < songs.length && i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              SizedBox(
                width: 150,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => playOrOpen(context, songs[i], songs, title),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SongCover(song: songs[i], size: 150, radius: 12),
                    const SizedBox(height: 8),
                    Text('${songs[i]['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, height: 1.25, fontWeight: FontWeight.w800, color: AppColors.text))),
                    Text(songByline(songs[i]), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                  ]),
                ),
              ),
            ],
          ]),
        ),
        if (many)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < _events.length && i < 5; i++) _chip(i),
              if (_events.length > 5)
                PopupMenuButton<int>(
                  tooltip: '',
                  onSelected: _go,
                  itemBuilder: (_) => [for (var i = 5; i < _events.length; i++) PopupMenuItem(value: i, child: Text('${_events[i]['title'] ?? ''}'))],
                  child: _chipBody(false, null, '+${_events.length - 5}', null),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _chip(int i) {
    final e = _events[i];
    final y = DateTime.tryParse('${e['event_date'] ?? ''}')?.year;
    final n = ((e['items']?['paginatorInfo']?['total'] as num?) ?? 0).toInt();
    return InkWell(borderRadius: BorderRadius.circular(20), onTap: () => _go(i), child: _chipBody(i == _at, y, '${e['title'] ?? ''}', '$n bài'));
  }

  Widget _chipBody(bool on, int? year, String title, String? count) => Container(
        height: 40,
        constraints: const BoxConstraints(maxWidth: 380),
        padding: EdgeInsets.only(left: year != null ? 6 : 14, right: 14),
        decoration: BoxDecoration(color: on ? AppColors.text : AppColors.surface, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (year != null) ...[
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: on ? AppColors.wine : AppColors.bg, borderRadius: BorderRadius.circular(14)),
              child: Text('$year', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: on ? Colors.white : AppColors.accentFg))),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: on ? AppColors.bg : AppColors.text)))),
          if (count != null) Text(' · $count', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: (on ? AppColors.bg : AppColors.text).withValues(alpha: 0.7)))),
        ]),
      );
}

/// A tear-off calendar page; [behind] more pages peek out when several
/// events fall on the same day.
class _Calendar extends StatelessWidget {
  final int day, month;
  final int? year;
  final int behind;
  const _Calendar({required this.day, required this.month, this.year, this.behind = 0});

  Widget _page({bool face = true}) => Container(
        width: 150,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 22, offset: const Offset(0, 8))]),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(color: AppColors.wine, height: 34, alignment: Alignment.center, child: Text('THÁNG $month', style: body(const TextStyle(fontSize: 14, letterSpacing: 1, fontWeight: FontWeight.w800, color: Colors.white)))),
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(face ? day.toString().padLeft(2, '0') : '', style: display(const TextStyle(fontSize: 72, height: 1, letterSpacing: -2, fontWeight: FontWeight.w800, color: Color(0xFF161112))))),
          Padding(padding: const EdgeInsets.fromLTRB(0, 4, 0, 14), child: Text(face && year != null ? 'năm $year' : ' ', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF665C5E))))),
        ]),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150 + behind * 8.0,
        child: Stack(clipBehavior: Clip.none, children: [
          for (var k = behind; k > 0; k--)
            Positioned(
              left: 0, top: 0,
              child: Transform.translate(
                offset: Offset(6.0 * k, -6.0 * k),
                child: Transform.rotate(angle: 0.044 * k, child: Opacity(opacity: 1 - 0.25 * k, child: _page(face: false))),
              ),
            ),
          _page(),
        ]),
      );
}
