import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../widgets/brand_logo.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';
import '../widgets/anniversary_rail.dart';
import '../services/lunar.dart';
import '../main.dart' show TabReselect;

export '../widgets/song_row.dart' show playOrOpen;

// Trang chủ for phone widths (2026-11 refresh, canvas "BCĐCNT App — Giao
// diện"). Order: greeting + lunar date → Nghe tiếp → Mọi người đang nghe →
// Kỷ niệm tuần này → Gợi ý (the coming occasion's playlist, else yesterday's
// most played) → Mới cập nhật → Nghe nhiều hôm nay → Cảm nhận hay → Có thể
// bạn thích → Nghe đi nghe lại → Thập niên → Nhạc sĩ tiêu biểu → Nghệ sĩ tiêu biểu. Most of it changes daily or faster. Thành viên tiêu
// biểu lives in Cộng đồng, Bài yêu thích in Cá nhân. Desktop keeps HomeScreen.

const _songFields = 'id slug title subtitle views created_at play_type file_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id slug title } } sheet { year composers(first: 2) { data { id slug title } } }';

const _mainQuery = '''query {
  stickySongs(first: 12) { data { $_songFields } }
  featuredComments(limit: 10) { id snippet likes created_at username user_avatar song_id song_title song_slug song_image audio_url play_type file_type }
}''';

/// The fast-changing blocks, asked separately so a slow or failing one
/// never holds up the rest of the page.
// Named so its GET URL differs from the one Cloudflare pinned for ~a day
// before the API sent s-maxage=60 (2026-11-08).
const _liveQuery = '''query HomeLive {
  nowListening(limit: 12) { listeners song { $_songFields } }
  topSongsToday(limit: 5) { $_songFields }
}''';

const _peopleFields = 'id slug title avatar { url }';
/// "Nhạc sĩ tiêu biểu" / "Nghệ sĩ tiêu biểu": the people the most listeners
/// played today (no groups, all with a photo), recounted every 5 minutes.
const _peopleQuery = '''query HomePeople {
  topComposersToday(limit: 12) { $_peopleFields }
  topArtistsToday(limit: 12) { $_peopleFields }
}''';

class _Cat {
  final String name, slug, query;
  const _Cat(this.name, this.slug, this.query);
}

const _cats = [
  _Cat('Tân nhạc', 'tan-nhac', 'songs'),
  _Cat('Dân ca', 'dan-ca', 'folks'),
  _Cat('Khí nhạc', 'khi-nhac', 'instrumentals'),
  _Cat('Tiếng thơ', 'tieng-tho', 'poems'),
  _Cat('Thành viên hát', 'thanh-vien-hat', 'karaokes'),
];

const _decades = [
  (1950, 'Hoà bình lập lại'),
  (1960, 'Chống Mỹ cứu nước'),
  (1970, 'Thống nhất đất nước'),
  (1980, 'Bao cấp – Đổi mới'),
];

const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];

/// Fixed-date days the archive has songs for. Within two weeks of one, the
/// big "Gợi ý" cards play its songs.
const _occasions = [
  (1, 1, 'Tết Dương lịch'), (3, 2, 'Ngày thành lập Đảng'), (8, 3, 'Quốc tế Phụ nữ'),
  (26, 3, 'Ngày thành lập Đoàn'), (30, 4, 'Ngày Giải phóng miền Nam'), (1, 5, 'Quốc tế Lao động'),
  (7, 5, 'Chiến thắng Điện Biên Phủ'), (19, 5, 'Sinh nhật Bác Hồ'), (1, 6, 'Quốc tế Thiếu nhi'),
  (27, 7, 'Ngày Thương binh Liệt sĩ'), (19, 8, 'Cách mạng Tháng Tám'), (2, 9, 'Quốc khánh'),
  (10, 10, 'Giải phóng Thủ đô'), (20, 10, 'Ngày Phụ nữ Việt Nam'), (20, 11, 'Ngày Nhà giáo Việt Nam'),
  (22, 12, 'Ngày thành lập Quân đội'),
];

/// Site playlists made for an occasion, used when BQT hasn't set up a
/// dated event playlist for it (playlist.event_start/event_end).
const _occasionPlaylist = {
  'Quốc tế Phụ nữ': 27, 'Ngày Phụ nữ Việt Nam': 27, 'Ngày thành lập Đoàn': 1558,
  'Ngày Giải phóng miền Nam': 40, 'Sinh nhật Bác Hồ': 18, 'Ngày Nhà giáo Việt Nam': 12,
  'Ngày thành lập Quân đội': 6, 'Quốc khánh': 1, 'Giải phóng Thủ đô': 2,
};

typedef _Occasion = ({int days, int day, int month, String label});

