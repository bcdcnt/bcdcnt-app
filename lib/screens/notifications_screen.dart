import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../services/date_groups.dart';
import '../widgets/empty_state.dart';
import '../widgets/mini_player.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _page = 1, _lastPage = 1;
  bool _loading = true, _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetch(1);
      _resetUnread();
    });
  }
  @override
  void dispose() { _scrollCtl.removeListener(_onScroll); _scrollCtl.dispose(); super.dispose(); }
  void _onScroll() {
    if (_loadingMore || _loading || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(_page + 1);
  }

  Future<void> _resetUnread() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    // Update local cache instantly for badge feedback
    auth.clearUnread();
    try { await auth.authedMutate(r'mutation { resetUnread }', null); } catch (_) {}
  }

  Future<void> _fetch(int page) async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) { setState(() => _loading = false); return; }
    setState(() { if (page == 1) _loading = true; else _loadingMore = true; });
    try {
      final data = await auth.authedQuery(r'''query($first: Int!, $page: Int) {
        me {
          notifications(first: $first, page: $page, orderBy: [{column: "created_at", order: DESC}]) {
            data { id code content action extra object_type object_id is_read created_at sender { id username avatar { url } } }
            paginatorInfo { lastPage currentPage }
          }
        }
      }''', {'first': 20, 'page': page});
      final n = data['me']?['notifications'];
      final list = ((n?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final pi = n?['paginatorInfo'] ?? {};
      if (!mounted) return;
      setState(() {
        if (page == 1) _items = list; else _items.addAll(list);
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _loading = false; _loadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _loadingMore = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Lỗi tải thông báo: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _markAllRead() async {
    final auth = context.read<AuthProvider>();
    try { await auth.authedMutate(r'mutation { markAsReadAll }', null); } catch (_) {}
    setState(() { _items = _items.map((i) { i['is_read'] = 1; return i; }).toList(); });
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    final auth = context.read<AuthProvider>();
    if (n['code'] == null) return;
    try { await auth.authedMutate(r'mutation($code: String!) { markAsRead(code: $code) }', {'code': n['code']}); } catch (_) {}
    setState(() { final idx = _items.indexWhere((i) => i['id'] == n['id']); if (idx >= 0) _items[idx]['is_read'] = 1; });
  }

  String? _routeFor(Map<String, dynamic> notif) {
    Map? router;
    final extra = notif['extra'];
    if (extra != null) {
      try {
        final parsed = extra is String ? jsonDecode(extra) : extra;
        if (parsed is Map) router = parsed['router'] is Map ? parsed['router'] : parsed;
      } catch (_) {}
    }
    // Upload notif without router data → review page (admin)
    if (notif['object_type'] == 'upload' && router?['slug'] == null) {
      return '/bai-gui/${notif['object_id']}';
    }
    final type = (router?['type'] ?? notif['object_type'])?.toString();
    final id = router?['id'] ?? notif['object_id'];
    final slug = router?['slug']?.toString();
    if (type == null) return null;

    const songTypes = {'song', 'folk', 'instrumental', 'karaoke', 'poem'};
    const peoplePrefix = {'artist': 'nghe-si', 'composer': 'nhac-si', 'recomposer': 'soan-gia', 'poet': 'nha-tho'};

    if (songTypes.contains(type) && id != null) return '/song/$id';
    if (peoplePrefix.containsKey(type) && slug != null) return '/${peoplePrefix[type]}/$slug';
    if (type == 'sheet' && id != null) return '/sheet/$id';
    if (type == 'discussion' && id != null) return '/thao-luan/$id';
    if (type == 'playlist' && id != null) return '/playlist/$id';
    if (type == 'document' && id != null) return '/tu-lieu/chi-tiet/$id';
    if (type == 'upload' && id != null) return '/bai-gui/$id';
    if (type == 'user' && id != null) return '/user/$id';
    if (type == 'page' && slug != null) return '/p/$slug';
    // Comment notifications: navigate to inner object (target of the comment)
    if (notif['object_type'] == 'comment') {
      // The inner object info isn't typically in `router` — fall back to nothing.
      // If router has a `commentable_type`/`commentable_id` we could use it.
      final ct = router?['commentable_type']?.toString();
      final cid = router?['commentable_id'];
      if (ct != null && cid != null) {
        if (songTypes.contains(ct.toLowerCase())) return '/song/$cid';
        if (ct.toLowerCase() == 'sheet') return '/sheet/$cid';
        if (ct.toLowerCase() == 'discussion') return '/thao-luan/$cid';
        if (ct.toLowerCase() == 'document') return '/tu-lieu/chi-tiet/$cid';
        if (ct.toLowerCase() == 'playlist') return '/playlist/$cid';
      }
    }
    return null;
  }

  void _open(Map<String, dynamic> notif) {
    if (notif['is_read'] != 1 && notif['is_read'] != true) _markRead(notif);
    final r = _routeFor(notif);
    if (r != null) context.push(r);
  }

  List<Object> get _grouped => groupByDay(_items, (n) => n['created_at']);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final player = context.watch<PlayerProvider>();
    if (!auth.isAuthenticated) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
        body: Center(child: Text('Vui lòng đăng nhập để xem thông báo', style: AppText.bodyText)),
      );
    }
    final hasUnread = _items.any((i) => i['is_read'] != 1 && i['is_read'] != true);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(controller: _scrollCtl, slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text('THÔNG BÁO', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
            actions: [
              if (hasUnread)
                TextButton(onPressed: _markAllRead, child: Text('Đọc tất cả', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accentLight)))),
            ],
          ),
          if (_loading && _items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else if (_items.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: EmptyState(
              icon: Icons.notifications_none,
              title: 'Chưa có thông báo',
              subtitle: 'Khi có người tương tác với bài gửi hoặc bình luận của bạn, thông báo sẽ xuất hiện ở đây.',
            ))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final entry = _grouped[i];
                  if (entry is String) return _NotifDayHeader(label: entry);
                  return _row(entry as Map<String, dynamic>);
                },
                childCount: _grouped.length,
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

  Widget _row(Map<String, dynamic> n) {
    final unread = n['is_read'] != 1 && n['is_read'] != true;
    final sender = n['sender'];
    final contentColor = unread ? AppColors.text : AppColors.textMuted;
    return InkWell(
      onTap: () => _open(n),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: unread ? AppColors.accent.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Opacity(
            opacity: unread ? 1.0 : 0.55,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceLight),
              child: ClipOval(
                child: sender?['avatar']?['url'] != null
                    ? CachedNetworkImage(imageUrl: sender['avatar']['url'], fit: BoxFit.cover, errorWidget: (_, __, ___) => Icon(Icons.notifications_outlined, color: AppColors.textMuted, size: 18))
                    : Icon(Icons.notifications_outlined, color: AppColors.textMuted, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RichText(text: TextSpan(children: [
              if (sender?['username'] != null)
                TextSpan(text: '${sender!['username']} ', style: body(TextStyle(fontSize: 13, fontWeight: unread ? FontWeight.w700 : FontWeight.w600, color: contentColor, height: 1.5))),
              TextSpan(text: n['content'] ?? '', style: body(TextStyle(fontSize: 13, fontWeight: unread ? FontWeight.w600 : FontWeight.w400, color: contentColor, height: 1.5))),
            ])),
            const SizedBox(height: 4),
            Text(timeago(n['created_at']), style: body(TextStyle(fontSize: 11, color: unread ? AppColors.accentLight : AppColors.textMuted))),
          ])),
          if (unread)
            Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6, left: 4), decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent))
          else
            const SizedBox(width: 14),
        ]),
      ),
    );
  }
}

class _NotifDayHeader extends StatelessWidget {
  final String label;
  const _NotifDayHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
      child: Text(
        label.toUpperCase(),
        style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.textMuted)),
      ),
    );
  }
}
