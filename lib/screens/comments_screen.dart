import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../widgets/song_row.dart' show playOrOpen;
import '../widgets/ui.dart';

const _objFields = '''
          __typename
          ... on Song { id title slug thumbnail { url } file { audio_url } }
          ... on Folk { id title slug thumbnail { url } file { audio_url } }
          ... on Instrumental { id title slug thumbnail { url } file { audio_url } }
          ... on Poem { id title slug thumbnail { url } file { audio_url } }
          ... on Karaoke { id title slug thumbnail { url } file { audio_url } }
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
          ... on Role { id name slug alias }''';

const _latestQuery = '''query(\$page: Int, \$where: WhereConditions) {
    latestComments(first: 20, orderBy: [{column: "created_at", order: DESC}], page: \$page, where: \$where) {
      data { id content likes created_at user { id username avatar { url } } object { $_objFields } }
      paginatorInfo { currentPage lastPage total }
    }
  }''';

const _featuredQuery = 'query { featuredComments(limit: 30) { id snippet likes created_at username user_avatar song_id song_title song_slug song_image audio_url file_type } }';

const _fileTypes = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem', 'Karaoke': 'karaoke'};

String _stripHtml(String? html) {
  if (html == null || html.isEmpty) return '';
  return html
      .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Bình luận route (desktop sidebar link and old deep links). On phones the
/// same feed lives in the Cộng đồng tab.
class CommentsScreen extends StatelessWidget {
  const CommentsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bg,
        body: const SafeArea(bottom: false, child: CommentsFeed(showTitle: true)),
      );
}

/// "Cảm nhận" feed: Nổi bật (featuredComments), Mới nhất (comments that are
/// not requests) and Yêu cầu bổ sung (is_request = 1), split by the API's
/// own flag so requests to BQT no longer bury listener stories.
class CommentsFeed extends StatefulWidget {
  final bool showTitle;
  const CommentsFeed({super.key, this.showTitle = false});
  @override
  State<CommentsFeed> createState() => _CommentsFeedState();
}

class _CommentsFeedState extends State<CommentsFeed> {
  static const _filters = ['Nổi bật', 'Mới nhất', 'Yêu cầu bổ sung'];
  final _scrollCtl = ScrollController();
  int _filter = 0;
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _lastPage = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    _fetch(1);
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_filter == 0 || _loadingMore || _loading || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(_page + 1);
  }

  Future<void> _fetch(int page) async {
    final filter = _filter;
    setState(() {
      _failed = false;
      if (page == 1) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
    });
    try {
      List<Map<String, dynamic>> list;
      if (filter == 0) {
        final d = await ApiClient.query(_featuredQuery);
        list = ((d['featuredComments'] ?? []) as List).whereType<Map>().map((c) {
          final m = Map<String, dynamic>.from(c);
          return <String, dynamic>{
            'id': m['id'],
            'text': m['snippet'],
            'likes': m['likes'],
            'created_at': m['created_at'],
            'user': {'username': m['username'], 'avatar': {'url': m['user_avatar']}},
            'object': {
              '__typename': 'Song',
              'id': m['song_id'],
              'title': m['song_title'],
              'slug': m['song_slug'],
              'file_type': m['file_type'] ?? 'song',
              if (m['song_image'] != null) 'thumbnail': {'url': m['song_image']},
              if (m['audio_url'] != null) 'file': {'audio_url': m['audio_url']},
            },
          };
        }).toList();
        _lastPage = 1;
        _page = 1;
      } else {
        final d = await ApiClient.query(_latestQuery, {
          'page': page,
          'where': {'AND': [{'column': 'is_request', 'value': filter == 2 ? 1 : 0}]},
        });
        final raw = d['latestComments'];
        list = ((raw?['data'] ?? []) as List).whereType<Map>().map((e) {
          final m = Map<String, dynamic>.from(e);
          m['text'] = _stripHtml(m['content']?.toString());
          return m;
        }).where((m) => (m['text'] as String).isNotEmpty).toList();
        final pi = raw?['paginatorInfo'] ?? {};
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
      }
      if (!mounted || filter != _filter) return;
      setState(() {
        if (page == 1) {
          _items = list;
        } else {
          _items.addAll(list);
        }
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadingMore = false; _failed = _items.isEmpty; });
    }
  }

  void _openObject(Map<String, dynamic> obj) {
    final tn = obj['__typename']?.toString();
    final id = obj['id']?.toString();
    final slug = obj['slug']?.toString();
    if (id == null) return;
    if (_fileTypes.containsKey(tn)) {
      context.push('/song/$id', extra: {...obj, 'file_type': obj['file_type'] ?? _fileTypes[tn]});
      return;
    }
    switch (tn) {
      case 'Artist': context.push('/nghe-si/$slug'); break;
      case 'Composer': context.push('/nhac-si/$slug'); break;
      case 'Poet': context.push('/nha-tho/$slug'); break;
      case 'Recomposer': context.push('/soan-gia/$slug'); break;
      case 'Document': context.push('/tu-lieu/chi-tiet/$id'); break;
      case 'Sheet': context.push('/sheet/$id'); break;
      case 'Discussion': context.push('/thao-luan/$id'); break;
      case 'Playlist': context.push('/playlist/$id'); break;
      case 'Page': context.push('/p/$slug'); break;
      case 'Upload': context.push('/bai-gui/$id'); break;
      case 'Ticket': context.push('/ho-tro/$id'); break;
      case 'Role': launchUrl(Uri.parse('$siteUrl/nhom/${obj['alias'] ?? slug}'), mode: LaunchMode.externalApplication); break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: () => _fetch(1),
      child: CustomScrollView(
        controller: _scrollCtl,
        slivers: [
          if (widget.showTitle) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(bottom: 14), child: PageTitle('Bình luận'))),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: ChipStrip(
                labels: _filters,
                selected: _filter,
                onSelect: (i) {
                  setState(() {
                    _filter = i;
                    _items = [];
                  });
                  _fetch(1);
                },
              ),
            ),
          ),
          if (_loading && _items.isEmpty)
            SliverList(delegate: SliverChildBuilderDelegate((_, __) => const _CommentSkeleton(), childCount: 5))
          else if (_failed)
            SliverToBoxAdapter(child: EmptyBlock(icon: Icons.wifi_off_rounded, title: 'Chưa tải được bình luận', message: 'Kiểm tra kết nối mạng rồi thử lại.', action: 'Tải lại', onAction: () => _fetch(1)))
          else if (_items.isEmpty)
            const SliverToBoxAdapter(child: EmptyBlock(icon: Icons.chat_bubble_outline_rounded, title: 'Chưa có bình luận', message: 'Cảm nhận mới của cộng đồng sẽ hiện ở đây.'))
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  if (i.isOdd) return Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.border);
                  return CommentTile(comment: _items[i ~/ 2], onOpenObject: _openObject);
                },
                childCount: _items.length * 2 - 1,
              ),
            ),
          SliverToBoxAdapter(
            child: _loadingMore
                ? Padding(padding: const EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)))
                : const SizedBox(height: 24),
          ),
        ],
      ),
    );
  }
}

