import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock;
import '../services/friendly_error.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import '../widgets/empty_state.dart';

class MyTopicsScreen extends StatefulWidget {
  const MyTopicsScreen({super.key});

  @override
  State<MyTopicsScreen> createState() => _MyTopicsScreenState();
}

class _MyTopicsScreenState extends State<MyTopicsScreen> {
  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _page = 1, _lastPage = 1;
  bool _loading = true, _loadingMore = false, _error = false;
  AuthProvider? _authRef;
  bool _didInitialFetch = false;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    // Wait for auth to finish restoring the session before the first fetch
    // (a cold start / deep link would otherwise show "chưa có" for members).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authRef = context.read<AuthProvider>();
      _authRef!.addListener(_initialFetch);
      _initialFetch();
    });
  }

  void _initialFetch() {
    if (_didInitialFetch || !mounted) return;
    if (context.read<AuthProvider>().loading) return;
    _didInitialFetch = true;
    _fetch(1);
  }

  @override
  void dispose() { _authRef?.removeListener(_initialFetch); _scrollCtl.removeListener(_onScroll); _scrollCtl.dispose(); super.dispose(); }
  void _onScroll() {
    if (_loadingMore || _loading || _error || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(_page + 1);
  }

  Future<void> _fetch(int page) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?['id'];
    if (uid == null) { setState(() => _loading = false); return; }
    setState(() { _error = false; if (page == 1) { _loading = true; } else { _loadingMore = true; } });
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
        if (page == 1) { _items = list; } else { _items.addAll(list); }
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _loading = false; _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _loadingMore = false; _error = page == 1 || _items.isEmpty; });
      if (page > 1) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
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
      case 1: return AppColors.successText;
      case 0: return AppColors.warningText;
      case -1: return AppColors.errorText;
      default: return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(controller: _scrollCtl, slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg,
            title: Text('Thảo luận của tôi'),
            centerTitle: true,
            leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          ),
          if (_loading && _items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accentFg)))
          else if (!auth.isAuthenticated)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: EmptyState(icon: Icons.lock_outline, title: 'Vui lòng đăng nhập', ctaLabel: 'Đăng nhập', onCta: () => askLogin(context))))
          else if (_error)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: OfflineBlock(onRetry: () => _fetch(1))))
          else if (_items.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: EmptyState(
              icon: Icons.forum_outlined,
              title: 'Chưa có thảo luận',
              subtitle: 'Chủ đề bạn mở trên diễn đàn sẽ xuất hiện tại đây.',
            ))
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
                            Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.push_pin, size: 16, color: AppColors.accentFg)),
                          Expanded(child: Text(d['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.4)))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                            child: Text(_statusLabel(status), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _statusColor(status)))),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Wrap(spacing: 12, runSpacing: 4, children: [
                          if (d['forum']?['title'] != null)
                            Text(d['forum']['title'].toString(), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentFg))),
                          Text(timeago(d['created_at']), style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
                          if ((d['comment_count'] ?? 0) > 0)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.textMuted),
                              const SizedBox(width: 3),
                              Text('${d['comment_count']}', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
                            ]),
                          if ((d['views'] ?? 0) > 0)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.visibility_outlined, size: 14, color: AppColors.textMuted),
                              const SizedBox(width: 3),
                              Text('${d['views']}', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
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
            if (_loadingMore) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accentFg, strokeWidth: 2))),
            SizedBox(height: player.currentSong != null ? 90 : 20),
          ])),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
