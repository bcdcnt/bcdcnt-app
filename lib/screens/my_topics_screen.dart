import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';

class MyTopicsScreen extends StatefulWidget {
  const MyTopicsScreen({super.key});

  @override
  State<MyTopicsScreen> createState() => _MyTopicsScreenState();
}

class _MyTopicsScreenState extends State<MyTopicsScreen> {
  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _page = 1, _lastPage = 1;
  bool _loading = true, _loadingMore = false;

  @override
  void initState() { super.initState(); _scrollCtl.addListener(_onScroll); WidgetsBinding.instance.addPostFrameCallback((_) => _fetch(1)); }
  @override
  void dispose() { _scrollCtl.removeListener(_onScroll); _scrollCtl.dispose(); super.dispose(); }
  void _onScroll() {
    if (_loadingMore || _loading || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(_page + 1);
  }

  Future<void> _fetch(int page) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?['id'];
    if (uid == null) { setState(() => _loading = false); return; }
    setState(() { if (page == 1) _loading = true; else _loadingMore = true; });
    try {
      final data = await ApiClient.query(r'''query($first: Int!, $page: Int, $where: WhereConditions) {
        discussions(first: $first, page: $page, orderBy: [{column: "is_sticky", order: DESC}, {column: "id", order: DESC}], where: $where) {
          data {
            id title slug status is_sticky created_at comment_count views
            forum { id title }
          }
          paginatorInfo { lastPage currentPage }
        }
      }''', {'first': 20, 'page': page, 'where': {'AND': [{'column': 'user_id', 'value': '$uid'}]}});
      final c = data['discussions'];
      final list = ((c?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final pi = c?['paginatorInfo'] ?? {};
      if (!mounted) return;
      setState(() {
        if (page == 1) _items = list; else _items.addAll(list);
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _loading = false; _loadingMore = false;
      });
    } catch (_) { if (mounted) setState(() { _loading = false; _loadingMore = false; }); }
  }

  String _statusLabel(int? status) {
    switch (status) {
      case 1: return 'Đã duyệt';
      case 0: return 'Chờ duyệt';
      case -1: return 'Từ chối';
      default: return '';
    }
  }
  Color _statusColor(int? status) {
    switch (status) {
      case 1: return const Color(0xFF66BB6A);
      case 0: return const Color(0xFFFFA726);
      case -1: return AppColors.error;
      default: return AppColors.textMuted;
    }
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
            title: Text('THẢO LUẬN CỦA TÔI', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          if (_loading && _items.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else if (_items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Bạn chưa có chủ đề nào', style: AppText.bodyText)))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final d = _items[i];
                  final status = d['status'] is int ? d['status'] as int : int.tryParse('${d['status']}');
                  return InkWell(
                    onTap: () => context.push('/thao-luan/${d['id']}'),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          if (d['is_sticky'] == true || d['is_sticky'] == 1)
                            Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.push_pin, size: 12, color: AppColors.accentLight)),
                          Expanded(child: Text(d['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.4)))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                            child: Text(_statusLabel(status), style: body(TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _statusColor(status)))),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Wrap(spacing: 12, children: [
                          if (d['forum']?['title'] != null)
                            Text(d['forum']['title'], style: body(const TextStyle(fontSize: 11, color: AppColors.accentLight))),
                          Text(timeago(d['created_at']), style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                          if ((d['comment_count'] ?? 0) > 0)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.chat_bubble_outline, size: 11, color: AppColors.textMuted),
                              const SizedBox(width: 3),
                              Text('${d['comment_count']}', style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                            ]),
                          if ((d['views'] ?? 0) > 0)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.visibility_outlined, size: 11, color: AppColors.textMuted),
                              const SizedBox(width: 3),
                              Text('${d['views']}', style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                            ]),
                        ]),
                      ]),
                    ),
                  );
                },
                childCount: _items.length,
              )),
            ),
          SliverToBoxAdapter(child: Column(children: [
            if (_loadingMore) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
            SizedBox(height: player.currentSong != null ? 90 : 20),
          ])),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
