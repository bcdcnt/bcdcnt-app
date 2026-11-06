import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, ChipStrip, OfflineBlock;
import '../services/auth.dart';
import '../main.dart' show TabReselect;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../services/date_groups.dart';
import '../widgets/empty_state.dart';
import '../widgets/mini_player.dart';

class ActivityScreen extends StatefulWidget {
  /// Inside the Cộng đồng tab: no app bar, the tab draws the header.
  final bool embedded;
  const ActivityScreen({super.key, this.embedded = false});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  // Long-form labels matching web's `activity.*` i18n keys (vi locale).
  static const _actionLabels = {
    'update_lyric': 'cập nhật lời bài hát',
    'comment': 'bình luận',
    'love_comment': 'thích bình luận',
    'create_sheet': 'đăng sheet nhạc mới',
    'create_document': 'đăng tư liệu mới',
    'create_song': 'đăng bài hát mới',
    'create_folk': 'đăng bài dân ca mới',
    'create_instrumental': 'đăng bài khí nhạc mới',
    'create_karaoke': 'đăng bài thành viên hát mới',
    'create_poem': 'đăng bài tiếng thơ mới',
    'approve_upload': 'duyệt bài gửi',
    'reject_upload': 'từ chối bài gửi',
    'create_discussion': 'đăng thảo luận mới',
  };
  static const _actionIcons = {
    'update_lyric': Icons.edit_outlined,
    'comment': Icons.chat_bubble_outline,
    'love_comment': Icons.favorite_outline,
    'create_sheet': Icons.description_outlined,
    'create_document': Icons.article_outlined,
    'create_song': Icons.music_note,
    'create_folk': Icons.music_note,
    'create_instrumental': Icons.music_note,
    'create_karaoke': Icons.mic,
    'create_poem': Icons.auto_stories_outlined,
    'approve_upload': Icons.check,
    'reject_upload': Icons.close,
    'create_discussion': Icons.forum_outlined,
  };
  static const _filters = [
    ('all', 'Tất cả'),
    ('update_lyric', 'Lời bài hát'),
    ('comment', 'Bình luận'),
    ('create_sheet', 'Bản nhạc'),
    ('create_song', 'Tân nhạc'),
    ('create_folk', 'Dân ca'),
    ('create_instrumental', 'Khí nhạc'),
    ('create_karaoke', 'Thành viên hát'),
    ('create_poem', 'Tiếng thơ'),
    ('create_document', 'Tư liệu'),
    ('create_discussion', 'Thảo luận'),
    ('upload', 'Bài gửi'),
  ];

