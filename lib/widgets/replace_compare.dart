import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import 'waveform_player.dart';

/// Bàn làm việc, "Thay thế bản thu chất lượng": the recording sent and the
/// one on the site now, each with its own player, then their technical
/// sheets side by side (API fileAudioStats, measured once with ffmpeg);
/// the better value of a measurable row is green with ▲.
class ReplaceCompare extends StatefulWidget {
  final Map<String, dynamic> upload;
  const ReplaceCompare({super.key, required this.upload});

  @override
  State<ReplaceCompare> createState() => _ReplaceCompareState();
}

class _ReplaceCompareState extends State<ReplaceCompare> {
  Map<String, dynamic>? _newStats, _curStats;
  bool _newDone = false, _curDone = false;
  /// Measuring failed (or never answered): that column offers "Thử lại".
  bool _newFailed = false, _curFailed = false;
  /// Nghe cân bằng: null = automatic (on when the two differ by ≥ 2 LU).
  bool? _balance;

  Map get _newFile => widget.upload['file'] is Map ? widget.upload['file'] as Map : const {};
  /// The recording being replaced: the upload's object, else the archive link
  /// it carries (".../bai-hat/slug-21.html"), as web /admin/gui-bai does.
  Map? _target;
  String _targetType = 'song';
  Map? get _song => _target;

  static const _routeType = {'bai-hat': 'song', 'dan-ca': 'folk', 'khi-nhac': 'instrumental', 'tieng-tho': 'poem', 'thanh-vien-hat': 'karaoke'};

