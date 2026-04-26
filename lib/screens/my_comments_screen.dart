import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';

class MyCommentsScreen extends StatefulWidget {
  const MyCommentsScreen({super.key});

  @override
  State<MyCommentsScreen> createState() => _MyCommentsScreenState();
}

class _MyCommentsScreenState extends State<MyCommentsScreen> {
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
      final data = await ApiClient.query(r'''query($id: ID!, $first: Int!, $page: Int) {
        user(id: $id) {
          comments(first: $first, page: $page, orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: 1}]}) {
            data {
              id content created_at
              object {
                __typename
                ... on Song { id title slug }
                ... on Folk { id title slug }
                ... on Instrumental { id title slug }
                ... on Poem { id title slug }
                ... on Karaoke { id title slug }
                ... on Artist { id title slug }
                ... on Composer { id title slug }
                ... on Discussion { id title slug }
                ... on Sheet { id title slug }
              }
            }
            paginatorInfo { lastPage currentPage }
          }
        }
      }''', {'id': '$uid', 'first': 20, 'page': page});
      final c = data['user']?['comments'];
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

  String _stripHtml(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  String? _routeForObject(Map<String, dynamic>? obj) {
    if (obj == null) return null;
    final type = (obj['__typename'] ?? '').toString().toLowerCase();
    if (['song', 'folk', 'instrumental', 'poem', 'karaoke'].contains(type)) return '/song/${obj['id']}';
    if (type == 'sheet') return '/sheet/${obj['id']}';
    if (type == 'discussion') return '/thao-luan/${obj['id']}';
    if (type == 'artist') return '/nghe-si/${obj['slug']}';
    if (type == 'composer') return '/nhac-si/${obj['slug']}';
    return null;
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
            title: Text('BÌNH LUẬN CỦA TÔI', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          if (_loading && _items.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else if (_items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Bạn chưa có bình luận nào', style: AppText.bodyText)))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final c = _items[i];
                  final obj = c['object'] != null ? Map<String, dynamic>.from(c['object'] as Map) : null;
                  final route = _routeForObject(obj);
                  return InkWell(
                    onTap: route != null ? () => context.push(route) : null,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (obj?['title'] != null)
                          Text(obj!['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accentLight))),
                        const SizedBox(height: 4),
                        Text(_stripHtml(c['content'] ?? ''), maxLines: 3, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, color: AppColors.text, height: 1.5))),
                        const SizedBox(height: 6),
                        Text(timeago(c['created_at']), style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
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
