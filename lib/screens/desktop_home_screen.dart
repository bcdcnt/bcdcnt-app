import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../widgets/anniversary_rail.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';

// Trang chủ desktop (canvas "Desktop — làm mới: Phòng lưu trữ đang hát"):
// Hôm nay trong năm tháng → Đài BCĐCNT → Nghe nhiều hôm nay | Đang nghe cùng
// bạn → Câu chuyện bài hát → Đi theo thập niên. One click plays a whole
// session: desktop is where people leave the music on for hours.

const _songFields = 'id slug title subtitle views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id slug title } } sheet { year composers(first: 2) { data { id slug title } } }';

const _liveQuery = '''query DesktopHomeLive {
  nowListening(limit: 8) { listeners song { $_songFields } }
  topSongsToday(limit: 8) { $_songFields }
}''';

const _mainQuery = '''query DesktopHomeMain {
  stickySongs(first: 30) { data { $_songFields } }
  featuredComments(limit: 6) { id snippet likes username user_avatar song_id song_title song_image audio_url video_url play_type file_type }
}''';

const _decades = [
  (1950, 'Hoà bình lập lại'),
  (1960, 'Chống Mỹ cứu nước'),
  (1970, 'Thống nhất đất nước'),
  (1980, 'Bao cấp – Đổi mới'),
];

