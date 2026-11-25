import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/theme_provider.dart';
import '../services/api.dart';
import '../services/events.dart';
import '../services/auth.dart';
import '../services/lunar.dart';
import '../services/player.dart';
import '../services/radio_presence.dart';
import '../widgets/anniversary_rail.dart';
import 'events_screen.dart' show EventSheet;
import '../widgets/auth_dialogs.dart';
import '../widgets/brand_logo.dart';
import '../widgets/eras.dart';
import '../widgets/home_extras.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';

// Trang chủ desktop (canvas "Desktop · Trang chủ", chốt 11/11/2026): nghe là
// chính, hoài cổ chỉ điểm xuyết. Lời chào + một câu về kho · Tờ lịch (sự kiện
// hôm nay, hoặc Bài hát hôm nay) | Đài BCĐCNT · Dành cho bạn (4 thẻ phát
// ngay; khách: lời mời đăng nhập) · Đi qua năm tháng · Mới về kho | Nghe
// nhiều · Người nghe kể · Chung tay xây dựng. Lối tắt Thư viện nằm ở menu
// trái; "nghe tiếp" là thanh phát nhớ bài lần trước.

const _songFields = 'id slug title subtitle views created_at play_type empty_file thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id slug title } } sheet { year composers(first: 2) { data { id slug title } } }';
const _personal = 'id title slug play_type thumbnail { url } file { audio_url video_url } artists(first: 2) { data { id title slug } }';

const _cats = [
  ('Tân nhạc', 'songs'),
  ('Dân ca', 'folks'),
  ('Khí nhạc', 'instrumentals'),
  ('Tiếng thơ', 'poems'),
  ('Thành viên hát', 'karaokes'),
];
const _catSlugs = ['tan-nhac', 'dan-ca', 'khi-nhac', 'tieng-tho', 'thanh-vien-hat'];
const _periods = [('Hôm nay', 'today'), ('Tháng này', 'month'), ('Năm nay', 'year'), ('Tất cả', 'all')];
const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
const _tn = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem', 'Karaoke': 'karaoke'};
final _march = RegExp(r'hành khúc|tiến quân|quốc ca|chiêu hồn|mặc niệm|nhạc hiệu|quân kỳ', caseSensitive: false);

