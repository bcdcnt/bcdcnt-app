import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, Skeleton, SortTabs, PagedLoader, PagedList, PageResult, pagedListBody;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import '../widgets/desktop_page.dart';

class SheetListScreen extends StatefulWidget {
  const SheetListScreen({super.key});

  @override
  State<SheetListScreen> createState() => _SheetListScreenState();
}

class _SheetListScreenState extends State<SheetListScreen> with PagedLoader {
  static const _perPage = 20;
  // The sheet table has views + id but no likes/downloads, and a score is
  // read, not listened to — so "Xem nhiều nhất" instead of "Nghe nhiều nhất".
  static const _sorts = ['Mới cập nhật', 'Xem nhiều nhất'];
  static const _sortCols = ['id', 'views'];
  final _scrollCtl = ScrollController();
  final _list = PagedList<Map<String, dynamic>>();

  @override
  void initState() { super.initState(); _fetch(1); }
  @override
  void dispose() { _scrollCtl.dispose(); super.dispose(); }

  Future<void> _fetch(int page, {int? sort}) => loadPage(_list, page, (page, sort) async {
        final data = await ApiClient.query('''query(\$page: Int, \$where: WhereConditions) {
          sheets(first: $_perPage, page: \$page, where: \$where, orderBy: [{column: "${_sortCols[sort]}", order: DESC}]) {
            data { id slug title year composers(first: 5) { data { id slug title } } }
            paginatorInfo { currentPage lastPage total }
          }
        }''', {'page': page, 'where': {'AND': [{'column': 'content', 'operator': 'NEQ', 'value': ''}]}});
        return PageResult.fromPaginator(data['sheets'], page);
      }, sort: sort, scrollToTop: _scrollCtl);

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 == 0) buf.write('.'); buf.write(s[i]); }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final desk = isDesk(context);
    final count = _list.total > 0 ? '${_formatInt(_list.total)} bản nhạc' : (!_list.loaded && !_list.failed ? 'Đang tải...' : (_list.failed ? '' : 'Chưa có'));
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        DeskFrame(maxWidth: desk ? 1320 : double.infinity, child: CustomScrollView(controller: _scrollCtl, slivers: [
          if (!desk)
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg,
            title: Text('Bản nhạc'),
            centerTitle: true,
            leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          ),
          SliverPadding(
            padding: desk ? deskPad : const EdgeInsets.fromLTRB(20, 8, 20, 16),
            sliver: SliverList(delegate: SliverChildListDelegate([
              if (desk)
                DeskHead(title: 'Bản nhạc', subtitle: count)
              else ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(colors: [AppColors.deep, AppColors.wine], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: AppColors.deep.withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Row(children: [
                  Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.music_note_outlined, color: Colors.white, size: 28)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Bản nhạc', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                    const SizedBox(height: 4),
                    Text(count, style: body(const TextStyle(fontSize: 15, color: Colors.white70))),
                  ])),
                ]),
              ),
              const SizedBox(height: 14),
              ],
              SortTabs(labels: _sorts, selected: _list.sort, padding: EdgeInsets.zero, onSelect: (i) => _fetch(1, sort: i)),
              SizedBox(height: desk ? 18 : 14),
              if (desk) const _SheetTableHead(),
              ...pagedListBody<Map<String, dynamic>>(
                _list,
                perPage: _perPage,
                emptyText: 'Chưa có bản nhạc',
                onRetry: () => _fetch(_list.page),
                onPage: (p) => _fetch(p),
                skeleton: desk
                    ? Column(children: [for (var i = 0; i < 10; i++) const Skeleton(height: 44, margin: EdgeInsets.only(top: 8))])
                    : Column(children: [for (var i = 0; i < 8; i++) const Skeleton(height: 66, margin: EdgeInsets.only(bottom: 8))]),
                itemBuilder: (s, i) => desk ? _SheetTableRow(sheet: s) : _SheetCard(sheet: s),
              ),
              SizedBox(height: player.currentSong != null ? 90 : 20),
            ])),
          ),
        ])),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}

class _SheetCard extends StatelessWidget {
  final Map<String, dynamic> sheet;
  const _SheetCard({required this.sheet});

  @override
  Widget build(BuildContext context) {
    final s = sheet;
    final composers = (s['composers']?['data'] ?? []) as List;
    return InkWell(
      onTap: () => context.push('/sheet/${s['id']}'),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.music_note_outlined, color: AppColors.accentLight, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(s['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
            const SizedBox(height: 2),
            Row(children: [
              if (composers.isNotEmpty) Flexible(child: Text(composers.map((c) => c['title']).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary)))),
              if (s['year'] != null && s['year'].toString().isNotEmpty) ...[
                if (composers.isNotEmpty) const SizedBox(width: 6),
                Text('(${s['year']})', style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary))),
              ],
            ]),
          ])),
          Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
        ]),
      ),
    );
  }
}

// Desktop table: BẢN NHẠC · TÁC GIẢ · NĂM · ›. Column widths are shared by
// the head and the rows.
const _kAuthorW = 260.0;
const _kYearW = 72.0;
const _kChevW = 32.0;

class _SheetTableHead extends StatelessWidget {
  const _SheetTableHead();

  @override
  Widget build(BuildContext context) {
    final st = body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted));
    return Container(
      height: 34,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        const SizedBox(width: 12),
        Expanded(child: Text('BẢN NHẠC', style: st)),
        SizedBox(width: _kAuthorW, child: Text('TÁC GIẢ', style: st)),
        SizedBox(width: _kYearW, child: Text('NĂM', style: st)),
        const SizedBox(width: _kChevW),
      ]),
    );
  }
}

class _SheetTableRow extends StatelessWidget {
  final Map<String, dynamic> sheet;
  const _SheetTableRow({required this.sheet});

  @override
  Widget build(BuildContext context) {
    final s = sheet;
    final composers = ((s['composers']?['data'] ?? []) as List).map((c) => c['title']).whereType<String>().join(', ');
    final year = s['year']?.toString() ?? '';
    final cell = body(TextStyle(fontSize: 15, color: AppColors.textSecondary));
    return InkWell(
      onTap: () => context.push('/sheet/${s['id']}'),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(children: [
          const SizedBox(width: 12),
          Expanded(child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(s['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
          )),
          SizedBox(width: _kAuthorW, child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(composers, maxLines: 1, overflow: TextOverflow.ellipsis, style: cell),
          )),
          SizedBox(width: _kYearW, child: Text(year, style: cell)),
          SizedBox(width: _kChevW, child: Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18)),
        ]),
      ),
    );
  }
}
