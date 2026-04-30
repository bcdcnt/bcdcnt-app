import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/empty_state.dart';

class CommentsScreen extends StatefulWidget {
  const CommentsScreen({super.key});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;

  static const _query = r'''query($page: Int) {
    latestComments(first: 20, orderBy: [{column: "created_at", order: DESC}], page: $page) {
      data {
        id content created_at
        user { id username avatar { url } }
        object {
          __typename
          ... on Song { id title slug thumbnail { url } }
          ... on Folk { id title slug thumbnail { url } }
          ... on Instrumental { id title slug thumbnail { url } }
          ... on Poem { id title slug thumbnail { url } }
          ... on Karaoke { id title slug thumbnail { url } }
          ... on Artist { id title slug avatar { url } }
          ... on Composer { id title slug avatar { url } }
          ... on Poet { id title slug avatar { url } }
          ... on Recomposer { id title slug avatar { url } }
          ... on Sheet { id title slug }
          ... on Document { id title slug thumbnail { url } }
          ... on Discussion { id title slug }
          ... on Playlist { id title slug thumbnail { url } }
          ... on Page { id title slug }
          ... on Upload { id title slug }
          ... on Ticket { id title slug }
          ... on Role { id name slug alias }
        }
      }
      paginatorInfo { currentPage lastPage total }
    }
  }''';

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    _fetch(1);
  }

  @override
  void dispose() {
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _loading) return;
    if (_page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) {
      _fetch(_page + 1);
    }
  }

  Future<void> _fetch(int page) async {
    setState(() { if (page == 1) _loading = true; else _loadingMore = true; });
    try {
      final data = await ApiClient.query(_query, {'page': page});
      final raw = data['latestComments'];
      final list = ((raw?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final pi = raw?['paginatorInfo'] ?? {};
      if (!mounted) return;
      setState(() {
        if (page == 1) _items = list; else _items.addAll(list);
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _total = pi['total'] ?? _total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadingMore = false; });
    }
  }

  Future<void> _refresh() async => _fetch(1);

  String _stripHtml(String? html) {
    if (html == null || html.isEmpty) return '';
    return html.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}…';

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso);
      final diff = DateTime.now().difference(d).inSeconds;
      if (diff < 60) return 'vừa xong';
      if (diff < 3600) return '${diff ~/ 60} phút trước';
      if (diff < 86400) return '${diff ~/ 3600} giờ trước';
      if (diff < 2592000) return '${diff ~/ 86400} ngày trước';
      if (diff < 31536000) return '${diff ~/ 2592000} tháng trước';
      return '${diff ~/ 31536000} năm trước';
    } catch (_) { return ''; }
  }

  String _objTypeLabel(String? typename) {
    const map = {
      'Song': 'Tân nhạc', 'Folk': 'Dân ca', 'Instrumental': 'Khí nhạc', 'Poem': 'Tiếng thơ', 'Karaoke': 'Thành viên hát',
      'Artist': 'Nghệ sĩ', 'Composer': 'Nhạc sĩ', 'Poet': 'Nhà thơ', 'Recomposer': 'Soạn giả',
      'Sheet': 'Bản nhạc', 'Document': 'Tư liệu', 'Discussion': 'Thảo luận', 'Playlist': 'Playlist', 'Page': 'Trang',
      'Upload': 'Bài gửi', 'Ticket': 'Ticket', 'Role': 'Nhóm thành viên',
    };
    return map[typename] ?? '';
  }

  void _openObject(Map<String, dynamic> obj) {
    final tn = obj['__typename']?.toString();
    final id = obj['id']?.toString();
    final slug = obj['slug']?.toString();
    if (id == null) return;
    const fileTypeMap = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem', 'Karaoke': 'karaoke'};
    if (fileTypeMap.containsKey(tn)) {
      final song = <String, dynamic>{
        'id': id, 'title': obj['title'], 'slug': slug, 'file_type': fileTypeMap[tn],
        if (obj['thumbnail'] != null) 'thumbnail': obj['thumbnail'],
      };
      context.push('/song/$id', extra: song);
      return;
    }
    switch (tn) {
      case 'Artist': context.push('/nghe-si/$slug'); break;
      case 'Composer': context.push('/nhac-si/$slug'); break;
      case 'Poet': context.push('/nha-tho/$slug'); break;
      case 'Recomposer': context.push('/soan-gia/$slug'); break;
      case 'Document':
        context.push('/tu-lieu/chi-tiet/$id');
        break;
      case 'Sheet':
        context.push('/sheet/$id');
        break;
      case 'Discussion':
        context.push('/thao-luan/$id');
        break;
      case 'Playlist':
        context.push('/playlist/$id');
        break;
      case 'Page':
        context.push('/p/$slug');
        break;
      case 'Upload':
        context.push('/bai-gui/$id');
        break;
      case 'Ticket':
        launchUrl(Uri.parse('$siteUrl/ticket/$slug-$id'), mode: LaunchMode.externalApplication);
        break;
      case 'Role':
        launchUrl(Uri.parse('$siteUrl/nhom/${obj['alias'] ?? slug}'), mode: LaunchMode.externalApplication);
        break;
    }
  }

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return n < 0 ? '-$buf' : buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollCtl,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverList(delegate: SliverChildListDelegate([
                Row(
                  children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: -2)],
                      ),
                      child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Bình luận mới nhất', style: display(const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.2))),
                          if (_total > 0) Text('${_formatInt(_total)} bình luận từ cộng đồng', style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ])),
            ),

            if (_loading && _items.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
            else if (_items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'Chưa có bình luận',
                  subtitle: 'Bình luận mới nhất từ cộng đồng sẽ hiển thị ở đây.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      if (i == _items.length) {
                        if (_loadingMore) return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)));
                        return SizedBox(height: player.currentSong != null ? 90 : 20);
                      }
                      return _CommentCard(
                        comment: _items[i],
                        onTapObject: _openObject,
                        stripHtml: _stripHtml,
                        truncate: _truncate,
                        timeAgo: _timeAgo,
                        objTypeLabel: _objTypeLabel,
                      );
                    },
                    childCount: _items.length + 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  final Map<String, dynamic> comment;
  final void Function(Map<String, dynamic>) onTapObject;
  final String Function(String?) stripHtml;
  final String Function(String, int) truncate;
  final String Function(String?) timeAgo;
  final String Function(String?) objTypeLabel;
  const _CommentCard({required this.comment, required this.onTapObject, required this.stripHtml, required this.truncate, required this.timeAgo, required this.objTypeLabel});

  @override
  Widget build(BuildContext context) {
    final user = comment['user'];
    final obj = comment['object'];
    final plain = truncate(stripHtml(comment['content']?.toString()), 200);
    final tn = obj?['__typename']?.toString();
    final isPerson = tn == 'Artist' || tn == 'Composer' || tn == 'Poet' || tn == 'Recomposer';
    final objImage = (obj?['thumbnail']?['url'] ?? obj?['avatar']?['url'])?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Object header
          if (obj != null) InkWell(
            onTap: () => onTapObject(Map<String, dynamic>.from(obj as Map)),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: isPerson ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: isPerson ? null : BorderRadius.circular(8),
                      color: AppColors.surface,
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: objImage != null
                        ? CachedNetworkImage(imageUrl: objImage, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.music_note, color: AppColors.textMuted, size: 16))
                        : const Icon(Icons.music_note, color: AppColors.textMuted, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          (obj['title'] ?? obj['name'] ?? '').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: display(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentLight, height: 1.3)),
                        ),
                        if (objTypeLabel(tn).isNotEmpty) Text(
                          objTypeLabel(tn),
                          style: body(const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
                ],
              ),
            ),
          ),

          // Comment content
          if (plain.isNotEmpty) Text(
            plain,
            style: body(const TextStyle(fontSize: 13, color: AppColors.text, height: 1.55)),
          ),

          if (plain.isNotEmpty) const SizedBox(height: 10),

          // User + time
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.surface,
                backgroundImage: user?['avatar']?['url'] != null ? CachedNetworkImageProvider(user['avatar']['url']) : null,
                child: user?['avatar']?['url'] == null
                    ? Text((user?['username'] ?? '?').toString().substring(0, 1).toUpperCase(), style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted)))
                    : null,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  user?['username'] ?? '?',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeAgo(comment['created_at']?.toString()),
                style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