List<Map<String, dynamic>> _maps(dynamic list) => ((list ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
/// Has a file to play — and not one marked lost (empty_file = 1).
bool _playable(Map s) => s['empty_file'] != 1 && (s['file']?['audio_url'] != null || s['file']?['video_url'] != null);
String _key(Map s) => '${s['file_type'] ?? 'song'}-${s['id']}';
String _first(dynamic people) => _maps(people is Map ? people['data'] : people).map((p) => '${p['title'] ?? ''}').firstWhere((t) => t.isNotEmpty && t != 'Đang cập nhật', orElse: () => '');

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
  if (days <= 0) return 'hôm nay';
  if (days == 1) return 'hôm qua';
  if (days < 7) return '$days ngày trước';
  return timeago(createdAt);
}

/// Passed away this year, within the week: years since is 0.
bool _isRecent(Anniv a) => !a.birth && a.years == 0;

/// "năm Bính Ngọ".
String _canChi(int y) {
  const stems = ['Giáp', 'Ất', 'Bính', 'Đinh', 'Mậu', 'Kỷ', 'Canh', 'Tân', 'Nhâm', 'Quý'];
  const branches = ['Tý', 'Sửu', 'Dần', 'Mão', 'Thìn', 'Tỵ', 'Ngọ', 'Mùi', 'Thân', 'Dậu', 'Tuất', 'Hợi'];
  return '${stems[(y + 6) % 10]} ${branches[(y + 8) % 12]}';
}

// Warm "paper" cards, tinted to the colour set (wine sets ≈ #FBF6F1 / #EDE1D8).
Color get _paper => AppColors.isLight ? Color.lerp(AppColors.bg, AppColors.rose, 0.07)! : Color.lerp(AppColors.surface, AppColors.bg, 0.3)!;
Color get _paperEdge => AppColors.isLight ? Color.lerp(AppColors.bg, AppColors.rose, 0.2)! : Color.lerp(AppColors.surfaceLight, AppColors.surfaceHover, 0.5)!;

/// Đài channels. "Tự động" picks one by the hour: morning songs about the
/// homeland, folk songs at noon, love songs at night, lullabies late.
enum _Ch { auto, all, folk, instr, poem }

class DesktopHomeScreen extends StatefulWidget {
  /// The phone layout (canvas "Trang chủ mobile — đề xuất"): the same
  /// blocks, fewer of them, one column.
  final bool mobile;
  const DesktopHomeScreen({super.key, this.mobile = false});
  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  // Kho
  Map<String, int> _totals = {};
  // Tờ lịch
  List<Map<String, dynamic>> _events = [];
  final Map<String, List<Map<String, dynamic>>> _eventSongs = {};
  int _eventAt = 0;
  /// Bài hát hôm nay: a slideshow — songs by this week's anniversary
  /// composers first, then random well-loved songs.
  List<(Map<String, dynamic>, Anniv?)> _todayList = [];
  int _todayAt = 0;
  /// Only well-loved songs today (nothing to remember): the phone hides the block.
  bool _todayHover = false;
  /// Theo năm tháng (phone): per period, songs written then + a cover.
  List<(int, String?)>? _eraInfo;
  Timer? _todayTimer;
  // Đài
  _Ch _ch = _Ch.auto;
  /// "N người đang nghe cùng": count + a few faces, refreshed each minute.
  final Map<_Ch, List<Map<String, dynamic>>> _radio = {};
  // Dành cho bạn
  String? _personalFor;
  List<Map<String, dynamic>> _forYou = [], _forgotten = [];
  Map<String, dynamic>? _myArtist, _myComposer;
  // Năm tháng: decade → (songs, a well-known title).
  /// (decade, songs, its 3 best-known songs).
  List<(int, int, List<Map<String, dynamic>>)> _decades = [];
  /// Songs per year written, for the sparkline in a hovered bar.
  Map<int, int> _yearCounts = {};
  // Mới về kho | Nghe nhiều
  int _cat = 0, _period = 0;
  final Map<String, List<Map<String, dynamic>>> _latest = {};
  List<Map<String, dynamic>>? _docs;
  final Map<String, List<Map<String, dynamic>>> _top = {};
  // Người nghe kể · Chung tay xây dựng
  /// Người nghe kể: one cảm nhận hay (left, big) · the newest comments (right).
  List<Map<String, dynamic>> _storyList = [];
  int _storyAt = 0;
  bool _storyHover = false;
  Timer? _storyTimer;
  List<Map<String, dynamic>> _comments = [];
  Map<String, int> _ctv = {};
  List<Map<String, dynamic>> _helpers = [];

  String? _starting;
  Timer? _topTimer;

  @override
  void initState() {
    super.initState();
    _loadRadio(_Ch.auto);
    RadioPresence.instance.watch();
    _fetchLatest(0);
    _fetchTop(0);
    if (widget.mobile) _fetchEras();
    // Desktop-only blocks.
    if (!widget.mobile) {
      _loadToday();
      _fetchStory();
      _fetchTotals();
      _fetchDecades();
      _fetchComments();
      _fetchCtv();
      _fetchHelpers();
    }
    _topTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _top.remove('today');
      if (_period == 0) _fetchTop(0);
    });
  }

  @override
  void dispose() {
    _topTimer?.cancel();
    RadioPresence.instance.unwatch();
    _storyTimer?.cancel();
    _todayTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final uid = auth.user?['id']?.toString();
    if (!auth.loading && uid != _personalFor) {
      _personalFor = uid;
      _forYou = []; _forgotten = []; _myArtist = null; _myComposer = null;
      if (uid != null) _fetchPersonal(auth, uid);
    }
  }

  void _play(List<Map<String, dynamic>> list, String label, [int at = 0]) {
    if (list.isEmpty) return;
    playOrOpen(context, list[at], list, label);
  }

  /// Load a list, then play it; [key] shows a spinner on the button meanwhile.
  Future<void> _start(String key, String label, Future<List<Map<String, dynamic>>> Function() load) async {
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

  List<Map<String, dynamic>> _songs(dynamic data, [String kind = 'song']) => _maps(data).map((s) => {...s, 'file_type': kind}).where(_playable).toList();

  // ------------------------------------------------------------ data

  Future<void> _fetchTotals() async {
    try {
      final d = await ApiClient.query('query { songs(first: 1) { paginatorInfo { total } } composers(first: 1) { paginatorInfo { total } } artists(first: 1) { paginatorInfo { total } } folks(first: 1) { paginatorInfo { total } } }');
      int n(String k) => (d[k]?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0;
      if (mounted) setState(() => _totals = {for (final k in ['songs', 'composers', 'artists', 'folks']) k: n(k)});
    } catch (_) {}
  }

  /// Tờ lịch: an event running today wins; else a song by the composer
  /// whose anniversary comes first this week; else one popular song a day.
  Future<void> _loadToday() async {
    final now = DateTime.now();
    final mmdd = '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    unawaited(loadAnniversaries(window: 7).then((a) async {
      if (!mounted) return;
      if (_events.isNotEmpty) return;
      final list = <(Map<String, dynamic>, Anniv?)>[];
      final seen = <String>{};
      for (final x in await _recentlyPassed(now)) {
        final s = await _topSongOf(x);
        if (s != null && seen.add('${s['id']}')) list.add((s, x));
      }
      for (final x in a) {
        if (list.length >= 3) break;
        final s = await _topSongOf(x);
        if (s != null && seen.add('${s['id']}')) list.add((s, x));
      }
      for (final s in await _roundYearSongs(now.year)) {
        if (list.length >= 4) break;
        if (seen.add('${s['id']}')) list.add((s, null));
      }
      // Then what's coming up in the next 30 days, instead of random songs.
      try {
        final ahead = (await loadSiteEvents()).where((e) => e.daysUntil(now) > 0 && e.daysUntil(now) <= 30).toList()
          ..sort((a, b) => a.daysUntil(now).compareTo(b.daysUntil(now)));
        for (final e in ahead.take(2)) {
          if (list.length >= 6) break;
          list.add(({'__event': e, 'id': 'event-${e.id}'}, null));
        }
      } catch (_) {}
      // Nothing at all to tell today: a well-loved song, so it's never empty.
      if (list.isEmpty) {
        for (final s in await _randomSongs()) {
          if (list.length >= 3) break;
          if (seen.add('${s['id']}')) list.add((s, null));
        }
      }
      if (!mounted || list.isEmpty) return;
      setState(() { _todayList = list; _todayAt = 0; });
      _todayTimer?.cancel();
      if (list.length > 1) {
        _todayTimer = Timer.periodic(const Duration(seconds: 10), (_) {
          if (mounted && !_todayHover && _events.isEmpty) setState(() => _todayAt = (_todayAt + 1) % _todayList.length);
        });
      }
    }));
    try {
      final d = await ApiClient.query(r'''query($w: WhereConditions) { playlists(first: 20, orderBy: [{column: "id", order: DESC}], where: $w) { data { id title description excerpt event_start event_end event_date items(first: 1) { paginatorInfo { total } } } } }''', {
        'w': {'AND': [
          {'column': 'is_system', 'value': '1'},
          {'column': 'is_public', 'value': '1'},
          {'column': 'event_start', 'operator': 'LTE', 'value': mmdd},
          {'column': 'event_end', 'operator': 'GTE', 'value': mmdd},
        ]},
      });
      int total(Map p) => ((p['items']?['paginatorInfo']?['total'] as num?) ?? 0).toInt();
      bool oneDay(Map p) => p['event_start'] == p['event_end'];
      final list = _maps(d['playlists']?['data']).where((p) => total(p) > 0).toList()
        ..sort((a, b) {
          if (oneDay(a) != oneDay(b)) return oneDay(a) ? -1 : 1;
          final e = '${a['event_end']}'.compareTo('${b['event_end']}');
          return e != 0 ? e : total(b).compareTo(total(a));
        });
      if (!mounted || list.isEmpty) return;
      setState(() => _events = list);
      _fetchEventSongs(list.first);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _topSongOf(Anniv a) async {
    final l = await _songsOf(a, 6);
    return l.isEmpty ? null : l.first;
  }

  /// The person's best-known songs, marches left out.
  Future<List<Map<String, dynamic>>> _songsOf(Anniv a, int n) async {
    final type = a.route == '/nhac-si/' ? 'composer' : 'artist';
    try {
      final d = await ApiClient.query('query(\$s: String!, \$n: Int!) { $type(slug: \$s) { songs(first: \$n, orderBy: [{column: "views", order: DESC}]) { data { $_songFields poets(first: 1) { data { id slug title } } } } } }', {'s': '${a.person['slug']}', 'n': n});
      return _songs(d[type]?['songs']?['data']).where((s) => !_march.hasMatch('${s['title']}')).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Composers and artists who passed away in the last 7 days (this year):
  /// they lead the slideshow as "Tưởng nhớ".
  Future<List<Anniv>> _recentlyPassed(DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(const Duration(days: 7));
    const f = 'id title slug views dob mob yob dod mod yod avatar { url }';
    String q(String type) => '$type: $type(first: 20, where: {AND: [{column: "yod", value: "${now.year}"}, {column: "mod", operator: IN, value: \$m}]}, orderBy: [{column: "views", order: DESC}]) { data { $f } }';
    try {
      final m = {from.month, today.month};
      final d = await ApiClient.query('query(\$m: Mixed) { ${q('composers')} ${q('artists')} }', {'m': [for (final x in m) ...['$x', x.toString().padLeft(2, '0')]]});
      final out = <Anniv>[];
      for (final (key, route, role) in [('composers', '/nhac-si/', 'Nhạc sĩ'), ('artists', '/nghe-si/', 'Nghệ sĩ')]) {
        for (final p in _maps(d[key]?['data'])) {
          final day = int.tryParse('${p['dod']}'.trim()), month = int.tryParse('${p['mod']}'.trim());
          if (day == null || month == null) continue;
          final date = DateTime(now.year, month, day);
          if (date.month != month || date.isBefore(from) || date.isAfter(today)) continue;
          out.add(Anniv(p, route, role, false, date, 0, date.difference(today).inDays));
        }
      }
      out.sort((a, b) => b.date.compareTo(a.date));
      return out.take(2).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Songs written a round 40/50/60/70/80 years ago, well-known ones
  /// shuffled so each visit brings a different one.
  Future<List<Map<String, dynamic>>> _roundYearSongs(int year) async {
    try {
      final years = [for (var n = 40; n <= 80; n += 10) year - n];
      final d = await ApiClient.query('query(\$y: Mixed) { songs(first: 20, orderBy: [{column: "views", order: DESC}], where: {AND: [{column: "empty_file", value: 0}, {HAS: {relation: "sheet", condition: {column: "year", operator: IN, value: \$y}}}]}) { data { $_songFields poets(first: 1) { data { id slug title } } } } }', {'y': years});
      return _songs(d['songs']?['data']).where((s) => !_march.hasMatch('${s['title']}')).toList()..shuffle();
    } catch (_) {
      return const [];
    }
  }

  /// Well-loved songs, a different handful each visit (no marches first).
  Future<List<Map<String, dynamic>>> _randomSongs() async {
    try {
      final d = await ApiClient.query('query { songs(first: 10, random: true, where: {AND: [{column: "views", operator: GT, value: 20000}, {column: "empty_file", value: 0}]}) { data { $_songFields poets(first: 1) { data { id slug title } } } } }', null, true);
      return _songs(d['songs']?['data']).where((s) => !_march.hasMatch('${s['title']}')).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _fetchEventSongs(Map<String, dynamic> pl) async {
    final id = '${pl['id']}';
    if (_eventSongs.containsKey(id)) return;
    try {
      // items, not songs: playlist.songs comes back empty for some event playlists.
      final d = await ApiClient.query('query(\$id: ID!) { playlist(id: \$id) { items(first: 40, orderBy: [{column: "position", order: ASC}]) { data { object { ... on Song { $_songFields } } } } } }', {'id': id});
      final songs = [for (final it in _maps(d['playlist']?['items']?['data'])) if (it['object'] is Map && (it['object'] as Map).isNotEmpty) Map<String, dynamic>.from(it['object'] as Map)]
          .where(_playable).map((s) => {...s, 'file_type': 'song'}).toList();
      if (mounted) setState(() => _eventSongs[id] = songs);
    } catch (_) {}
  }

  /// "Tối nay: tình ca"… — what "Tự động" plays right now.
  (String, String?, String) get _slot {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 11) return ('Sáng nay: quê hương', 'Tình yêu quê hương đất nước', 'song');
    if (h >= 11 && h < 14) return ('Trưa nay: dân ca', null, 'folk');
    if (h >= 14 && h < 18) return ('Chiều nay: tân nhạc', null, 'song');
    if (h >= 18 && h < 22) return ('Tối nay: tình ca', 'Tình yêu đôi lứa / tình ca', 'song');
    return ('Đêm nay: khúc ru', 'Hát ru', 'song');
  }

  String _chLabel(_Ch c) => switch (c) { _Ch.auto => _slot.$1, _Ch.all => 'Tân nhạc', _Ch.folk => 'Dân ca', _Ch.instr => 'Không lời', _Ch.poem => 'Tiếng thơ' };

  Future<List<Map<String, dynamic>>> _radioBatch(_Ch c) async {
    List<Map<String, dynamic>> out;
    Future<List<Map<String, dynamic>>> popular() async {
      final d = await ApiClient.query('query { songs(first: 40, random: true, where: {AND: [{column: "views", operator: GT, value: 2000}, {column: "empty_file", value: 0}]}) { data { $_songFields } } }', null, true);
      return _songs(d['songs']?['data']);
    }
    Future<List<Map<String, dynamic>>> folk() async {
      final d = await ApiClient.query('query { folks(first: 40, random: true, where: {AND: [{column: "views", operator: GT, value: 300}, {column: "empty_file", value: 0}]}) { data { id slug title subtitle views play_type empty_file thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id slug title } } } } }', null, true);
      return _songs(d['folks']?['data'], 'folk');
    }
    switch (c) {
      case _Ch.all:
        out = await popular();
      case _Ch.folk:
        out = await folk();
      case _Ch.instr:
        out = await _instrumentalMix();
      case _Ch.poem:
        final d = await ApiClient.query('query { poems(first: 40, random: true, where: {column: "empty_file", value: 0}) { data { id slug title subtitle views play_type empty_file thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id slug title } } } } }', null, true);
        out = _songs(d['poems']?['data'], 'poem');
      case _Ch.auto:
        final (_, tag, kind) = _slot;
        if (kind == 'folk') {
          out = await folk();
        } else if (tag != null) {
          final d = await ApiClient.query('query(\$t: String!) { songsByTag(first: 40, random: true, tag: \$t, where: {AND: [{column: "views", operator: GT, value: 1000}, {column: "empty_file", value: 0}]}) { data { $_songFields } } }', {'t': tag}, true);
          out = _songs(d['songsByTag']?['data']);
          if (out.length < 10) out = [...out, ...await popular()];
        } else {
          out = await popular();
        }
    }
    // Marches never open the stream; they may come later.
    out.sort((a, b) => (_march.hasMatch('${a['title']}') ? 1 : 0).compareTo(_march.hasMatch('${b['title']}') ? 1 : 0));
    return out;
  }

  Future<void> _loadRadio(_Ch c) async {
    if (_radio[c] != null) return;
    try {
      final l = await _radioBatch(c);
      if (mounted) setState(() => _radio[c] = l);
    } catch (_) {
      if (mounted) setState(() => _radio[c] = []);
    }
  }

  void _playRadio() {
    final list = _radio[_ch] ?? const [];
    if (list.isEmpty) return;
    _play(list, 'Đài BCĐCNT · ${_chLabel(_ch)}');
    final ch = _ch;
    // Endless: near the end of the queue another random batch follows.
    context.read<PlayerProvider>().setFetchMore((_) => _radioBatch(ch));
    // Next time it starts fresh.
    _radio.remove(ch);
    _loadRadio(ch);
  }

  /// ~30 instrumentals: no ceremonial music or marches, instruments taking
  /// turns so it never runs five guitar pieces in a row.
  Future<List<Map<String, dynamic>>> _instrumentalMix() async {
    final d = await ApiClient.query('query(\$w: WhereConditions) { instrumentals(first: 100, random: true, where: \$w) { data { $_songFields } } }', {'w': {'AND': [{'column': 'views', 'operator': 'GT', 'value': 300}, {'column': 'empty_file', 'value': 0}]}}, true);
    final ceremony = RegExp(r'nghi lễ|quân nhạc|kèn đồng', caseSensitive: false);
    final kinds = {
      'guitar': RegExp(r'guitar|ghi-ta|ghita', caseSensitive: false),
      'bau': RegExp(r'đàn bầu', caseSensitive: false),
      'sao': RegExp(r'sáo|flute', caseSensitive: false),
      'day': RegExp(r'vĩ cầm|violin|piano|dương cầm|đàn tranh|nhị|cello', caseSensitive: false),
    };
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final s in _songs(d['instrumentals']?['data'], 'instrumental')) {
      final who = songByline(s);
      if (ceremony.hasMatch(who) || _march.hasMatch('${s['title'] ?? ''}')) continue;
      final k = kinds.keys.firstWhere((k) => kinds[k]!.hasMatch(who), orElse: () => 'other');
      groups.putIfAbsent(k, () => []).add(s);
    }
    final lists = groups.values.toList()..sort((a, b) => b.length.compareTo(a.length));
    final out = <Map<String, dynamic>>[];
    for (var i = 0; out.length < 30 && lists.any((l) => i < l.length); i++) {
      for (final l in lists) {
        if (i < l.length && out.length < 30) out.add(l[i]);
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _objects(dynamic data) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final e in _maps(data)) {
      if (e['object'] is! Map) continue;
      final m = Map<String, dynamic>.from(e['object']);
      m['file_type'] = _tn[m['__typename']] ?? 'song';
      if (_playable(m) && seen.add(_key(m))) out.add(m);
    }
    return out;
  }

  void _fetchPersonal(AuthProvider auth, String uid) {
    auth.authedQuery(r'''query($id: ID) { recommendedSongs(user_id: $id, limit: 30) { id title slug image audio_url video_url play_type file_type artists { id title slug } } }''', {'id': uid}).then((d) {
      final out = <Map<String, dynamic>>[];
      for (final m in _maps(d['recommendedSongs'])) {
        if (m['audio_url'] == null && m['video_url'] == null) continue;
        out.add({
          'id': m['id'], 'title': m['title'], 'slug': m['slug'], 'thumbnail': {'url': m['image']},
          'file': {'audio_url': m['audio_url'], 'video_url': m['video_url']}, 'play_type': m['play_type'],
          'file_type': const {'audio': 'song', 'video': 'song'}[m['file_type']] ?? m['file_type'] ?? 'song',
          'artists': {'data': m['artists'] ?? []},
        });
      }
      if (mounted && _personalFor == uid) setState(() => _forYou = out);
    }).catchError((_) {});
    ApiClient.query(r'''query($id: ID!) { a: userTopListens(user_id: $id, type: "artist", period: "month", limit: 3) { id title slug image count } c: userTopListens(user_id: $id, type: "composer", period: "month", limit: 3) { id title slug image count } }''', {'id': uid}).then((d) {
      // Groups ("Tốp ca…", "Hợp ca…") are not "your singer".
      final group = RegExp(r'tốp ca|hợp ca|hợp xướng|dàn nhạc|ban nhạc|đồng ca', caseSensitive: false);
      final a = _maps(d['a']).where((x) => !group.hasMatch('${x['title']}')).toList();
      final c = _maps(d['c']);
      if (mounted && _personalFor == uid) setState(() { _myArtist = a.isEmpty ? null : a.first; _myComposer = c.isEmpty ? null : c.first; });
    }).catchError((_) {});
    // Lâu rồi chưa nghe: loved, but not in the last ~3 months of listening.
    const objs = '__typename ... on Song { $_personal } ... on Folk { $_personal } ... on Instrumental { $_personal } ... on Poem { $_personal }';
    auth.authedQuery('''query(\$id: ID!) { user(id: \$id) {
      loves(first: 100, page: 1, orderBy: [{column: "id", order: DESC}]) { data { created_at object { $objs } } }
      recentListens(first: 300, page: 1, orderBy: [{column: "id", order: DESC}]) { data { created_at object { __typename ... on Song { id } ... on Folk { id } ... on Instrumental { id } ... on Poem { id } } } }
    } }''', {'id': uid}).then((d) {
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      final heard = <String>{};
      for (final e in _maps(d['user']?['recentListens']?['data'])) {
        final at = DateTime.tryParse('${e['created_at'] ?? ''}'.replaceFirst(' ', 'T'));
        final o = e['object'];
        if (at != null && at.isAfter(cutoff) && o is Map) heard.add('${_tn[o['__typename']] ?? 'song'}-${o['id']}');
      }
      final loved = _maps(d['user']?['loves']?['data']).where((e) {
        final at = DateTime.tryParse('${e['created_at'] ?? ''}'.replaceFirst(' ', 'T'));
        return at == null || at.isBefore(cutoff);
      }).toList();
      final out = _objects(loved).where((s) => !heard.contains(_key(s))).toList()..shuffle();
      if (mounted && _personalFor == uid) setState(() => _forgotten = out);
    }).catchError((_) {});
  }

  /// One query: how many songs each period has, and its best-known song's cover.
  Future<void> _fetchEras() async {
    final q = [for (final (i, e) in kEras.indexed) 'e$i: songsByYear(from: ${e.from}, to: ${e.toYear}, first: 1, sort: "views") { data { thumbnail { url } } paginatorInfo { total } }'].join(' ');
    try {
      final d = await ApiClient.query('query { $q }');
      if (!mounted) return;
      setState(() => _eraInfo = [
            for (var i = 0; i < kEras.length; i++)
              ((d['e$i']?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0, _maps(d['e$i']?['data']).firstOrNull?['thumbnail']?['url']?.toString()),
          ]);
    } catch (_) {}
  }

  /// A period's best-known songs, shuffled: "nghe liền mạch" one era.
  Future<List<Map<String, dynamic>>> _eraSongs(int i) async {
    final e = kEras[i];
    final d = await ApiClient.query('query(\$f: Int!, \$t: Int!) { songsByYear(from: \$f, to: \$t, first: 60, sort: "views") { data { $_songFields } } }', {'f': e.from, 't': e.toYear});
    return _songs(d['songsByYear']?['data'])..shuffle();
  }

  Future<List<Map<String, dynamic>>> _personSongs(String type, String slug) async {
    final d = await ApiClient.query('query(\$s: String!) { $type(slug: \$s) { songs(first: 60, orderBy: [{column: "views", order: DESC}]) { data { $_songFields } } } }', {'s': slug});
    return _songs(d[type]?['songs']?['data'])..shuffle();
  }

  Future<void> _fetchDecades() async {
    try {
      final d = await ApiClient.query('query { songYearCounts { year total } }');
      final counts = <int, int>{};
      final years = <int, int>{};
      for (final r in _maps(d['songYearCounts'])) {
        final y = (r['year'] as num?)?.toInt() ?? 0;
        if (y < 1940) continue;
        years[y] = (r['total'] as num?)?.toInt() ?? 0;
        final dec = y >= 2010 ? 2010 : y ~/ 10 * 10;
        counts[dec] = (counts[dec] ?? 0) + ((r['total'] as num?)?.toInt() ?? 0);
      }
      final decs = counts.keys.toList()..sort();
      // The three best-known songs of each decade, in one request.
      final q = decs.map((y) => 'd$y: songsByYear(from: $y, to: ${y == 2010 ? 2100 : y + 10}, first: 3) { data { $_songFields } }').join(' ');
      final t = await ApiClient.query('query { $q }');
      if (!mounted) return;
      setState(() {
        _yearCounts = years;
        _decades = [for (final y in decs) (y, counts[y]!, _songs(t['d$y']?['data']))];
      });
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _decadeSongs(int y) async {
    final d = await ApiClient.query('query { songsByYear(from: $y, to: ${y == 2010 ? 2100 : y + 10}, first: 80) { data { $_songFields } } }');
    return _songs(d['songsByYear']?['data'])..shuffle();
  }

  Future<void> _fetchLatest(int i) async {
    final (_, q) = _cats[i];
    if (_latest[q] != null) return;
    final people = q == 'karaokes' ? 'users(first: 3) { data { id slug: username title: username } }' : 'artists(first: 3) { data { id slug title } }';
    final sheet = q == 'songs' ? 'sheet { composers(first: 2) { data { id slug title } } }' : '';
    try {
      final d = await ApiClient.query('query { $q(first: 7, orderBy: [{column: "id", order: DESC}]) { data { id slug title subtitle views created_at play_type thumbnail { url } file { audio_url video_url duration } uploader { username } $people $sheet } } }');
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

  Future<void> _fetchDocs() async {
    if (_docs != null) return;
    try {
      final d = await ApiClient.query('query { documents(first: 7, orderBy: [{column: "id", order: DESC}]) { data { id title type created_at thumbnail { url } uploader { username } } } }');
      if (mounted) setState(() => _docs = _maps(d['documents']?['data']));
    } catch (_) {
      if (mounted) setState(() => _docs = []);
    }
  }

  Future<void> _fetchTop(int i) async {
    final p = _periods[i].$2;
    if (_top[p] != null) return;
    try {
      if (p == 'today') {
        final d = await ApiClient.query('query { topSongsToday(limit: 7) { $_songFields } }');
        if (mounted) setState(() => _top[p] = _songs(d['topSongsToday']));
      } else {
        final d = await ApiClient.query('query(\$p: String) { statisticListen(period: \$p, type: "song", first: 7) { data { object { ... on Song { $_songFields } } } } }', {'p': p});
        if (mounted) setState(() => _top[p] = [for (final e in _maps(d['statisticListen']?['data'])) if (e['object'] is Map) {...Map<String, dynamic>.from(e['object']), 'file_type': 'song'}].where(_playable).toList());
      }
    } catch (_) {
      if (mounted) setState(() => _top[p] = []);
    }
  }

  /// The big quote: a slideshow of comments marked "cảm nhận hay"
  /// (is_featured), a different set each visit.
  Future<void> _fetchStory() async {
    try {
      final d = await ApiClient.query('query { featuredComments(limit: 8) { id snippet excerpt likes created_at username user_avatar song_id song_title song_image audio_url video_url play_type file_type } }');
      const typenames = {'song': 'Song', 'folk': 'Folk', 'instrumental': 'Instrumental', 'poem': 'Poem', 'karaoke': 'Karaoke'};
      final out = [
        for (final c in _maps(d['featuredComments']))
          if (c['song_id'] != null && '${c['snippet'] ?? ''}'.isNotEmpty)
            {
              'id': c['id'],
              // The hand-picked trích đoạn; else the opening, cut at a sentence.
              'text': '${c['excerpt'] ?? ''}'.trim().isNotEmpty ? '${c['excerpt']}'.trim() : _sentences('${c['snippet']}'),
              'cut': '${c['excerpt'] ?? ''}'.trim().isNotEmpty || '${c['snippet']}'.length > 220,
              'likes': c['likes'],
              'created_at': c['created_at'],
              'user': {'username': c['username'], 'avatar': {'url': c['user_avatar']}},
              'object': {
                '__typename': typenames[c['file_type']] ?? 'Song',
                'id': c['song_id'],
                'title': c['song_title'],
                'thumbnail': {'url': c['song_image']},
                'play_type': c['play_type'],
                'file': {'audio_url': c['audio_url'], 'video_url': c['video_url']},
              },
            },
      ];
      if (out.isEmpty || !mounted) return;
      setState(() { _storyList = out; _storyAt = 0; });
      // Next story every 9s; resting the mouse on it holds it.
      _storyTimer?.cancel();
      if (out.length > 1) {
        _storyTimer = Timer.periodic(const Duration(seconds: 9), (_) {
          if (mounted && !_storyHover) setState(() => _storyAt = (_storyAt + 1) % _storyList.length);
        });
      }
    } catch (_) {}
  }

  /// The small cards: the three newest comments, three different people.
  Future<void> _fetchComments() async {
    try {
      final d = await ApiClient.query('''query { latestComments(first: 30, orderBy: [{column: "created_at", order: DESC}]) { data { id content likes created_at user { id username avatar { url } } object { __typename ... on Song { id title slug thumbnail { url } file { audio_url video_url } } ... on Folk { id title slug thumbnail { url } file { audio_url } } ... on Instrumental { id title slug thumbnail { url } file { audio_url } } ... on Poem { id title slug thumbnail { url } file { audio_url } } } } } }''');
      final seen = <String>{};
      final out = <Map<String, dynamic>>[];
      for (final c in _maps(d['latestComments']?['data'])) {
        final who = '${c['user']?['id'] ?? ''}';
        final obj = c['object'];
        if (who.isEmpty || obj is! Map || obj['title'] == null || !seen.add(who)) continue;
        out.add({...c, 'text': _sentences('${c['content'] ?? ''}')});
        if (out.length == 3) break;
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

  /// Pictures, lyrics, tags still missing across the whole catalogue — the
  /// same totals as the Bàn làm việc queues.
  Future<void> _fetchCtv() async {
    try {
      final d = await ApiClient.query('''query {
        songs(first: 1) { paginatorInfo { total } }
        sheets(first: 1) { paginatorInfo { total } }
        no_image: songs(first: 1, where: {column: "image_id", operator: IS_NULL}) { paginatorInfo { total } }
        no_lyric: songs(first: 1, where: {OR: [{column: "content", operator: IS_NULL}, {column: "content", value: ""}]}) { paginatorInfo { total } }
        no_tag: sheets(first: 1, untagged: true) { paginatorInfo { total } }
      }''');
      int n(String k) => (d[k]?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0;
      if (mounted) setState(() => _ctv = {'songs': n('songs'), 'sheets': n('sheets'), 'no_image': n('no_image'), 'no_lyric': n('no_lyric'), 'no_tag': n('no_tag')});
    } catch (_) {}
  }

  /// The members who gave most (Top cống hiến), faces for Chung tay xây dựng.
  Future<void> _fetchHelpers() async {
    try {
      final d = await ApiClient.query(r'query { topMember(field: "point", first: 18) { data { id username avatar { url } } } }');
      if (mounted) setState(() => _helpers = _maps(d['topMember']?['data']));
    } catch (_) {}
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    if (widget.mobile) return _mobileBuild(context);
    final authed = context.select<AuthProvider, bool>((a) => a.isAuthenticated);
    final name = context.select<AuthProvider, String?>((a) => a.user?['username']?.toString());
    final now = DateTime.now();
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
                Text('${_greeting(now)}${authed && name != null ? ', $name' : ''}', style: display(TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.text))),
                const SizedBox(height: 6),
                _stats(),
                const SizedBox(height: 22),
                LayoutBuilder(builder: (context, cc) {
                  final today = _todayCard(now);
                  final radio = _radioCard(big: true);
                  if (cc.maxWidth < 980) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [today, const SizedBox(height: 20), radio]);
                  return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(flex: 13, child: today), const SizedBox(width: 20), Expanded(flex: 10, child: radio)]));
                }),
                ...(authed ? _forYouBlock() : _guestInvite()),
                const HomeLiveBlock(mobile: false),
                if (_decades.isNotEmpty) ...[_head('Đi qua năm tháng', action: 'Mở Dòng thời gian', onAction: () => context.push('/dong-thoi-gian')), _decadeChart()],
                const SizedBox(height: 48),
                LayoutBuilder(builder: (context, cc) {
                  final latest = _latestCol();
                  final top = _topCol();
                  if (cc.maxWidth < 900) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [latest, const SizedBox(height: 40), top]);
                  return IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(flex: 17, child: latest),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 28), child: VerticalDivider(width: 1, thickness: 1, color: AppColors.border)),
                      Expanded(flex: 10, child: top),
                    ]),
                  );
                }),
                const HomeCollectionsBlock(mobile: false),
                if (_storyList.isNotEmpty || _comments.isNotEmpty) ...[_head('Người nghe kể', action: 'Vào Cộng đồng', onAction: () => context.push('/binh-luan')), _stories()],
                // Ngày này năm xưa | Nghe theo nhạc sĩ side by side; stacked when narrow.
                LayoutBuilder(builder: (context, cc) {
                  const anniv = HomeAnnivBlock(mobile: false);
                  const people = HomeComposersBlock(mobile: false);
                  if (cc.maxWidth < 900) return const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [anniv, people]);
                  return const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 23, child: anniv), SizedBox(width: 40), Expanded(flex: 20, child: people)]);
                }),
                const HomeTopicsBlock(mobile: false),
                if (_ctv.isNotEmpty) _together(),
              ]),
            ),
          ),
        );
      }),
    );
  }

  // ---------- Phone ----------
  /// Trang chủ on a phone, built for listening (search has its own tab): greeting · Đài ·
  /// Dành cho bạn · Theo năm tháng · Mọi người đang nghe · Nghe nhiều · Tuyển
  /// tập · Mới về kho · Ngày này năm xưa · Nghe theo nhạc sĩ · Nghe theo chủ đề.
  Widget _mobileBuild(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final authed = auth.isAuthenticated;
    final name = auth.user?['username']?.toString();
    final unread = (auth.user?['unread'] is num) ? (auth.user!['unread'] as num).toInt() : 0;
    final now = DateTime.now();
    const side = EdgeInsets.symmetric(horizontal: 20);
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accent,
          onRefresh: () async {
            _top.remove(_periods[_period].$2);
            _latest.remove(_cats[_cat].$2);
            await Future.wait([_fetchTop(_period), _fetchLatest(_cat)]);
          },
          child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${weekdaysVi[now.weekday - 1]} · ${now.day} tháng ${now.month}'.toUpperCase(), style: body(TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
                    const SizedBox(height: 2),
                    Text('${_greeting(now)}${authed && name != null ? ', $name' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.text))),
                  ]),
                ),
                const SizedBox(width: 12),
                if (authed)
                  RoundIcon(icon: Icons.notifications_none_rounded, tooltip: 'Thông báo', count: unread, onTap: () => context.push('/thong-bao'))
                else
                  PillButton(label: 'Đăng nhập', height: 38, onTap: () => showDialog(context: context, useRootNavigator: true, builder: (_) => const LoginDialog())),
              ]),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 0), child: _radioCard()),
            if (authed) Padding(padding: side, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _forYouBlock())),
            ..._eraRail(),
            const HomeLiveBlock(mobile: true),
            Padding(padding: const EdgeInsets.fromLTRB(20, 32, 20, 0), child: _topCol()),
            const HomeCollectionsBlock(mobile: true),
            Padding(padding: const EdgeInsets.fromLTRB(20, 32, 20, 0), child: _latestCol()),
            const HomeAnnivBlock(mobile: true),
            const HomeComposersBlock(mobile: true),
            const HomeTopicsBlock(mobile: true),
          ]),
        ),
      ),
    );
  }

  Widget _stats() {
    if (_totals.isEmpty) return const SizedBox(height: 20);
    final mute = body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textMuted));
    final b = body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text));
    return Text.rich(TextSpan(style: mute, children: [
      const TextSpan(text: 'Hôm nay kho có '),
      TextSpan(text: formatInt(_totals['songs']), style: b),
      const TextSpan(text: ' bài hát của '),
      TextSpan(text: formatInt(_totals['composers']), style: b),
      const TextSpan(text: ' nhạc sĩ, '),
      TextSpan(text: formatInt(_totals['artists']), style: b),
      const TextSpan(text: ' nghệ sĩ — và '),
      TextSpan(text: formatInt(_totals['folks']), style: b),
      const TextSpan(text: ' làn điệu dân ca.'),
    ]));
  }

  /// Title row, action at the end.
  Widget _head(String title, {double top = 48, String? action, VoidCallback? onAction}) => Padding(
        padding: EdgeInsets.only(top: top, bottom: 16),
        child: Row(children: [
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text)))),
          if (action != null)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onAction,
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('$action ›', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
            ),
        ]),
      );

  Widget _chips(List<String> labels, int sel, ValueChanged<int> onTap) {
    final chips = [
        for (var i = 0; i < labels.length; i++)
          Material(
            color: i == sel ? AppColors.text : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onTap(i),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Center(widthFactor: 1, child: Text(labels[i], style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: i == sel ? AppColors.bg : AppColors.textSecondary)))),
              ),
            ),
          ),
      ];
    if (!widget.mobile) return Wrap(spacing: 6, runSpacing: 6, children: chips);
    // Phone: one row that scrolls sideways, fading at the right edge so the
    // chips past it read as "more".
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(colors: [Colors.black, Colors.black, Colors.transparent], stops: [0, .88, 1]).createShader(r),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 24),
        child: Row(children: [for (final (i, c) in chips.indexed) Padding(padding: EdgeInsets.only(left: i == 0 ? 0 : 6), child: c)]),
      ),
    );
  }

  Widget _playDot(double size, {Color? bg, Color? fg, bool busy = false}) => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: bg ?? AppColors.wine, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: busy
            ? SizedBox(width: size * 0.4, height: size * 0.4, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg ?? Colors.white))
            : Icon(Icons.play_arrow_rounded, size: size * 0.56, color: fg ?? Colors.white),
      );

  // ---------- Tờ lịch ----------
  Widget _todayCard(DateTime now) {
    final lunar = LunarDate.fromSolar(now);
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
      decoration: BoxDecoration(color: _paper, borderRadius: BorderRadius.circular(24), border: Border.all(color: _paperEdge)),
      // An event gets the tear-off calendar; a plain day lets the song's
      // picture take that place (the date sits in the eyebrow instead).
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (_events.isNotEmpty)
          GestureDetector(
            onTap: () => context.push('/su-kien'),
            child: MouseRegion(cursor: SystemMouseCursors.click, child: _CalendarSheet(weekday: _weekdays[now.weekday - 1], day: now.day, month: now.month, year: now.year, lunar: '${lunar.label.replaceAll(' âm lịch', '')}\nnăm ${_canChi(lunar.year)}')),
          )
        else
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Builder(builder: (_) {
              final a = _todayList.isEmpty ? null : _todayList[_todayAt % _todayList.length].$2;
              if ((_todayList.isEmpty ? null : _todayList[_todayAt % _todayList.length].$1['__event']) case final SiteEvent e) {
                return GestureDetector(
                  key: ValueKey('event-${e.id}'),
                  onTap: () => context.push('/su-kien?id=${e.id}'),
                  child: MouseRegion(cursor: SystemMouseCursors.click, child: EventSheet(day: e.day, month: e.month, year: e.year, size: 176)),
                );
              }
              final shadow = BoxShadow(color: Colors.black.withValues(alpha: AppColors.isLight ? 0.14 : 0.4), blurRadius: 24, offset: const Offset(0, 12));
              // A song on its own keeps the square cover.
              if (a == null) {
                return Container(
                  key: ValueKey(_todayCover()),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: [shadow]),
                  child: NetImage(url: _todayCover(), width: 176, height: 176, radius: 18, tint: true),
                );
              }
              return _Portrait(key: ValueKey(_todayCover()), url: _todayCover(), mourning: _isRecent(a), shadow: shadow);
            }),
          ),
        const SizedBox(width: 26),
        Expanded(child: _events.isNotEmpty ? _eventBody() : _songOfDay(now)),
      ]),
    );
  }

  Widget _eyebrow(String t) => Text(t, style: body(TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: AppColors.textMuted)));

  Widget _outlineButton(String label, VoidCallback onTap) => Material(
        color: AppColors.isLight ? Colors.white : AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: _paperEdge)),
        child: InkWell(customBorder: const StadiumBorder(), onTap: onTap, child: Container(height: 38, padding: const EdgeInsets.symmetric(horizontal: 14), child: Center(widthFactor: 1, child: Text(label, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)))))),
      );

  Widget _playPill(String label, VoidCallback? onTap, {bool busy = false}) => Material(
        color: AppColors.wine,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 5, 16, 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _playDot(28, bg: Colors.white, fg: AppColors.wine, busy: busy),
              const SizedBox(width: 8),
              Text(label, style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white))),
            ]),
          ),
        ),
      );

  /// The picture for the song of the day: the composer's portrait on an
  /// anniversary, else the song's own.
  String? _todayCover() {
    if (_todayList.isEmpty) return null;
    final (s, a) = _todayList[_todayAt % _todayList.length];
    final avatar = a?.person['avatar'];
    return (a != null ? (avatar is Map ? avatar['url'] : null) : (s['thumbnail'] as Map?)?['url'])?.toString();
  }

  Widget _songOfDay(DateTime now) {
    if (_todayList.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _eyebrow('BÀI HÁT HÔM NAY'),
        const SizedBox(height: 12),
        const Skeleton(width: 260, height: 24),
        const SizedBox(height: 10),
        const Skeleton(width: 200, height: 14),
      ]);
    }
    final (s, a) = _todayList[_todayAt % _todayList.length];
    final n = _todayList.length;
    if (s['__event'] case final SiteEvent e) return _eventSlide(e, now, n);
    final composer = _first(s['sheet']?['composers']);
    final poet = _first(s['poets']);
    final year = int.tryParse('${s['sheet']?['year'] ?? ''}');
    final singers = songByline(s);
    final age = year == null ? 0 : now.year - year;
    // Why this song today: the anniversary, or the song's round birthday.
    final recent = a != null && _isRecent(a);
    final yob = a == null ? null : int.tryParse('${a.person['yob'] ?? ''}'.trim());
    final (IconData, Color, String)? why = recent
        ? (Icons.local_florist_rounded, AppColors.textSecondary, '${a.role} ${a.person['title'] ?? ''} vừa qua đời ngày ${a.date.day}/${a.date.month}${yob != null && yob > 1800 ? ', hưởng thọ ${a.date.year - yob} tuổi' : ''}')
        : a != null && a.years > 0
        ? (a.birth ? Icons.cake_rounded : Icons.local_florist_rounded, a.birth ? AppColors.accentFg : AppColors.textSecondary, '${a.years} năm ngày ${a.birth ? 'sinh' : 'mất'} ${a.role.toLowerCase()} ${a.person['title'] ?? ''}')
        : age >= 40 && age % 10 == 0
            ? (Icons.music_note_rounded, AppColors.isLight ? const Color(0xFF9C6B2F) : const Color(0xFFC9965A), 'Tròn $age năm ra đời bài hát ($year)')
            : null;
    Future<void> playNow() async {
      // In memory of someone: their songs, best known first.
      if (recent) {
        final l = await _songsOf(a, 20);
        if (mounted) _play(l.isEmpty ? [s] : l, 'Tưởng nhớ ${a.person['title'] ?? ''}');
        return;
      }
      _play([s], 'Bài hát hôm nay');
    }
    // Someone remembered: straight to their page; a song alone: to the song.
    final String? personRoute = a != null ? '${a.route}${a.person['slug']}' : null;
    final line = [if (composer.isNotEmpty) composer, if (poet.isNotEmpty) 'thơ $poet'].join(' · ');
    return MouseRegion(
      onEnter: (_) => _todayHover = true,
      onExit: (_) => _todayHover = false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: recent ? 'TƯỞNG NHỚ' : 'BÀI HÁT HÔM NAY'),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: body(TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: AppColors.textMuted)),
          ),
        ),
        if (n > 1) _dots(n, _todayAt, (i) => setState(() => _todayAt = i), on: recent ? AppColors.textSecondary : null),
      ]),
      const SizedBox(height: 10),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topLeft, children: [...prev, ?cur]),
        child: Column(key: ValueKey('${s['id']}'), crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // The title plays it too, like the Nghe button.
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: playNow,
                child: Text('${s['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 24, height: 1.15, letterSpacing: -0.4, fontWeight: FontWeight.w800, color: AppColors.text))),
              ),
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: line),
                if (line.isNotEmpty && singers.isNotEmpty) const TextSpan(text: ' · '),
                TextSpan(text: singers, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
            ),
          ]),
        ),
      ]),
      if (why != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: _paperEdge))),
          child: Row(children: [
            Icon(why.$1, size: 15, color: why.$2),
            const SizedBox(width: 6),
            Expanded(child: Text(why.$3, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w500, color: why.$2)))),
          ]),
        ),
      ],
      const SizedBox(height: 18),
      Row(children: [
        _playPill('Nghe', playNow),
        const SizedBox(width: 10),
        personRoute != null
            ? _outlineButton(personRoute.startsWith('/nghe-si/') ? 'Đến nghệ sĩ' : 'Đến nhạc sĩ', () => context.push(personRoute))
            : _outlineButton('Đến bài hát', () => context.push('/song/${s['id']}', extra: s)),
      ]),
        ]),
      ),
    ]),
    );
  }

  /// An event coming up within the month, in the song-of-the-day slideshow.
  Widget _eventSlide(SiteEvent e, DateTime now, int n) {
    final date = e.nextDate(now);
    final days = e.daysUntil(now);
    final years = e.yearsOn(date);
    final when = days == 1 ? 'Ngày mai (${e.day}/${e.month})' : days < 7 ? '${weekdaysVi[date.weekday - 1]} này (${e.day}/${e.month})' : '${weekdaysVi[date.weekday - 1]} ${e.day}/${e.month}';
    return MouseRegion(
      onEnter: (_) => _todayHover = true,
      onExit: (_) => _todayHover = false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: _eyebrow('SỰ KIỆN SẮP TỚI')),
          if (n > 1) _dots(n, _todayAt, (i) => setState(() => _todayAt = i)),
        ]),
        const SizedBox(height: 10),
        Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 24, height: 1.15, letterSpacing: -0.4, fontWeight: FontWeight.w800, color: AppColors.text))),
        const SizedBox(height: 4),
        Text('Tuyển tập ${e.songCount} bài', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: _paperEdge))),
          child: Row(children: [
            Icon(Icons.event_rounded, size: 15, color: AppColors.accentFg),
            const SizedBox(width: 6),
            Expanded(child: Text(years != null && years > 0 ? '$when · $years năm trước, ngày này' : when, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w500, color: AppColors.accentFg)))),
          ]),
        ),
        const SizedBox(height: 18),
        Row(children: [
          _playPill('Nghe', () => _start('event-${e.id}', e.title, () => loadEventSongs(e.id)), busy: _starting == 'event-${e.id}'),
          const SizedBox(width: 10),
          _outlineButton('Đến sự kiện', () => context.push('/su-kien?id=${e.id}')),
        ]),
      ]),
    );
  }

  /// Slideshow dots: the current one a longer wine pill; tap to jump.
  Widget _dots(int n, int at, ValueChanged<int> go, {Color? on}) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < n; i++)
          GestureDetector(
            onTap: () => go(i),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(left: 6),
                width: i == at ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(color: i == at ? (on ?? AppColors.wine) : _paperEdge, borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
      ]);

  String _plain(dynamic html) => '${html ?? ''}'.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// An event running today (event_start ≤ today ≤ event_end) takes the
  /// place of the song of the day; several: "Tiếp: …" flips, wrapping.
  Widget _eventBody() {
    final ev = _events[_eventAt];
    final id = '${ev['id']}';
    final songs = _eventSongs[id] ?? const <Map<String, dynamic>>[];
    final title = '${ev['title'] ?? ''}';
    final desc = _plain(ev['excerpt']).isNotEmpty ? _plain(ev['excerpt']) : _plain(ev['description']);
    final end = '${ev['event_end'] ?? ''}'.split('-');
    final eyebrow = ev['event_start'] != ev['event_end'] && end.length == 2 ? 'HÔM NAY · ĐẾN ${end[1]}/${end[0]}' : 'HÔM NAY';
    void go(int i) {
      setState(() => _eventAt = i % _events.length);
      _fetchEventSongs(_events[_eventAt]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: _eyebrow(eyebrow)),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.push('/su-kien'),
          child: Text('Tất cả sự kiện ›', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
        ),
        if (_events.length > 1) const SizedBox(width: 14),
        if (_events.length > 1)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => go(_eventAt + 1),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text('Tiếp: ${_events[(_eventAt + 1) % _events.length]['title'] ?? ''} ›', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 24, height: 1.15, letterSpacing: -0.4, fontWeight: FontWeight.w800, color: AppColors.text))),
      const SizedBox(height: 8),
      Text(desc.isNotEmpty ? desc : '${(ev['items']?['paginatorInfo']?['total'] as num?)?.toInt() ?? songs.length} bài', maxLines: 3, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
      const SizedBox(height: 14),
      Row(children: [
        _playPill(songs.length > 1 ? 'Phát tất cả' : 'Phát', songs.isEmpty ? null : () => _play(songs, title)),
        const SizedBox(width: 10),
        _outlineButton('Xem playlist', () => context.push('/playlist/$id')),
      ]),
    ]);
  }

  // ---------- Đài ----------
  // ---------- Đài ----------
  /// One frame for both states, only the content changes: before anything
  /// plays the app logo and "Bật một lần, nghe cả ngày"; on air the song,
  /// its singers, live bars and what comes next. [big]: the desktop home,
  /// same card a size up, stretched to the height of Bài hát hôm nay.
  Widget _radioCard({bool big = false}) {
    double z(double phone, double desk) => big ? desk : phone;
    final list = _radio[_ch];
    // Cream type on the radio card, tinted to the colour set (wine ≈ #E3CFCB / #D9B6B0).
    final soft = Color.lerp(AppColors.rose, Colors.white, 0.6)!, muted = Color.lerp(AppColors.rose, Colors.white, 0.45)!;
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;
    final radio = song != null && RadioPresence.isRadio(player);
    final playing = radio && player.isPlaying;
    final next = radio && player.currentIndex + 1 < player.queue.length ? player.queue[player.currentIndex + 1] : null;
    Widget chip(String label, _Ch c) {
      final sel = c == _ch;
      return Material(
        color: sel ? Colors.white : Colors.white.withValues(alpha: 0.10),
        shape: StadiumBorder(side: BorderSide(color: sel ? Colors.white : Colors.white.withValues(alpha: 0.18))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          // Picking a channel tunes in right away; every tap, even on the
          // channel already playing, brings a new random batch.
          onTap: () async {
            if (c != _ch) setState(() => _ch = c);
            await _loadRadio(c);
            if (mounted && _ch == c) _playRadio();
          },
          child: Container(height: z(34, 38), padding: EdgeInsets.symmetric(horizontal: z(13, 15)), child: Center(widthFactor: 1, child: Text(label, style: body(TextStyle(fontSize: z(13, 14), fontWeight: FontWeight.w800, color: sel ? AppColors.wine : const Color(0xFFF3E7E4)))))),
        ),
      );
    }
    final onTap = radio ? player.togglePlay : (list == null || list.isEmpty ? null : _playRadio);
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.symmetric(horizontal: z(16, 24), vertical: z(16, 22)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: RadialGradient(center: const Alignment(0.8, -1.0), radius: 1.4, colors: [Color.lerp(AppColors.wineMid, AppColors.deep, 0.1)!, Color.lerp(AppColors.deep, AppColors.wine, 0.15)!, Color.lerp(AppColors.deep, AppColors.night, 0.35)!], stops: const [0, 0.55, 1]),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: z(16, 18),
          child: Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: const Color(0xFFFF6B5E), shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFFF6B5E).withValues(alpha: 0.25), spreadRadius: 4)])),
            const SizedBox(width: 8),
            Expanded(child: Text(radio ? 'ĐÀI BCĐCNT · ĐANG PHÁT' : 'ĐÀI BCĐCNT · PHÁT 24/7', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: z(11, 12), letterSpacing: z(1.1, 1.2), fontWeight: FontWeight.w800, color: Color.lerp(AppColors.rose, Colors.white, 0.55)!)))),
            ValueListenableBuilder<(int, List<Map<String, dynamic>>)>(
              valueListenable: RadioPresence.instance.listeners,
              // Counting yourself, one is just you: show it from two.
              builder: (context, l, _) => l.$1 < 2 ? const SizedBox.shrink() : Text('${l.$1} đang nghe', style: body(const TextStyle(fontSize: 12, letterSpacing: 0.3, fontWeight: FontWeight.w800, color: Colors.white))),
            ),
          ]),
        ),
        if (!big) const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: z(84, 88),
            child: Row(children: [
              radio
                  ? SongCover(song: song, size: z(84, 88), radius: 14)
                  : Container(width: z(84, 88), height: z(84, 88), decoration: BoxDecoration(color: const Color(0xFFF9F4EA), borderRadius: BorderRadius.circular(14)), alignment: Alignment.center, child: BrandLogo(height: z(56, 60), full: false, onDark: false)),
              SizedBox(width: z(14, 18)),
              Expanded(
                child: radio
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${song['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: z(20, 24), height: 1.2, fontWeight: FontWeight.w800, color: Colors.white))),
                        Text(songByline(song), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: z(14, 15), fontWeight: FontWeight.w600, color: soft))),
                        const SizedBox(height: 6),
                        SizedBox(height: 24, child: Align(alignment: Alignment.centerLeft, child: playing ? const NowPlayingBars(color: Colors.white) : const _StillWave())),
                      ])
                    : Text('Bật một lần,\nnghe cả ngày', maxLines: 2, style: display(TextStyle(fontSize: z(20, 26), height: 1.2, letterSpacing: z(-0.2, -0.3), fontWeight: FontWeight.w800, color: Colors.white))),
              ),
              const SizedBox(width: 10),
              Container(
                width: z(52, 60), height: z(52, 60),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: !radio && list == null
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.wine))
                    : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: z(30, 32), color: AppColors.wine),
              ),
            ]),
          ),
        ),
        if (!big) const SizedBox(height: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: z(16, 18),
          child: Row(children: [
            Text('Kênh', style: body(TextStyle(fontSize: z(12, 13), fontWeight: FontWeight.w700, color: muted))),
            const SizedBox(width: 16),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: next != null
                    ? _Marquee(text: 'Tiếp theo: ${next['title'] ?? ''}${songByline(next).isNotEmpty ? ' · ${songByline(next)}' : ''}', style: body(TextStyle(fontSize: z(12, 13), fontWeight: FontWeight.w700, color: muted)))
                    : Text(radio ? '' : 'Chọn kênh hoặc bấm ▶', maxLines: 1, style: body(TextStyle(fontSize: z(12, 13), fontWeight: FontWeight.w700, color: muted))),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        _SlideRow(children: [
          chip('Tự động', _Ch.auto),
          chip('Tân nhạc', _Ch.all),
          chip('Dân ca', _Ch.folk),
          chip('Không lời', _Ch.instr),
          chip('Tiếng thơ', _Ch.poem),
        ]),
        ]),
      ]),
    );
  }

  // ---------- Theo năm tháng (phone) ----------
  List<Widget> _eraRail() {
    final info = _eraInfo;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Theo năm tháng', style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text))),
          const SizedBox(height: 3),
          Text('Chọn một thời kỳ, nghe liền mạch', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
        ]),
      ),
      SizedBox(
        height: 190,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: kEras.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final e = kEras[i];
            return EraCard(
              era: e,
              count: info?[i].$1,
              image: info?[i].$2,
              busy: _starting == 'era$i',
              onTap: () => context.push('/nam-thang/${e.slug}', extra: {'count': info?[i].$1, 'image': info?[i].$2}),
              onPlay: () => _start('era$i', e.title, () => _eraSongs(i)),
            );
          },
        ),
      ),
    ];
  }

  // ---------- Dành cho bạn ----------
  List<Widget> _forYouBlock() {
    final cards = <Widget>[
      if (_forYou.isNotEmpty)
        _MixCard(
          cover: Stack(fit: StackFit.expand, children: [
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFC79A3E), Color(0xFF7A5414)]))),
            Positioned(right: 18, top: 12, child: Icon(Icons.auto_awesome_rounded, size: 72, color: Colors.white.withValues(alpha: 0.28))),
          ]),
          eyebrow: 'GỢI Ý HÔM NAY',
          title: '${_forYou.length} bài bạn chưa nghe',
          sub: 'Hợp gu bạn · đổi mỗi sáng',
          busy: false,
          onPlay: () => _play(_forYou, 'Gợi ý hôm nay'),
        ),
      if (_myArtist != null)
        _MixCard(
          cover: NetImage(url: _myArtist!['image']?.toString(), tint: true),
          eyebrow: 'GIỌNG CA CỦA BẠN',
          title: '${_myArtist!['title'] ?? ''}',
          sub: 'Nghe nhiều nhất tháng này · ${_myArtist!['count'] ?? 0} lượt',
          busy: _starting == 'artist',
          onPlay: () => _start('artist', 'Giọng ca ${_myArtist!['title'] ?? ''}', () => _personSongs('artist', '${_myArtist!['slug']}')),
        ),
      if (_myComposer != null)
        _MixCard(
          cover: NetImage(url: _myComposer!['image']?.toString(), tint: true),
          eyebrow: 'NHẠC SĨ CỦA BẠN',
          title: '${_myComposer!['title'] ?? ''}',
          sub: '${_myComposer!['count'] ?? 0} lượt tháng này · phát cả kho',
          busy: _starting == 'composer',
          onPlay: () => _start('composer', 'Nhạc sĩ ${_myComposer!['title'] ?? ''}', () => _personSongs('composer', '${_myComposer!['slug']}')),
        ),
      if (_forgotten.length >= 5)
        _MixCard(
          cover: _Mosaic(songs: _forgotten.take(4).toList(), sepia: true),
          eyebrow: 'LÂU RỒI CHƯA NGHE',
          title: '${_forgotten.length} bài bạn từng thích',
          sub: 'Hơn 3 tháng chưa mở lại',
          busy: false,
          onPlay: () => _play(_forgotten, 'Lâu rồi chưa nghe'),
        ),
    ];
    if (cards.isEmpty) return const [];
    return [
      _head('Dành cho bạn', top: 40),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth < 760 ? 2 : 4;
        final w = (c.maxWidth - (cols - 1) * 18) / cols;
        return Wrap(spacing: 18, runSpacing: 18, children: [for (final x in cards) SizedBox(width: w, child: x)]);
      }),
    ];
  }

  List<Widget> _guestInvite() => [
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            for (final (c1, c2, icon) in const [(Color(0xFFC79A3E), Color(0xFF7A5414), Icons.auto_awesome_rounded), (Color(0xFFC0392B), Color(0xFF711313), Icons.favorite_rounded)]) ...[
              Container(width: 64, height: 64, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(colors: [c1, c2])), child: Icon(icon, size: 28, color: Colors.white)),
              const SizedBox(width: 10),
            ],
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dành cho bạn', style: body(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
                const SizedBox(height: 4),
                Text('Đăng nhập để có gợi ý theo gu nghe, lưu bài yêu thích và nghe tiếp từ chỗ đã dừng.', style: body(TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
              ]),
            ),
            const SizedBox(width: 16),
            PillButton(label: 'Đăng nhập', height: 44, onTap: () => showDialog(context: context, useRootNavigator: true, builder: (_) => const LoginDialog())),
            const SizedBox(width: 10),
            PillButton(label: 'Đăng ký', height: 44, primary: false, onTap: () => showDialog(context: context, useRootNavigator: true, builder: (_) => const RegisterDialog())),
          ]),
        ),
      ];

  // ---------- Đi qua năm tháng ----------
  static String _decadeName(int y) => y == 2010 ? 'Từ 2010' : (y >= 2000 ? '2000–09' : 'Thập niên ${y % 100}');

  Widget _decadeChart() {
    final max = _decades.map((d) => d.$2).reduce((a, b) => a > b ? a : b);
    final lo = AppColors.isLight ? Color.lerp(AppColors.bg, AppColors.rose, 0.22)! : Color.lerp(AppColors.surfaceLight, AppColors.rose, 0.12)!;
    final hi = AppColors.isLight ? Color.lerp(AppColors.rose, AppColors.wine, 0.35)! : Color.lerp(AppColors.wine, AppColors.rose, 0.3)!;
    // The decade of the song playing gets a pulsing dot.
    return Selector<PlayerProvider, int?>(
      selector: (_, p) {
        final s = p.currentSong;
        final y = int.tryParse('${s?['sheet']?['year'] ?? s?['year'] ?? ''}');
        return y == null || y < 1940 ? null : (y >= 2010 ? 2010 : y ~/ 10 * 10);
      },
      builder: (context, playingDec, _) => _decadeBox(max, lo, hi, playingDec),
    );
  }

  Widget _decadeBox(int max, Color lo, Color hi, int? playingDec) {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 18),
      decoration: BoxDecoration(color: AppColors.isLight ? Color.lerp(AppColors.bg, AppColors.surface, 0.5) : AppColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.borderSubtle)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (i, (y, n, songs)) in _decades.indexed) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(
              child: _DecadeBar(
                decade: y,
                label: _decadeName(y),
                count: n,
                songs: songs,
                years: [for (var k = y; k < (y == 2010 ? DateTime.now().year + 1 : y + 10); k++) (k, _yearCounts[k] ?? 0)],
                height: (96 * n / max).clamp(6, 96).toDouble(),
                color: Color.lerp(lo, hi, (n / max))!,
                busy: _starting == 'dec$y',
                playing: playingDec == y,
                popLeft: i >= _decades.length - 3,
                onTap: () => _start('dec$y', _decadeName(y), () => _decadeSongs(y)),
                onPlaySong: (list, at) => _play(list, _decadeName(y), at),
                onMore: () => context.push('/dong-thoi-gian'),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 18),
        _EraBand(first: _decades.first.$1, onTap: (e) => context.push('/nam-thang/${e.slug}')),
      ]),
    );
  }

  // ---------- Mới về kho | Nghe nhiều ----------
  Widget _listRow(Map<String, dynamic> s, List<Map<String, dynamic>> list, int i, String label, {Widget? lead, required String sub}) => draggableSong(context, s, _HoverRow(
        onTap: () => _play(list, label, i),
        onMore: () => showSongActions(context, s),
        lead: lead,
        cover: SongCover(song: s, size: 44, radius: 10),
        title: '${s['title'] ?? ''}',
        sub: sub,
        last: i == list.length - 1,
      ));

  Widget _latestCol() {
    final docs = _cat == _cats.length;
    final list = docs ? null : _latest[_cats[_cat].$2]?.take(widget.mobile ? 5 : 99).toList();
    Widget content;
    if (docs) {
      content = _docsList();
    } else if (list == null) {
      content = Column(children: [for (var i = 0; i < 6; i++) const SkeletonSongRow()]);
    } else if (list.isEmpty) {
      content = Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Chưa tải được, thử lại sau.', style: AppText.bodyText));
    } else {
      final label = 'Mới về kho · ${_cats[_cat].$1}';
      content = Column(children: [
        for (var i = 0; i < list.length; i++)
          _listRow(list[i], list, i, label, sub: [
            songByline(list[i], withComposer: _cat == 0 && songByline(list[i]).isEmpty),
            if (list[i]['uploader']?['username'] != null) '${list[i]['uploader']['username']}',
            _postedAgo(list[i]['created_at']?.toString()),
          ].where((x) => x.isNotEmpty).join(' · ')),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _head('Mới về kho', top: 0, action: 'Xem tất cả', onAction: () => context.push(docs ? '/tu-lieu' : '/the-loai/${_catSlugs[_cat]}')),
      _chips([for (final (l, _) in _cats) l, 'Tư liệu'], _cat, (i) {
        setState(() => _cat = i);
        i < _cats.length ? _fetchLatest(i) : _fetchDocs();
      }),
      const SizedBox(height: 10),
      content,
    ]);
  }

  Widget _docsList() {
    final list = _docs?.take(widget.mobile ? 5 : 99).toList();
    if (list == null) return Column(children: [for (var i = 0; i < 6; i++) const SkeletonSongRow()]);
    const kinds = {'image': ('Ảnh', Icons.image_outlined), 'audio': ('Âm thanh', Icons.graphic_eq_rounded), 'video': ('Video', Icons.videocam_outlined), 'news': ('Bài viết', Icons.article_outlined), 'sheet': ('Bản nhạc', Icons.library_music_outlined)};
    return Column(children: [
      for (final (i, d) in list.indexed)
        Builder(builder: (context) {
          final k = kinds['${d['type']}'] ?? ('Tư liệu', Icons.folder_outlined);
          final thumb = d['thumbnail']?['url']?.toString();
          return _HoverRow(
            onTap: () => context.push('/tu-lieu/chi-tiet/${d['id']}'),
            cover: thumb != null
                ? NetImage(url: thumb, width: 44, height: 44, radius: 10, tint: true)
                : Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)), child: Icon(k.$2, color: AppColors.textMuted)),
            title: '${d['title'] ?? ''}',
            sub: [k.$1, if (d['uploader']?['username'] != null) '${d['uploader']['username']}', _postedAgo(d['created_at']?.toString())].where((x) => x.isNotEmpty).join(' · '),
            last: i == list.length - 1,
          );
        }),
    ]);
  }

  Widget _topCol() {
    final p = _periods[_period].$2;
    final list = _top[p]?.take(widget.mobile ? 5 : 99).toList();
    Widget content;
    if (list == null) {
      content = Column(children: [for (var i = 0; i < 6; i++) const SkeletonSongRow()]);
    } else if (list.isEmpty) {
      content = Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Chưa có số liệu.', style: AppText.bodyText));
    } else {
      final label = 'Nghe nhiều · ${_periods[_period].$1}';
      content = Column(children: [
        for (var i = 0; i < list.length; i++)
          _HoverRow(
            onTap: () => _play(list, label, i),
            onMore: () => showSongActions(context, list[i]),
            lead: SizedBox(width: widget.mobile ? 20 : 28, child: Text('${i + 1}', textAlign: TextAlign.center, style: display(TextStyle(fontSize: widget.mobile ? 18 : (i < 3 ? 24 : 20), fontWeight: FontWeight.w800, letterSpacing: -1, color: i < 3 ? AppColors.accentFg : AppColors.textMuted.withValues(alpha: 0.6))))),
            // A cover per song, like Mới về kho beside it.
            cover: SongCover(song: list[i], size: 44, radius: 10),
            title: '${list[i]['title'] ?? ''}',
            sub: songByline(list[i]).isNotEmpty ? songByline(list[i]) : songByline(list[i], withComposer: true),
            last: i == list.length - 1,
          ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _head('Nghe nhiều', top: 0, action: 'Bảng xếp hạng', onAction: () => context.push('/bang-xep-hang')),
      _chips([for (final (l, _) in _periods) l], _period, (i) {
        setState(() => _period = i);
        _fetchTop(i);
      }),
      const SizedBox(height: 10),
      content,
    ]);
  }

  // ---------- Người nghe kể ----------
  void _openObject(Map<String, dynamic> obj, {String? commentId}) {
    final kind = _tn['${obj['__typename']}'] ?? 'song';
    // Mọi loại bản thu đi chung route /song/:id; loại nằm trong extra.file_type.
    context.push(commentId != null ? '/song/${obj['id']}?binh-luan=1' : '/song/${obj['id']}', extra: {...obj, 'file_type': kind, 'highlightCommentId': ?commentId});
  }

  Widget _likes(Map c, {double size = 18}) {
    final n = (c['likes'] as num?)?.toInt() ?? 0;
    if (n <= 0) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.favorite_border_rounded, size: size, color: AppColors.textMuted),
      const SizedBox(width: 5),
      Text('$n', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
    ]);
  }

  Widget _stories() {
    final big = _storyList.isNotEmpty ? _storyList[_storyAt % _storyList.length] : _comments.first;
    final rest = _comments.where((c) => '${c['id']}' != '${big['id']}').take(3).toList();
    final obj = Map<String, dynamic>.from(big['object'] as Map);
    final n = _storyList.length;
    final dots = _dots(n, _storyAt, (i) => setState(() => _storyAt = i));
    final quote = MouseRegion(
      onEnter: (_) => _storyHover = true,
      onExit: (_) => _storyHover = false,
      child: Container(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 24),
      decoration: BoxDecoration(color: _paper, borderRadius: BorderRadius.circular(24), border: Border.all(color: _paperEdge)),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        layoutBuilder: (cur, prev) => Stack(children: [...prev, ?cur]),
        child: Column(key: ValueKey('${big['id']}'), crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('“', style: TextStyle(fontFamily: 'Georgia', fontFamilyFallback: const ['Times New Roman', 'serif'], fontSize: 84, height: 0.6, fontWeight: FontWeight.w700, color: AppColors.isLight ? const Color(0xFFD8B9B3) : const Color(0xFF5A3A38))),
          const Spacer(),
          if (n > 1) Padding(padding: const EdgeInsets.only(top: 6), child: dots),
        ]),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _openObject(obj, commentId: '${big['id']}'),
          // Longer trích đoạn: a little smaller so ~280 chars still fit.
          child: Text('${big['text']}', maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Georgia', fontFamilyFallback: const ['Times New Roman', 'serif'], fontSize: '${big['text']}'.length > 180 ? 18 : 21, height: 1.5, fontWeight: FontWeight.w600, color: AppColors.text)),
        ),
        if (big['cut'] == true) ...[
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _openObject(obj, commentId: '${big['id']}'),
            child: Text('Đọc toàn bộ ›', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
          ),
        ],
        const Spacer(),
        const SizedBox(height: 18),
        Row(children: [
          UserAvatar(url: big['user']?['avatar']?['url']?.toString(), name: '${big['user']?['username'] ?? ''}', size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${big['user']?['username'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text))),
              Row(children: [
                Text(timeago(big['created_at']?.toString()), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                const SizedBox(width: 8),
                _likes(big),
              ]),
            ]),
          ),
          Material(
            color: AppColors.isLight ? Colors.white : AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: _paperEdge)),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openObject(obj),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  NetImage(url: obj['thumbnail']?['url']?.toString(), width: 32, height: 32, radius: 8, tint: true),
                  const SizedBox(width: 10),
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: Text('${obj['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)))),
                  const SizedBox(width: 10),
                  if (_playable(obj)) InkWell(customBorder: const CircleBorder(), onTap: () => _play([{...obj, 'file_type': _tn['${obj['__typename']}'] ?? 'song'}], 'Người nghe kể'), child: _playDot(30, bg: AppColors.accentSoft, fg: AppColors.accentFg)),
                ]),
              ),
            ),
          ),
        ]),
      ]),
      ),
    ),
    );
    Widget small(Map<String, dynamic> c) {
      final o = Map<String, dynamic>.from(c['object'] as Map);
      return Expanded(
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.border)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openObject(o, commentId: '${c['id']}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  UserAvatar(url: c['user']?['avatar']?['url']?.toString(), name: '${c['user']?['username'] ?? ''}', size: 28),
                  const SizedBox(width: 10),
                  Text('${c['user']?['username'] ?? ''}', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text))),
                  const SizedBox(width: 8),
                  Text(timeago(c['created_at']?.toString()), style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${o['title'] ?? ''}', textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accentFg)))),
                ]),
                const SizedBox(height: 7),
                Text('${c['text']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w600, color: AppColors.text))),
              ]),
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900 || rest.isEmpty) return SizedBox(height: 300, child: quote);
      return SizedBox(
        height: 330,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 13, child: quote),
          const SizedBox(width: 20),
          Expanded(flex: 10, child: Column(children: [for (final (i, x) in rest.indexed) ...[if (i > 0) const SizedBox(height: 12), small(x)]])),
        ]),
      );
    });
  }

  // ---------- Chung tay xây dựng ----------
  Widget _together() {
    int pct(String done, String total) {
      final t = _ctv[total] ?? 0;
      return t <= 0 ? 0 : (100 * (t - (_ctv[done] ?? 0)) / t).round().clamp(0, 100);
    }
    final pink = AppColors.isLight ? Color.lerp(AppColors.bg, AppColors.rose, 0.07)! : Color.lerp(AppColors.surface, AppColors.rose, 0.05)!;
    final pinkEdge = AppColors.isLight ? Color.lerp(AppColors.bg, AppColors.rose, 0.22)! : Color.lerp(AppColors.surfaceLight, AppColors.rose, 0.12)!;
    final items = [
      (Icons.image_rounded, _ctv['no_image'] ?? 0, 'bài chờ ảnh minh hoạ', pct('no_image', 'songs'), 'Thêm ảnh', 'no_image'),
      (Icons.description_rounded, _ctv['no_lyric'] ?? 0, 'bài chờ chép lời', pct('no_lyric', 'songs'), 'Chép lời', 'no_lyric'),
      (Icons.sell_rounded, _ctv['no_tag'] ?? 0, 'bản nhạc chờ gắn tag', pct('no_tag', 'sheets'), 'Gắn tag', 'no_tag'),
    ];
    Widget meter((IconData, int, String, int, String, String) m) => Expanded(
          child: Material(
            color: AppColors.isLight ? Colors.white : AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: pinkEdge)),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push('/ban-lam-viec?q=${m.$6}&s=new'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 34, height: 34, decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(10)), child: Icon(m.$1, size: 18, color: AppColors.accentFg)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(formatInt(m.$2), style: display(TextStyle(fontSize: 22, height: 1.1, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
                        // Narrow beside the faces: the line shrinks rather than losing words.
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(m.$3, maxLines: 1, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)))),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: m.$4 / 100, minHeight: 6, backgroundColor: AppColors.accentSoft, color: AppColors.accentLight)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Text('Đã xong ${m.$4}%', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                    const Spacer(),
                    Text('${m.$5} ›', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
                  ]),
                ]),
              ),
            ),
          ),
        );
    // Top cống hiến, face by face in a grid as tall as the meters beside it.
    Widget face(Map<String, dynamic> u, double size) => Tooltip(
          message: '${u['username'] ?? ''}',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.push('/user/${u['id']}'),
            child: UserAvatar(url: u['avatar']?['url']?.toString(), name: '${u['username'] ?? ''}', size: size),
          ),
        );
    Widget faces() {
      const cols = 6, size = 36.0;
      final rows = [for (var r = 0; r * cols < _helpers.length && r < 3; r++) _helpers.skip(r * cols).take(cols).toList()];
      return Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final row in rows)
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var k = 0; k < cols; k++) k < row.length ? face(row[k], size) : const SizedBox(width: size),
          ]),
      ]);
    }
    final head = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Text('CHUNG TAY XÂY DỰNG', style: body(TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
        const Spacer(),
        InkWell(
          onTap: () => context.push('/bang-xep-hang/cong-hien'),
          child: Text('Top cống hiến ›', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
        ),
      ]),
    );
    final meters = [for (final (i, m) in items.indexed) ...[if (i > 0) const SizedBox(width: 18), meter(m)]];
    return Container(
      margin: const EdgeInsets.only(top: 48),
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 24),
      decoration: BoxDecoration(color: pink, borderRadius: BorderRadius.circular(24), border: Border.all(color: pinkEdge)),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 900;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          head,
          if (narrow && _helpers.isNotEmpty) ...[SizedBox(height: 132, child: faces()), const SizedBox(height: 16)],
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!narrow && _helpers.isNotEmpty) ...[SizedBox(width: 280, child: faces()), const SizedBox(width: 18)],
              ...meters,
            ]),
          ),
        ]);
      }),
    );
  }
}