class _CommentSkeleton extends StatelessWidget {
  const _CommentSkeleton();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Skeleton(width: 40, height: 40, radius: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FractionallySizedBox(widthFactor: 0.4, child: Skeleton(height: 13)),
              SizedBox(height: 10),
              Skeleton(height: 12),
              SizedBox(height: 6),
              FractionallySizedBox(widthFactor: 0.8, child: Skeleton(height: 12)),
              SizedBox(height: 12),
              Skeleton(height: 48, radius: 12),
            ]),
          ),
        ]),
      );
}

/// One comment: avatar, name, time, text, the song/page it belongs to (tap
/// to open, play button for songs) and the like count.
class CommentTile extends StatelessWidget {
  final Map<String, dynamic> comment;
  final void Function(Map<String, dynamic>) onOpenObject;
  const CommentTile({super.key, required this.comment, required this.onOpenObject});

  @override
  Widget build(BuildContext context) {
    final user = comment['user'] as Map?;
    final obj = comment['object'] is Map ? Map<String, dynamic>.from(comment['object']) : null;
    final text = (comment['text'] ?? '').toString();
    final tn = obj?['__typename']?.toString();
    final isSong = _fileTypes.containsKey(tn);
    final img = (obj?['thumbnail']?['url'] ?? obj?['avatar']?['url'])?.toString();
    final likes = comment['likes'] is num ? (comment['likes'] as num).toInt() : 0;
    final name = (user?['username'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(url: user?['avatar']?['url']?.toString(), name: name, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)))),
                  const SizedBox(width: 8),
                  Text(timeago(comment['created_at']?.toString()), style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                ]),
                const SizedBox(height: 4),
                Text(text.length > 320 ? '${text.substring(0, 320)}…' : text, style: body(TextStyle(fontSize: 15, height: 1.55, fontWeight: FontWeight.w500, color: AppColors.text))),
                if (obj != null) ...[
                  const SizedBox(height: 10),
                  Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onOpenObject(obj);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(children: [
                          if (img != null) NetImage(url: img, width: 34, height: 34, radius: 8),
                          if (img != null) const SizedBox(width: 10),
                          Expanded(child: Text((obj['title'] ?? obj['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)))),
                          if (isSong && obj['file']?['audio_url'] != null)
                            IconButton(
                              tooltip: 'Nghe',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.play_circle_fill_rounded, color: AppColors.accentLight, size: 30),
                              onPressed: () => playOrOpen(context, {...obj, 'file_type': obj['file_type'] ?? _fileTypes[tn]}, [], 'Cộng đồng'),
                            )
                          else
                            Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                        ]),
                      ),
                    ),
                  ),
                ],
                if (likes > 0) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.favorite_border_rounded, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text('$likes', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
