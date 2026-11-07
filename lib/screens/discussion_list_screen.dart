import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock, EmptyBlock, PillButton, ChipStrip, UserAvatar;
import 'discussion_compose_screen.dart';
import '../main.dart' show TabReselect;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';

class DiscussionListScreen extends StatefulWidget {
  /// Inside the Cộng đồng tab: no app bar / hero, the tab draws the header.
  final bool embedded;
  const DiscussionListScreen({super.key, this.embedded = false});

  @override
  State<DiscussionListScreen> createState() => _DiscussionListScreenState();
}

class _DiscussionListScreenState extends State<DiscussionListScreen> {
  List<Map<String, dynamic>> _forums = [];
  bool _loading = true, _failed = false;
  final _scrollCtl = ScrollController();

  // Cộng đồng › Thảo luận: one chip row instead of a box per forum.
  static const _tabs = ['Mới hoạt động', 'Sôi nổi', 'Được ghim', 'Chuyên mục'];
  int _tab = 0;
  final Map<int, List<Map<String, dynamic>>> _topics = {};
  final Map<int, int> _limit = {};
  bool _topicsLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.embedded) TabReselect.tick.addListener(_onReselect);
    _fetch();
    if (widget.embedded) _fetchTopics(0);
  }

  /// BQT's internal forums ("Ban truyền thông"…) and the bin stay out of
  /// the community lists.
  static bool _hiddenForum(String? title) {
    final t = (title ?? '').trim();
    return t.startsWith('Ban ') || t == 'Sọt rác';
  }

  /// Mới hoạt động: last reply first. Sôi nổi: most comments among topics
  /// with a reply in the last 12 months (the all-time list is old forum
  /// threads nobody posts in). Được ghim: BQT's pinned topics.
  Future<void> _fetchTopics(int tab, {bool more = false}) async {
    if (tab == 3) return;
    final limit = more ? (_limit[tab] ?? 20) + 20 : (_limit[tab] ?? 20);
    final yearAgo = DateTime.now().subtract(const Duration(days: 365));
    final since = '${yearAgo.year}-${yearAgo.month.toString().padLeft(2, '0')}-${yearAgo.day.toString().padLeft(2, '0')}';
    final where = [
      {'column': 'status', 'value': 1},
      if (tab == 1) {'column': 'last_comment_at', 'operator': 'GTE', 'value': since},
      if (tab == 2) {'column': 'is_sticky', 'value': 1},
    ];
    final order = tab == 1 ? 'comment_count' : 'last_comment_at';
    setState(() => _topicsLoading = true);
    try {
      final d = await ApiClient.query('''query(\$w: WhereConditions, \$n: Int) {
        discussions(first: \$n, orderBy: [{column: "$order", order: DESC}], where: \$w) {
          data { id title comment_count views is_sticky created_at last_comment_at forum { id title } author { id username avatar { url } } lastCommentBy { id username avatar { url } } }
        }
      }''', {'w': {'AND': where}, 'n': limit});
      final list = ((d['discussions']?['data'] ?? []) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((t) => !_hiddenForum(t['forum']?['title']?.toString()))
          .toList();
      if (!mounted) return;
      setState(() {
        _topics[tab] = list;
        _limit[tab] = limit;
        _topicsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _topicsLoading = false);
    }
  }

  @override
  void dispose() { TabReselect.tick.removeListener(_onReselect); _scrollCtl.dispose(); super.dispose(); }

  /// Cộng đồng tab tapped again while this pane is on screen → back to top.
  void _onReselect() {
    if (TabReselect.tick.value.$1 != 2 || !_scrollCtl.hasClients) return;
    if (!TickerMode.valuesOf(context).enabled) return;
    _scrollCtl.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  Future<void> _fetch() async {
    if (_failed) setState(() { _failed = false; _loading = true; });
    try {
      final data = await ApiClient.query(r'''query {
        forums(first: 100, where: {AND: [{column: "parent_id", value: null}]}, orderBy: [{column: "position", order: ASC}]) {
          data {
            id title slug content
            children(first: 100, orderBy: [{column: "position", order: ASC}]) {
              data {
                id title slug content
                discussions(first: 5, orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: 1}]}) {
                  data { id title slug created_at comment_count views author { id username avatar { url } } }
                  paginatorInfo { total }
                }
              }
            }
          }
        }
      }''');
      if (!mounted) return;
      setState(() {
        _forums = ((data['forums']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
        _failed = false;
      });
    } catch (_) { if (mounted) setState(() { _loading = false; _failed = true; }); }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        RefreshIndicator(
          color: AppColors.accent,
          onRefresh: () async {
            await _fetch();
            if (widget.embedded) await _fetchTopics(_tab);
          },
          child: CustomScrollView(controller: _scrollCtl, physics: const AlwaysScrollableScrollPhysics(), slivers: [
          if (!widget.embedded)
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.bg,
              title: const Text('Thảo luận'),
              centerTitle: true,
              leading: IconButton(tooltip: 'Quay lại', icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => goBack(context)),
            ),
          if (_loading)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else if (_failed && _forums.isEmpty)
            SliverToBoxAdapter(child: OfflineBlock(onRetry: _fetch))
          else if (_forums.isEmpty)
            const SliverToBoxAdapter(child: EmptyBlock(icon: Icons.forum_outlined, title: 'Chưa có diễn đàn'))
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, widget.embedded ? 0 : 24),
              sliver: SliverList(delegate: SliverChildListDelegate([
                // Hero
                if (!widget.embedded) Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(colors: [Color(0xFF4A0D0D), Color(0xFF711313)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: const Color(0xFF4A0D0D).withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.forum_outlined, color: Colors.white, size: 28)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Diễn đàn', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                      const SizedBox(height: 4),
                      Text('Cộng đồng yêu nhạc cùng thảo luận', style: body(const TextStyle(fontSize: 13, color: Colors.white70))),
                    ])),
                  ]),
                ),
                if (!widget.embedded) const SizedBox(height: 22),
                // Asks which forum in the compose screen.
                Padding(
                  padding: EdgeInsets.only(bottom: widget.embedded ? 10 : 22),
                  child: PillButton(
                    label: 'Đăng thảo luận',
                    icon: Icons.edit_note_rounded,
                    height: 52,
                    onTap: () => openDiscussionCompose(context, onPosted: () { _fetch(); if (widget.embedded) _fetchTopics(_tab); }),
                  ),
                ),

                if (!widget.embedded) ..._forums.map((parent) => _parentForum(parent)),
              ])),
            ),
          // Full-width chip row (it scrolls to the screen edge), then the list.
          if (widget.embedded && !_loading && _forums.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: ChipStrip(
                labels: _tabs,
                selected: _tab,
                onSelect: (i) {
                  setState(() => _tab = i);
                  if (!_topics.containsKey(i)) _fetchTopics(i);
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              sliver: SliverList(delegate: SliverChildListDelegate(_embeddedBody())),
            ),
          ],
          SliverToBoxAdapter(child: SizedBox(height: player.currentSong != null ? 90 : 20)),
        ])),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  List<Widget> _embeddedBody() {
    final list = _topics[_tab];
    return [
      if (_tab == 3)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final parent in _forums)
              for (final c in ((parent['children']?['data'] ?? []) as List).whereType<Map>())
                if (!_hiddenForum(c['title']?.toString()))
                  ActionChip(
                    label: Text('${c['title'] ?? ''}', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                    backgroundColor: AppColors.surface,
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    onPressed: () => context.push('/dien-dan/${c['id']}'),
                  ),
          ]),
        )
      else if (list == null)
        const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
      else if (list.isEmpty)
        Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Chưa có chủ đề nào', style: body(TextStyle(fontSize: 15, color: AppColors.textMuted)))))
      else ...[
        for (final t in list) _topicRow(t, showPin: _tab != 2),
        const SizedBox(height: 8),
        PillButton(
          label: 'Xem thêm chủ đề',
          primary: false,
          height: 48,
          loading: _topicsLoading,
          onTap: _topicsLoading ? null : () => _fetchTopics(_tab, more: true),
        ),
      ],
    ];
  }

  /// A topic: title (📌 when pinned), "forum · when it last moved", then
  /// counts and who replied last.
  Widget _topicRow(Map<String, dynamic> d, {bool showPin = true}) {
    final last = d['lastCommentBy'] ?? d['author'];
    final pinned = showPin && '${d['is_sticky'] ?? 0}' == '1';
    final when = timeago((d['last_comment_at'] ?? d['created_at'])?.toString());
    final muted = body(TextStyle(fontSize: 13, color: AppColors.textMuted));
    return InkWell(
      onTap: () => context.push('/thao-luan/${d['id']}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: UserAvatar(url: last?['avatar']?['url']?.toString(), name: '${last?['username'] ?? ''}', size: 36)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                if (pinned)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(9)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.push_pin_outlined, size: 11, color: AppColors.accentLight),
                        const SizedBox(width: 3),
                        Text('Ghim', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
                      ]),
                    ),
                  ),
                TextSpan(text: '${d['title'] ?? ''}'),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: body(TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.text)),
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '${d['forum']?['title'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accentLight)),
                TextSpan(text: ' · $when'),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 3),
              Text('${d['comment_count'] ?? 0}', style: muted),
              const SizedBox(width: 10),
              Icon(Icons.visibility_outlined, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 3),
              Text(formatViews(d['views'] is num ? (d['views'] as num).toInt() : null), style: muted),
              if (d['lastCommentBy']?['username'] != null) ...[
                const SizedBox(width: 10),
                Expanded(child: Text('trả lời mới: ${d['lastCommentBy']['username']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted)),
              ],
            ]),
          ])),
        ]),
      ),
    );
  }

  Widget _parentForum(Map<String, dynamic> parent) {
    final children = ((parent['children']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text((parent['title'] ?? '').toString().toUpperCase(), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.2))),
        ),
        if (children.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
            alignment: Alignment.center,
            child: Text('Chưa có chuyên mục', style: body(TextStyle(fontSize: 15, color: AppColors.textMuted))),
          )
        else
          _ForumChildrenLayout(children: children, buildBox: _forumBox),
      ]),
    );
  }

  Widget _forumBox(Map<String, dynamic> forum) {
    final discussions = ((forum['discussions']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final total = forum['discussions']?['paginatorInfo']?['total'] ?? 0;
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      clipBehavior: Clip.hardEdge,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Forum header (tappable -> forum detail)
        InkWell(
          onTap: () => context.push('/dien-dan/${forum['id']}'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.surfaceLight, border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(forum['title'] ?? '', style: display(TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text))),
                if ((forum['content'] ?? '').toString().isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text(forum['content'], style: body(TextStyle(fontSize: 14, color: AppColors.textMuted)))),
              ])),
              if (total > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                  child: Text('$total chủ đề', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
                ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
            ]),
          ),
        ),
        if (discussions.isEmpty)
          Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('Chưa có chủ đề nào', style: body(TextStyle(fontSize: 15, color: AppColors.textMuted)))))
        else ...[
          ...discussions.map(_discussionRow),
          if (total > 5)
            InkWell(
              onTap: () => context.push('/dien-dan/${forum['id']}'),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                alignment: Alignment.center,
                child: Text('Xem tất cả $total chủ đề', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.accentLight))),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _discussionRow(Map<String, dynamic> d) {
    final author = d['author'];
    return InkWell(
      onTap: () => context.push('/thao-luan/${d['id']}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36, height: 36, margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accentSoft),
            child: ClipOval(
              child: author?['avatar']?['url'] != null
                  ? CachedNetworkImage(imageUrl: cdnImg((author['avatar']['url']).toString(), 160), fit: BoxFit.cover, errorWidget: (_, __, ___) => Icon(Icons.person, color: AppColors.accentLight, size: 16))
                  : Icon(Icons.person, color: AppColors.accentLight, size: 16),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.4))),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              if (author?['username'] != null) Text(author['username'], style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
              Text(timeago(d['created_at']), style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
            ]),
          ])),
          const SizedBox(width: 8),
          if ((d['comment_count'] ?? 0) > 0) ...[
            Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 3),
            Text('${d['comment_count']}', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
            const SizedBox(width: 8),
          ],
          if ((d['views'] ?? 0) > 0) ...[
            Icon(Icons.visibility_outlined, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 3),
            Text(formatViews(d['views'] is num ? (d['views'] as num).toInt() : null), style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
          ],
        ]),
      ),
    );
  }
}

/// Layouts forum boxes responsively — single column on mobile, 2 columns
/// from 900px, 3 from 1280px. Boxes flow into rows so very long discussion
/// lists don't push subsequent forums far down the page.
class _ForumChildrenLayout extends StatelessWidget {
  final List<Map<String, dynamic>> children;
  final Widget Function(Map<String, dynamic>) buildBox;
  const _ForumChildrenLayout({required this.children, required this.buildBox});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cols = w >= 1280 ? 3 : (w >= 900 ? 2 : 1);
    if (cols == 1) {
      return Column(
        children: children.map((c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: buildBox(c))).toList(),
      );
    }
    // Distribute round-robin so column heights stay balanced even when
    // discussion counts vary wildly between boxes.
    final columns = List.generate(cols, (_) => <Map<String, dynamic>>[]);
    for (var i = 0; i < children.length; i++) {
      columns[i % cols].add(children[i]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cols; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          Expanded(
            child: Column(
              children: columns[i].map((c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: buildBox(c))).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
