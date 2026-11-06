import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../widgets/song_row.dart' show SongCover;
import '../widgets/ui.dart';

/// "Góp tay" — songs BQT flagged as missing information (empty_info = Y),
/// best-known first, each with what is missing. Members who remember the
/// composer, the year or the singers open the song and leave it in the
/// comments, where BQT turns it into page data (and points).
class ContributeScreen extends StatefulWidget {
  const ContributeScreen({super.key});

  @override
  State<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends State<ContributeScreen> {
  static const _perPage = 20;
  final List<Map<String, dynamic>> _items = [];
  int _page = 0, _lastPage = 1, _total = 0;
  bool _loading = false, _failed = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 500) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (!reset && _page >= _lastPage)) return;
    if (reset) {
      _items.clear();
      _page = 0;
      _lastPage = 1;
    }
    setState(() { _loading = true; _failed = false; });
    try {
      final d = await ApiClient.query(
        r'''query($page: Int!, $first: Int!) { songs(first: $first, page: $page, where: {AND: [{column: "empty_info", value: "Y"}]}, orderBy: [{column: "views", order: DESC}]) {
          data { id slug title views play_type thumbnail { url } file { audio_url video_url } sheet { year composers(first: 3) { data { id title } } } artists(first: 3) { data { id title } } }
          paginatorInfo { currentPage lastPage total }
        } }''',
        {'page': _page + 1, 'first': _perPage},
      );
      final s = d['songs'] ?? {};
      final list = ((s['data'] as List?) ?? const []).whereType<Map>().map((e) => <String, dynamic>{...Map<String, dynamic>.from(e), 'file_type': 'song'});
      if (!mounted) return;
      setState(() {
        _items.addAll(list);
        _page = (s['paginatorInfo']?['currentPage'] as num?)?.toInt() ?? _page + 1;
        _lastPage = (s['paginatorInfo']?['lastPage'] as num?)?.toInt() ?? _page;
        _total = (s['paginatorInfo']?['total'] as num?)?.toInt() ?? _items.length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  /// What the page is missing, in words a listener can answer.
  List<String> _missing(Map s) {
    final out = <String>[];
    final composers = (s['sheet']?['composers']?['data'] as List?) ?? const [];
    final artists = ((s['artists']?['data'] as List?) ?? const []).whereType<Map>().map((a) => '${a['title']}'.toLowerCase());
    if (composers.isEmpty) out.add('Tác giả');
    final year = s['sheet']?['year'];
    if (year == null || year == 0) out.add('Năm sáng tác');
    if (artists.isEmpty || artists.any((a) => a.contains('đang cập nhật'))) out.add('Người thể hiện');
    if (s['thumbnail']?['url'] == null) out.add('Ảnh');
    return out.isEmpty ? ['Thông tin bài hát'] : out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const SubPageBar(title: 'Góp tay cho kho nhạc'),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => _load(reset: true),
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 140),
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_total > 0 ? '$_total bài đang chờ bạn' : 'Bài đang chờ bạn', style: display(TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text))),
                const SizedBox(height: 8),
                Text(
                  'Những bài dưới đây còn thiếu thông tin. Bạn nhớ tác giả, năm sáng tác hay ai đã hát? Mở bài và viết vào bình luận. BQT sẽ bổ sung lên trang và cộng điểm cho bạn.',
                  style: body(TextStyle(fontSize: 15, height: 1.55, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                ),
              ]),
            ),
            for (final s in _items) _row(s),
            if (_loading)
              for (var i = 0; i < (_items.isEmpty ? 6 : 2); i++) const SkeletonSongRow()
            else if (_failed && _items.isEmpty)
              OfflineBlock(onRetry: () => _load(reset: true))
            else if (_items.isEmpty)
              const EmptyBlock(icon: Icons.volunteer_activism_outlined, title: 'Không còn bài nào thiếu', message: 'Cảm ơn các thành viên đã góp tay!'),
          ],
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> s) {
    final missing = _missing(s);
    return InkWell(
      onTap: () => context.push('/song/${s['id']}', extra: s),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SongCover(song: s, size: 56, radius: 12),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                Text('Còn thiếu:', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                for (final m in missing)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                    child: Text(m, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentLight))),
                  ),
              ]),
            ]),
          ),
          Padding(padding: const EdgeInsets.only(top: 14), child: Icon(Icons.chevron_right_rounded, color: AppColors.textMuted)),
        ]),
      ),
    );
  }
}
