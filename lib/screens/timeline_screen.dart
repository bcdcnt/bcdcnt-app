import 'package:flutter/material.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';

/// "Dòng thời gian" (desktop menu): walk through the years by the songs
/// written in each (the sheet's year, else the song's). A ruler of songs per
/// year on top; pick a decade, then a year; ▶ plays what is shown.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

const _decades = [
  (1940, 'Kháng chiến chống Pháp'),
  (1950, 'Hoà bình lập lại'),
  (1960, 'Chống Mỹ cứu nước'),
  (1970, 'Thống nhất đất nước'),
  (1980, 'Bao cấp – Đổi mới'),
  (1990, 'Thời mở cửa'),
];

class _TimelineScreenState extends State<TimelineScreen> {
  int _decade = 1970;
  int? _year;
  List<Map<String, dynamic>> _songs = [];
  bool _loading = true;
  int _total = 0;
  /// Songs per year (songYearCounts); empty until the API has it.
  Map<int, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _load();
    ApiClient.query('query { songYearCounts { year total } }').then((d) {
      final m = <int, int>{};
      for (final e in ((d['songYearCounts'] ?? []) as List).whereType<Map>()) {
        m[(e['year'] as num).toInt()] = (e['total'] as num).toInt();
      }
      if (mounted) setState(() => _counts = m);
    }).catchError((_) {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final from = _year ?? _decade, to = _year != null ? _year! + 1 : _decade + 10;
    final key = '$_decade-$_year';
    // By composition year (songsByYear); servers without it yet fall back
    // to the song's own year column.
    try {
      final d = await ApiClient.query('''query(\$from: Int!, \$to: Int!) {
        songsByYear(from: \$from, to: \$to, first: 30, page: 1) {
          data { id slug title play_type views thumbnail { url } file { audio_url video_url duration } sheet { year composers(first: 2) { data { id slug title } } } artists(first: 3) { data { id slug title } } }
          paginatorInfo { total }
        }
      }''', {'from': from, 'to': to});
      if (!mounted || key != '$_decade-$_year') return;
      setState(() {
        _songs = ((d['songsByYear']?['data'] ?? []) as List).whereType<Map>().map((e) => <String, dynamic>{...Map<String, dynamic>.from(e), 'file_type': 'song'}).toList();
        _total = (d['songsByYear']?['paginatorInfo']?['total'] as num?)?.toInt() ?? _songs.length;
        _loading = false;
      });
      return;
    } catch (_) {}
    try {
      final d = await ApiClient.query('''query(\$w: WhereConditions) {
        songs(first: 30, page: 1, orderBy: [{column: "views", order: DESC}], where: \$w) {
          data { id slug title play_type views thumbnail { url } file { audio_url video_url duration } sheet { year composers(first: 2) { data { id slug title } } } artists(first: 3) { data { id slug title } } }
          paginatorInfo { total }
        }
      }''', {
        'w': {'AND': [
          {'column': 'year', 'operator': 'GTE', 'value': '$from'},
          {'column': 'year', 'operator': 'LT', 'value': '$to'},
        ]},
      });
      if (!mounted || key != '$_decade-$_year') return;
      setState(() {
        _songs = ((d['songs']?['data'] ?? []) as List).whereType<Map>().map((e) => <String, dynamic>{...Map<String, dynamic>.from(e), 'file_type': 'song'}).toList();
        _total = (d['songs']?['paginatorInfo']?['total'] as num?)?.toInt() ?? _songs.length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dec = _decades.firstWhere((d) => d.$1 == _decade);
    final playable = _songs.where((s) => s['file']?['audio_url'] != null || s['file']?['video_url'] != null).toList();
    return Material(
      color: AppColors.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 32, 40, 48),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Dòng thời gian', style: display(TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: AppColors.text))),
              const SizedBox(height: 6),
              Text('Đi qua các năm tháng bằng những bài hát ra đời trong từng năm', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
              if (_counts.isNotEmpty) ...[
                const SizedBox(height: 24),
                _ruler(),
              ],
              const SizedBox(height: 24),
              // Decades as a ruler of big year numbers.
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  for (final (y, label) in _decades)
                    Expanded(
                      child: Material(
                        color: y == _decade ? AppColors.wine : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            setState(() { _decade = y; _year = null; });
                            _load();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${y}s', style: display(TextStyle(fontSize: 30, height: 1, letterSpacing: -1, fontWeight: FontWeight.w300, color: y == _decade ? Colors.white : AppColors.text))),
                              const SizedBox(height: 4),
                              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: y == _decade ? Colors.white70 : AppColors.textMuted))),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 28),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_year != null ? 'NĂM $_year' : 'THẬP NIÊN $_decade'}${_loading ? '' : ' · $_total BÀI'}', style: AppText.eyebrow),
                    const SizedBox(height: 6),
                    Text(dec.$2, style: display(TextStyle(fontSize: 40, height: 1.1, letterSpacing: -1, fontWeight: FontWeight.w800, color: AppColors.text))),
                  ]),
                ),
                PillButton(label: _year != null ? 'Phát năm $_year' : 'Phát cả thập niên', icon: Icons.play_arrow_rounded, onTap: playable.isEmpty ? null : () => playOrOpen(context, playable.first, playable, 'Dòng thời gian ${_year ?? '${_decade}s'}')),
                const SizedBox(width: 10),
                PillButton(label: 'Trộn bài', icon: Icons.shuffle_rounded, primary: false, onTap: playable.isEmpty ? null : () {
                  final l = [...playable]..shuffle();
                  playOrOpen(context, l.first, l, 'Dòng thời gian ${_year ?? '${_decade}s'}');
                }),
              ]),
              const SizedBox(height: 18),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var y = _decade; y < _decade + 10; y++)
                  ChoiceChip(
                    label: Text('$y', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _year == y ? Colors.white : AppColors.text))),
                    selected: _year == y,
                    showCheckmark: false,
                    selectedColor: AppColors.text,
                    backgroundColor: AppColors.surface,
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    onSelected: (_) {
                      setState(() => _year = _year == y ? null : y);
                      _load();
                    },
                  ),
              ]),
              const SizedBox(height: 24),
              if (_loading)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)))
              else if (_songs.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Text('Chưa có bài nào được ghi năm sáng tác này.', style: AppText.bodyText))
              else
                LayoutBuilder(builder: (context, c) {
                  final cols = (c.maxWidth / 190).floor().clamp(3, 7);
                  final w = (c.maxWidth - (cols - 1) * 20) / cols;
                  return Wrap(spacing: 20, runSpacing: 24, children: [
                    for (final s in _songs)
                      SizedBox(
                        width: w,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => playOrOpen(context, s, playable.contains(s) ? playable : [s], 'Dòng thời gian'),
                          onSecondaryTap: () => showSongActions(context, s),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SongCover(song: s, size: w, radius: 14),
                            const SizedBox(height: 8),
                            Text('${s['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, height: 1.3, fontWeight: FontWeight.w800, color: AppColors.text))),
                            Text([songByline(s, withComposer: true), if ('${s['sheet']?['year'] ?? ''}'.isNotEmpty) '${s['sheet']['year']}'].where((x) => x.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                          ]),
                        ),
                      ),
                  ]);
                }),
            ]),
          ),
        ),
      ),
    );
  }

  /// Songs per year, 1940–1999: bars in the chosen decade are wine, the
  /// chosen year darker; a bar picks its year.
  Widget _ruler() {
    const first = 1940, last = 1999;
    final peak = [for (var y = first; y <= last; y++) _counts[y] ?? 0].fold<int>(1, (a, b) => b > a ? b : a);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 120,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var y = first; y <= last; y++)
              Expanded(
                child: Tooltip(
                  message: '$y · ${_counts[y] ?? 0} bài',
                  child: InkWell(
                    onTap: () {
                      setState(() { _decade = y ~/ 10 * 10; _year = y; });
                      _load();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: ((_counts[y] ?? 0) / peak).clamp(0.03, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: y == _year ? AppColors.text : (y ~/ 10 * 10 == _decade ? AppColors.wine : AppColors.rose.withValues(alpha: 0.45)),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
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
        const SizedBox(height: 8),
        Row(children: [
          for (var y = first; y <= last; y += 10)
            Expanded(child: Text('$y', style: body(TextStyle(fontSize: 13, fontWeight: y == _decade ? FontWeight.w800 : FontWeight.w700, color: y == _decade ? AppColors.accentFg : AppColors.textMuted)))),
        ]),
      ]),
    );
  }
}