/// The nearest occasion within the next 14 days (today included).
_Occasion? _nextOccasion(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  _Occasion? best;
  for (final (d, m, label) in _occasions) {
    var date = DateTime(now.year, m, d);
    if (date.isBefore(today)) date = DateTime(now.year + 1, m, d);
    final days = date.difference(today).inDays;
    if (days <= 14 && (best == null || days < best.days)) best = (days: days, day: d, month: m, label: label);
  }
  return best;
}

String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 11) return 'Chào buổi sáng';
  if (h < 14) return 'Chào buổi trưa';
  if (h < 18) return 'Chào buổi chiều';
  return 'Chào buổi tối';
}

/// "Hôm nay" / "Hôm qua" / "3 ngày trước" by calendar day, for "Mới cập nhật".
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

List<Map<String, dynamic>> _maps(dynamic list) =>
    ((list ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

class HomeMobileScreen extends StatefulWidget {
  const HomeMobileScreen({super.key});
  @override
  State<HomeMobileScreen> createState() => _HomeMobileScreenState();
}

class _HomeMobileScreenState extends State<HomeMobileScreen> {
  bool _loading = true;
  bool _failed = false;
  /// Yesterday's most played (stickySongs): the "Gợi ý" cards outside occasions.
  List<Map<String, dynamic>> _picks = [];
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _composers = [];
  List<Map<String, dynamic>> _artists = [];
  List<Map<String, dynamic>> _recent = [];
  List<Map<String, dynamic>> _forYou = [];
  /// "Nghe đi nghe lại": the member's most played, with 'plays'.
  List<Map<String, dynamic>> _again = [];
  /// "Mới thích gần đây": the member's latest loves, newest first.
  List<Map<String, dynamic>> _loved = [];
  /// "Mọi người đang nghe": {listeners, song}.
  List<Map<String, dynamic>> _live = [];
  List<Map<String, dynamic>> _today = [];
  _Occasion? _occasion;
  String? _occasionPlaylistId;
  List<Map<String, dynamic>> _occasionSongs = [];
  int _cat = 0;
  final Map<String, List<Map<String, dynamic>>> _latest = {};
  AuthProvider? _auth;
  String? _recentFor;
  final _scroll = ScrollController();

  void _onReselect() {
    if (TabReselect.tick.value.$1 == 0 && _scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    }
  }

  @override
  void initState() {
    super.initState();
    TabReselect.tick.addListener(_onReselect);
    _fetch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _auth = context.read<AuthProvider>()..addListener(_maybeFetchRecent);
      _maybeFetchRecent();
    });
  }

  @override
  void dispose() {
    TabReselect.tick.removeListener(_onReselect);
    _life.dispose();
    _scroll.dispose();
    _auth?.removeListener(_maybeFetchRecent);
    super.dispose();
  }

  // Home lives for days in the tab stack: rebuild the daily cards when the
  // date (Vietnam time) changes, and on pull-to-refresh.
  String get _dayKey {
    final vn = DateTime.now().toUtc().add(const Duration(hours: 7));
    return '${vn.year}-${vn.month}-${vn.day}';
  }
  int _refreshTick = 0;
  late final AppLifecycleListener _life = AppLifecycleListener(onResume: () {
    if (!mounted) return;
    setState(() {});
    // Coming back hours later: "Nghe tiếp" should show what was played
    // meanwhile (on the web, another phone…), "đang nghe" what is on now.
    _refreshPersonal(throttle: true);
    _fetchLive(throttle: true);
  });

  bool get _hasContent => _picks.isNotEmpty || _today.isNotEmpty || _comments.isNotEmpty || _composers.isNotEmpty || _artists.isNotEmpty;

  Future<void> _fetch() async {
    _life; // start listening
    // null = that request failed (vs. an empty answer).
    Future<Map<String, dynamic>?> safe(Future<Map<String, dynamic>> f) => f.then<Map<String, dynamic>?>((v) => v).catchError((_) => null);
    if (_failed) setState(() => _failed = false);
    _refreshPersonal();
    _fetchOccasion(_nextOccasion(DateTime.now()));
    final r = await Future.wait([
      safe(ApiClient.query(_mainQuery)),
      safe(ApiClient.query(_peopleQuery)),
      safe(ApiClient.query(_liveQuery)),
    ]);
    if (!mounted) return;
    if (r.every((x) => x == null)) {
      // Offline: a pull-to-refresh must not wipe a page that was fine a
      // minute ago. Keep it and say so; only an empty first load shows
      // the offline block.
      if (_hasContent) {
        setState(() => _loading = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Không tải được, đang hiện nội dung cũ')));
      } else {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    _latest.clear();
    _fetchLatest(_cats[_cat]);
    final main = r[0], people = r[1], live = r[2];
    setState(() {
      // Daily cards re-key (and refetch) only when the network is back.
      _refreshTick++;
      // Each block updates only from a request that answered.
      if (main != null) {
        _picks = _maps(main['stickySongs']?['data']).where((s) => s['thumbnail']?['url'] != null).toList();
        _comments = _maps(main['featuredComments']).where((c) => (c['snippet'] ?? '').toString().trim().isNotEmpty).toList();
      }
      if (people != null) {
        // image_id > 0 doesn't guarantee the image row exists (~10% don't):
        // keep only people with a real photo so the rail stays all faces.
        bool hasPhoto(Map p) => (p['avatar']?['url']?.toString() ?? '').isNotEmpty;
        _composers = _maps(people['topComposersToday']).where(hasPhoto).toList();
        _artists = _maps(people['topArtistsToday']).where(hasPhoto).toList();
      }
      if (live != null) _applyLive(live);
      _loading = false;
      _failed = false;
    });
  }

  DateTime? _liveAt;

  void _applyLive(Map<String, dynamic> live) {
    _liveAt = DateTime.now();
    _live = _maps(live['nowListening']).where((x) => x['song'] is Map).map((x) => {
          'listeners': x['listeners'],
          'song': {...Map<String, dynamic>.from(x['song']), 'file_type': 'song'},
        }).toList();
    _today = _maps(live['topSongsToday']).map((s) => {...s, 'file_type': 'song'}).toList();
  }

  /// "Mọi người đang nghe" moves minute to minute: re-read it on resume.
  Future<void> _fetchLive({bool throttle = false}) async {
    if (throttle && _liveAt != null && DateTime.now().difference(_liveAt!) < const Duration(minutes: 1)) return;
    try {
      final d = await ApiClient.query(_liveQuery);
      if (mounted) setState(() => _applyLive(d));
    } catch (_) {}
  }

  /// The coming occasion's songs: a dated event playlist BQT set up for that
  /// day if there is one, else the site's themed playlist.
  Future<void> _fetchOccasion(_Occasion? o) async {
    if (o == null) {
      if (_occasion != null && mounted) setState(() { _occasion = null; _occasionSongs = []; });
      return;
    }
    final mmdd = '${o.month.toString().padLeft(2, '0')}-${o.day.toString().padLeft(2, '0')}';
    try {
      String? id;
      final ev = await ApiClient.query(r'''query($w: WhereConditions) { playlists(first: 1, orderBy: [{column: "id", order: DESC}], where: $w) { data { id } } }''', {
        'w': {'AND': [
          {'column': 'is_system', 'value': '1'},
          {'column': 'is_public', 'value': '1'},
          {'column': 'event_start', 'operator': 'LTE', 'value': mmdd},
          {'column': 'event_end', 'operator': 'GTE', 'value': mmdd},
        ]},
      });
      id = (ev['playlists']?['data'] as List?)?.firstOrNull?['id']?.toString() ?? _occasionPlaylist[o.label]?.toString();
      if (id == null) return;
      final d = await ApiClient.query('query(\$id: ID!) { playlist(id: \$id) { songs(first: 12) { data { $_songFields } } } }', {'id': id});
      final songs = _maps(d['playlist']?['songs']?['data'])
          .where((s) => s['thumbnail']?['url'] != null && (s['file']?['audio_url'] != null || s['file']?['video_url'] != null))
          .map((s) => {...s, 'file_type': 'song'})
          .toList();
      if (!mounted) return;
      setState(() {
        _occasion = o;
        _occasionPlaylistId = id;
        _occasionSongs = songs;
      });
    } catch (_) {}
  }

  DateTime? _personalAt;

  /// Re-reads the member's own rails (Nghe tiếp, Có thể bạn thích, Nghe đi
  /// nghe lại). A failed request keeps what is on screen.
  void _refreshPersonal({bool throttle = false}) {
    final auth = _auth;
    final uid = auth?.user?['id']?.toString();
    if (auth == null || uid == null || uid != _recentFor) return;
    final now = DateTime.now();
    // Switching apps back and forth must not refire the queries each time.
    if (throttle && _personalAt != null && now.difference(_personalAt!) < const Duration(minutes: 2)) return;
    _personalAt = now;
    _fetchRecent(auth, uid);
    _fetchLoved(auth, uid);
    _fetchForYou(auth, uid);
    _fetchAgain(uid);
  }

  void _maybeFetchRecent() {
    final auth = _auth;
    if (auth == null || auth.loading || !mounted) return;
    final uid = auth.user?['id']?.toString();
    if (uid == _recentFor) return;
    _recentFor = uid;
    if (uid == null) {
      setState(() { _recent = []; _forYou = []; _again = []; _loved = []; });
      return;
    }
    _personalAt = DateTime.now();
    _fetchRecent(auth, uid);
    _fetchLoved(auth, uid);
    _fetchForYou(auth, uid);
    _fetchAgain(uid);
  }

  Future<void> _fetchRecent(AuthProvider auth, String uid) async {
    const f = 'id title slug play_type thumbnail { url } file { audio_url video_url } artists(first: 2) { data { id title slug } }';
    try {
      final d = await auth.authedQuery('''query(\$id: ID!) { user(id: \$id) { recentListens(first: 12, page: 1, orderBy: [{column: "id", order: DESC}]) { data { object { __typename ... on Song { $f } ... on Folk { $f } ... on Instrumental { $f } ... on Poem { $f } } } } } }''', {'id': uid});
      const tn = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem'};
      final seen = <String>{};
      final out = <Map<String, dynamic>>[];
      for (final e in _maps(d['user']?['recentListens']?['data'])) {
        final o = e['object'];
        if (o is! Map) continue;
        final m = Map<String, dynamic>.from(o);
        if (!seen.add('${m['__typename']}-${m['id']}')) continue;
        m['file_type'] = tn[m['__typename']] ?? 'song';
        out.add(m);
      }
      if (mounted && _recentFor == uid) setState(() => _recent = out);
    } catch (_) {}
  }

  Future<void> _fetchLoved(AuthProvider auth, String uid) async {
    const f = 'id title slug play_type thumbnail { url } file { audio_url video_url } artists(first: 2) { data { id title slug } }';
    try {
      final d = await auth.authedQuery('''query(\$id: ID!) { user(id: \$id) { loves(first: 12, page: 1, orderBy: [{column: "id", order: DESC}]) { data { object { __typename ... on Song { $f } ... on Folk { $f } ... on Instrumental { $f } ... on Poem { $f } } } } } }''', {'id': uid});
      const tn = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem'};
      final out = <Map<String, dynamic>>[];
      for (final e in _maps(d['user']?['loves']?['data'])) {
        final o = e['object'];
        if (o is! Map) continue;
        final m = Map<String, dynamic>.from(o);
        m['file_type'] = tn[m['__typename']] ?? 'song';
        out.add(m);
      }
      if (mounted && _recentFor == uid) setState(() => _loved = out);
    } catch (_) {}
  }

  /// "Có thể bạn thích" — the recommendedSongs resolver the desktop home
  /// uses (same composer / singer / topic as what the member plays), shown
  /// as one plain rail: the API already shuffles them.
  Future<void> _fetchForYou(AuthProvider auth, String uid) async {
    try {
      final d = await auth.authedQuery(r'''query($id: ID) { recommendedSongs(user_id: $id, limit: 20) {
        id title subtitle slug image audio_url video_url play_type file_type artists { id title slug }
      } }''', {'id': uid});
      final out = <Map<String, dynamic>>[];
      for (final m in _maps(d['recommendedSongs'])) {
        if (m['audio_url'] == null && m['video_url'] == null) continue;
        // Picture-led rail: songs without artwork read as gaps here.
        if ('${m['image'] ?? ''}'.isEmpty) continue;
        out.add({
          'id': m['id'],
          'title': m['title'],
          'subtitle': m['subtitle'],
          'slug': m['slug'],
          if (m['image'] != null) 'thumbnail': {'url': m['image']},
          'file': {'audio_url': m['audio_url'], 'video_url': m['video_url']},
          'play_type': m['play_type'],
          'file_type': const {'audio': 'song', 'video': 'song'}[m['file_type']] ?? m['file_type'] ?? 'song',
          'artists': {'data': m['artists'] ?? []},
        });
      }
      if (mounted && _recentFor == uid) setState(() => _forYou = out);
    } catch (_) {}
  }

  /// "Nghe đi nghe lại": the songs this member played most, all time
  /// (most_listens is recounted on every listen), 3 plays or more.
  Future<void> _fetchAgain(String uid) async {
    const f = 'id title slug play_type thumbnail { url } file { audio_url video_url duration } artists(first: 2) { data { id title slug } }';
    try {
      final d = await ApiClient.query('''query(\$w: WhereConditions) { mostListens(first: 20, where: \$w, orderBy: [{column: "total", order: DESC}]) { data { total object { __typename ... on Song { $f } ... on Folk { $f } ... on Instrumental { $f } ... on Poem { $f } } } } }''', {
        'w': {'column': 'user_id', 'value': uid},
      });
      const tn = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem'};
      final out = <Map<String, dynamic>>[];
      for (final e in _maps(d['mostListens']?['data'])) {
        final o = e['object'];
        final plays = (e['total'] as num?)?.toInt() ?? 0;
        if (o is! Map || plays < 3) continue;
        final m = Map<String, dynamic>.from(o);
        if (m['file']?['audio_url'] == null && m['file']?['video_url'] == null) continue;
        m['file_type'] = tn[m['__typename']] ?? 'song';
        m['plays'] = plays;
        out.add(m);
      }
      if (mounted && _recentFor == uid) setState(() => _again = out.take(12).toList());
    } catch (_) {}
  }

  Future<void> _fetchLatest(_Cat cat) async {
    final people = cat.query == 'karaokes'
        ? 'users(first: 3) { data { id slug: username title: username } }'
        : 'artists(first: 3) { data { id slug title } }';
    final q = '''query {
      ${cat.query}(first: 8, orderBy: [{column: "id", order: DESC}]) {
        data { id slug title subtitle views created_at play_type file_type thumbnail { url } file { audio_url video_url duration } $people }
      }
    }''';
    try {
      final d = await ApiClient.query(q);
      if (!mounted) return;
      setState(() => _latest[cat.slug] = _maps(d[cat.query]?['data']).map((s) {
            if (cat.query == 'karaokes' && s['users'] != null) s['artists'] = s['users'];
            // API file_type is "audio"/"video"; the player needs the table
            // (folks → folk…), or it loads the tân nhạc with the same id.
            s['file_type'] = cat.query.substring(0, cat.query.length - 1);
            return s;
          }).toList());
    } catch (_) {
      if (mounted) setState(() => _latest[cat.slug] = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final user = context.select<AuthProvider, Map<String, dynamic>?>((a) => a.user);
    final unread = (user?['unread'] is num) ? (user!['unread'] as num).toInt() : 0;
    final name = user?['username']?.toString();
    final cat = _cats[_cat];
    final latest = _latest[cat.slug];
    // Suggestions are new songs: skip what the member just played or plays
    // over and over.
    final seen = <String>{for (final x in [..._recent, ..._again]) '${x['file_type']}-${x['id']}'};
    final forYou = [for (final x in _forYou) if (seen.add('${x['file_type']}-${x['id']}')) x];
    final occ = _occasion;
    final occasionOn = occ != null && _occasionSongs.length >= 3;
    // Outside occasions the big cards are yesterday's most played: leave out
    // what "Nghe nhiều hôm nay" already lists.
    final todayIds = {for (final s in _today) '${s['id']}'};
    final picks = occasionOn ? _occasionSongs : _picks.where((s) => !todayIds.contains('${s['id']}')).toList();

    return ColoredBox(
      color: AppColors.bg,
      child: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: _fetch,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Row(
                children: [
                  const BrandLogo(height: 30),
                  const Spacer(),
                  RoundIcon(icon: Icons.search_rounded, tooltip: 'Tìm kiếm', onTap: () => context.go('/search')),
                  const SizedBox(width: 8),
                  RoundIcon(icon: Icons.notifications_none_rounded, tooltip: 'Thông báo', dot: unread > 0, onTap: () => context.push('/thong-bao')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name != null && name.isNotEmpty ? '${_greeting(now)}, $name' : _greeting(now),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: display(TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w800, color: AppColors.text))),
                  const SizedBox(height: 6),
                  Text(
                    '${_weekdays[now.weekday - 1]}, ${now.day}/${now.month} · ${LunarDate.fromSolar(now).label}',
                    style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  ),
                ],
              ),
            ),
            if (_failed) ...[
              OfflineBlock(onRetry: _fetch),
              // Offline is exactly when saved songs matter: one tap to them.
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 0, 36, 8),
                child: PillButton(label: 'Mở bài đã tải về', icon: Icons.download_done_rounded, primary: false, onTap: () => context.push('/da-tai-ve')),
              ),
            ],
            if (_recent.isNotEmpty) ...[
              // Right under the greeting: picking up where they left off is
              // what most people open the app for.
              SectionTitle('Nghe tiếp', action: 'Xem tất cả', onAction: () => context.push('/nghe-gan-day'), padding: const EdgeInsets.fromLTRB(20, 18, 12, 10)),
              Rail(
                height: 226,
                count: _recent.length,
                builder: (_, i) => _songCard(_recent[i], _recent, 'Nghe gần đây'),
              ),
            ],
            // Songs just loved, to play them again: a heart marks the rail.
            if (_loved.isNotEmpty) ...[
              SectionTitle('Mới thích gần đây', action: 'Xem tất cả', onAction: () => context.push('/yeu-thich'), padding: const EdgeInsets.fromLTRB(20, 18, 12, 10)),
              Rail(
                height: 226,
                count: _loved.length,
                builder: (_, i) => RailCard(
                  cover: Stack(fit: StackFit.expand, children: [
                    SongCover(song: _loved[i], size: 148, radius: 0),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), shape: BoxShape.circle),
                        child: const Icon(Icons.favorite_rounded, size: 16, color: Color(0xFF8E1F1F)),
                      ),
                    ),
                  ]),
                  title: _loved[i]['title']?.toString() ?? '',
                  subtitle: songByline(_loved[i]),
                  onTap: () => playOrOpen(context, _loved[i], _loved, 'Yêu thích'),
                ),
              ),
            ],

            // What others are playing right now: never the same twice.
            if (_live.length >= 3) ...[
              const _LiveTitle(),
              Rail(
                height: 226,
                count: _live.length,
                builder: (_, i) {
                  final s = Map<String, dynamic>.from(_live[i]['song'] as Map);
                  final n = (_live[i]['listeners'] as num?)?.toInt() ?? 0;
                  final queue = [for (final x in _live) Map<String, dynamic>.from(x['song'] as Map)];
                  return RailCard(
                    cover: Stack(fit: StackFit.expand, children: [
                      SongCover(song: s, size: 148, radius: 0),
                      if (n > 1) Positioned(left: 8, top: 8, child: _ListenersPill(count: n)),
                    ]),
                    title: s['title']?.toString() ?? '',
                    subtitle: songByline(s),
                    onTap: () => playOrOpen(context, s, queue, 'Mọi người đang nghe'),
                  );
                },
              ),
            ],

            // Birthdays / anniversaries in the coming week.
            AnniversaryRail(key: ValueKey('anniv-$_dayKey-$_refreshTick')),

            // The coming occasion's songs, else what everyone played yesterday.
            if (_loading) ...[
              const SizedBox(height: 18),
              const Skeleton(height: 236, radius: 24, margin: EdgeInsets.symmetric(horizontal: 20)),
            ] else if (picks.isNotEmpty) ...[
              if (occasionOn)
                _EyebrowTitle(
                  eyebrow: 'Kỷ niệm ngày lễ, sự kiện',
                  title: '${occ.label} ${occ.day}/${occ.month}',
                  chevron: _occasionPlaylistId != null,
                  onTap: _occasionPlaylistId == null ? null : () => context.push('/playlist/$_occasionPlaylistId'),
                )
              else
                const _EyebrowTitle(eyebrow: 'Hôm qua', title: 'Mọi người nghe nhiều'),
              _PickCarousel(key: ValueKey(occasionOn ? 'occ-${occ.label}' : 'top'), picks: picks, label: occasionOn ? occ.label : 'Hôm qua nghe nhiều'),
            ],

            if (!_failed) ...[
              SectionTitle('Mới cập nhật', onAction: () => context.push('/the-loai/${cat.slug}')),
              ChipStrip(
                labels: [for (final c in _cats) c.name],
                selected: _cat,
                onSelect: (i) {
                  setState(() => _cat = i);
                  if (!_latest.containsKey(_cats[i].slug)) _fetchLatest(_cats[i]);
                },
              ),
              const SizedBox(height: 14),
              if (latest == null)
                Rail(height: 246, textHeight: 80, count: 4, builder: (_, __) => const Skeleton(width: 148, height: 148, radius: 18))
              else
                Rail(
                  height: 246,
                  textHeight: 80,
                  count: latest.length,
                  builder: (_, i) {
                    final s = latest[i];
                    return RailCard(
                      cover: SongCover(song: s, size: 148, radius: 0),
                      title: s['title']?.toString() ?? '',
                      subtitle: songByline(s),
                      // When it went up: a list that didn't change since
                      // yesterday still reads as current.
                      meta: _postedAgo(s['created_at']?.toString()),
                      onTap: () => playOrOpen(context, s, latest, 'Mới cập nhật · ${cat.name}'),
                    );
                  },
                ),
            ],

            // Offline first launch: no titles over empty space.
            if (_loading || _today.length >= 3) ...[
              SectionTitle('Nghe nhiều hôm nay', action: 'Bảng xếp hạng', onAction: () => context.push('/bang-xep-hang')),
              if (_loading)
                for (var i = 0; i < 5; i++) const SkeletonSongRow()
              else
                for (var i = 0; i < _today.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 20, right: 6),
                    // The rank says the order; no listen counts (small
                    // numbers early in the day read as an empty site).
                    child: SongRow(song: _today[i], index: i, showIndex: true, queue: _today, sourceLabel: 'Nghe nhiều hôm nay', subtitle: _chartLine(_today[i])),
                  ),
            ],

            // Members' memories: what no other music app has.
            if (_comments.isNotEmpty) ...[
              SectionTitle('Cảm nhận hay', action: 'Xem thêm', onAction: () => context.go('/cong-dong')),
              Rail(
                height: 226,
                count: _comments.length,
                builder: (_, i) => _QuoteCard(comment: _comments[i]),
              ),
            ],

            if (forYou.isNotEmpty) ...[
              const SectionTitle('Có thể bạn thích', action: null),
              Rail(
                height: 226,
                count: forYou.length,
                builder: (_, i) => _songCard(forYou[i], forYou, 'Có thể bạn thích'),
              ),
            ],

            // The member's own favourites, by how often they come back.
            if (_again.length >= 3) ...[
              const SectionTitle('Nghe đi nghe lại', action: null),
              Rail(
                height: 246,
                textHeight: 80,
                count: _again.length,
                builder: (_, i) {
                  final s = _again[i];
                  return RailCard(
                    cover: SongCover(song: s, size: 148, radius: 0),
                    title: s['title']?.toString() ?? '',
                    subtitle: songByline(s),
                    meta: '${s['plays']} lần',
                    onTap: () => playOrOpen(context, s, _again, 'Nghe đi nghe lại'),
                  );
                },
              ),
            ],

            if (!_failed) ...[
              const SectionTitle('Nghe theo thập niên', action: null),
              _DecadeGrid(images: [for (final s in _picks.skip(1).take(4)) s['thumbnail']?['url']?.toString()]),
            ],

            // Composers and singers in their own rails: behind a chip, the
            // second one was never opened.
            if (_loading || _composers.isNotEmpty) ...[
              SectionTitle('Nhạc sĩ tiêu biểu', onAction: () => context.push('/nhac-si')),
              _PeopleRail(people: _composers, loading: _loading, route: '/nhac-si/'),
            ],
            if (_loading || _artists.isNotEmpty) ...[
              SectionTitle('Nghệ sĩ tiêu biểu', onAction: () => context.push('/nghe-si')),
              _PeopleRail(people: _artists, loading: _loading, route: '/nghe-si/'),
            ],
          ],
        ),
      ),
    );
  }

  /// Singer(s); a song with none on record shows its composer instead.
  String _chartLine(Map<String, dynamic> s) {
    final by = songByline(s);
    if (by.isNotEmpty) return by;
    final comp = songByline({'artists': s['sheet']?['composers']});
    return comp.isEmpty ? '' : 'Nhạc: $comp';
  }

  Widget _songCard(Map<String, dynamic> s, List<Map<String, dynamic>> list, String label) => RailCard(
        cover: SongCover(song: s, size: 148, radius: 0),
        title: s['title']?.toString() ?? '',
        subtitle: songByline(s),
        onTap: () => playOrOpen(context, s, list, label),
      );
}