/// A calendar page: weekday band, the day, month and year, lunar date.
class _CalendarSheet extends StatelessWidget {
  final String weekday, lunar;
  final int day, month, year;
  const _CalendarSheet({required this.weekday, required this.day, required this.month, required this.year, required this.lunar});

  @override
  Widget build(BuildContext context) {
    final sheet = AppColors.isLight ? Colors.white : AppColors.surfaceLight;
    return SizedBox(
      width: 148,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          decoration: BoxDecoration(color: sheet, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: AppColors.isLight ? 0.10 : 0.4), blurRadius: 22, offset: const Offset(0, 10))]),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(color: AppColors.wine, height: 36, alignment: Alignment.center, child: Text(weekday.toUpperCase(), style: body(const TextStyle(fontSize: 13, letterSpacing: 1.5, fontWeight: FontWeight.w800, color: Colors.white)))),
            Padding(padding: const EdgeInsets.only(top: 12), child: Text('$day', style: display(TextStyle(fontSize: 72, height: 1, letterSpacing: -3, fontWeight: FontWeight.w800, color: AppColors.text)))),
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('tháng $month, $year', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)))),
            Container(margin: const EdgeInsets.fromLTRB(16, 10, 16, 0), height: 1, color: AppColors.border),
            Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 14), child: Text(lunar, textAlign: TextAlign.center, style: body(TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w700, color: AppColors.textMuted)))),
          ]),
        ),
        // The two rings it hangs from.
        for (final x in [38.0, 100.0]) Positioned(left: x, top: -7, child: Container(width: 10, height: 16, decoration: BoxDecoration(color: AppColors.isLight ? const Color(0xFF5A2A26) : const Color(0xFF8A5A56), borderRadius: BorderRadius.circular(5)))),
      ]),
    );
  }
}

