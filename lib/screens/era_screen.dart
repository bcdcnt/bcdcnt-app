import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/eras.dart';
import '../widgets/list_search.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart' show goBack, PillButton, SortTabs, PagedLoader, PagedList, PageResult, infiniteListBody, nearListEnd, Rail, SectionTitle, UserAvatar;

/// "Theo năm tháng" › one period (canvas "Theo năm tháng — trang giai
/// đoạn"): laid out like a Thể loại page — head card in the period's look,
/// its leading composers, Phát tất cả / Ngẫu nhiên, search, then every song
/// written in those years, loading more as you scroll.
class EraScreen extends StatefulWidget {
  final String slug;
  /// From the home card, so the head shows at once: {count, image}.
  final Map<String, dynamic>? seed;
  const EraScreen({super.key, required this.slug, this.seed});

  @override
  State<EraScreen> createState() => _EraScreenState();
}

class _EraScreenState extends State<EraScreen> with PagedLoader {
  static const _perPage = 20;
  static const _sorts = ['Nghe nhiều nhất', 'Theo năm'];
  static const _fields = 'id slug title subtitle views likes downloads created_at play_type thumbnail { url } file { audio_url video_url duration } sheet { year composers(first: 2) { data { id slug title } } } artists(first: 3) { data { id slug title } }';
  Era? get _era => eraBySlug(widget.slug);
  final _list = PagedList<Map<String, dynamic>>();
  final _scrollCtl = ScrollController();
  String _q = '';
  String? _image;
  List<Map<String, dynamic>> _composers = [];

