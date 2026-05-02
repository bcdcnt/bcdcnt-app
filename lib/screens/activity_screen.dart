import 'package:flutter/material.dart';
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
  const ActivityScreen({super.key});

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
    ('update_lyric', 'Lời'),
    ('comment', 'Bình luận'),
    ('create_sheet', 'Bản nhạc'),
    ('create_song', 'Tân nhạc'),
    ('create_folk', 'Dân ca'),
    ('create_instrumental', 'Khí nhạc'),
    ('create_karaoke', 'Karaoke'),
    ('create_poem', 'Tiếng thơ'),
    ('create_document', 'Tư liệu'),
    ('create_discussion', 'Thảo luận'),
    ('upload', 'Bài gửi'),
  ];

  String _filter = 'all';
  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true, _loadingMore = false, _hasNext = false;
  String _endCursor = '';

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    _fetch(reset: true);
  }
  @override
  void dispose() { _scrollCtl.removeListener(_onScroll); _scrollCtl.dispose(); super.dispose(); }
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

  Future<void> _fetch({required bool reset}) async {
    setState(() { if (reset) { _loading = true; _items = []; _endCursor = ''; } else _loadingMore = true; });
    try {
      final actions = _actionsForFilter(_filter);
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
              ... on Upload { id title type user { id username } }
              ... on Comment { id commentable_type user { id username } object { __typename ... on Song { id title slug } ... on Folk { id title slug } ... on Instrumental { id title slug } ... on Poem { id title slug } ... on Karaoke { id title slug } ... on Document { id title slug } ... on Discussion { id title slug } } }
            }
          } }
          pageInfo { hasNextPage endCursor }
        }
      }''';
      final data = await ApiClient.query(q);
      final edges = (data['activities']?['edges'] ?? []) as List;
      final nodes = edges.map((e) => Map<String, dynamic>.from(e['node'] as Map)).toList();
      final pi = data['activities']?['pageInfo'] ?? {};
      if (!mounted) return;
      setState(() {
        if (reset) _items = nodes; else _items.addAll(nodes);
        _hasNext = pi['hasNextPage'] ?? false;
        _endCursor = pi['endCursor'] ?? '';
        _loading = false; _loadingMore = false;
      });
    } catch (_) { if (mounted) setState(() { _loading = false; _loadingMore = false; }); }
  }

  String? _objectRoute(Map<String, dynamic> obj) {
    final type = (obj['__typename'] ?? '').toString().toLowerCase();
    if (type == 'song' || type == 'folk' || type == 'instrumental' || type == 'poem' || type == 'karaoke') return '/song/${obj['id']}';
    if (type == 'sheet') return '/sheet/${obj['id']}';
    if (type == 'document') return '/tu-lieu/chi-tiet/${obj['id']}';
    return null;
  }

  void _openObject(Map<String, dynamic>? obj) {
    if (obj == null) return;
    var target = obj;
    if (obj['__typename'] == 'Comment' && obj['object'] != null) target = Map<String, dynamic>.from(obj['object'] as Map);
    final r = _objectRoute(target);
    if (r != null) context.push(r);
  }

  List<Object> get _grouped => groupByDay(_items, (a) => a['created_at']);

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
            title: Text('HOẠT ĐỘNG', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            sliver: SliverToBoxAdapter(child: Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: _filters.map((f) {
                  final active = _filter == f.$1;
                  return InkWell(
                    onTap: active ? null : () { setState(() => _filter = f.$1); _fetch(reset: true); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: active ? AppColors.accent : Colors.transparent, width: 2))),
                      child: Text(f.$2, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? AppColors.text : AppColors.textMuted))),
                    ),
                  );
                }).toList()),
              ),
            )),
          ),
          if (_loading && _items.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
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
            if (_loadingMore) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
            SizedBox(height: player.currentSong != null ? 90 : 20),
          ])),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> a) {
    final action = (a['action'] ?? '').toString();
    final user = a['user'];
    final obj = a['object'] != null ? Map<String, dynamic>.from(a['object'] as Map) : null;
    final iconData = _actionIcons[action] ?? Icons.access_time;
    final actionLabel = _actionLabels[action] ?? action;
    final isComment = obj?['__typename'] == 'Comment';
    final isUpload = obj?['__typename'] == 'Upload';
    Map<String, dynamic>? innerObj;
    if (isComment && obj?['object'] != null) innerObj = Map<String, dynamic>.from(obj!['object'] as Map);
    final objTitle = (innerObj ?? obj)?['title'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Avatar
        InkWell(
          onTap: user?['id'] != null ? () => context.push('/user/${user['id']}') : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accentSoft),
            child: ClipOval(
              child: user?['avatar']?['url'] != null
                  ? CachedNetworkImage(imageUrl: user['avatar']['url'], fit: BoxFit.cover, errorWidget: (_, __, ___) => Icon(iconData, color: AppColors.accentLight, size: 16))
                  : Icon(iconData, color: AppColors.accentLight, size: 16),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DefaultTextStyle(
            style: body(const TextStyle(fontSize: 13, color: AppColors.text, height: 1.5)),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (user != null)
                InkWell(
                  onTap: () => context.push('/user/${user['id']}'),
                  child: Text(user['username'] ?? '', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                ),
              const Text(' '),
              Text(actionLabel, style: body(const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
              if (isComment && obj != null && obj['user']?['username'] != null) ...[
                Text(' của ', style: body(const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                InkWell(
                  onTap: () => context.push('/user/${obj['user']['id']}'),
                  child: Text(obj['user']['username'], style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text))),
                ),
              ],
              if (isUpload && obj != null && obj['user']?['username'] != null) ...[
                if (objTitle != null) ...[
                  const Text(' '),
                  InkWell(
                    onTap: () => _openObject(obj),
                    child: Text(objTitle.toString(), style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
                  ),
                ],
                Text(' của ', style: body(const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                InkWell(
                  onTap: () => context.push('/user/${obj['user']['id']}'),
                  child: Text(obj['user']['username'], style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text))),
                ),
              ],
              if (objTitle != null && !isUpload) ...[
                Text(isComment || action == 'comment' || action == 'love_comment' ? ' trong ' : ' ', style: body(const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                InkWell(
                  onTap: () => _openObject(obj),
                  child: Text(objTitle.toString(), style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 4),
          Text(timeago(a['created_at']), style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
        ])),
        const SizedBox(width: 8),
        Container(
          width: 26, height: 26, margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(8)),
          child: Icon(iconData, size: 14, color: AppColors.accentLight),
        ),
      ]),
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
        style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.textMuted)),
      ),
    );
  }
}