/// "Dành cho bạn": a 16:10 cover with the name on it; ▶ shows on hover.
class _MixCard extends StatefulWidget {
  final Widget cover;
  final String eyebrow, title, sub;
  final bool busy;
  final VoidCallback onPlay;
  const _MixCard({required this.cover, required this.eyebrow, required this.title, required this.sub, required this.busy, required this.onPlay});
  @override
  State<_MixCard> createState() => _MixCardState();
}

class _MixCardState extends State<_MixCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPlay,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: _hover ? [BoxShadow(color: const Color(0xFF3C1414).withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 8))] : const []),
                child: Stack(fit: StackFit.expand, children: [
                  widget.cover,
                  const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB8140606)], stops: [0.4, 1]))),
                  Positioned(
                    left: 14, right: 64, bottom: 12,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.eyebrow, style: body(TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.85)))),
                      const SizedBox(height: 2),
                      Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 18, height: 1.2, fontWeight: FontWeight.w800, color: Colors.white))),
                    ]),
                  ),
                  Positioned(
                    right: 10, bottom: 10,
                    child: AnimatedOpacity(
                      opacity: _hover || widget.busy ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(color: AppColors.wine, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: widget.busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)) : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text(widget.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)))),
          ]),
        ),
      );
}

/// Four covers in a square grid.
class _Mosaic extends StatelessWidget {
  final List<Map<String, dynamic>> songs;
  final bool sepia;
  const _Mosaic({required this.songs, this.sepia = false});
  @override
  Widget build(BuildContext context) {
    Widget cell(int i) => i < songs.length
        ? NetImage(url: songs[i]['thumbnail']?['url']?.toString(), tint: true)
        : Container(color: AppColors.surface);
    final grid = Column(children: [
      Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: cell(0)), Expanded(child: cell(1))])),
      Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: cell(2)), Expanded(child: cell(3))])),
    ]);
    if (!sepia || !context.select<ThemeProvider, bool>((t) => t.tintPhotos)) return grid;
    return ColorFiltered(colorFilter: const ColorFilter.matrix([0.39, 0.77, 0.19, 0, 0, 0.35, 0.69, 0.17, 0, 0, 0.27, 0.53, 0.13, 0, 0, 0, 0, 0, 1, 0]), child: grid);
  }
}

