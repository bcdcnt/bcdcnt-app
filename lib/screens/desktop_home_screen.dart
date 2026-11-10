import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import 'comments_screen.dart' show CommentTile;
import '../services/lunar.dart';
import '../widgets/anniversary_rail.dart';
import '../widgets/auth_dialogs.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';

// Trang chủ desktop (canvas "Desktop · Trang chủ"): Lời chào + Phát nhanh ·
// Gợi ý ngày lễ (only near one) · Của bạn (Nghe tiếp | Mới thích | Nghe đi
// nghe lại) · Nghe nhiều hôm nay · Kỷ niệm tuần này ·
// Mới cập nhật · Câu chuyện bài hát · Có thể bạn thích · Nhạc sĩ tiêu biểu ·
// Nghệ sĩ tiêu biểu. Guests get a login invite in place of "Của bạn".
// Showcase rows stay always visible; only what the member picks has tabs.

const _songFields = 'id slug title subtitle views created_at play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id slug title } } sheet { year composers(first: 2) { data { id slug title } } }';
const _personal = 'id title slug play_type thumbnail { url } file { audio_url video_url } artists(first: 2) { data { id title slug } }';


const _topQuery = '''query DesktopHomeTop {
  topSongsToday(limit: 8) { $_songFields }
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
  List<Map<String, dynamic>> _comments = [], _top = [];
  List<Map<String, dynamic>>? _docs;
  /// Việc của CTV: queue → count (zeros left out).
  Map<String, int> _ctv = {};
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
  Timer? _topTimer;

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
    _topTimer = Timer.periodic(const Duration(minutes: 10), (_) => _fetchTop());
  }

  @override
  void dispose() {
    _topTimer?.cancel();
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
      _fetchComments(),
      _fetchCtv(),
      _fetchTop(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchTop() async {
    try {
      final d = await ApiClient.query(_topQuery);
      if (!mounted) return;
      setState(() => _top = _maps(d['topSongsToday']).map((s) => {...s, 'file_type': 'song'}).toList());
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

  /// ~30 instrumentals (≈ 2 hours) to listen to in the background: no
  /// ceremonial music or marches, instruments taking turns so it never runs
  /// five guitar pieces in a row.
  Future<List<Map<String, dynamic>>> _instrumentalMix() async {
    final d = await ApiClient.query('query(\$w: WhereConditions) { instrumentals(first: 100, random: true, where: \$w) { data { $_songFields } } }', {'w': {'column': 'views', 'operator': 'GT', 'value': 300}});
    final ceremony = RegExp(r'nghi lễ|quân nhạc|kèn đồng', caseSensitive: false);
    final march = RegExp(r'hành khúc|tiến quân|quốc ca|chiêu hồn|mặc niệm|nhạc hiệu|quân kỳ', caseSensitive: false);
    final kinds = {
      'guitar': RegExp(r'guitar|ghi-ta|ghita', caseSensitive: false),
      'bau': RegExp(r'đàn bầu', caseSensitive: false),
      'sao': RegExp(r'sáo|flute', caseSensitive: false),
      'day': RegExp(r'vĩ cầm|violin|piano|dương cầm|đàn tranh|nhị|cello', caseSensitive: false),
    };
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final s in _maps(d['instrumentals']?['data'])) {
      final s2 = {...s, 'file_type': 'instrumental'};
      final who = songByline(s2);
      if (!_playable(s2) || ceremony.hasMatch(who) || march.hasMatch('${s['title'] ?? ''}')) continue;
      final k = kinds.keys.firstWhere((k) => kinds[k]!.hasMatch(who), orElse: () => 'other');
      groups.putIfAbsent(k, () => []).add(s2);
    }
    // Round-robin over the instruments, fullest first, so they alternate.
    final lists = groups.values.toList()..sort((a, b) => b.length.compareTo(a.length));
    final out = <Map<String, dynamic>>[];
    for (var i = 0; out.length < 30 && lists.any((l) => i < l.length); i++) {
      for (final l in lists) {
        if (i < l.length && out.length < 30) out.add(l[i]);
      }
    }
    return out;
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
    final seen = <String>{for (final s in [...yoursList, ..._top]) _key(s)};
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
                LayoutBuilder(builder: (context, cc) => _section('Nghe nhiều hôm nay', _loading && _top.isEmpty ? _skeletonRows() : _rankGrid(cc.maxWidth >= 760), action: 'Xem tất cả', onAction: () => context.push('/bang-xep-hang'))),
                if (_anniv.isNotEmpty) ...[_head('Kỷ niệm tuần này'), _annivGrid()],
                // What is still missing in the catalogue, by the newest songs.
                if (_ctv.isNotEmpty) _ctvStrip(),
                _head('Mới cập nhật', tabs: [for (final (l, _) in _cats) l, 'Tư liệu'], tab: _cat, onTab: (i) { setState(() => _cat = i); i < _cats.length ? _fetchLatest(i) : _fetchDocs(); }, action: 'Xem tất cả', onAction: () => context.push(_cat < _cats.length ? '/the-loai/${const ['tan-nhac', 'dan-ca', 'khi-nhac', 'tieng-tho', 'thanh-vien-hat'][_cat]}' : '/tu-lieu')),
                _cat < _cats.length ? _latestBlock() : _docsBlock(),
                if (_comments.isNotEmpty) ...[_head('Bình luận mới', action: 'Xem tất cả', onAction: () => context.push('/binh-luan')), _newComments()],
                if (authed && forYou.isNotEmpty) ...[_head('Có thể bạn thích', action: 'Làm mới', onAction: () => setState(() => _forYou.shuffle())), _cards(forYou, 'Có thể bạn thích')],
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
          if (action != null)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onAction,
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(action, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
            ),
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
        ('decade', Icons.play_arrow_rounded, 'Thập niên ${_topDecade! % 100}', () => _quick('decade', 'Thập niên $_topDecade', () => _decadeSongs(_topDecade!))),
      if (authed && _topComposer != null)
        ('composer', Icons.play_arrow_rounded, 'Theo ${_topComposer!['title']}', () => _quick('composer', 'Nhạc sĩ ${_topComposer!['title']}', () => _composerSongs('${_topComposer!['slug']}'))),
      // About two hours of music without words, for listening while working.
      ('instr', Icons.music_note_rounded, 'Nhạc không lời', () => _quick('instr', 'Nhạc không lời', _instrumentalMix)),
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
        final cols = ((c.maxWidth + 18) / 162).floor().clamp(4, 9);
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

  /// Full-width "Nghe nhiều hôm nay": eight songs in two columns.
  Widget _rankGrid(bool wide) {
    String sub(Map<String, dynamic> s) {
      final a = songByline(s);
      if (a.isNotEmpty) return a;
      final c = songByline({'sheet': s['sheet']}, withComposer: true);
      return c.isEmpty ? '' : 'Nhạc: $c';
    }
    Widget r(int i) => _row(_top[i], _top, i, 'Nghe nhiều hôm nay', sub: sub(_top[i]),
        lead: SizedBox(width: 46, child: Text('${i + 1}', textAlign: TextAlign.center, style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w300, color: i < 3 ? AppColors.accentFg : AppColors.textMuted)))));
    final n = _top.length.clamp(0, 8);
    if (!wide) return Column(children: [for (var i = 0; i < n; i++) r(i)]);
    final half = (n + 1) ~/ 2;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(children: [for (var i = 0; i < half; i++) r(i)])),
      const SizedBox(width: 40),
      Expanded(child: Column(children: [for (var i = half; i < n; i++) r(i)])),
    ]);
  }

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

  // ---------- Nhờ bạn giúp sức ----------
  /// Pictures, tags, lyrics still missing across the whole catalogue — shown
  /// to everyone to invite help; same totals as the Bàn làm việc queues.
  Future<void> _fetchCtv() async {
    try {
      final d = await ApiClient.query('''query {
        no_image: songs(first: 1, where: {column: "image_id", operator: IS_NULL}) { paginatorInfo { total } }
        no_tag: sheets(first: 1, untagged: true) { paginatorInfo { total } }
        no_lyric: songs(first: 1, where: {OR: [{column: "content", operator: IS_NULL}, {column: "content", value: ""}]}) { paginatorInfo { total } }
      }''');
      int n(String k) => (d[k]?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0;
      if (mounted) setState(() => _ctv = {for (final k in ['no_image', 'no_tag', 'no_lyric']) if (n(k) > 0) k: n(k)});
    } catch (_) {}
  }

  /// A zero hides its item, all zero hides the strip. Each item opens its queue.
  Widget _ctvStrip() {
    const labels = {'no_image': 'bài chờ ảnh minh hoạ', 'no_tag': 'bản nhạc chờ gắn tag', 'no_lyric': 'bài chờ lời'};
    return Container(
      margin: const EdgeInsets.only(top: 44),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.isLight ? const Color(0xFFFBF3F3) : AppColors.accentSoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.isLight ? const Color(0xFFEBD3D3) : AppColors.accentSoft),
      ),
      child: LayoutBuilder(builder: (context, box) {
      final link = TextButton(onPressed: () => context.push('/ban-lam-viec'), child: Text('Mở Bàn làm việc ›', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentFg))));
      final items = <Widget>[
        Text('NHỜ BẠN GIÚP SỨC', style: body(TextStyle(fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
        for (final e in _ctv.entries) ...[
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push('/ban-lam-viec?q=${e.key}&s=new'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 28),
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.wine, borderRadius: BorderRadius.circular(12)),
                  child: Text(formatInt(e.value), style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white))),
                ),
                const SizedBox(width: 8),
                Text(labels[e.key]!, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text))),
              ]),
            ),
          ),
        ],
      ];
      // Wide: one line, the link on the right edge. Narrow: wraps instead of overflowing.
      if (box.maxWidth >= 1000) return Row(children: [for (final w in items) ...[w, const SizedBox(width: 18)], const Spacer(), link]);
      return Wrap(spacing: 18, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [...items, link]);
      }),
    );
  }

  // ---------- Bình luận mới ----------
  Future<void> _fetchComments() async {
    try {
      final d = await ApiClient.query('''query { latestComments(first: 40, orderBy: [{column: "created_at", order: DESC}]) { data { id content likes created_at is_request user { id username avatar { url } } object { __typename ... on Song { id title slug thumbnail { url } file { audio_url video_url } } ... on Folk { id title slug thumbnail { url } file { audio_url } } ... on Instrumental { id title slug thumbnail { url } file { audio_url } } ... on Poem { id title slug thumbnail { url } file { audio_url } } } } } }''');
      final seen = <String>{};
      final out = <Map<String, dynamic>>[];
      for (final c in _maps(d['latestComments']?['data'])) {
        final who = '${c['user']?['id'] ?? ''}';
        final obj = c['object'];
        if (who.isEmpty || obj is! Map || obj['title'] == null) continue;
        final raw = '${c['content'] ?? ''}';
        // Lyrics pasted as a comment (numbered verses, many short lines) are not a story.
        final lines = raw.split(RegExp(r'<br\s*/?>|</p>|\n', caseSensitive: false)).map((l) => l.replaceAll(RegExp(r'<[^>]*>'), '').trim()).where((l) => l.isNotEmpty).toList();
        final lyricLike = RegExp(r'^\s*(\d+|đk|điệp khúc)\s*[-.:)]', caseSensitive: false).hasMatch(lines.isEmpty ? '' : lines.first) || (lines.length >= 4 && lines.every((l) => l.length < 60));
        final text = _sentences(raw);
        if (lyricLike || text.length < 30 || !seen.add(who)) continue;
        out.add({...c, 'text': text});
        if (out.length == 4) break;
      }
      if (mounted) setState(() => _comments = out);
    } catch (_) {}
  }

  /// Plain text cut at a sentence end (≤ ~220 chars), never mid-word.
  static String _sentences(String html) {
    final t = html.replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), ' ').replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= 220) return t;
    final cut = t.substring(0, 220);
    final end = cut.lastIndexOf(RegExp(r'[.!?…](\s|$)'));
    if (end > 60) return cut.substring(0, end + 1);
    return '${cut.substring(0, cut.lastIndexOf(' '))}…';
  }

  /// Same tiles as Cộng đồng › Bình luận mới, two columns.
  Widget _newComments() {
    void open(Map<String, dynamic> obj, {String? commentId}) {
      final kind = const {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem'}['${obj['__typename']}'] ?? 'song';
      // From a comment: land on the song's comments, that comment lit up.
      context.push(commentId != null ? '/$kind/${obj['id']}?binh-luan=1' : '/$kind/${obj['id']}', extra: {...obj, 'file_type': kind, 'highlightCommentId': ?commentId});
    }
    Widget item(Map<String, dynamic> c) => Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
          child: CommentTile(comment: c, onOpenObject: open, padding: const EdgeInsets.symmetric(vertical: 18), maxLines: 3),
        );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 760) return Column(children: [for (final x in _comments) item(x)]);
      // Rows of two, each pair as tall as its taller comment, so the rules line up.
      return Column(children: [
        for (var i = 0; i < _comments.length; i += 2)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: item(_comments[i])),
              const SizedBox(width: 36),
              Expanded(child: i + 1 < _comments.length ? item(_comments[i + 1]) : const SizedBox()),
            ]),
          ),
      ]);
    });
  }

  // ---------- Tư liệu (tab của Mới cập nhật) ----------
  Future<void> _fetchDocs() async {
    if (_docs != null) return;
    try {
      final d = await ApiClient.query('query { documents(first: 8, orderBy: [{column: "id", order: DESC}]) { data { id title type created_at thumbnail { url } uploader { username } } } }');
      if (mounted) setState(() => _docs = _maps(d['documents']?['data']));
    } catch (_) {
      if (mounted) setState(() => _docs = []);
    }
  }

  Widget _docsBlock() {
    final list = _docs;
    if (list == null) return _skeletonRows();
    if (list.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Chưa tải được, thử lại sau.', style: AppText.bodyText));
    const kinds = {'image': ('Ảnh', Icons.image_outlined), 'audio': ('Âm thanh', Icons.graphic_eq_rounded), 'video': ('Video', Icons.videocam_outlined), 'news': ('Bài viết', Icons.article_outlined), 'sheet': ('Bản nhạc', Icons.library_music_outlined)};
    Widget row(Map<String, dynamic> d) {
      final k = kinds['${d['type']}'] ?? ('Tư liệu', Icons.folder_outlined);
      final thumb = d['thumbnail']?['url']?.toString();
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.push('/tu-lieu/chi-tiet/${d['id']}'),
        child: Container(
          height: 64,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
          child: Row(children: [
            thumb != null
                ? NetImage(url: thumb, width: 46, height: 46, radius: 10, tint: true)
                : Container(width: 46, height: 46, decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)), child: Icon(k.$2, color: AppColors.textMuted)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
                Text([k.$1, if (d['uploader']?['username'] != null) '${d['uploader']['username']}', _postedAgo(d['created_at']?.toString())].where((x) => x.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
              ]),
            ),
          ]),
        ),
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(children: [for (final d in list.take(4)) row(d)])),
      const SizedBox(width: 36),
      Expanded(child: Column(children: [for (final d in list.skip(4).take(4)) row(d)])),
    ]);
  }

}

/// "Hôm nay": the event playlists running today (event_start ≤ today ≤
/// event_end, set in the playlist's settings) as a tear-off calendar page —
/// canvas "Desktop · Trang chủ — khối Sự kiện B". Several at once: the
/// pages stack and "Tiếp: <next>" / ‹ › / ←→ flip between them, wrapping
/// round; never on its own.
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
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) { _go(_at - 1); return true; }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) { _go(_at + 1); return true; }
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
        ..sort((a, b) {
          // One-day events first, then the one ending soonest, then more songs.
          if (oneDay(a) != oneDay(b)) return oneDay(a) ? -1 : 1;
          final e = '${a['event_end']}'.compareTo('${b['event_end']}');
          return e != 0 ? e : total(b).compareTo(total(a));
        });
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

  /// Wraps round: past the last event comes the first again.
  void _go(int i) {
    i %= _events.length;
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
    // No original date: the page shows the day the event leads up to.
    final parts = '${ev['event_end'] ?? ''}'.split('-');
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
              // Names the next event instead of "1 / 2", so it is clear what is there.
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _go(_at + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Tiếp: ', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text('${_events[(_at + 1) % _events.length]['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text))),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              circle(Icons.chevron_left_rounded, () => _go(_at - 1)),
              const SizedBox(width: 8),
              circle(Icons.chevron_right_rounded, () => _go(_at + 1)),
            ] else
              TextButton(onPressed: () => context.push('/playlist/$id'), child: Text('Mở playlist', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
          // Song cards only as many as fit beside the text (narrow windows: fewer).
          child: LayoutBuilder(builder: (context, box) {
          // Text keeps ~340px; song cards fill the rest (up to five), so no hole in between.
          // The text takes what it needs (~360px); the song cards share the rest
          // evenly (each 130–190px wide), so there is no hole in the middle.
          const textW = 360.0;
          final behind = (_events.length - 1).clamp(0, 2);
          final rest = box.maxWidth - (150 + behind * 8) - 28 - textW - 24;
          final n = [songs.length, (rest / 144).floor(), 4].reduce((a, b) => a < b ? a : b);
          final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(eyebrow, style: body(TextStyle(fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
                const SizedBox(height: 6),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 28, height: 1.15, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: AppColors.text))),
                ...[
                  const SizedBox(height: 8),
                  // No description: at least say how much there is to hear.
                  Text(desc.isNotEmpty ? desc : '${(ev['items']?['paginatorInfo']?['total'] as num?)?.toInt() ?? songs.length} bài', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.5, color: AppColors.textSecondary))),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  PillButton(label: songs.length > 1 ? 'Phát tất cả' : 'Phát', icon: Icons.play_arrow_rounded, height: 44, onTap: songs.isEmpty ? null : () => playOrOpen(context, songs.first, songs, title)),
                  const SizedBox(width: 10),
                  Material(
                    color: AppColors.isLight ? Colors.white : const Color(0xFF2A2021),
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => context.push('/playlist/$id'),
                      child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 18), alignment: Alignment.center, child: Text('Xem playlist', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)))),
                    ),
                  ),
                ]),
              ]);
          final cardW = n > 0 ? ((rest - (n - 1) * 14) / n).clamp(0.0, 190.0) : 0.0;
          return Row(children: [
            _Calendar(day: day, month: month, year: date?.year, behind: (_events.length - 1).clamp(0, 2)),
            const SizedBox(width: 28),
            if (n > 0) SizedBox(width: textW, child: text) else Expanded(child: text),
            if (n > 0) ...[
            const SizedBox(width: 24),
            // Song cards share the remaining width; tops aligned.
            Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              SizedBox(
                width: cardW,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => playOrOpen(context, songs[i], songs, title),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SongCover(song: songs[i], size: cardW, radius: 12),
                    const SizedBox(height: 8),
                    Text('${songs[i]['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, height: 1.25, fontWeight: FontWeight.w800, color: AppColors.text))),
                    Text(songByline(songs[i]), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                  ]),
                ),
              ),
            ],
            ])),
            ],
          ]);
          }),
        ),
      ]),
    );
  }
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
        // Dark theme: a dark sheet, not a white glare.
        decoration: BoxDecoration(color: AppColors.isLight ? Colors.white : const Color(0xFF2A2021), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: AppColors.isLight ? 0.12 : 0.4), blurRadius: 22, offset: const Offset(0, 8))]),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(color: AppColors.wine, height: 34, alignment: Alignment.center, child: Text('THÁNG $month', style: body(const TextStyle(fontSize: 14, letterSpacing: 1, fontWeight: FontWeight.w800, color: Colors.white)))),
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(face ? day.toString().padLeft(2, '0') : '', style: display(TextStyle(fontSize: 72, height: 1, letterSpacing: -2, fontWeight: FontWeight.w800, color: AppColors.text)))),
          // No year known: no empty line under the day.
          if (year != null)
            Padding(padding: const EdgeInsets.fromLTRB(0, 4, 0, 14), child: Text(face ? 'năm $year' : ' ', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textMuted))))
          else
            const SizedBox(height: 16),
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