  String _filter = 'all';
  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true, _loadingMore = false, _hasNext = false, _failed = false;
  String _endCursor = '';
  /// Bumped on every reset load so a slow page for an old filter is dropped.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    if (widget.embedded) TabReselect.tick.addListener(_onReselect);
    _fetch(reset: true);
  }
  @override
  void dispose() { TabReselect.tick.removeListener(_onReselect); _scrollCtl.removeListener(_onScroll); _scrollCtl.dispose(); super.dispose(); }

  /// Cộng đồng tab tapped again while this pane is on screen → back to top.
  /// (IndexedStack keeps hidden panes laid out, so check visibility.)
  void _onReselect() {
    if (TabReselect.tick.value.$1 != 2 || !_scrollCtl.hasClients) return;
    if (!TickerMode.valuesOf(context).enabled) return;
    _scrollCtl.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }
  void _onScroll() {
    if (_loadingMore || _loading || !_hasNext) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(reset: false);
  }

  List<String> _actionsForFilter(String f) {
    if (f == 'all') return _actionLabels.keys.toList();
    if (f == 'upload') return ['approve_upload', 'reject_upload'];
    if (f == 'comment') return ['comment', 'love_comment'];
    return [f];
  }

  Future<void> _fetch({required bool reset, bool keepItems = false}) async {
    if (reset) _gen++;
    final gen = _gen;
    final filter = _filter;
    setState(() {
      _failed = false;
      if (reset) { _loading = true; if (!keepItems) _items = []; _endCursor = ''; } else { _loadingMore = true; }
    });
    try {
      final actions = _actionsForFilter(filter);
      final actionsStr = actions.map((a) => '"$a"').join(', ');
      final after = reset ? '' : _endCursor;
      final q = '''query {
        activities(first: 30, after: "$after", where: {AND: [{column: "action", value: [$actionsStr], operator: IN}]}, orderBy: [{column: "id", order: DESC}]) {
          edges { node {
            action extra created_at
            user { id username avatar { url } }
            object { __typename
              ... on Song { id title slug }
              ... on Folk { id title slug }
              ... on Instrumental { id title slug }
              ... on Poem { id title slug }
              ... on Karaoke { id title slug }
              ... on Document { id title slug }
              ... on Sheet { id title slug }
              ... on Discussion { id title slug }
              ... on Upload { id title type status result user { id username } }
              ... on Comment { id commentable_type user { id username } object { __typename ... on Song { id title slug } ... on Folk { id title slug } ... on Instrumental { id title slug } ... on Poem { id title slug } ... on Karaoke { id title slug } ... on Document { id title slug } ... on Discussion { id title slug } ... on Sheet { id title slug } ... on Upload { id title status result user_id } } }
            }
          } }
          pageInfo { hasNextPage endCursor }
        }
      }''';
      final data = await ApiClient.query(q);
      final edges = (data['activities']?['edges'] ?? []) as List;
      final nodes = edges.map((e) => Map<String, dynamic>.from(e['node'] as Map)).toList();
      final pi = data['activities']?['pageInfo'] ?? {};
      // Filter changed / refreshed while waiting → this answer is stale.
      if (!mounted || gen != _gen || filter != _filter) return;
      setState(() {
        if (reset) { _items = nodes; } else { _items.addAll(nodes); }
        _hasNext = pi['hasNextPage'] ?? false;
        _endCursor = pi['endCursor'] ?? '';
        _loading = false; _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen || filter != _filter) return;
      setState(() { _loading = false; _loadingMore = false; _failed = reset || _items.isEmpty; });
      if (!reset && _items.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa tải thêm được. Kiểm tra mạng rồi thử lại.')));
      }
    }
  }

  ({String path, Map<String, dynamic>? extra})? _objectRoute(Map<String, dynamic> obj) {
    final type = (obj['__typename'] ?? '').toString().toLowerCase();
    final id = obj['id'];
    if (id == null) return null;
    if (type == 'song' || type == 'folk' || type == 'instrumental' || type == 'poem' || type == 'karaoke') return (path: '/song/$id', extra: {'id': id, 'file_type': type});
    if (type == 'sheet') return (path: '/sheet/$id', extra: null);
    if (type == 'document') return (path: '/tu-lieu/chi-tiet/$id', extra: null);
    if (type == 'discussion') return (path: '/thao-luan/$id', extra: null);
    if (type == 'upload') return context.read<AuthProvider>().uploadRoute(obj);
    return null;
  }

  Map<String, dynamic>? _target(Map<String, dynamic>? obj) {
    if (obj == null) return null;
    if (obj['__typename'] == 'Comment') return obj['object'] is Map ? Map<String, dynamic>.from(obj['object'] as Map) : null;
    return obj;
  }

  /// Tap handler for an object title, or null when it can't be opened.
  VoidCallback? _openerFor(Map<String, dynamic>? obj) {
    final t = _target(obj);
    final r = t == null ? null : _objectRoute(t);
    if (r == null) return null;
    return () => context.push(r.path, extra: r.extra);
  }

  List<Object> get _grouped => groupByDay(_items, (a) => a['created_at']);

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        RefreshIndicator(
          color: AppColors.accent,
          onRefresh: () => _fetch(reset: true, keepItems: true),
          child: CustomScrollView(controller: _scrollCtl, physics: const AlwaysScrollableScrollPhysics(), slivers: [
          if (!widget.embedded)
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.bg,
              title: const Text('Hoạt động'),
              centerTitle: true,
              leading: IconButton(tooltip: 'Quay lại', icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => goBack(context)),
            ),
          SliverPadding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            sliver: SliverToBoxAdapter(child: ChipStrip(
              labels: [for (final f in _filters) f.$2],
              selected: _filters.indexWhere((f) => f.$1 == _filter),
              onSelect: (i) {
                if (_filters[i].$1 == _filter) return;
                setState(() => _filter = _filters[i].$1);
                _fetch(reset: true);
              },
            )),
          ),
          if (_loading && _items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else if (_failed && _items.isEmpty)
            SliverToBoxAdapter(child: OfflineBlock(onRetry: () => _fetch(reset: true)))
          else if (_items.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: EmptyState(
              icon: Icons.timeline,
              title: 'Chưa có hoạt động',
              subtitle: 'Hoạt động mới nhất từ cộng đồng sẽ xuất hiện ở đây.',
            ))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final entry = _grouped[i];
                  if (entry is String) return _DayHeader(label: entry);
                  return _row(entry as Map<String, dynamic>);
                },
                childCount: _grouped.length,
              )),
            ),
          SliverToBoxAdapter(child: Column(children: [
            if (_loadingMore) Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
            SizedBox(height: player.currentSong != null ? 90 : 20),
          ])),
        ])),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> a) {
    final action = (a['action'] ?? '').toString();
    final obj = a['object'] != null ? Map<String, dynamic>.from(a['object'] as Map) : null;
    final iconData = _actionIcons[action] ?? Icons.access_time;
    final actionLabel = _actionLabels[action] ?? action;
    final isComment = obj?['__typename'] == 'Comment';
    final isUpload = obj?['__typename'] == 'Upload';
    // Approvals are a BQT decision, not one moderator's: "BQT duyệt bài gửi X của Y".
    final byBqt = action == 'approve_upload' || action == 'reject_upload';
    final user = byBqt ? null : a['user'];
    final innerObj = isComment ? _target(obj) : null;
    final objTitle = (innerObj ?? obj)?['title'];
    final openObj = _openerFor(obj);

    final base = body(TextStyle(fontSize: 15, color: AppColors.text, height: 1.5));
    final muted = body(TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.5));
    final strong = body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.5));
    final link = body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: openObj != null ? AppColors.accentLight : AppColors.text, height: 1.5));

    Widget userLink(Map? u, TextStyle style) => InkWell(
          onTap: u?['id'] != null ? () => context.push('/user/${u!['id']}') : null,
          child: Text((u?['username'] ?? '').toString(), style: style),
        );
    Widget objLink() => InkWell(onTap: openObj, child: Text(objTitle.toString(), style: link));

    return InkWell(
      // The whole row opens the object (song, discussion…) when it can.
      onTap: openObj,
      child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Avatar
        InkWell(
          onTap: user?['id'] != null ? () => context.push('/user/${user['id']}') : null,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accentSoft),
            child: ClipOval(
              child: byBqt
                  ? Icon(Icons.verified_user_outlined, color: AppColors.accentLight, size: 20)
                  : user?['avatar']?['url'] != null
                      ? CachedNetworkImage(imageUrl: cdnImg((user['avatar']['url']).toString(), 160), fit: BoxFit.cover, errorWidget: (_, __, ___) => Icon(iconData, color: AppColors.accentLight, size: 18))
                      : Icon(iconData, color: AppColors.accentLight, size: 18),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DefaultTextStyle(
            style: base,
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (byBqt) Text('BQT', style: strong)
              else if (user != null) userLink(user, strong),
              const Text(' '),
              Text(actionLabel, style: muted),
              if (isComment && obj != null && obj['user']?['username'] != null) ...[
                Text(' của ', style: muted),
                userLink(obj['user'], strong),
              ],
              if (isUpload && obj != null) ...[
                if (objTitle != null) ...[
                  const Text(' '),
                  objLink(),
                ],
                if (obj['user']?['username'] != null) ...[
                  Text(' của ', style: muted),
                  userLink(obj['user'], strong),
                ],
              ],
              if (objTitle != null && !isUpload) ...[
                Text(isComment || action == 'comment' || action == 'love_comment' ? ' trong ' : ' ', style: muted),
                objLink(),
              ],
            ]),
          ),
          const SizedBox(height: 4),
          Text(timeago(a['created_at']), style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
        ])),
        const SizedBox(width: 8),
        Container(
          width: 28, height: 28, margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(8)),
          child: Icon(iconData, size: 16, color: AppColors.accentLight),
        ),
      ]),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String label;
  const _DayHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
      child: Text(
        label.toUpperCase(),
        style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.textMuted)),
      ),
    );
  }
}
