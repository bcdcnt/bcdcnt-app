import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';

class ForumDetailScreen extends StatefulWidget {
  final String id;
  const ForumDetailScreen({super.key, required this.id});

  @override
  State<ForumDetailScreen> createState() => _ForumDetailScreenState();
}

class _ForumDetailScreenState extends State<ForumDetailScreen> {
  Map<String, dynamic>? _forum;
  List<Map<String, dynamic>> _children = [];
  List<Map<String, dynamic>> _discussions = [];
  int _page = 1, _lastPage = 1, _total = 0;
  bool _loading = true, _loadingMore = false;
  final _scrollCtl = ScrollController();

  @override
  void initState() { super.initState(); _scrollCtl.addListener(_onScroll); _fetchInitial(); }
  @override
  void dispose() { _scrollCtl.removeListener(_onScroll); _scrollCtl.dispose(); super.dispose(); }
  void _onScroll() {
    if (_loadingMore || _loading || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetchDiscussions(_page + 1);
  }

  Future<void> _fetchInitial() async {
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        forum(id: $id) {
          id title slug content
          parent { id title slug }
          children(first: 50) { data { id title slug content } }
          discussions(first: 20, page: 1, orderBy: [{column: "is_sticky", order: DESC}, {column: "id", order: DESC}], where: {AND: [{column: "status", value: 1}]}) {
            data {
              id title slug created_at comment_count views is_sticky
              author { id username avatar { url } }
              thumbnail { url }
            }
            paginatorInfo { currentPage lastPage total }
          }
        }
      }''', {'id': widget.id});
      final f = data['forum'];
      if (!mounted) return;
      if (f == null) { setState(() => _loading = false); return; }
      final forum = Map<String, dynamic>.from(f as Map);
      final children = ((forum['children']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final discussions = ((forum['discussions']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final pi = forum['discussions']?['paginatorInfo'] ?? {};
      setState(() {
        _forum = forum;
        _children = children;
        _discussions = discussions;
        _page = pi['currentPage'] ?? 1;
        _lastPage = pi['lastPage'] ?? 1;
        _total = pi['total'] ?? 0;
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _fetchDiscussions(int page) async {
    setState(() => _loadingMore = true);
    try {
      final data = await ApiClient.query(r'''query($id: ID!, $page: Int) {
        forum(id: $id) {
          discussions(first: 20, page: $page, orderBy: [{column: "is_sticky", order: DESC}, {column: "id", order: DESC}], where: {AND: [{column: "status", value: 1}]}) {
            data {
              id title slug created_at comment_count views is_sticky
              author { id username avatar { url } }
              thumbnail { url }
            }
            paginatorInfo { currentPage lastPage total }
          }
        }
      }''', {'id': widget.id, 'page': page});
      final disc = data['forum']?['discussions'];
      final list = ((disc?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final pi = disc?['paginatorInfo'] ?? {};
      if (!mounted) return;
      setState(() {
        _discussions.addAll(list);
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _loadingMore = false;
      });
    } catch (_) { if (mounted) setState(() => _loadingMore = false); }
  }

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 == 0) buf.write('.'); buf.write(s[i]); }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (_loading) return Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    if (_forum == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
        body: Center(child: Text('Không tìm thấy diễn đàn', style: AppText.bodyText)),
      );
    }
    final f = _forum!;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(controller: _scrollCtl, slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text((f['title'] ?? '').toString().toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            sliver: SliverList(delegate: SliverChildListDelegate([
              if (f['parent']?['title'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(f['parent']['title'], style: body(TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
                ),
              Text(f['title'] ?? '', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.3))),
              if ((f['content'] ?? '').toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(f['content'], style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5))),
                ),
              const SizedBox(height: 16),

              if (_children.isNotEmpty) ...[
                Text('BOX CON', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.2))),
                const SizedBox(height: 8),
                ..._children.map((c) => InkWell(
                  onTap: () => context.push('/dien-dan/${c['id']}'),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.folder_outlined, size: 16, color: AppColors.accentLight),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c['title'] ?? '', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                        if ((c['content'] ?? '').toString().isNotEmpty)
                          Padding(padding: const EdgeInsets.only(top: 2), child: Text(c['content'], maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 11, color: AppColors.textMuted)))),
                      ])),
                      Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                    ]),
                  ),
                )),
                const SizedBox(height: 16),
              ],

              Row(children: [
                Icon(Icons.forum_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('Chủ đề (${_formatInt(_total)})', style: display(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
              ]),
              const SizedBox(height: 8),
            ])),
          ),
          if (_discussions.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              sliver: SliverToBoxAdapter(child: Center(child: Text('Chưa có chủ đề nào', style: body(TextStyle(color: AppColors.textMuted))))),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (ctx, i) => _discussionRow(_discussions[i]),
                childCount: _discussions.length,
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

  Widget _discussionRow(Map<String, dynamic> d) {
    final author = d['author'];
    final isSticky = d['is_sticky'] == 1 || d['is_sticky'] == true;
    return InkWell(
      onTap: () => context.push('/thao-luan/${d['id']}'),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36, height: 36, margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accentSoft),
            child: ClipOval(
              child: author?['avatar']?['url'] != null
                  ? CachedNetworkImage(imageUrl: author['avatar']['url'], fit: BoxFit.cover, errorWidget: (_, __, ___) => Icon(Icons.person, color: AppColors.accentLight, size: 18))
                  : Icon(Icons.person, color: AppColors.accentLight, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (isSticky) Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(4)),
                  child: Text('Ghim', style: body(TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.accentLight))),
                ),
              ),
              Expanded(child: Text(d['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.4)))),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 10, children: [
              if (author?['username'] != null) Text(author['username'], style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              Text(timeago(d['created_at']), style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
              if ((d['comment_count'] ?? 0) > 0)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_bubble_outline, size: 11, color: AppColors.textMuted),
                  const SizedBox(width: 3),
                  Text('${d['comment_count']}', style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
                ]),
              if ((d['views'] ?? 0) > 0)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.visibility_outlined, size: 11, color: AppColors.textMuted),
                  const SizedBox(width: 3),
                  Text('${d['views']}', style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
                ]),
            ]),
          ])),
          if (d['thumbnail']?['url'] != null) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(imageUrl: d['thumbnail']['url'], width: 56, height: 56, fit: BoxFit.cover),
            ),
          ],
        ]),
      ),
    );
  }
}
