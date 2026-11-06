import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock, EmptyBlock;
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

  @override
  void initState() {
    super.initState();
    if (widget.embedded) TabReselect.tick.addListener(_onReselect);
    _fetch();
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
          onRefresh: _fetch,
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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

                ..._forums.map((parent) => _parentForum(parent)),
              ])),
            ),
          SliverToBoxAdapter(child: SizedBox(height: player.currentSong != null ? 90 : 20)),
        ])),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
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