class _DecadeBar extends StatefulWidget {
  final int decade, count;
  final String label;
  final List<Map<String, dynamic>> songs;
  final List<(int, int)> years;
  final double height;
  final Color color;
  final bool busy, playing, popLeft;
  final VoidCallback onTap, onMore;
  final void Function(List<Map<String, dynamic>> list, int at) onPlaySong;
  const _DecadeBar({required this.decade, required this.label, required this.count, required this.songs, required this.years, required this.height, required this.color, required this.busy, required this.playing, required this.popLeft, required this.onTap, required this.onPlaySong, required this.onMore});
  @override
  State<_DecadeBar> createState() => _DecadeBarState();
}

/// One decade: the bar (taller, with songs per year, on hover), its
/// best-known song under the name, and on hover a card beside it with the
/// three best-known songs and Phát thập niên.
class _DecadeBarState extends State<_DecadeBar> {
  final _link = LayerLink();
  final _pop = OverlayPortalController();
  Timer? _hide;
  bool _hover = false, _coverHover = false;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _enter() {
    _hide?.cancel();
    if (!_hover) setState(() => _hover = true);
    if (!_pop.isShowing && widget.songs.isNotEmpty) _pop.show();
  }

  // A short grace so the pointer can travel from the bar onto the card.
  void _leave() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      setState(() => _hover = false);
      if (_pop.isShowing) _pop.hide();
    });
  }

  Widget _card() {
    final peak = widget.years.fold<(int, int)>((0, 0), (a, b) => b.$2 > a.$2 ? b : a);
    final to = widget.decade == 2010 ? 'nay' : '${widget.decade + 9}';
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _leave(),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 340,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          // Floats over the chart's pale panel: solid white, a firm edge and
          // a deep shadow so it never melts into the page.
          decoration: BoxDecoration(
            color: AppColors.isLight ? Colors.white : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.isLight ? Color.lerp(AppColors.bg, AppColors.rose, 0.25)! : AppColors.border),
            boxShadow: [
              BoxShadow(color: const Color(0xFF280A0A).withValues(alpha: AppColors.isLight ? 0.22 : 0.5), blurRadius: 36, offset: const Offset(0, 16)),
              BoxShadow(color: const Color(0xFF280A0A).withValues(alpha: AppColors.isLight ? 0.08 : 0.3), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${widget.decade}–$to · ${formatInt(widget.count)} BÀI', style: body(TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
            if (peak.$2 > 0) ...[
              const SizedBox(height: 2),
              Text('Nhiều nhất năm ${peak.$1} · ${formatInt(peak.$2)} bài', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            ],
            const SizedBox(height: 6),
            for (final (i, s) in widget.songs.indexed)
              _PopSongRow(song: s, onTap: () => widget.onPlaySong(widget.songs, i)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: PillButton(onTap: widget.onTap, icon: Icons.play_arrow, label: 'Phát tất cả', primary: true, height: 36)),
              const SizedBox(width: 8),
              PillButton(onTap: widget.onMore, label: 'Xem tất cả ›', primary: false, height: 36),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.songs.firstOrNull;
    final grow = _hover ? 40.0 : 0.0;
    return OverlayPortal(
      controller: _pop,
      overlayChildBuilder: (_) => Positioned(
        left: 0, top: 0,
        child: CompositedTransformFollower(
          link: _link,
          targetAnchor: widget.popLeft ? Alignment.topLeft : Alignment.topRight,
          followerAnchor: widget.popLeft ? Alignment.topRight : Alignment.topLeft,
          offset: Offset(widget.popLeft ? -12 : 12, 0),
          child: _card(),
        ),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _enter(),
        onExit: (_) => _leave(),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: widget.onTap,
            child: SizedBox(
              height: 172,
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                SizedBox(
                  height: 22,
                  child: widget.busy
                      ? Center(child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentFg)))
                      : Text(formatInt(widget.count), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _hover ? AppColors.accentFg : AppColors.textMuted))),
                ),
                const SizedBox(height: 4),
                CompositedTransformTarget(
                  link: _link,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    height: widget.height + grow,
                    decoration: BoxDecoration(
                      color: _hover ? AppColors.wine : widget.color,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12), bottom: Radius.circular(3)),
                    ),
                    child: Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
                      if (_hover) Padding(padding: const EdgeInsets.fromLTRB(8, 18, 8, 8), child: _YearSpark(years: widget.years)),
                      if (widget.playing) const Positioned(top: -7, right: 10, child: _PlayingDot()),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(onTap: widget.onTap, child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)))),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: song == null
                ? null
                : GestureDetector(
                    onTap: () => widget.onPlaySong([song], 0),
                    child: Row(children: [
                      MouseRegion(
                        onEnter: (_) => setState(() => _coverHover = true),
                        onExit: (_) => setState(() => _coverHover = false),
                        child: Stack(children: [
                          SongCover(song: song, size: 30, radius: 7),
                          if (_coverHover)
                            Container(width: 30, height: 30, decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${song['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w700, color: AppColors.textMuted)))),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _PopSongRow extends StatefulWidget {
  final Map<String, dynamic> song;
  final VoidCallback onTap;
  const _PopSongRow({required this.song, required this.onTap});
  @override
  State<_PopSongRow> createState() => _PopSongRowState();
}

class _PopSongRowState extends State<_PopSongRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final s = widget.song;
    final by = songByline(s).isNotEmpty ? songByline(s) : songByline(s, withComposer: true);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(color: _hover ? AppColors.surface.withValues(alpha: 0.7) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            SongCover(song: s, size: 40, radius: 8),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text))),
                Text([by, if (s['views'] != null) '${formatViews((s['views'] as num).toInt())} lượt nghe'].where((x) => x.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: _hover ? AppColors.wine : AppColors.wine.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(Icons.play_arrow_rounded, size: 18, color: _hover ? Colors.white : AppColors.accentFg),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Songs per year across a decade, as a white line inside the hovered bar,
/// the busiest year named above its peak.
class _YearSpark extends StatelessWidget {
  final List<(int, int)> years;
  const _YearSpark({required this.years});
  @override
  Widget build(BuildContext context) {
    if (years.length < 2) return const SizedBox.shrink();
    final peak = years.indexed.fold<(int, (int, int))>((0, years.first), (a, b) => b.$2.$2 > a.$2.$2 ? b : a);
    return LayoutBuilder(builder: (context, c) {
      final x = c.maxWidth * peak.$1 / (years.length - 1);
      return Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: CustomPaint(painter: _SparkPainter([for (final y in years) y.$2.toDouble()]))),
        if (peak.$2.$2 > 0)
          Positioned(left: (x - 14).clamp(0, c.maxWidth - 28), top: -14, child: Text('${peak.$2.$1}', style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)))),
      ]);
    });
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> v;
  _SparkPainter(this.v);
  @override
  void paint(Canvas canvas, Size size) {
    final m = v.reduce((a, b) => a > b ? a : b);
    if (m <= 0) return;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final p = Offset(size.width * i / (v.length - 1), size.height * (1 - v[i] / m));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.v != v;
}

/// The red dot over the decade of the song playing, breathing slowly.
class _PlayingDot extends StatefulWidget {
  const _PlayingDot();
  @override
  State<_PlayingDot> createState() => _PlayingDotState();
}

class _PlayingDotState extends State<_PlayingDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          width: 14, height: 14,
          decoration: BoxDecoration(color: const Color(0xFFC8312B), shape: BoxShape.circle, boxShadow: [
            BoxShadow(color: const Color(0xFFC8312B).withValues(alpha: 0.28 * (1 - _c.value)), spreadRadius: 2 + 8 * _c.value),
          ]),
        ),
      );
}

/// The six periods under the decades, each in its own colour (as on the phone),
/// with the turning years below; a tap opens the period's page.
class _EraBand extends StatelessWidget {
  final int first;
  final void Function(Era) onTap;
  const _EraBand({required this.first, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final start = first.toDouble(), end = 2020.0;
    return LayoutBuilder(builder: (context, c) {
      double x(num y) => c.maxWidth * ((y.clamp(start, end) - start) / (end - start));
      return SizedBox(
        height: 50,
        child: Stack(children: [
          for (final e in kEras)
            if (x(e.toYear) - x(e.from) > 4)
              Positioned(
                left: x(e.from) + 1, width: x(e.toYear) - x(e.from) - 2, top: 0, height: 30,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => onTap(e),
                    child: Tooltip(
                      message: '${e.title} · ${e.years}',
                      child: Container(
                        decoration: BoxDecoration(color: eraBg(e.style), borderRadius: BorderRadius.circular(8)),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            // Short periods are narrow: the name shrinks instead of losing letters.
                            child: Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: Text(e.name, maxLines: 1, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: eraFg(e.style)))))),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          for (final y in [for (final e in kEras.skip(1)) e.from])
            if (y > start && y < end)
              Positioned(left: x(y) - 20, width: 40, top: 34, child: Text('$y', textAlign: TextAlign.center, style: body(TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted)))),
        ]),
      );
    });
  }
}

/// A 64px list row: cover (▶ over it on hover), title, one grey line,
/// ♡ and ⋯ on hover.
class _HoverRow extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final Widget? lead;
  final Widget? cover;
  final String title, sub;
  final bool last;
  const _HoverRow({required this.onTap, this.onMore, this.lead, this.cover, required this.title, required this.sub, this.last = false});
  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTap: widget.onMore,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: _hover ? AppColors.surface.withValues(alpha: 0.7) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            foregroundDecoration: BoxDecoration(border: widget.last || _hover ? null : Border(bottom: BorderSide(color: AppColors.borderSubtle))),
            child: Row(children: [
              if (widget.lead != null) ...[widget.lead!, const SizedBox(width: 14)],
              if (widget.cover != null) ...[
                Stack(children: [
                  widget.cover!,
                  if (_hover)
                    Positioned.fill(child: Container(decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.play_arrow_rounded, color: Colors.white))),
                ]),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
                  if (widget.sub.isNotEmpty) Text(widget.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                ]),
              ),
              if (widget.onMore != null)
                Opacity(
                  opacity: _hover ? 1 : 0.55,
                  child: IconButton(tooltip: 'Tuỳ chọn', onPressed: widget.onMore, icon: Icon(Icons.more_horiz_rounded, color: AppColors.textMuted)),
                ),
            ]),
          ),
        ),
      );
}

