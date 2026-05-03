import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/realtime.dart';

/// Narrow right-column sidebar showing the latest comments across the site —
/// mirror of bcdcnt-web's CommentSidebar/LatestCommentsWidget. Visible when
/// the authed user has show_comment_sidebar enabled.
///
/// Two render modes:
/// - default (`inline = false`): viewport-edge sidebar with fixed 320 width
///   and a left border, used by DesktopShell on detail/list routes.
/// - `inline = true`: card-style box that fills its parent's width, intended
///   for embedding inside a page's own right column (e.g. HomeScreen).
class DesktopCommentSidebar extends StatefulWidget {
  final bool inline;
  final double maxHeight;
  /// When `true`, drops the chrome (outer container, fixed width, "Bình luận
  /// mới" title row) so this widget can be embedded inside the unified
  /// right-panel container in DesktopShell. The refresh control moves to
  /// just above the list as a small icon.
  final bool embedded;
  const DesktopCommentSidebar({super.key, this.inline = false, this.maxHeight = 600, this.embedded = false});

  @override
  State<DesktopCommentSidebar> createState() => _DesktopCommentSidebarState();
}

class _DesktopCommentSidebarState extends State<DesktopCommentSidebar> {
  static const _commentFields = r'''id content created_at
        user { id username avatar { url } }
        object {
          __typename
          ... on Song { id title slug }
          ... on Folk { id title slug }
          ... on Instrumental { id title slug }
          ... on Poem { id title slug }
          ... on Karaoke { id title slug }
          ... on Artist { id title slug }
          ... on Composer { id title slug }
          ... on Poet { id title slug }
          ... on Recomposer { id title slug }
          ... on Sheet { id title slug }
          ... on Document { id title slug }
          ... on Discussion { id title slug }
          ... on Playlist { id title slug }
          ... on Page { id title slug }
        }''';

  static const _pageSize = 15;

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  final _scrollController = ScrollController();

