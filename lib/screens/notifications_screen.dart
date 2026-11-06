import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../widgets/ui.dart' show SkeletonSongRow, OfflineBlock, EmptyBlock, goBack;
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../services/date_groups.dart';
import '../services/notification_route.dart';
import '../services/push.dart';
import '../services/realtime.dart';
import '../services/friendly_error.dart';
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
  bool _loading = true, _loadingMore = false, _failed = false;

  AuthProvider? _authRef;
  bool _didInitialFetch = false;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    // Wait for auth to finish restoring before the first fetch — a fresh
    // launch here would otherwise race the async token load → empty list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authRef = context.read<AuthProvider>();
      _authRef!.addListener(_initialFetch);
      _initialFetch();
    });
    realtimeService?.notificationTick.addListener(_onRealtime);
  }

  /// A new notification arrived while the list is open: reload page 1 so
  /// it shows up, and keep the badge at zero since the user is looking.
  void _onRealtime() {
    if (!mounted || _fetchedFor == null) return;
    _fetch(1);
    _resetUnread();
  }

  /// Bumped on every page-1 load / account switch so a slow response for an
  /// older request (or another account) is dropped.
  int _gen = 0;

  String? _fetchedFor;

  void _initialFetch() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.loading) return;
    final uid = auth.user?['id']?.toString();
    // Another account on the same phone must never see the last one's list.
    if (_didInitialFetch && uid == _fetchedFor) return;
    _didInitialFetch = true;
    _fetchedFor = uid;
    _gen++;
    setState(() { _items = []; _page = 1; _lastPage = 1; _loading = uid != null; _loadingMore = false; _failed = false; });
    if (uid == null) return;
    _fetch(1);
    _resetUnread();
  }

  @override
  void dispose() { realtimeService?.notificationTick.removeListener(_onRealtime); _authRef?.removeListener(_initialFetch); _scrollCtl.removeListener(_onScroll); _scrollCtl.dispose(); super.dispose(); }
  void _onScroll() {
    if (_loadingMore || _loading || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(_page + 1);
  }

  Future<void> _resetUnread() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    // Update local cache instantly for badge feedback
    auth.clearUnread();
    PushService.clearBadge();
    try { await auth.authedMutate(r'mutation { resetUnread }', null); } catch (_) {}
  }

  Future<void> _fetch(int page) async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) { setState(() => _loading = false); return; }
    if (page == 1) _gen++;
    final gen = _gen;
    final uid = auth.user?['id']?.toString();
    setState(() { _failed = false; if (page == 1) _loading = _items.isEmpty; else _loadingMore = true; });
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
      // Account switched, or a newer page-1 load started, while waiting.
      if (gen != _gen || uid != context.read<AuthProvider>().user?['id']?.toString()) {
        if (page > 1) setState(() => _loadingMore = false);
        return;
      }
      setState(() {
        if (page == 1) _items = list; else _items.addAll(list);
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _loading = false; _loadingMore = false;
      });
    } catch (e) {
      if (mounted && (gen == _gen || page > 1)) {
        setState(() { _loading = false; _loadingMore = false; _failed = page == 1; });
        if (page > 1) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa tải thêm được thông báo. Kiểm tra mạng rồi kéo lại.')));
        }
      }
    }
  }

  Future<void> _markAllRead() async {
    final auth = context.read<AuthProvider>();
    try {
      await auth.authedMutate(r'mutation { markAsReadAll }', null);
    } catch (e) {
      // Keep the dots: the server still has them as unread.
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'Chưa đánh dấu đã đọc được, vui lòng thử lại.'))));
      return;
    }
    auth.setUnread(0);
    if (mounted) setState(() { _items = _items.map((i) { i['is_read'] = 1; return i; }).toList(); });
  }

  Future<void> _markRead(Map<String, dynamic> n, {bool quiet = false}) async {
    final auth = context.read<AuthProvider>();
    if (n['code'] == null) return;
    try {
      await auth.authedMutate(r'mutation($code: String!) { markAsRead(code: $code) }', {'code': n['code']});
    } catch (e) {
      if (mounted && !quiet) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'Chưa đánh dấu đã đọc được, vui lòng thử lại.'))));
      return;
    }
    auth.decrementUnread();
    if (mounted) setState(() { final idx = _items.indexWhere((i) => i['id'] == n['id']); if (idx >= 0) _items[idx]['is_read'] = 1; });
  }

  void _open(Map<String, dynamic> notif) {
    // A grouped row marks every notification it stands for as read.
    var first = true;
    for (final m in (notif['_members'] as List<Map<String, dynamic>>? ?? [notif])) {
      // One snackbar per tap at most, even for a grouped row.
      if (m['is_read'] != 1 && m['is_read'] != true) { _markRead(m, quiet: !first); first = false; }
    }
    final r = notificationRoute(notif);
    if (r != null) context.push(r.path, extra: r.extra);
  }

  /// Same action on the same thing on the same day collapses into one row:
  /// "Lan và 4 người khác thích bình luận của bạn…" instead of five rows.
  List<Map<String, dynamic>> get _collapsed {
    final out = <Map<String, dynamic>>[];
    final at = <String, int>{};
    for (final n in _items) {
      final day = '${n['created_at'] ?? ''}'.split(' ').first.split('T').first;
      // Likes/votes fold together; replies and mentions carry their own
      // text, so each stays a row of its own.
      final act = '${n['action'] ?? ''}'.toLowerCase();
      final groupable = n['action'] != null && n['object_id'] != null && n['sender'] != null && (act.contains('like') || act.contains('love') || act.contains('poll'));
      final key = '$day|${n['action']}|${n['object_type']}|${n['object_id']}';
      final i = groupable ? at[key] : null;
      if (i == null) {
        final row = <String, dynamic>{...n, '_members': <Map<String, dynamic>>[n], '_senders': <String>{'${n['sender']?['id']}'}};
        if (groupable) at[key] = out.length;
        out.add(row);
        continue;
      }
      final row = out[i];
      (row['_members'] as List<Map<String, dynamic>>).add(n);
      (row['_senders'] as Set<String>).add('${n['sender']?['id']}');
      if (n['is_read'] != 1 && n['is_read'] != true) row['is_read'] = 0;
    }
    return out;
  }

  List<Object> get _grouped => groupByDay(_collapsed, (n) => n['created_at']);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final player = context.watch<PlayerProvider>();
    if (!auth.isAuthenticated) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context))),
        body: Center(child: SingleChildScrollView(child: EmptyBlock(
          icon: Icons.notifications_none,
          title: 'Đăng nhập để xem thông báo',
          message: 'Bạn sẽ biết khi có người trả lời, thích bình luận hoặc BQT duyệt bài gửi của bạn.',
          action: 'Đăng nhập',
          onAction: () => askLogin(context),
        ))),
      );
    }
    final hasUnread = _items.any((i) => i['is_read'] != 1 && i['is_read'] != true);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(controller: _scrollCtl, slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg,
            title: Text('Thông báo'),
            centerTitle: true,
            leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
            actions: [
              if (hasUnread)
                TextButton(onPressed: _markAllRead, child: Text('Đọc tất cả', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.accentLight)))),
            ],
          ),
          if (_loading && _items.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              sliver: SliverList(delegate: SliverChildBuilderDelegate((_, __) => const SkeletonSongRow(), childCount: 8)),
            )
          else if (_failed && _items.isEmpty)
            SliverToBoxAdapter(child: OfflineBlock(onRetry: () => _fetch(1)))
          else if (_items.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: EmptyState(
              icon: Icons.notifications_none,
              title: 'Chưa có thông báo',
              subtitle: 'Khi có người tương tác với bài gửi hoặc bình luận của bạn, thông báo sẽ xuất hiện ở đây.',
            ))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
          color: unread ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Opacity(
            opacity: unread ? 1.0 : 0.75,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceLight),
              child: ClipOval(
                child: sender?['avatar']?['url'] != null
                    ? CachedNetworkImage(imageUrl: cdnImg((sender['avatar']['url']).toString(), 160), fit: BoxFit.cover, errorWidget: (_, __, ___) => Icon(Icons.notifications_outlined, color: AppColors.textMuted, size: 18))
                    : sender?['username'] != null
                        ? Center(child: Text('${sender!['username']}'.characters.first.toUpperCase(), style: body(TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.accentLight))))
                        : Icon(Icons.notifications_outlined, color: AppColors.textMuted, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RichText(textScaler: MediaQuery.textScalerOf(context), text: TextSpan(children: [
              if (sender?['username'] != null)
                TextSpan(text: '${sender!['username']} ', style: body(TextStyle(fontSize: 15, fontWeight: unread ? FontWeight.w700 : FontWeight.w600, color: contentColor, height: 1.5))),
              if (((n['_senders'] as Set?)?.length ?? 1) > 1)
                TextSpan(text: 'và ${(n['_senders'] as Set).length - 1} người khác ', style: body(TextStyle(fontSize: 15, fontWeight: unread ? FontWeight.w700 : FontWeight.w600, color: contentColor, height: 1.5))),
              TextSpan(text: n['content'] ?? '', style: body(TextStyle(fontSize: 15, fontWeight: unread ? FontWeight.w600 : FontWeight.w400, color: contentColor, height: 1.5))),
            ])),
            const SizedBox(height: 4),
            Text(timeago(n['created_at']), style: body(TextStyle(fontSize: 13, color: unread ? AppColors.accentLight : AppColors.textMuted))),
          ])),
          if (unread)
            Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6, left: 12), decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent))
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
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
      child: Text(
        label.toUpperCase(),
        style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.textMuted)),
      ),
    );
  }
}