/// A ticker line: the text keeps sliding sideways without pause, repeated
/// with a gap so the loop is seamless, short or long alike.
class _Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _Marquee({required this.text, required this.style});
  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee> with SingleTickerProviderStateMixin {
  static const _gap = 40.0;
  late final AnimationController _c = AnimationController(vsync: this);
  double _dist = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _run(double dist) {
    if (dist == _dist) return;
    _dist = dist;
    // ~30 px a second, steady.
    _c.duration = Duration(milliseconds: (dist / 30 * 1000).round());
    _c.repeat();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final tp = TextPainter(text: TextSpan(text: widget.text, style: widget.style), maxLines: 1, textDirection: TextDirection.ltr, textScaler: MediaQuery.textScalerOf(context))..layout();
        final step = tp.width + _gap;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _run(step);
        });
        final text = Text(widget.text, maxLines: 1, softWrap: false, style: widget.style);
        // Enough copies to cover the box plus one step of travel.
        final copies = (c.maxWidth / step).ceil() + 1;
        return SizedBox(
          width: c.maxWidth,
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent], stops: [0, 0.06, 0.94, 1]).createShader(r),
            blendMode: BlendMode.dstIn,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, child) => Transform.translate(offset: Offset(-step * _c.value, 0), child: child),
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < copies; i++) ...[text, const SizedBox(width: _gap)],
                  ]),
                ),
              ),
            ),
          ),
        );
      });
}