  VoidCallback? _realtimeListener;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetch();
    // Live refresh — RealtimeService bumps newCommentTick whenever any
    // user posts a comment site-wide. Re-fetch the panel so it shows
    // the new entry without manual reload.
    final tick = realtimeService?.newCommentTick;
    if (tick != null) {
      _realtimeListener = () { if (mounted) _fetch(); };
      tick.addListener(_realtimeListener!);
    }
  }

  @override
  void dispose() {
    if (_realtimeListener != null) {
      realtimeService?.newCommentTick.removeListener(_realtimeListener!);
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _fetch() async {
    try {
      final q = '''query { latestComments(first: $_pageSize, page: 1, orderBy: [{column: "created_at", order: DESC}]) { data { $_commentFields } paginatorInfo { currentPage lastPage } } }''';
      final data = await ApiClient.query(q, null);
      final raw = (data['latestComments']?['data'] ?? []) as List;
      final pi = data['latestComments']?['paginatorInfo'] as Map?;
      if (!mounted) return;
      setState(() {
        _items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
        _page = 1;
        _hasMore = (pi?['lastPage'] ?? 1) > 1;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() { _loadingMore = true; });
    try {
      final next = _page + 1;
      final q = '''query { latestComments(first: $_pageSize, page: $next, orderBy: [{column: "created_at", order: DESC}]) { data { $_commentFields } paginatorInfo { currentPage lastPage } } }''';
      final data = await ApiClient.query(q, null);
      final raw = (data['latestComments']?['data'] ?? []) as List;
      final pi = data['latestComments']?['paginatorInfo'] as Map?;
      if (!mounted) return;
      setState(() {
        _items.addAll(raw.map((e) => Map<String, dynamic>.from(e as Map)));
        _page = next;
        _hasMore = next < ((pi?['lastPage'] ?? 1) as int);
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loadingMore = false; });
    }
  }

  String _stripHtml(String? html) {
    if (html == null || html.isEmpty) return '';
    return html.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso);
      final diff = DateTime.now().difference(d).inSeconds;
      if (diff < 60) return 'vừa xong';
      if (diff < 3600) return '${diff ~/ 60}p';
      if (diff < 86400) return '${diff ~/ 3600}h';
      if (diff < 2592000) return '${diff ~/ 86400}d';
      if (diff < 31536000) return '${diff ~/ 2592000}th';
      return '${diff ~/ 31536000}n';
    } catch (_) { return ''; }
  }

  void _openObject(Map<String, dynamic> obj) {
    final tn = obj['__typename']?.toString();
    final id = obj['id']?.toString();
    final slug = obj['slug']?.toString();
    if (id == null) return;
    const fileTypeMap = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem', 'Karaoke': 'karaoke'};
    if (fileTypeMap.containsKey(tn)) {
      context.push('/song/$id', extra: {
        'id': id, 'title': obj['title'], 'slug': slug, 'file_type': fileTypeMap[tn],
      });
      return;
    }
    switch (tn) {
      case 'Artist': context.push('/nghe-si/$slug'); break;
      case 'Composer': context.push('/nhac-si/$slug'); break;
      case 'Poet': context.push('/nha-tho/$slug'); break;
      case 'Recomposer': context.push('/soan-gia/$slug'); break;
      case 'Sheet': context.push('/sheet/$id'); break;
      case 'Document': context.push('/tu-lieu/chi-tiet/$id'); break;
      case 'Discussion': context.push('/thao-luan/$id'); break;
      case 'Playlist': context.push('/playlist/$id'); break;
      case 'Page': if (slug != null) context.push('/p/$slug'); break;
    }
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _page = 1; _hasMore = true; });
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final inline = widget.inline;
    final embedded = widget.embedded;
    Widget list = _loading
        ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        : _items.isEmpty
            ? Padding(padding: const EdgeInsets.all(20), child: Text('Chưa có bình luận nào', style: body(TextStyle(color: AppColors.textMuted, fontSize: 13))))
            : ListView.separated(
                controller: inline ? null : _scrollController,
                shrinkWrap: inline,
                physics: inline ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                itemCount: _items.length + (_loadingMore || _hasMore ? 1 : 0),
                separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.borderSubtle),
                itemBuilder: (_, i) {
                  if (i >= _items.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: _loadingMore
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const SizedBox.shrink(),
                      ),
                    );
                  }
                  return _CommentTile(
                    comment: _items[i],
                    stripHtml: _stripHtml,
                    timeAgo: _timeAgo,
                    onTap: () {
                      final obj = _items[i]['object'];
                      if (obj is Map) _openObject(Map<String, dynamic>.from(obj));
                    },
                  );
                },
              );

    // Pull-to-refresh on the scrollable variants. Embedded mode lives inside
    // the shell panel which has its own header; standalone mode keeps the
    // original header. Inline mode doesn't scroll, so no refresh wrap.
    if (!inline) {
      list = RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        onRefresh: _refresh,
        child: list,
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: inline ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (!embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                Text('Bình luận mới', style: display(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text))),
                const Spacer(),
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Làm mới',
                  icon: Icon(Icons.refresh, color: AppColors.textSecondary),
                  onPressed: _refresh,
                ),
              ],
            ),
          ),
        if (inline)
          ConstrainedBox(constraints: BoxConstraints(maxHeight: widget.maxHeight), child: list)
        else
          Expanded(child: list),
      ],
    );

    if (embedded) return content;
    if (inline) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.hardEdge,
        child: content,
      );
    }
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: content,
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Map<String, dynamic> comment;
  final String Function(String?) stripHtml;
  final String Function(String?) timeAgo;
  final VoidCallback onTap;
  const _CommentTile({required this.comment, required this.stripHtml, required this.timeAgo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final user = (comment['user'] as Map?) ?? {};
    final username = user['username']?.toString() ?? '';
    final avatar = (user['avatar'] as Map?)?['url']?.toString();
    final obj = (comment['object'] as Map?) ?? {};
    final objTitle = obj['title']?.toString() ?? '';
    final content = stripHtml(comment['content']?.toString());
    final t = timeAgo(comment['created_at']?.toString());

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipOval(
              child: SizedBox(
                width: 28, height: 28,
                child: avatar != null && avatar.isNotEmpty
                    ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, errorWidget: (_, __, ___) => _placeholder(username))
                    : _placeholder(username),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title (parent post) leads — matches web's emphasis on
                  // what's being commented on rather than the commenter.
                  if (objTitle.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            objTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: body(TextStyle(fontSize: 12, color: AppColors.text, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(t, style: body(TextStyle(fontSize: 10, color: AppColors.textMuted))),
                      ],
                    ),
                  if (objTitle.isNotEmpty) const SizedBox(height: 1),
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(TextStyle(fontSize: 11, color: AppColors.accentLight, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(String username) {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    return Container(
      color: AppColors.accent,
      alignment: Alignment.center,
      child: Text(initial, style: body(const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
    );
  }
}