/// Section title with a small line above it: "Kỷ niệm ngày lễ, sự kiện" over
/// "Ngày Nhà giáo Việt Nam 20/11 ›".
class _EyebrowTitle extends StatelessWidget {
  final String eyebrow;
  final String title;
  final bool chevron;
  final VoidCallback? onTap;
  const _EyebrowTitle({required this.eyebrow, required this.title, this.chevron = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(eyebrow, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
      const SizedBox(height: 2),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)))),
        if (chevron) Icon(Icons.chevron_right_rounded, size: 26, color: AppColors.text),
      ]),
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 12, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: onTap == null
                ? text
                : Semantics(
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onTap,
                      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: text),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }
}

/// "● Mọi người đang nghe" title.
class _LiveTitle extends StatelessWidget {
  const _LiveTitle();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 12, 10),
        child: Row(children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: const Color(0xFFC62828), shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFC62828).withValues(alpha: 0.18), spreadRadius: 4)]),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Mọi người đang nghe', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)))),
        ]),
      );
}

/// "● 6 người" on a cover in "Mọi người đang nghe".
class _ListenersPill extends StatelessWidget {
  final int count;
  const _ListenersPill({required this.count});
  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(13)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFC62828), shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$count người', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF161112)))),
        ]),
      );
}

