import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';

/// "Dòng thời gian" (desktop menu, canvas "Desktop · Dòng thời gian"): one
/// chart of songs per year written (the sheet's year, else the song's) with
/// the historical periods under it. A period or a bar picks what the table
/// below lists; ▶ plays the whole period, not just the page.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

/// [from, to) · short name on the band · title above the list. `to` 0 = now.
const _eras = [
  (1930, 1945, 'Tiền chiến', 'Nhạc tiền chiến'),
  (1945, 1954, 'Chống Pháp', 'Kháng chiến chống Pháp'),
  (1954, 1975, 'Chống Mỹ', 'Kháng chiến chống Mỹ'),
  (1975, 1986, 'Sau giải phóng', 'Sau giải phóng'),
  (1986, 2000, 'Đổi mới', 'Thời kỳ Đổi mới'),
  (2000, 0, 'Sau 2000', 'Sau năm 2000'),
];
const _first = 1930;
const _perPage = 30;
const _fields = 'id slug title play_type views thumbnail { url } file { audio_url video_url duration } sheet { year composers(first: 2) { data { id slug title } } } artists(first: 3) { data { id slug title } }';

String _num(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

class _TimelineScreenState extends State<TimelineScreen> {
  int _era = 2;
  int? _year;
  /// 'views' (Nghe nhiều nhất) or 'year' (Theo năm, oldest first).
  String _sort = 'views';
  int _page = 1, _lastPage = 1, _total = 0;
  List<Map<String, dynamic>> _songs = [];
  bool _loading = true;
  Map<int, int> _counts = {};
  List<Map<String, dynamic>> _composers = [];
  final Set<String> _open = {};
  String? _starting;
  final _scroll = ScrollController();

  int get _last => DateTime.now().year;
  int _eraTo(int i) => _eras[i].$2 == 0 ? _last + 1 : _eras[i].$2;
  (int, int) get _range => _year != null ? (_year!, _year! + 1) : (_eras[_era].$1, _eraTo(_era));

  @override
  void initState() {
    super.initState();
    _load();
    _loadComposers();
    ApiClient.query('query { songYearCounts { year total } }').then((d) {
      final m = <int, int>{};
      for (final e in ((d['songYearCounts'] ?? []) as List).whereType<Map>()) {
        m[(e['year'] as num).toInt()] = (e['total'] as num).toInt();
      }
      if (mounted) setState(() => _counts = m);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Songs of the range; servers without `sort` / `songsByYear` fall back.
  Future<(List<Map<String, dynamic>>, int, int)> _fetch(int first, int page) async {
    final (from, to) = _range;
    List<Map<String, dynamic>> list(dynamic data) => ((data ?? []) as List).whereType<Map>().map((e) => <String, dynamic>{...Map<String, dynamic>.from(e), 'file_type': 'song'}).toList();
    for (final withSort in [true, false]) {
      try {
        final d = await ApiClient.query('''query(\$from: Int!, \$to: Int!, \$first: Int!, \$page: Int${withSort ? ', \$sort: String' : ''}) {
          songsByYear(from: \$from, to: \$to, first: \$first, page: \$page${withSort ? ', sort: \$sort' : ''}) { data { $_fields } paginatorInfo { total lastPage } }
        }''', {'from': from, 'to': to, 'first': first, 'page': page, if (withSort) 'sort': _sort});
        final p = d['songsByYear']?['paginatorInfo'];
        return (list(d['songsByYear']?['data']), (p?['total'] as num?)?.toInt() ?? 0, (p?['lastPage'] as num?)?.toInt() ?? 1);
      } catch (_) {}
    }
    final d = await ApiClient.query('''query(\$w: WhereConditions, \$first: Int!, \$page: Int) {
      songs(first: \$first, page: \$page, orderBy: [{column: "${_sort == 'year' ? 'year' : 'views'}", order: ${_sort == 'year' ? 'ASC' : 'DESC'}}], where: \$w) { data { $_fields } paginatorInfo { total lastPage } }
    }''', {
      'first': first, 'page': page,
      'w': {'AND': [{'column': 'year', 'operator': 'GTE', 'value': '$from'}, {'column': 'year', 'operator': 'LT', 'value': '$to'}]},
    });
    final p = d['songs']?['paginatorInfo'];
    return (list(d['songs']?['data']), (p?['total'] as num?)?.toInt() ?? 0, (p?['lastPage'] as num?)?.toInt() ?? 1);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final key = '$_era-$_year-$_sort-$_page';
    try {
      final (songs, total, last) = await _fetch(_perPage, _page);
      if (!mounted || key != '$_era-$_year-$_sort-$_page') return;
      setState(() { _songs = songs; _total = total; _lastPage = last; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadComposers() async {
    final era = _era;
    try {
      final d = await ApiClient.query(r'query($from: Int!, $to: Int!) { composersByYear(from: $from, to: $to, limit: 6) { total composer { id slug title avatar { url } } } }', {'from': _eras[era].$1, 'to': _eraTo(era)});
      if (!mounted || era != _era) return;
      setState(() => _composers = ((d['composersByYear'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (_) {
      if (mounted && era == _era) setState(() => _composers = []);
    }
  }

  void _pick({int? era, int? year}) {
    final eraChanged = era != null && era != _era;
    setState(() {
      if (era != null) _era = era;
      _year = year;
      _page = 1;
      _open.clear();
    });
    _load();
    if (eraChanged) _loadComposers();
  }

  void _pickYear(int y) {
    if (y == _year) return _pick();
    final e = _eras.indexWhere((e) => y >= e.$1 && y < (e.$2 == 0 ? _last + 1 : e.$2));
    _pick(era: e < 0 ? null : e, year: y);
  }

  String get _label => _year != null ? 'Năm $_year' : _eras[_era].$4;

  /// ▶ / Trộn: up to 200 songs of the whole range, not just this page.
  Future<void> _playAll(bool shuffle) async {
    if (_starting != null) return;
    setState(() => _starting = shuffle ? 'shuffle' : 'play');
    try {
      final (songs, _, _) = await _fetch(200, 1);
      final playable = songs.where((s) => s['file']?['audio_url'] != null || s['file']?['video_url'] != null).toList();
      if (shuffle) playable.shuffle();
      if (mounted && playable.isNotEmpty) playOrOpen(context, playable.first, playable, 'Dòng thời gian · $_label');
    } catch (_) {
    } finally {
      if (mounted) setState(() => _starting = null);
    }
  }

  void _goPage(int p) {
    if (p < 1 || p > _lastPage || p == _page) return;
    setState(() { _page = p; _open.clear(); });
    _load();
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _range;
    final total = _counts.isEmpty ? _total : [for (var y = from; y < to; y++) _counts[y] ?? 0].fold<int>(0, (a, b) => a + b);
    final eyebrow = _year != null
        ? '${_eras[_era].$4.toUpperCase()} · ${_num(total)} BÀI'
        : '${_eras[_era].$1} – ${_eras[_era].$2 == 0 ? 'NAY' : _eras[_era].$2} · ${_num(total)} BÀI';
    return Material(
      color: AppColors.bg,
      child: LayoutBuilder(builder: (context, c) {
        final pad = c.maxWidth < 1000 ? 28.0 : 40.0;
        final side = c.maxWidth >= 1100 && _composers.isNotEmpty;
        return SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(pad, 28, pad, 56),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Dòng thời gian', style: display(TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: AppColors.text))),
                const SizedBox(height: 6),
                Text(
                  _counts.isEmpty ? 'Bấm một giai đoạn hoặc một năm' : 'Bấm một giai đoạn hoặc một cột năm · ${_num(_counts.values.fold<int>(0, (a, b) => a + b))} bài có ghi năm sáng tác',
                  style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                ),
                const SizedBox(height: 22),
                _chart(),
                const SizedBox(height: 30),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(eyebrow, style: AppText.eyebrow),
                      const SizedBox(height: 4),
                      Text(_label, style: display(TextStyle(fontSize: 34, height: 1.15, letterSpacing: -0.7, fontWeight: FontWeight.w800, color: AppColors.text))),
                    ]),
                  ),
                  PillButton(label: _year != null ? 'Phát năm $_year' : 'Phát cả giai đoạn', icon: Icons.play_arrow_rounded, height: 48, loading: _starting == 'play', onTap: _songs.isEmpty ? null : () => _playAll(false)),
                  const SizedBox(width: 10),
                  PillButton(label: 'Trộn bài', icon: Icons.shuffle_rounded, height: 48, primary: false, loading: _starting == 'shuffle', onTap: _songs.isEmpty ? null : () => _playAll(true)),
                ]),
                const SizedBox(height: 22),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 7, child: _list()),
                  if (side) ...[const SizedBox(width: 40), Expanded(flex: 3, child: Padding(padding: const EdgeInsets.only(top: 48), child: _composerList()))],
                ]),
              ]),
            ),
          ),
        );
      }),
    );
  }

  /// Bars per year from 1930 (the chosen period wine, the chosen year
  /// darkest; hover shows "1968 · 158 bài"), decade ticks, period bands.
  Widget _chart() {
    final last = _last;
    final n = last - _first + 1;
    final peak = [for (var y = _first; y <= last; y++) _counts[y] ?? 0].fold<int>(1, (a, b) => b > a ? b : a);
    final (from, to) = (_eras[_era].$1, _eraTo(_era));
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_counts.isNotEmpty) ...[
          SizedBox(
            height: 150,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var y = _first; y <= last; y++)
                Expanded(
                  child: Tooltip(
                    message: '$y · ${_counts[y] ?? 0} bài',
                    waitDuration: Duration.zero,
                    child: InkWell(
                      onTap: () => _pickYear(y),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: (_counts[y] ?? 0) == 0 ? 0.0 : ((_counts[y] ?? 0) / peak).clamp(0.02, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: y == _year ? AppColors.text : (y >= from && y < to ? AppColors.wine : AppColors.rose.withValues(alpha: 0.45)),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 18,
            child: LayoutBuilder(builder: (context, c) => Stack(clipBehavior: Clip.none, children: [
                  for (var y = (_first + 9) ~/ 10 * 10; y <= last; y += 10)
                    Positioned(
                      left: (y - _first) / n * c.maxWidth,
                      child: Text('$y', style: body(TextStyle(fontSize: 12, fontWeight: y >= from && y < to ? FontWeight.w800 : FontWeight.w700, color: y >= from && y < to ? AppColors.accentFg : AppColors.textMuted))),
                    ),
                ])),
          ),
          const SizedBox(height: 10),
        ],
        Row(children: [
          for (var i = 0; i < _eras.length; i++)
            Expanded(
              // Width follows the years, so a band sits under its bars.
              flex: _eraTo(i).clamp(_first, last + 1) - _eras[i].$1.clamp(_first, last + 1),
              child: Padding(
                padding: EdgeInsets.only(right: i == _eras.length - 1 ? 0 : 4),
                child: Material(
                  color: i == _era && _year == null ? AppColors.wine : (i == _era ? AppColors.accentSoft : AppColors.bg),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _pick(era: i),
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      alignment: Alignment.centerLeft,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // Short periods are narrow: the name shrinks instead of losing letters.
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(_eras[i].$3, maxLines: 1, style: body(TextStyle(fontSize: 13, letterSpacing: -0.2, fontWeight: FontWeight.w800, color: i == _era && _year == null ? Colors.white : AppColors.text)))),
                        Text('${_eras[i].$1}–${_eras[i].$2 == 0 ? 'nay' : _eras[i].$2}', maxLines: 1, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i == _era && _year == null ? Colors.white70 : AppColors.textMuted))),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _tab(String label, String sort) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(19),
          onTap: () {
            if (_sort == sort) return;
            setState(() { _sort = sort; _page = 1; _open.clear(); });
            _load();
          },
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _sort == sort ? AppColors.text : AppColors.surface, borderRadius: BorderRadius.circular(19)),
            child: Text(label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _sort == sort ? AppColors.bg : AppColors.text))),
          ),
        ),
      );

  /// The table: recordings of one song (title + composer) fold into a row.
  Widget _list() {
    final rows = <Widget>[];
    if (_loading && _songs.isEmpty) {
      rows.addAll([for (var i = 0; i < 8; i++) const SkeletonSongRow()]);
    } else if (_songs.isEmpty) {
      rows.add(Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Text('Chưa có bài nào được ghi năm sáng tác này.', style: AppText.bodyText)));
    } else {
      final order = <String>[];
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final s in _songs) {
        final comps = ((s['sheet']?['composers']?['data'] ?? const []) as List).map((c) => c['id']).join(',');
        final k = '${'${s['title'] ?? ''}'.toLowerCase().trim()}|$comps';
        groups.putIfAbsent(k, () {
          order.add(k);
          return [];
        }).add(s);
      }
      final playable = _songs.where((s) => s['file']?['audio_url'] != null || s['file']?['video_url'] != null).toList();
      void play(Map<String, dynamic> s) => playOrOpen(context, s, playable.contains(s) ? playable : [s], 'Dòng thời gian · $_label');
      for (final k in order) {
        final g = groups[k]!;
        final open = _open.contains(k);
        rows.add(_YearRow(
          song: g.first,
          sub: g.length > 1 ? {for (final s in g) songByline(s)}.where((x) => x.isNotEmpty).join(', ') : songByline(g.first),
          views: g.fold<int>(0, (a, s) => a + ((s['views'] as num?)?.toInt() ?? 0)),
          recordings: g.length,
          open: open,
          onToggle: () => setState(() => open ? _open.remove(k) : _open.add(k)),
          onTap: () => play(g.first),
        ));
        if (open && g.length > 1) {
          for (final s in g) {
            rows.add(_YearRow(song: s, sub: '', views: (s['views'] as num?)?.toInt() ?? 0, nested: true, onTap: () => play(s)));
          }
        }
      }
    }
    final head = body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [_tab('Nghe nhiều nhất', 'views'), _tab('Theo năm', 'year')]),
      const SizedBox(height: 10),
      Container(
        height: 34,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(children: [
          SizedBox(width: 52, child: Text('NĂM', style: head)),
          const SizedBox(width: 60),
          Expanded(child: Text('BÀI HÁT · TRÌNH BÀY', style: head)),
          SizedBox(width: 160, child: Text('SÁNG TÁC', style: head)),
          SizedBox(width: 84, child: Text('LƯỢT NGHE', textAlign: TextAlign.right, style: head)),
          const SizedBox(width: 48),
        ]),
      ),
      AnimatedOpacity(opacity: _loading ? 0.5 : 1, duration: const Duration(milliseconds: 150), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
      if (_lastPage > 1) _pager(),
    ]);
  }

  Widget _pager() {
    final pages = <int>{1, _lastPage, for (var p = _page - 1; p <= _page + 1; p++) if (p >= 1 && p <= _lastPage) p}.toList()..sort();
    Widget btn(Widget child, VoidCallback? onTap, {bool on = false}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minWidth: 40),
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: on ? AppColors.text : AppColors.surface, borderRadius: BorderRadius.circular(20)),
              child: DefaultTextStyle.merge(style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: on ? AppColors.bg : AppColors.text)), child: child),
            ),
          ),
        );
    final items = <Widget>[btn(Icon(Icons.chevron_left_rounded, color: AppColors.text), _page > 1 ? () => _goPage(_page - 1) : null)];
    for (var i = 0; i < pages.length; i++) {
      if (i > 0 && pages[i] - pages[i - 1] > 1) items.add(Padding(padding: const EdgeInsets.only(right: 6), child: Text('…', style: body(TextStyle(color: AppColors.textMuted)))));
      items.add(btn(Text('${pages[i]}'), () => _goPage(pages[i]), on: pages[i] == _page));
    }
    items.add(btn(Icon(Icons.chevron_right_rounded, color: AppColors.text), _page < _lastPage ? () => _goPage(_page + 1) : null));
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      // A Row, not a Wrap: in a Wrap each centred button stretched full width.
      child: Row(children: [
        ...items,
        Padding(padding: const EdgeInsets.only(left: 6), child: Text('$_perPage bài mỗi trang', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)))),
      ]),
    );
  }

  Widget _composerList() {
    final e = _eras[_era];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Nhạc sĩ của giai đoạn', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
      const SizedBox(height: 2),
      Text('Nhiều bài nhất trong ${e.$1} – ${e.$2 == 0 ? 'nay' : e.$2}', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
      const SizedBox(height: 4),
      for (final r in _composers)
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.push('/nhac-si/${r['composer']?['slug']}'),
          child: SizedBox(
            height: 64,
            child: Row(children: [
              NetImage(url: r['composer']?['avatar']?['url']?.toString(), width: 48, height: 48, circle: true, tint: true, fallback: GeneratedCover(title: '${r['composer']?['title'] ?? ''}', size: 48, radius: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['composer']?['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
                  Text('${r['total']} bài trong giai đoạn', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ]),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: () => context.push('/nhac-si'), child: Text('Xem tất cả nhạc sĩ', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
      ),
    ]);
  }
}

/// A table row: year · cover · title / performers (+ "N bản thu") ·
/// composer · plays · ⋯. Nested rows are the folded recordings.
class _YearRow extends StatelessWidget {
  final Map<String, dynamic> song;
  final String sub;
  final int views;
  final int recordings;
  final bool open;
  final bool nested;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  const _YearRow({required this.song, required this.sub, required this.views, required this.onTap, this.recordings = 1, this.open = false, this.nested = false, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final year = '${song['sheet']?['year'] ?? ''}';
    final comps = ((song['sheet']?['composers']?['data'] ?? const []) as List).map((c) => '${c['title']}').join(', ');
    final title = nested ? (songByline(song).isEmpty ? 'Bản thu' : songByline(song)) : '${song['title'] ?? ''}';
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
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
        child: Row(children: [
          SizedBox(width: 52, child: nested ? null : Text(year, style: display(TextStyle(fontSize: 18, fontWeight: FontWeight.w300, color: AppColors.textSecondary)))),
          SizedBox(width: 60, child: Align(alignment: Alignment.centerLeft, child: SongCover(song: song, size: nested ? 36 : 46, radius: nested ? 8 : 10))),
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
          SizedBox(width: 160, child: Text(nested ? '' : comps, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
          SizedBox(width: 84, child: Text(views > 0 ? formatViews(views) : '', textAlign: TextAlign.right, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)))),
          IconButton(tooltip: 'Tuỳ chọn', onPressed: () => showSongActions(context, song), icon: Icon(Icons.more_horiz_rounded, color: AppColors.textMuted)),
        ]),
      ),
    ));
  }
}
