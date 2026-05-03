import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';

class TagListScreen extends StatefulWidget {
  const TagListScreen({super.key});

  @override
  State<TagListScreen> createState() => _TagListScreenState();
}

class _TagListScreenState extends State<TagListScreen> {
  static const _sortOptions = [
    ('views', 'Nghe nhiều', 'views'),
    ('newest', 'Mới cập nhật', 'id'),
  ];

  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  bool _loading = true;
  String _sort = 'views';
  String _query = '';
  final _searchCtl = TextEditingController();

  @override
  void initState() { super.initState(); _fetch(); }

  @override
  void dispose() { _searchCtl.dispose(); super.dispose(); }

  Future<void> _fetch({String? sort}) async {
    final useSort = sort ?? _sort;
    final col = _sortOptions.firstWhere((o) => o.$1 == useSort, orElse: () => _sortOptions.first).$3;
    setState(() { _sort = useSort; _loading = true; });
    try {
      final data = await ApiClient.query(
        'query { tags(first: 200, page: 1, orderBy: [{column: "$col", order: DESC}]) { data { id name slug views } paginatorInfo { total } } }',
      );
      final raw = data['tags'];
      final list = ((raw?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _items = list;
        _total = raw?['paginatorInfo']?['total'] ?? 0;
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final filtered = _query.isEmpty
        ? _items
        : _items.where((t) => (t['name']?.toString() ?? '').toLowerCase().contains(_query)).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.bg.withValues(alpha: 0.88),
              title: Text('TAG', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
              centerTitle: true,
              leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList(delegate: SliverChildListDelegate([
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(colors: [Color(0xFF7A3B3A), Color(0xFF4A0D0D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: const Color(0xFF7A3B3A).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.tag, color: Colors.white, size: 28)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Tag', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                      const SizedBox(height: 4),
                      Text(_total > 0 ? '$_total tag' : (_loading ? 'Đang tải...' : 'Chưa có'), style: body(const TextStyle(fontSize: 13, color: Colors.white70))),
                    ])),
                  ]),
                ),
                const SizedBox(height: 16),

                // Sort tabs (underline style, matches search/category/BXH)
                Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                  child: SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _sortOptions.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 16),
                      itemBuilder: (ctx, i) {
                        final opt = _sortOptions[i];
                        final active = _sort == opt.$1;
                        return InkWell(
                          onTap: active ? null : () => _fetch(sort: opt.$1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: active ? AppColors.accentLight : Colors.transparent, width: 2)),
                            ),
                            child: Text(opt.$2, style: body(TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? AppColors.accentLight : AppColors.textSecondary))),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Inline filter
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: _searchCtl,
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                    style: body(TextStyle(fontSize: 14, color: AppColors.text)),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      hintText: 'Lọc tag...',
                      hintStyle: body(TextStyle(fontSize: 14, color: AppColors.textMuted)),
                      prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textMuted),
                      suffixIcon: _query.isEmpty ? null : IconButton(
                        icon: Icon(Icons.close, size: 18, color: AppColors.textMuted),
                        onPressed: () { _searchCtl.clear(); setState(() => _query = ''); },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                if (_loading)
                  Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
                else if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text(
                      _query.isEmpty ? 'Chưa có tag' : 'Không có kết quả cho "${_searchCtl.text}"',
                      style: body(TextStyle(color: AppColors.textMuted)),
                    )),
                  )
                else
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: filtered.map((t) {
                      return InkWell(
                        onTap: () => context.push('/tag/${t['slug']}'),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('#', style: TextStyle(fontSize: 12, color: AppColors.accentLight, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 2),
                            Text(t['name'] ?? '', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text))),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),

                SizedBox(height: player.currentSong != null ? 90 : 20),
              ])),
            ),
          ],
        ),
        if (player.currentSong != null)
          const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