List<Map<String, dynamic>> _maps(dynamic list) => ((list ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
bool _playable(Map s) => s['file']?['audio_url'] != null || s['file']?['video_url'] != null;

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});
  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  List<Anniv> _anniv = [];
  int _annivIdx = 0;
  List<Map<String, dynamic>> _sticky = [];
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _top = [];
  List<Map<String, dynamic>> _live = [];
  List<Map<String, dynamic>> _recent = [];
  List<Map<String, dynamic>> _forYou = [];
  String? _forYouReason;
  String? _personalFor;
  bool _loading = true;
  Timer? _liveTimer;
  /// Station whose songs are being fetched.
  String? _starting;

  @override
  void initState() {
    super.initState();
    _fetch();
    loadAnniversaries(window: 7).then((a) {
      if (mounted) setState(() => _anniv = a.take(5).toList());
    });
    // "Đang nghe cùng bạn" stays alive while the home is open.
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
      _recent = [];
      _forYou = [];
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
      _fetchLive(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchLive() async {
    try {
      final d = await ApiClient.query(_liveQuery);
      if (!mounted) return;
      setState(() {
        _live = _maps(d['nowListening']).where((x) => x['song'] is Map).map((x) => {
              ...Map<String, dynamic>.from(x['song'] as Map),
              'file_type': 'song',
              'listeners': x['listeners'],
            }).toList();
        _top = _maps(d['topSongsToday']).map((s) => {...s, 'file_type': 'song'}).toList();
      });
    } catch (_) {}
  }

  Future<void> _fetchPersonal(AuthProvider auth, String uid) async {
    const f = 'id title slug play_type thumbnail { url } file { audio_url video_url } artists(first: 2) { data { id title slug } }';
    const tn = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem'};
    auth.authedQuery('''query(\$id: ID!) { user(id: \$id) { recentListens(first: 30, page: 1, orderBy: [{column: "id", order: DESC}]) { data { object { __typename ... on Song { $f } ... on Folk { $f } ... on Instrumental { $f } ... on Poem { $f } } } } } }''', {'id': uid}).then((d) {
      final seen = <String>{};
      final out = <Map<String, dynamic>>[];
      for (final e in _maps(d['user']?['recentListens']?['data'])) {
        if (e['object'] is! Map) continue;
        final m = Map<String, dynamic>.from(e['object']);
        if (!seen.add('${m['__typename']}-${m['id']}')) continue;
        m['file_type'] = tn[m['__typename']] ?? 'song';
        if (_playable(m)) out.add(m);
      }
      if (mounted && _personalFor == uid) setState(() => _recent = out);
    }).catchError((_) {});
    auth.authedQuery(r'''query($id: ID) { recommendedSongs(user_id: $id, limit: 30) { id title subtitle slug image audio_url video_url play_type file_type reason artists { id title slug } } }''', {'id': uid}).then((d) {
      final out = <Map<String, dynamic>>[];
      String? reason;
      for (final m in _maps(d['recommendedSongs'])) {
        if (m['audio_url'] == null && m['video_url'] == null) continue;
        reason ??= '${m['reason'] ?? ''}'.trim().isEmpty ? null : '${m['reason']}';
        out.add({
          'id': m['id'], 'title': m['title'], 'slug': m['slug'],
          if (m['image'] != null) 'thumbnail': {'url': m['image']},
          'file': {'audio_url': m['audio_url'], 'video_url': m['video_url']},
          'play_type': m['play_type'],
          'file_type': const {'audio': 'song', 'video': 'song'}[m['file_type']] ?? m['file_type'] ?? 'song',
          'artists': {'data': m['artists'] ?? []},
        });
      }
      if (mounted && _personalFor == uid) setState(() { _forYou = out; _forYouReason = reason; });
    }).catchError((_) {});
  }

  void _play(List<Map<String, dynamic>> list, String label, [int at = 0]) {
    if (list.isEmpty) return;
    playOrOpen(context, list[at], list, label);
  }

  Future<void> _playRandom() async {
    setState(() => _starting = 'random');
    try {
      final d = await ApiClient.query('query { songs(first: 40, random: true, where: {column: "views", operator: GT, value: 2000}) { data { $_songFields } } }');
      final list = _maps(d['songs']?['data']).map((s) => {...s, 'file_type': 'song'}).where(_playable).toList();
      if (mounted) _play(list, 'Đài BCĐCNT · Ngẫu nhiên');
    } catch (_) {
    } finally {
      if (mounted) setState(() => _starting = null);
    }
  }

  Future<void> _playAnniv(Anniv a) async {
    setState(() => _starting = 'anniv');
    final songs = await annivSongs(a);
    if (!mounted) return;
    setState(() => _starting = null);
    if (songs.isEmpty) {
      context.push('${a.route}${a.person['slug']}');
    } else {
      _play(songs, '${a.role} ${a.person['title'] ?? ''}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      child: LayoutBuilder(builder: (context, c) {
        final pad = c.maxWidth < 900 ? 28.0 : 40.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 28, pad, 48),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_anniv.isNotEmpty) _hero(_anniv[_annivIdx.clamp(0, _anniv.length - 1)]),
                const SizedBox(height: 40),
                _stations(),
                const SizedBox(height: 48),
                LayoutBuilder(builder: (context, cc) {
                  final top = _section('Nghe nhiều hôm nay', _loading && _top.isEmpty ? _skeletonRows() : _rankList(), action: 'Xem tất cả', onAction: () => context.push('/bang-xep-hang'));
                  final live = _section('Đang nghe cùng bạn', _liveList(), dot: true);
                  if (cc.maxWidth < 760) return Column(children: [top, const SizedBox(height: 40), live]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 7, child: top),
                    const SizedBox(width: 40),
                    Expanded(flex: 5, child: live),
                  ]);
                }),
                if (_comments.isNotEmpty) ...[
                  const SizedBox(height: 48),
                  _section('Câu chuyện bài hát', _stories(), action: 'Xem thêm', onAction: () => context.go('/cong-dong')),
                ],
                const SizedBox(height: 48),
                _section('Đi theo thập niên', _decadeRow(), action: 'Mở dòng thời gian', onAction: () => context.go('/dong-thoi-gian')),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _section(String title, Widget child, {String? action, VoidCallback? onAction, bool dot = false}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (dot) ...[
            Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFFC62828), shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFC62828).withValues(alpha: 0.18), spreadRadius: 4)])),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(title, style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text)))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
        ]),
        const SizedBox(height: 12),
        child,
      ]);

  // ---------- Hôm nay trong năm tháng ----------
  Widget _hero(Anniv a) {
    final p = a.person;
    final born = '${p['yob'] ?? ''}'.trim(), died = '${p['yod'] ?? ''}'.trim();
    final span = [if (born.isNotEmpty && born != '0') born, if (died.isNotEmpty && died != '0') died].join(' – ');
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 300,
        child: Stack(fit: StackFit.expand, children: [
          Container(color: const Color(0xFF2E080A)),
          Positioned(
            right: 0, top: 0, bottom: 0, width: 620,
            child: NetImage(url: p['avatar']?['url']?.toString(), tint: true),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xF02E080A), Color(0xB32E080A), Color(0x002E080A)], stops: [0, 0.55, 1]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 32, 40, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('HÔM NAY TRONG NĂM THÁNG · ${annivWhen(a).toUpperCase()}${a.inDays > 1 ? '' : ' ${a.date.day}/${a.date.month}'}', style: body(const TextStyle(fontSize: 13, letterSpacing: 1, fontWeight: FontWeight.w800, color: Color(0xFFF6E8DE)))),
              const SizedBox(height: 10),
              Text('${a.role} ${p['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 48, height: 1.05, letterSpacing: -1, fontWeight: FontWeight.w800, color: Colors.white))),
              const SizedBox(height: 8),
              Text.rich(TextSpan(children: [
                if (span.isNotEmpty) TextSpan(text: '$span · ', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w300)),
                TextSpan(text: annivYears(a)),
              ]), style: body(const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xE6FFFFFF)))),
              const SizedBox(height: 22),
              Row(children: [
                _bigButton('Nghe tuyển tập', Icons.play_arrow_rounded, () => _playAnniv(a), loading: _starting == 'anniv'),
                const SizedBox(width: 12),
                _bigButton('Xem hồ sơ', null, () => context.push('${a.route}${p['slug']}'), ghost: true),
                const Spacer(),
                if (_anniv.length > 1)
                  for (var i = 0; i < _anniv.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message: '${_anniv[i].person['title'] ?? ''}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() => _annivIdx = i),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: i == _annivIdx ? 22 : 9, height: 9,
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: i == _annivIdx ? 0.95 : 0.5), borderRadius: BorderRadius.circular(5)),
                            ),
                          ),
                        ),
                      ),
                    ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bigButton(String label, IconData? icon, VoidCallback onTap, {bool ghost = false, bool loading = false}) => Material(
        color: ghost ? Colors.white.withValues(alpha: 0.16) : AppColors.wine,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: loading ? null : onTap,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (loading)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              else if (icon != null)
                Icon(icon, size: 26, color: Colors.white),
              if (icon != null || loading) const SizedBox(width: 8),
              Text(label, style: body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
            ]),
          ),
        ),
      );

  // ---------- Đài BCĐCNT ----------
  Widget _stations() {
    String? img(List<Map<String, dynamic>> l) => l.isEmpty ? null : l.first['thumbnail']?['url']?.toString();
    final tiles = <Widget>[
      if (_recent.isNotEmpty) _station('Nghe tiếp', '${_recent.first['title']} · ${_recent.length} bài', img(_recent), () => _play(_recent, 'Nghe gần đây')),
      if (_forYou.isNotEmpty) _station('Dành cho bạn', _forYouReason ?? 'Theo gu nghe của bạn', img(_forYou), () => _play(_forYou, 'Dành cho bạn')),
      _station('Hôm qua nghe nhiều', 'Những bài được nghe nhiều nhất', img(_sticky), () => _play(_sticky, 'Hôm qua nghe nhiều')),
      _station('Ngẫu nhiên kho nhạc', 'Mỗi lần một khác', _sticky.length > 5 ? img(_sticky.sublist(5)) : null, _playRandom, loading: _starting == 'random'),
      if (_recent.isEmpty) _station('Nghe nhiều hôm nay', 'Bảng xếp hạng trong ngày', img(_top), () => _play(_top, 'Nghe nhiều hôm nay')),
      if (_forYou.isEmpty) _station('Đang nghe cùng bạn', 'Những bài mọi người đang mở', img(_live), () => _play(_live, 'Mọi người đang nghe')),
    ].take(4).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.radio_rounded, size: 26, color: AppColors.accentFg),
        const SizedBox(width: 10),
        Text('Đài BCĐCNT', style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text))),
      ]),
      const SizedBox(height: 4),
      Text('Bấm một lần, nhạc phát liên tục cả buổi', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
      const SizedBox(height: 16),
      Row(children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(child: tiles[i]),
        ],
      ]),
    ]);
  }

  Widget _station(String title, String sub, String? image, VoidCallback onTap, {bool loading = false}) => Material(
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        color: const Color(0xFF2E080A),
        child: InkWell(
          onTap: loading ? null : onTap,
          child: SizedBox(
            height: 124,
            child: Stack(fit: StackFit.expand, children: [
              if (image != null) NetImage(url: image, tint: true),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x262E080A), Color(0xD92E080A)]))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 14, 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 17, height: 1.2, fontWeight: FontWeight.w800, color: Colors.white))),
                      const SizedBox(height: 3),
                      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xD9FFFFFF)))),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 44, height: 44,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: loading
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.wine))
                        : Icon(Icons.play_arrow_rounded, size: 28, color: AppColors.wine),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );

  // ---------- Lists ----------
  Widget _row(Map<String, dynamic> s, List<Map<String, dynamic>> list, int i, String label, {Widget? lead, Widget? trail}) => InkWell(
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
                Text(songByline(s, withComposer: true), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
              ]),
            ),
            ?trail,
            IconButton(tooltip: 'Tuỳ chọn', onPressed: () => showSongActions(context, s), icon: Icon(Icons.more_horiz_rounded, color: AppColors.textMuted)),
          ]),
        ),
      );

  Widget _rankList() => Column(children: [
        for (var i = 0; i < _top.length; i++)
          _row(_top[i], _top, i, 'Nghe nhiều hôm nay',
              lead: SizedBox(
                width: 46,
                child: Text('${i + 1}', textAlign: TextAlign.center, style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w300, color: i < 3 ? AppColors.accentFg : AppColors.textMuted))),
              )),
      ]);

  Widget _liveList() => Column(children: [
        for (var i = 0; i < _live.length; i++)
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
            Text('${c['snippet'] ?? ''}'.trim(), maxLines: 5, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 18, height: 1.6, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500, color: AppColors.text))),
            const SizedBox(height: 16),
            Row(children: [
              UserAvatar(url: c['user_avatar']?.toString(), name: '${c['username'] ?? ''}', size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c['username'] ?? ''}', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text))),
                  Text.rich(TextSpan(children: [
                    const TextSpan(text: 'về bài '),
                    TextSpan(text: '${c['song_title'] ?? ''}', style: TextStyle(color: AppColors.accentFg, fontWeight: FontWeight.w700)),
                  ]), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                ]),
              ),
              if (_playable(song))
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.wine, minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 18)),
                  onPressed: () => playOrOpen(context, song, [song], 'Câu chuyện bài hát'),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: Text('Nghe bài', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ---------- Thập niên ----------
  Widget _decadeRow() => Row(children: [
        for (var i = 0; i < _decades.length; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          Expanded(
            child: Material(
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              color: const Color(0xFF2E080A),
              child: InkWell(
                onTap: () => context.push('/bai-hat/thap-nien/${_decades[i].$1}'),
                child: SizedBox(
                  height: 150,
                  child: Stack(fit: StackFit.expand, children: [
                    if (_sticky.length > i + 1) Opacity(opacity: 0.7, child: NetImage(url: _sticky[i + 1]['thumbnail']?['url']?.toString(), tint: true)),
                    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x0D2E080A), Color(0xCC2E080A)]))),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_decades[i].$1}s', style: display(const TextStyle(fontSize: 34, height: 1, letterSpacing: -1, fontWeight: FontWeight.w300, color: Colors.white))),
                        const SizedBox(height: 4),
                        Text(_decades[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xE0FFFFFF)))),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ]);
}