/// Chips on one line that scroll sideways: mouse drag, wheel (turned
/// sideways) and trackpad; the right edge fades while more is hidden.
class _SlideRow extends StatefulWidget {
  final List<Widget> children;
  const _SlideRow({required this.children});
  @override
  State<_SlideRow> createState() => _SlideRowState();
}

class _SlideRowState extends State<_SlideRow> {
  final _ctrl = ScrollController();
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _check() {
    if (!_ctrl.hasClients) return;
    final more = _ctrl.position.extentAfter > 1;
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 32,
        child: Listener(
          // A plain wheel scrolls the row instead of the page.
          onPointerSignal: (e) {
            if (e is PointerScrollEvent && _ctrl.hasClients && _ctrl.position.maxScrollExtent > 0) {
              final d = e.scrollDelta.dx != 0 ? e.scrollDelta.dx : e.scrollDelta.dy;
              GestureBinding.instance.pointerSignalResolver.register(e, (_) => _ctrl.jumpTo((_ctrl.offset + d).clamp(0.0, _ctrl.position.maxScrollExtent)));
            }
          },
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => LinearGradient(colors: [Colors.white, Colors.white, _more ? Colors.transparent : Colors.white], stops: const [0, 0.88, 1]).createShader(r),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, dragDevices: {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.trackpad}),
              child: ListView.separated(
                controller: _ctrl,
                scrollDirection: Axis.horizontal,
                itemCount: widget.children.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) => widget.children[i],
              ),
            ),
          ),
        ),
      );
}

