import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';

class SheetListScreen extends StatefulWidget {
  const SheetListScreen({super.key});

  @override
  State<SheetListScreen> createState() => _SheetListScreenState();
}

class _SheetListScreenState extends State<SheetListScreen> {
  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _page = 1, _lastPage = 1, _total = 0;
  bool _loading = true, _loadingMore = false;

  @override
  void initState() { super.initState(); _scrollCtl.addListener(_onScroll); _fetch(1); }
  @override
  void dispose() { _scrollCtl.removeListener(_onScroll); _scrollCtl.dispose(); super.dispose(); }
  void _onScroll() {
    if (_loadingMore || _loading || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(_page + 1);
  }

  Future<void> _fetch(int page) async {
    setState(() { if (page == 1) _loading = true; else _loadingMore = true; });
    try {
      final data = await ApiClient.query(r'''query($page: Int, $where: WhereConditions) {
        sheets(first: 20, page: $page, where: $where, orderBy: [{column: "id", order: DESC}]) {
          data { id slug title year composers(first: 5) { data { id slug title } } }
          paginatorInfo { currentPage lastPage total }
        }
      }''', {'page': page, 'where': {'AND': [{'column': 'content', 'operator': 'NEQ', 'value': ''}]}});
      final raw = data['sheets'];
      final list = ((raw?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final pi = raw?['paginatorInfo'] ?? {};
      if (!mounted) return;
      setState(() {
        if (page == 1) _items = list; else _items.addAll(list);
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _total = pi['total'] ?? _total;
        _loading = false; _loadingMore = false;
      });
    } catch (_) { if (mounted) setState(() { _loading = false; _loadingMore = false; }); }
  }

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 == 0) buf.write('.'); buf.write(s[i]); }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(controller: _scrollCtl, slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text('BẢN NHẠC', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            sliver: SliverList(delegate: SliverChildListDelegate([
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(colors: [Color(0xFF4A0D0D), Color(0xFF711313)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: const Color(0xFF4A0D0D).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Row(children: [
                  Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.music_note_outlined, color: Colors.white, size: 28)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Bản nhạc', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                    const SizedBox(height: 4),
                    Text(_total > 0 ? '${_formatInt(_total)} bản nhạc' : (_loading ? 'Đang tải...' : 'Chưa có'), style: body(const TextStyle(fontSize: 13, color: Colors.white70))),
                  ])),
                ]),
              ),
              const SizedBox(height: 14),
            ])),
          ),
          if (_loading && _items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final s = _items[i];
                  final composers = (s['composers']?['data'] ?? []) as List;
                  return InkWell(
                    onTap: () => context.push('/sheet/${s['id']}'),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                      child: Row(children: [
                        Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.music_note_outlined, color: AppColors.accentLight, size: 18)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(s['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
                          const SizedBox(height: 2),
                          Row(children: [
                            if (composers.isNotEmpty) Flexible(child: Text(composers.map((c) => c['title']).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 11, color: AppColors.textMuted)))),
                            if (s['year'] != null && s['year'].toString().isNotEmpty) ...[
                              if (composers.isNotEmpty) const SizedBox(width: 6),
                              Text('(${s['year']})', style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
                            ],
                          ]),
                        ])),
                        Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
                      ]),
                    ),
                  );
                },
                childCount: _items.length,
              )),
            ),
          SliverToBoxAdapter(child: Column(children: [
            if (_loadingMore) Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
            SizedBox(height: player.currentSong != null ? 90 : 20),
          ])),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
