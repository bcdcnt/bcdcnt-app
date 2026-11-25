import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import 'waveform_player.dart';

/// "Bản thu cùng bài trong kho": for a Tân nhạc or Bổ sung bản ghi upload,
/// every archived recording of the same song (same title, a shared
/// composer), each with its own waveform; the singer sent again is flagged.
/// Nothing shows for other types or when there is no match.
class SameRecordings extends StatefulWidget {
  final Map<String, dynamic> upload;
  const SameRecordings({super.key, required this.upload});

  @override
  State<SameRecordings> createState() => _SameRecordingsState();
}

String _names(dynamic v) => (((v is Map ? v['data'] : v) as List?) ?? const []).whereType<Map>().map((e) => '${e['title'] ?? ''}').where((t) => t.isNotEmpty).join(', ');
String _norm(String x) => x.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

class _SameRecordingsState extends State<SameRecordings> {
  List<Map<String, dynamic>> _same = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SameRecordings old) {
    super.didUpdateWidget(old);
    final u = widget.upload, o = old.upload;
    if (u['id'] != o['id'] || u['title'] != o['title'] || u['composers'] != o['composers'] || u['type'] != o['type']) _load();
  }

  Future<void> _load() async {
    final u = widget.upload;
    final type = '${u['type'] ?? ''}';
    // A replacement has its own side-by-side (ReplaceCompare).
    if (type != 'song') {
      if (_same.isNotEmpty) setState(() => _same = const []);
      return;
    }
    final obj = u['object'] is Map ? u['object'] as Map : null;
    // A replacement is about the song it replaces; a new song about itself.
    final objTitle = type == 'replace' && obj != null ? obj['title'] : null;
    final title = '${objTitle ?? u['title'] ?? ''}'.trim();
    final composers = type == 'replace' && obj != null ? _names(obj['sheet']?['composers']).split(', ') : '${u['composers'] ?? ''}'.split(RegExp(r'[,;]|\s-\s'));
    final want = composers.map(_norm).where((x) => x.isNotEmpty).toSet();
    if (title.isEmpty) return;
    final key = '${u['id']}|$title|${want.join(',')}';
    try {
      final d = await ApiClient.query(r'query($q: String) { songs(first: 30, q: $q) { data { id title subtitle views record_year artists(first: 3) { data { title } } sheet { composers(first: 3) { data { title } } } file { audio_url duration bitrate } } } }', {'q': title});
      final u2 = widget.upload;
      if (!mounted || key != '${u2['id']}|$title|${want.join(',')}') return;
      setState(() => _same = [
            for (final m in ((d['songs']?['data'] ?? []) as List).whereType<Map>())
              if (_norm('${m['title'] ?? ''}') == _norm(title) &&
                  m['file']?['audio_url'] != null &&
                  (want.isEmpty || _names(m['sheet']?['composers']).split(', ').map(_norm).any(want.contains)))
                Map<String, dynamic>.from(m),
          ]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_same.isEmpty) return const SizedBox.shrink();
    final sent = '${widget.upload['artists'] ?? ''}'.split(RegExp(r'[,;]|\s-\s')).map(_norm).where((x) => x.isNotEmpty).toSet();
    final composers = _names(_same.first['sheet']?['composers']);
    // Singers with two or more recordings here: their cards show the note
    // ("bản 1", "bản 2 · đĩa nhựa…") so the versions tell apart (canvas
    // Desktop_BanLamViec_GhiChuBanThu, chốt 24/11).
    final seen = <String, int>{};
    for (final m in _same) {
      final a = _norm(_names(m['artists']));
      if (a.isNotEmpty) seen[a] = (seen[a] ?? 0) + 1;
    }
    final repeated = {for (final e in seen.entries) if (e.value > 1) e.key};
    final ordered = _byArtist(sent);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text('Bản thu cùng bài trong kho', style: body(TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text))),
          const SizedBox(width: 8),
          Text('${_same.length}', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
        ]),
        const SizedBox(height: 2),
        Text('Cùng tên “${_same.first['title']}”${composers.isEmpty ? '' : ' · cùng nhạc sĩ $composers'} — nghe so sánh trước khi duyệt', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
        for (final m in ordered) _card(context, m, sent, repeated),
      ]),
    );
  }

  /// Grouped by singer (canvas Desktop_BanLamViec_GhiChuBanThu, chốt 24/11):
  /// the singer of the upload first, then singers with more recordings
  /// (tie: more plays), "Chưa rõ người trình bày" last; inside a singer by
  /// "bản N", else by recording year.
  List<Map<String, dynamic>> _byArtist(Set<String> sent) {
    String key(Map m) => _norm(_names(m['artists']));
    final count = <String, int>{}, plays = <String, int>{};
    for (final m in _same) {
      final k = key(m);
      count[k] = (count[k] ?? 0) + 1;
      plays[k] = (plays[k] ?? 0) + ((m['views'] as num?)?.toInt() ?? 0);
    }
    bool isSent(String k) => k.isNotEmpty && _names(_same.firstWhere((m) => key(m) == k)['artists']).split(', ').map(_norm).any(sent.contains);
    int? version(Map m) => int.tryParse(RegExp(r'bản\s*(\d+)', caseSensitive: false).firstMatch('${m['subtitle'] ?? ''}')?.group(1) ?? '');
    int year(Map m) => int.tryParse('${m['record_year'] ?? ''}') ?? 0;
    final list = [..._same];
    list.sort((a, b) {
      final ka = key(a), kb = key(b);
      if (ka != kb) {
        if (ka.isEmpty != kb.isEmpty) return ka.isEmpty ? 1 : -1;
        final sa = isSent(ka), sb = isSent(kb);
        if (sa != sb) return sa ? -1 : 1;
        final c = count[kb]!.compareTo(count[ka]!);
        if (c != 0) return c;
        final p = plays[kb]!.compareTo(plays[ka]!);
        return p != 0 ? p : ka.compareTo(kb);
      }
      final va = version(a), vb = version(b);
      if (va != null && vb != null && va != vb) return va.compareTo(vb);
      if ((va == null) != (vb == null)) return va == null ? 1 : -1;
      final y = year(a).compareTo(year(b));
      if (y != 0) return y;
      return (int.tryParse('${a['id']}') ?? 0).compareTo(int.tryParse('${b['id']}') ?? 0);
    });
    return list;
  }

  /// "(bản 2 - đĩa nhựa Nhật Bản)" → "bản 2 · đĩa nhựa Nhật Bản".
  static String _note(dynamic v) {
    var t = '${v ?? ''}'.trim();
    if (t.startsWith('(') && t.endsWith(')')) t = t.substring(1, t.length - 1).trim();
    return t.replaceAll(RegExp(r'\s+[-–—]\s+'), ' · ');
  }

  Widget _card(BuildContext context, Map<String, dynamic> m, Set<String> sent, Set<String> repeated) {
    final artists = _names(m['artists']);
    final note = repeated.contains(_norm(artists)) ? _note(m['subtitle']) : '';
    final dup = artists.split(', ').map(_norm).any(sent.contains);
    final f = m['file'] as Map;
    final meta = [
      if ('${m['record_year'] ?? ''}'.isNotEmpty && '${m['record_year']}' != '0') 'thu ${m['record_year']}',
      if (f['bitrate'] != null) '${f['bitrate']} kbps',
      '${formatViews((m['views'] as num?)?.toInt() ?? 0)} lượt nghe',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          // Name + meta share the left; "Mở ›" always sits at the right edge.
          Expanded(
            child: Row(children: [
              Flexible(child: Text(artists.isEmpty ? 'Chưa rõ người trình bày' : artists, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)))),
              if (note.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.accentFg.withValues(alpha: 0.35), width: 1.5)),
                    child: Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
                  ),
                ),
              ],
              if (dup) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.warningText.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text('trùng ca sĩ', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.warningText))),
                ),
              ],
              const SizedBox(width: 8),
              Flexible(child: Text('· $meta', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)))),
            ]),
          ),
          TextButton(onPressed: () => context.push('/song/${m['id']}', extra: {...m, 'file_type': 'song'}), child: const Text('Mở ›')),
        ]),
        const SizedBox(height: 4),
        WaveformPlayer(key: ValueKey('same-${m['id']}'), audioUrl: '${f['audio_url']}', seed: int.tryParse('${m['id']}') ?? 0, height: 34, buttonSize: 36, durationHint: (f['duration'] as num?)?.toDouble()),
      ]),
    );
  }
}