/// A still waveform beside the Đài's play button when nothing plays.
class _StillWave extends StatelessWidget {
  const _StillWave();
  static const _h = <double>[6, 12, 18, 10, 22, 16, 8, 20, 26, 14, 9, 18, 24, 12, 7, 16];
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (i, h) in _h.indexed) ...[
          if (i > 0) const SizedBox(width: 3),
          Container(width: 3, height: h, decoration: BoxDecoration(color: Colors.white.withValues(alpha: i > 9 ? 0.25 : 0.7), borderRadius: BorderRadius.circular(2))),
        ],
      ]);
}

/// The person on the song-of-the-day card: an old round print — sepia,
/// cream mount, darker edges. In mourning: black and white with a black
/// ribbon across the corner.
class _Portrait extends StatelessWidget {
  final String? url;
  final bool mourning;
  final BoxShadow shadow;
  const _Portrait({super.key, required this.url, required this.mourning, required this.shadow});

  static const _sepia = ColorFilter.matrix([
    0.393 * 0.9, 0.769 * 0.9, 0.189 * 0.9, 0, 6,
    0.349 * 0.9, 0.686 * 0.9, 0.168 * 0.9, 0, 4,
    0.272 * 0.9, 0.534 * 0.9, 0.131 * 0.9, 0, 2,
    0, 0, 0, 1, 0,
  ]);
  static const _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final mount = mourning ? const Color(0xFFE6E2E0) : const Color(0xFFF4EADC);
    final edge = mourning ? const Color(0xFFBDB6B4) : const Color(0xFFE3D3BE);
    return Container(
      width: 188,
      height: 188,
      decoration: BoxDecoration(shape: BoxShape.circle, color: mount, border: Border.all(color: edge), boxShadow: [shadow]),
      padding: const EdgeInsets.all(5),
      child: ClipOval(
        child: Stack(fit: StackFit.expand, children: [
          if (mourning || context.select<ThemeProvider, bool>((t) => t.tintPhotos))
            ColorFiltered(colorFilter: mourning ? _grey : _sepia, child: NetImage(url: url, width: 176, height: 176))
          else
            NetImage(url: url, width: 176, height: 176),
          const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(colors: [Color(0x00000000), Color(0x00000000), Color(0x52462814)], stops: [0, 0.55, 1]))),
          if (mourning)
            Positioned(
              top: 20,
              right: -38,
              child: Transform.rotate(angle: 0.785, child: Container(width: 140, height: 20, decoration: BoxDecoration(color: const Color(0xFF1A1415), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 3, offset: const Offset(0, 1))]))),
            ),
        ]),
      ),
    );
  }
}