/// Big swipeable "Gợi ý" cards with brand-tinted photos (the section title
/// above says why these songs).
class _PickCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> picks;
  /// Player header and VoiceOver: "Ngày Nhà giáo Việt Nam", …
  final String label;
  const _PickCarousel({super.key, required this.picks, required this.label});
  @override
  State<_PickCarousel> createState() => _PickCarouselState();
}

class _PickCarouselState extends State<_PickCarousel> {
  static const _maxSlides = 6;
  // Sized so each card is exactly screen − 40 wide: its edges sit on the
  // 20pt gutter like every other block (0.9 put them at 26pt).
  late final PageController _ctrl = PageController(
    viewportFraction: (() {
      final w = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.width / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      return w <= 0 ? 0.9 : ((w - 28) / w).clamp(0.8, 0.97);
    })(),
  );
  int _index = 0;
  Timer? _timer;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      // Moving slides under a reader's finger is the worst case for older
      // users: stop for good once they touch it, and never move when the
      // phone asks for reduced motion.
      if (_touched || !mounted || !TickerMode.of(context) || MediaQuery.of(context).disableAnimations || MediaQuery.of(context).accessibleNavigation) return;
      // Count the slides actually shown (build() takes the first 6), else
      // the last slide asks for a page that doesn't exist and stays put.
      final count = widget.picks.length.clamp(0, _maxSlides);
      if (!_ctrl.hasClients || count < 2) return;
      final next = (_index + 1) % count;
      _ctrl.animateToPage(next, duration: Duration(milliseconds: next == 0 ? 700 : 450), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picks = widget.picks.take(_maxSlides).toList();
    return Column(
      children: [
        SizedBox(
          height: 156 + MediaQuery.textScalerOf(context).scale(80),
          child: Listener(
            onPointerDown: (_) => _touched = true,
            child: PageView.builder(
            controller: _ctrl,
            // Centred slides: every card sits on the same margin, not just
            // the first one.
            padEnds: true,
            itemCount: picks.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final s = picks[i];
              final comp = (s['sheet']?['composers']?['data'] as List?)?.whereType<Map>().map((c) => c['title']).join(', ') ?? '';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Semantics(
                  button: true,
                  label: '${widget.label}: ${s['title'] ?? ''}${comp.isNotEmpty ? ', $comp' : ''}',
                  hint: 'Chạm để nghe',
                  excludeSemantics: true,
                  child: GestureDetector(
                  onTap: () => playOrOpen(context, s, picks, widget.label),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImage(url: s['thumbnail']?['url']?.toString(), tint: true),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.3, 1],
                              colors: [Color(0x000E0A0A), Color(0xD60E0A0A)],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 16,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (comp.isNotEmpty)
                                      Text(comp.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 14, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: Color(0xD9FFFFFF)))),
                                    const SizedBox(height: 4),
                                    Text(noOrphan('${s['title'] ?? ''}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800, color: Colors.white))),
                                    const SizedBox(height: 3),
                                    Text(songByline(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xD9FFFFFF)))),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 52,
                                height: 52,
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                child: const Icon(Icons.play_arrow_rounded, color: AppColors.wine, size: 30),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              );
            },
          ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < picks.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(color: i == _index ? AppColors.wine : AppColors.rose.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(3)),
              ),
          ],
        ),
      ],
    );
  }
}