  @override
  void initState() {
    super.initState();
    _image = widget.seed?['image']?.toString();
    _scrollCtl.addListener(() {
      if (nearListEnd(_scrollCtl, _list)) _fetch(_list.page + 1, append: true);
    });
    _fetch(1);
    _fetchComposers();
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<PageResult<Map<String, dynamic>>> _page(int page, int sort, String q) async {
    final e = _era!;
    final d = await ApiClient.query('query(\$f: Int!, \$t: Int!, \$p: Int, \$s: String, \$q: String) { songsByYear(from: \$f, to: \$t, first: $_perPage, page: \$p, sort: \$s, q: \$q) { data { $_fields } paginatorInfo { total currentPage lastPage } } }',
        {'f': e.from, 't': e.toYear, 'p': page, 's': sort == 1 ? 'year' : 'views', 'q': q});
    return PageResult.fromPaginator(d['songsByYear'], page, (m) => {...m, 'file_type': 'song'});
  }

  Future<void> _fetch(int page, {int? sort, bool append = false}) async {
    if (_era == null) return;
    await loadPage(_list, page, (page, sort) async {
      final r = await _page(page, sort, _q);
      // The best-known song's cover heads the page when the card gave none.
      if (_image == null && page == 1 && _q.isEmpty && sort == 0 && r.items.isNotEmpty) {
        _image = r.items.first['thumbnail']?['url']?.toString();
      }
      return r;
    }, sort: sort, scrollToTop: _scrollCtl, append: append);
  }

  Future<void> _fetchComposers() async {
    final e = _era;
    if (e == null) return;
    try {
      final d = await ApiClient.query(r'query($f: Int!, $t: Int!) { composersByYear(from: $f, to: $t, limit: 12) { total composer { id slug title avatar { url } } } }', {'f': e.from, 't': e.toYear});
      if (mounted) setState(() => _composers = ((d['composersByYear'] ?? []) as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList());
    } catch (_) {}
  }

  void _search(String q) {
    setState(() => _q = _list.query = q);
    _fetch(1);
  }

  /// In list order (Phát tất cả) or shuffled (Ngẫu nhiên); either way the
  /// queue keeps going into the next pages of the period.
  void _playAll({bool shuffle = false}) {
    final queue = [for (final s in _list.items) if (s['file']?['audio_url'] != null) {...s, 'audioUrl': s['file']['audio_url']}];
    if (queue.isEmpty) return;
    if (shuffle) queue.shuffle();
    final player = context.read<PlayerProvider>();
    player.playSong(queue.first, queue, 'manual', _era!.title);
    var next = _list.page + 1;
    final sort = _list.sort, q = _q;
    player.setFetchMore((_) async {
      if (next > _list.lastPage) return const [];
      final r = await _page(next++, sort, q);
      final more = [for (final s in r.items) if (s['file']?['audio_url'] != null) {...s, 'audioUrl': s['file']['audio_url']}];
      if (shuffle) more.shuffle();
      return more;
    });
    if (shuffle != player.shuffle) player.toggleShuffle();
  }

  Widget _head(Era e) {
    final fg = eraFg(e.style), sub = eraSubFg(e.style);
    final count = _list.allTotal > 0 ? _list.allTotal : (widget.seed?['count'] as int?);
    return Container(
      height: 132,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: eraBg(e.style),
        borderRadius: BorderRadius.circular(18),
        border: e.style == EraStyle.now ? Border.all(color: const Color(0xFFECE4E4)) : null,
        boxShadow: e.style == EraStyle.now ? null : [BoxShadow(color: eraBg(e.style).withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Stack(fit: StackFit.expand, children: [
        EraBackdrop(style: e.style, image: _image, wide: true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.years, style: body(TextStyle(fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w800, color: sub))),
            const SizedBox(height: 2),
            Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: fg))),
            const SizedBox(height: 4),
            Text(count != null ? '${formatInt(count)} bài' : 'Đang tải...', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: sub))),
          ]),
        ),
      ]),
    );
  }

  /// "Nhạc sĩ tiêu biểu", drawn like Cộng đồng's "Thành viên tiêu biểu".
  Widget _composerRail() {
    if (_composers.isEmpty) return const SizedBox.shrink();
    const medals = [Color(0xFFC9A227), Color(0xFF9EA3A8), Color(0xFFB0703C)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Nhạc sĩ tiêu biểu', action: null, padding: const EdgeInsets.fromLTRB(0, 4, 0, 12)),
      Rail(
        height: 130,
        textHeight: 52,
        gap: 22,
        count: _composers.length,
        builder: (_, i) {
          final c = Map<String, dynamic>.from(_composers[i]['composer'] as Map);
          final n = (_composers[i]['total'] as num?)?.toInt() ?? 0;
          return Semantics(
            button: true,
            excludeSemantics: true,
            label: 'Nhạc sĩ ${c['title']}, $n bài',
            child: GestureDetector(
              onTap: () => context.push('/nhac-si/${c['slug']}'),
              child: SizedBox(
                width: 76,
                child: Column(children: [
                  Stack(clipBehavior: Clip.none, children: [
                    UserAvatar(url: c['avatar']?['url']?.toString(), name: '${c['title'] ?? ''}', size: 76),
                    Positioned(
                      right: -2, bottom: -2,
                      child: Container(
                        width: 26, height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: i < 3 ? medals[i] : const Color(0xFFC4B8B9), shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2)),
                        child: Text('${i + 1}', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white))),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text('${c['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
                  Text('$n bài', maxLines: 1, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                ]),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final e = _era;
    final back = IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context));
    if (e == null) {
      return Scaffold(backgroundColor: AppColors.bg, appBar: AppBar(leading: back), body: Center(child: Text('Không tìm thấy giai đoạn', style: AppText.bodyText)));
    }
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(
          controller: _scrollCtl,
          slivers: [
            SliverAppBar(pinned: true, backgroundColor: AppColors.bg, title: const Text('Theo năm tháng'), centerTitle: true, leading: back),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _head(e),
                  _composerRail(),
                  if (_list.items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(children: [
                        Expanded(child: PillButton(onTap: () => _playAll(), icon: Icons.play_arrow, label: 'Phát tất cả', primary: true)),
                        const SizedBox(width: 10),
                        Expanded(child: PillButton(onTap: () => _playAll(shuffle: true), icon: Icons.shuffle, label: 'Ngẫu nhiên', primary: false)),
                      ]),
                    ),
                  ListSearchField(hint: 'Tìm trong ${_list.allTotal > 0 ? '${formatInt(_list.allTotal)} bài ' : ''}${e.title}', onChanged: _search),
                  ListSearchSummary(query: _q, total: _list.total, loading: _list.loading),
                  const SizedBox(height: 14),
                  SortTabs(labels: _sorts, selected: _list.sort, padding: EdgeInsets.zero, onSelect: (i) => _fetch(1, sort: i)),
                  const SizedBox(height: 14),
                  ...infiniteListBody<Map<String, dynamic>>(
                    _list,
                    onRetry: () => _fetch(_list.page),
                    onMore: () => _fetch(_list.page + 1, append: true),
                    empty: _q.isEmpty ? null : ListSearchEmpty(query: _q),
                    itemBuilder: (song, i) => SongRow(highlight: _q, song: song, index: i, showIndex: true, metricKey: 'views', queue: _list.items, sourceLabel: e.title),
                  ),
                  SizedBox(height: player.currentSong != null ? 90 : 20),
                ]),
              ),
            ),
          ],
        ),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
