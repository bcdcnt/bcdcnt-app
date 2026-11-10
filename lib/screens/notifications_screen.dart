import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../widgets/ui.dart' show SkeletonSongRow, OfflineBlock, EmptyBlock, goBack, PillButton;
import '../widgets/desktop_page.dart';
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
import '../widgets/contribute_card.dart';
import '../services/upload_types.dart';

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
  /// Desktop filter tab (see [_tabs]); the phone always shows everything.
  String _tab = 'all';
  int _unreadTotal = 0;
  /// BQT side card: uploads waiting, total and per type.
  int _pendingTotal = 0;
  List<(String, int)> _pendingByType = const [];
  /// Older API without `thumbnail_url`: ask without it.
  bool _noThumbField = false;

  static const _tabs = [
    ('all', 'Tất cả'),
    ('unread', 'Chưa đọc'),
    ('comment', 'Bình luận & trả lời'),
    ('like', 'Thích & đánh giá'),
    ('review', 'Cần duyệt'),
  ];

  /// Server-side filter for a tab. "Cần duyệt" shares its action with
  /// "đã sử dụng bài gửi của bạn", so the text tells them apart.
  Map<String, dynamic>? _where(String tab) => switch (tab) {
        'unread' => {'column': 'is_read', 'value': 0},
        'comment' => {'column': 'action', 'operator': 'IN', 'value': ['comment', 'mention', 'process_comment_request']},
        'like' => {'column': 'action', 'operator': 'IN', 'value': ['love_comment', 'answer_poll']},
        'review' => {'OR': [
            {'AND': [
              {'column': 'action', 'value': 'process_upload'},
              {'column': 'content', 'operator': 'LIKE', 'value': '%thẩm định%'},
            ]},
            {'column': 'action', 'value': 'change_username_request'},
          ]},
        _ => null,
      };

  void _setTab(String t) {
    if (t == _tab) return;
    _gen++;
    setState(() { _tab = t; _items = []; _page = 1; _lastPage = 1; _loading = true; _failed = false; });
    _fetch(1);
  }

  /// Desktop extras: unread count for its tab, and for BQT the uploads
  /// waiting by type.
  Future<void> _fetchSide() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    final review = auth.hasPermission('manage_upload');
    const types = ['song', 'replace', 'sheet', 'folk', 'instrumental', 'karaoke', 'poem', 'document_audio', 'document_image', 'document_video', 'document_news', 'beat'];
    final per = review ? [for (final t in types) '$t: uploads(first: 1, where: {AND: [{column: "status", value: "pending"}, {column: "type", value: "$t"}]}) { paginatorInfo { total } }'].join(' ') : '';
    final all = review ? 'pending: uploads(first: 1, where: {column: "status", value: "pending"}) { paginatorInfo { total } }' : '';
    try {
      final d = await auth.authedQuery('query { me { notifications(first: 1, where: {column: "is_read", value: 0}) { paginatorInfo { total } } } $all $per }');
      if (!mounted) return;
      int n(dynamic v) => (v?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0;
      final byType = [for (final t in types) (uploadTypeLabel(t), n(d[t]))]..retainWhere((e) => e.$2 > 0);
      byType.sort((a, b) => b.$2.compareTo(a.$2));
      setState(() {
        _unreadTotal = n(d['me']?['notifications']);
        _pendingTotal = n(d['pending']);
        _pendingByType = byType;
      });
    } catch (_) {}
  }

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
    _fetchSide();
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
      Future<Map<String, dynamic>> ask() => auth.authedQuery('''query(\$first: Int!, \$page: Int, \$where: WhereConditions) {
        me {
          notifications(first: \$first, page: \$page, where: \$where, orderBy: [{column: "created_at", order: DESC}]) {
            data { id code content action extra object_type object_id is_read created_at ${_noThumbField ? '' : 'thumbnail_url'} sender { id username avatar { url } } }
            paginatorInfo { lastPage currentPage }
          }
        }
      }''', {'first': 20, 'page': page, 'where': _where(_tab)});
      Map<String, dynamic> data;
      try {
        data = await ask();
      } catch (e) {
        if (_noThumbField || !'$e'.contains('thumbnail_url')) rethrow;
        _noThumbField = true;
        data = await ask();
      }
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
    if (mounted) setState(() { _unreadTotal = 0; _items = _items.map((i) { i['is_read'] = 1; return i; }).toList(); });
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
    if (mounted) setState(() {
      if (_unreadTotal > 0) _unreadTotal--; final idx = _items.indexWhere((i) => i['id'] == n['id']); if (idx >= 0) _items[idx]['is_read'] = 1; });
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
    final desk = isDesk(context);
    if (!auth.isAuthenticated) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: desk ? null : AppBar(leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context))),
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
        // List up to ~820px; on a wide window a 320px column beside it.
        DeskFrame(maxWidth: desk ? 1320 : double.infinity, child: _withSide(desk, auth, CustomScrollView(controller: _scrollCtl, slivers: [
          if (desk)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(deskPad.left, deskPad.top, deskPad.right, 0),
              sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DeskHead(title: 'Thông báo', actions: [
                  if (hasUnread || _unreadTotal > 0) PillButton(label: 'Đọc tất cả', icon: Icons.done_all_rounded, height: 44, primary: false, onTap: _markAllRead),
                ]),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (k, label) in _tabs)
                    if (k != 'review' || auth.hasPermission('manage_upload'))
                      _TabChip(
                        label: label,
                        count: k == 'unread' && _unreadTotal > 0 ? (_unreadTotal > 999 ? '999+' : '$_unreadTotal') : null,
                        on: _tab == k,
                        onTap: () => _setTab(k),
                      ),
                ]),
                const SizedBox(height: 8),
              ])),
            )
          else
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
              padding: EdgeInsets.symmetric(horizontal: desk ? deskPad.left - 12 : 8, vertical: 8),
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
              // Rows have their own 12px inset; desktop lines their text up
              // with the DeskHead title.
              padding: EdgeInsets.symmetric(horizontal: desk ? deskPad.left - 12 : 20, vertical: desk ? 0 : 8),
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
        ]))),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  /// Desktop ≥ 1180px wide: the list (max 820) and a 320px column — BQT see
  /// the uploads waiting, members the Góp tay card.
  Widget _withSide(bool desk, AuthProvider auth, Widget list) {
    if (!desk) return list;
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 1180) return ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: list);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: (c.maxWidth - 320 - deskPad.right - 32).clamp(0, 900).toDouble(), child: list),
        const SizedBox(width: 32),
        SizedBox(
          width: 320,
          child: Padding(
            padding: EdgeInsets.only(top: deskPad.top + 122),
            child: auth.hasPermission('manage_upload') ? _pendingCard() : const ContributeCard(),
          ),
        ),
      ]);
    });
  }

  Widget _pendingCard() {
    final top = _pendingByType.take(4).toList();
    final rest = _pendingByType.skip(4).fold<int>(0, (a, e) => a + e.$2);
    final row = body(TextStyle(fontSize: 14, color: AppColors.textSecondary));
    final num = body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text));
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.wine, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.assignment_rounded, color: Colors.white, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text('Đang chờ duyệt', style: body(TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)))),
          Text('$_pendingTotal', style: display(TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
        ]),
        const SizedBox(height: 6),
        for (final (label, n) in top)
          Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Expanded(child: Text(label, style: row)), Text('$n', style: num)])),
        if (rest > 0)
          Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Expanded(child: Text('Loại khác', style: row)), Text('$rest', style: num)])),
        const SizedBox(height: 14),
        PillButton(label: 'Mở Bàn làm việc', height: 42, onTap: () => context.push('/ban-lam-viec')),
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
              // Some server texts end in `: ""` when the title is missing.
              TextSpan(text: '${n['content'] ?? ''}'.replaceFirst(RegExp(r':\s*(""|“”)\s*$'), ''), style: body(TextStyle(fontSize: 15, fontWeight: unread ? FontWeight.w600 : FontWeight.w400, color: contentColor, height: 1.5))),
            ])),
            const SizedBox(height: 4),
            Text(timeago(n['created_at']), style: body(TextStyle(fontSize: 13, color: unread ? AppColors.accentLight : AppColors.textMuted))),
          ])),
          if (isDesk(context) && (n['thumbnail_url'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: cdnImg(n['thumbnail_url'].toString(), 120), width: 44, height: 44, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox(width: 44, height: 44))),
            ),
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

class _TabChip extends StatelessWidget {
  final String label;
  final String? count;
  final bool on;
  final VoidCallback onTap;
  const _TabChip({required this.label, required this.on, required this.onTap, this.count});

  @override
  Widget build(BuildContext context) {
    final fg = on ? Colors.white : AppColors.textSecondary;
    return Material(
      color: on ? AppColors.wine : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg))),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text(count!, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg.withValues(alpha: 0.75)))),
            ],
          ]),
        ),
      ),
    );
  }
}