/// 2x2 decade tiles with tinted archive photos.
class _DecadeGrid extends StatelessWidget {
  final List<String?> images;
  const _DecadeGrid({required this.images});
  static const _tones = [Color(0xFF711313), Color(0xFF8C3B3A), Color(0xFF5A1D1D), Color(0xFF9C5E5C)];

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < _decades.length; i++)
              Material(
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push('/bai-hat/thap-nien/${_decades[i].$1}'),
                  child: Ink(
                    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_tones[i], const Color(0xFF1B0909)])),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (i < images.length && images[i] != null) Opacity(opacity: 0.5, child: NetImage(url: images[i], tint: true)),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('Thập niên ${_decades[i].$1 % 100}', style: display(const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white))),
                              Text(_decades[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xEBFFFFFF)))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// "Cảm nhận hay" quote card; tap plays the song it was written for.
class _QuoteCard extends StatelessWidget {
  final Map<String, dynamic> comment;
  const _QuoteCard({required this.comment});

  @override
  Widget build(BuildContext context) {
    final song = <String, dynamic>{
      'id': comment['song_id'],
      'title': comment['song_title'],
      'slug': comment['song_slug'],
      'file_type': comment['file_type'] ?? 'song',
      if (comment['song_image'] != null) 'thumbnail': {'url': comment['song_image']},
      if (comment['audio_url'] != null) 'file': {'audio_url': comment['audio_url']},
    };
    return SizedBox(
      width: 300,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            HapticFeedback.selectionClick();
            context.push('/song/${comment['song_id']}', extra: {...song, 'highlightCommentId': comment['id']?.toString()});
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Về bài “${comment['song_title'] ?? ''}”', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta.copyWith(color: AppColors.accentLight, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    (comment['snippet'] ?? '').toString(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: body(TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                  ),
                ),
                Row(
                  children: [
                    UserAvatar(url: comment['user_avatar']?.toString(), name: (comment['username'] ?? '').toString(), size: 28),
                    const SizedBox(width: 10),
                    Expanded(child: Text((comment['username'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted)))),
                    if ((comment['likes'] ?? 0) is num && (comment['likes'] as num) > 0) ...[
                      Icon(Icons.favorite_border_rounded, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text('${comment['likes']}', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                    ],
                    if (comment['audio_url'] != null) ...[
                      const SizedBox(width: 6),
                      // A real 48pt button (was a 36pt dot): its own target,
                      // with a name VoiceOver can read.
                      IconButton(
                        tooltip: 'Nghe bài này',
                        onPressed: () => playOrOpen(context, song, [song], 'Cảm nhận hay'),
                        style: IconButton.styleFrom(backgroundColor: AppColors.wine, fixedSize: const Size(48, 48), minimumSize: const Size(48, 48)),
                        icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PeopleRail extends StatelessWidget {
  final List<Map<String, dynamic>> people;
  final bool loading;
  final String route;
  const _PeopleRail({required this.people, required this.loading, required this.route});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Rail(height: 150, count: 4, gap: 14, builder: (_, __) => const Skeleton(width: 88, height: 88, radius: 44));
    }
    // 88 photo + 8 gap + up to two lines of name, with room for the
    // larger text sizes in Cài đặt.
    return Rail(
      height: 150,
      gap: 14,
      count: people.length,
      builder: (_, i) {
        final p = people[i];
        return PersonBubble(
          name: p['title']?.toString() ?? '',
          image: p['avatar']?['url']?.toString(),
          onTap: () => context.push('$route${p['slug']}'),
        );
      },
    );
  }
}