  Future<void> _resolveTarget() async {
    final u = widget.upload;
    if (u['object'] is Map && (u['object'] as Map)['id'] != null) {
      _target = u['object'] as Map;
      _targetType = 'song';
      return;
    }
    RegExpMatch? m;
    for (final x in [u['link'], u['title']]) {
      m = RegExp(r'/(bai-hat|dan-ca|khi-nhac|tieng-tho|thanh-vien-hat)/[^/]+-(\d+)\.html').firstMatch('${x ?? ''}');
      if (m != null) break;
    }
    if (m == null) return;
    final type = _routeType[m.group(1)]!;
    final withArtists = const {'song', 'folk', 'instrumental'}.contains(type);
    try {
      final d = await context.read<AuthProvider>().authedQuery(
        'query(\$id: ID!) { t: $type(id: \$id) { id title ${withArtists ? 'artists(first: 3) { data { title } }' : ''} file { id audio_url duration bitrate is_hq user { username } } } }',
        {'id': m.group(2)},
      );
      if (d['t'] is Map) {
        _target = Map<String, dynamic>.from(d['t']);
        _targetType = type;
      }
    } catch (_) {}
  }
  Map get _curFile => _song?['file'] is Map ? _song!['file'] as Map : const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReplaceCompare old) {
    super.didUpdateWidget(old);
    if (old.upload['id'] != widget.upload['id']) _load();
  }

  Future<void> _load() async {
    final uid = widget.upload['id'];
    setState(() { _newStats = _curStats = null; _newDone = _curDone = false; _target = null; });
    await _resolveTarget();
    if (!mounted || widget.upload['id'] != uid) return;
    setState(() {});
    _measure(isNew: true);
    _measure(isNew: false);
  }

  /// Measured in the API queue: {pending: true} until done, so ask again
  /// every 3 s (up to ~2 minutes). [refresh] asks for a new measurement.
  Future<void> _measure({required bool isNew, bool refresh = false}) async {
    final uid = widget.upload['id'];
    final fileId = (isNew ? _newFile : _curFile)['id'];
    setState(() {
      if (isNew) { _newDone = false; _newFailed = false; } else { _curDone = false; _curFailed = false; }
    });
    Map<String, dynamic>? s;
    var failed = fileId != null;
    if (fileId != null) {
      for (var i = 0; i < 40; i++) {
        try {
          final d = await context.read<AuthProvider>().authedQuery(
            r'query($id: ID!, $refresh: Boolean) { fileAudioStats(id: $id, refresh: $refresh) { pending failed sample_rate channels bitrate size duration loudness true_peak peak clipped cutoff lead_silence trail_silence } }',
            {'id': '$fileId', 'refresh': refresh && i == 0},
          );
          final r = d['fileAudioStats'];
          if (r is Map && r['pending'] != true) {
            if (r['failed'] != true) {
              s = Map<String, dynamic>.from(r);
              failed = false;
            }
            break;
          }
          if (r == null) break;
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted || widget.upload['id'] != uid) return;
      }
    }
    if (!mounted || widget.upload['id'] != uid) return;
    setState(() {
      if (isNew) { _newStats = s; _newDone = true; _newFailed = failed; } else { _curStats = s; _curDone = true; _curFailed = failed; }
    });
  }

  static String _dec(num v, [int d = 1]) => v.toStringAsFixed(d).replaceAll('.', ',').replaceAll('-', '−');
  static String _dur(num? s) => s == null ? '—' : '${s ~/ 60}:${(s.round() % 60).toString().padLeft(2, '0')}';
  static String _hz(num? v) => v == null ? '—' : (v % 1000 == 0 ? '${v ~/ 1000} kHz' : '${_dec(v / 1000)} kHz');
  static String _cut(num? v) => v == null ? '—' : v == 0 ? '< 11 kHz' : v >= 21000 ? '≥ 21 kHz' : '≈${v ~/ 1000} kHz';
  static String _mb(num? b) => b == null ? '—' : '${_dec(b / 1048576)} MB';

  /// Loudness band: quá to (> −11 LUFS) / vừa (−20 … −11) / nhỏ (< −20).
  static (String, Color, Color) _loudBand(num lufs) {
    final light = AppColors.isLight;
    if (lufs > -11) return ('quá to', light ? const Color(0xFFFFF4DE) : const Color(0xFF3A2E14), AppColors.warningText);
    if (lufs < -20) return ('nhỏ', AppColors.surfaceLight, AppColors.textSecondary);
    return ('vừa', light ? const Color(0xFFE5F3EA) : const Color(0xFF15301F), AppColors.successText);
  }

  Widget _loudCell(Map stats, bool waiting) {
    final v = stats['loudness'] as num?;
    if (waiting || v == null) return Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), child: Text(waiting ? 'Đang phân tích…' : '—', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: waiting ? AppColors.textMuted : AppColors.text))));
    final (label, bg, fg) = _loudBand(v);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
        Text('${_dec(v)} LUFS', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Text(label, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg))),
        ),
      ]),
    );
  }

  /// "Đo không được · Thử lại" in the column whose measuring failed.
  Widget _retry(bool isNew) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: InkWell(
          onTap: () => _measure(isNew: isNew, refresh: true),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'Đo không được · ', style: TextStyle(color: AppColors.errorText)),
            TextSpan(text: 'Thử lại', style: TextStyle(color: AppColors.accentFg, decoration: TextDecoration.underline)),
          ]), style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
        ),
      );

  Widget _player({required String tag, required Color tagBg, required Widget sub, required Map file, required int seed, double volume = 1.0}) {
    final url = file['audio_url'];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 20, 14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(6)),
            child: Text(tag, style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Colors.white))),
          ),
          const SizedBox(width: 8),
          Flexible(child: sub),
        ]),
        const SizedBox(height: 8),
        if (url == null)
          Text('Không có file', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted)))
        else
          WaveformPlayer(
            key: ValueKey('rc-$seed-$url'),
            audioUrl: '$url',
            seed: seed,
            durationHint: (file['duration'] as num?)?.toDouble(),
            volume: volume,
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = _song;
    final muted = body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary));
    final n = _newStats ?? const {}, c = _curStats ?? const {};

    // (label, hint, new, current, which is better: 1 new, -1 current, 0 none)
    int cmp(num? a, num? b, {bool higher = true}) => a == null || b == null || a == b ? 0 : ((a > b) == higher ? 1 : -1);
    final rows = <(String, String?, String, String, int)>[
      ('Thời lượng', null, _dur(n['duration'] ?? _newFile['duration']), _dur(c['duration'] ?? _curFile['duration']), 0),
      ('Bitrate', null, '${n['bitrate'] ?? _newFile['bitrate'] ?? '—'} kbps', '${c['bitrate'] ?? _curFile['bitrate'] ?? '—'} kbps', cmp(n['bitrate'] ?? _newFile['bitrate'], c['bitrate'] ?? _curFile['bitrate'])),
      ('Tần số lấy mẫu', null, _hz(n['sample_rate']), _hz(c['sample_rate']), cmp(n['sample_rate'], c['sample_rate'])),
      ('Kênh', null, n['channels'] == null ? '—' : (n['channels'] == 1 ? 'Mono' : 'Stereo'), c['channels'] == null ? '—' : (c['channels'] == 1 ? 'Mono' : 'Stereo'), cmp(n['channels'], c['channels'])),
      ('Dung lượng', null, _mb(n['size']), _mb(c['size']), 0),
      ('Chất lượng cao (HQ)', null, _newFile['is_hq'] == 1 ? 'Đã đánh dấu' : '—', _curFile['is_hq'] == 1 ? 'Đã đánh dấu' : 'Chưa đánh dấu', 0),
      ('Độ to', 'âm lượng cảm nhận · vừa: −20 … −11', n['loudness'] == null ? '—' : '${_dec(n['loudness'])} LUFS', c['loudness'] == null ? '—' : '${_dec(c['loudness'])} LUFS', 0),
      ('Đỉnh · cắt đỉnh', 'méo do vượt 0 dB', n['peak'] == null ? '—' : '${_dec(n['peak'])} dBFS · ${n['clipped'] ?? 0} chỗ', c['peak'] == null ? '—' : '${_dec(c['peak'])} dBFS · ${c['clipped'] ?? 0} chỗ', cmp(n['clipped'], c['clipped'], higher: false)),
      ('Tần số cắt', 'thấp = nâng bitrate giả / bản gốc kém', _cut(n['cutoff']), _cut(c['cutoff']), cmp(n['cutoff'], c['cutoff'])),
      ('Lặng đầu · cuối', '0 s ở đầu có thể bị cụt', n['lead_silence'] == null ? '—' : '${_dec(n['lead_silence'])} s · ${_dec(n['trail_silence'] ?? 0)} s', c['lead_silence'] == null ? '—' : '${_dec(c['lead_silence'])} s · ${_dec(c['trail_silence'] ?? 0)} s', 0),
    ];

    Widget cell(String text, {bool better = false, bool waiting = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            waiting ? 'Đang phân tích…' : (better ? '$text ▲' : text),
            style: body(TextStyle(
              fontSize: 14,
              fontWeight: better ? FontWeight.w800 : FontWeight.w700,
              color: waiting ? AppColors.textMuted : (better ? AppColors.successText : AppColors.text),
            )),
          ),
        );
    final head = body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textMuted));

    // Nghe cân bằng: lower the louder one by the LUFS gap.
    final ln = n['loudness'] as num?, lc = c['loudness'] as num?;
    final gap = ln != null && lc != null ? (ln - lc).toDouble() : null;
    final balanceOn = gap != null && (_balance ?? gap.abs() >= 2);
    double gain(double db) => math.pow(10, -db.abs() / 20).toDouble();
    final newVol = balanceOn && gap > 0 ? gain(gap) : 1.0;
    final curVol = balanceOn && gap < 0 ? gain(gap) : 1.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (gap != null) ...[
        Row(children: [
          Material(
            color: balanceOn ? AppColors.accent : AppColors.bg,
            shape: StadiumBorder(side: balanceOn ? BorderSide.none : BorderSide(color: AppColors.border, width: 1.5)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => setState(() => _balance = !balanceOn),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.balance_rounded, size: 18, color: balanceOn ? Colors.white : AppColors.text),
                  const SizedBox(width: 6),
                  Text('Nghe cân bằng', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: balanceOn ? Colors.white : AppColors.text))),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              gap.abs() < 0.05
                  ? 'Hai bản to ngang nhau'
                  : balanceOn
                      ? 'Đang giảm ${gap > 0 ? 'bản gửi mới' : 'bản hiện tại'} ${_dec(gap.abs())} dB để nghe ngang ${gap > 0 ? 'bản hiện tại' : 'bản gửi mới'}'
                      : '${gap > 0 ? 'Bản gửi mới' : 'Bản hiện tại'} to hơn ${_dec(gap.abs())} dB',
              style: muted,
            ),
          ),
        ]),
        const SizedBox(height: 10),
      ],
      _player(
        tag: 'BẢN GỬI MỚI',
        volume: newVol,
        tagBg: AppColors.accent,
        sub: Text('${widget.upload['user']?['username'] ?? ''} gửi', style: muted),
        file: _newFile,
        seed: int.tryParse('${widget.upload['id']}') ?? 0,
      ),
      const SizedBox(height: 10),
      _player(
        tag: 'BẢN HIỆN TẠI',
        volume: curVol,
        tagBg: const Color(0xFF3B3335),
        sub: song == null
            ? Text('Không tìm thấy bài đang thay', style: muted)
            : InkWell(
                onTap: () => context.push('/song/${song['id']}', extra: {...Map<String, dynamic>.from(song), 'file_type': _targetType}),
                child: Text.rich(TextSpan(children: [
                  // Who uploaded the file on the site now, like "X gửi" above.
                  TextSpan(text: '${'${_curFile['user']?['username'] ?? ''}'.trim().isEmpty ? 'Không rõ người tải' : '${_curFile['user']['username']} gửi'} · '),
                  TextSpan(text: 'Mở bài ›', style: TextStyle(color: AppColors.accentFg)),
                ]), style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
        file: _curFile,
        seed: int.tryParse('${song?['id']}') ?? 1,
      ),
      const SizedBox(height: 14),
      Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: Table(
          columnWidths: const {0: FixedColumnWidth(200), 1: FlexColumnWidth(), 2: FlexColumnWidth()},
          border: TableBorder(horizontalInside: BorderSide(color: AppColors.borderSubtle)),
          children: [
            TableRow(decoration: BoxDecoration(color: AppColors.surface), children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Text('THÔNG SỐ', style: head)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Text('BẢN GỬI MỚI', style: head.copyWith(color: AppColors.accentFg))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Text('BẢN HIỆN TẠI', style: head)),
            ]),
            for (final (i, r) in rows.indexed)
              TableRow(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.$1, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                    if (r.$2 != null) Text(r.$2!, style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                  ]),
                ),
                // Rows past the first two come from the analysis.
                if (i == 2 && _newFailed) _retry(true)
                else if (i == 6) _loudCell(n, !_newDone && _newFile['id'] != null)
                else cell(r.$3, better: r.$5 == 1, waiting: i >= 2 && i != 5 && !_newDone && _newFile['id'] != null),
                if (i == 2 && _curFailed) _retry(false)
                else if (i == 6) _loudCell(c, !_curDone && _curFile['id'] != null)
                else cell(r.$4, better: r.$5 == -1, waiting: i >= 2 && i != 5 && !_curDone && _curFile['id'] != null),
              ]),
          ],
        ),
      ),
    ]);
  }
}
