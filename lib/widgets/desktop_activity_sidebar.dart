import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';

/// Compact member-activity feed for the right inspector panel — mirrors
/// the Bình luận sidebar but lists "thành viên X làm gì với Y" rows.
/// `embedded=true` strips chrome (title bar, surrounding container) so it
/// fits inside the shell panel; the standalone `/cong-dong/hoat-dong-...`
/// route still uses the full `ActivityScreen` with filter chips +
/// day groups.
class DesktopActivitySidebar extends StatefulWidget {
  final bool embedded;
  const DesktopActivitySidebar({super.key, this.embedded = true});

  @override
  State<DesktopActivitySidebar> createState() => _DesktopActivitySidebarState();
}

class _DesktopActivitySidebarState extends State<DesktopActivitySidebar> {
  // Long-form action labels matching web's i18n strings (vi/common.json
  // → activity.*) so sidebar rows read naturally: "username Cập nhật lời
  // bài hát trong [Bài X]".
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

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final actionsStr = _actionLabels.keys.map((a) => '"$a"').join(', ');
      final q = '''query {
        activities(first: 30, where: {AND: [{column: "action", value: [$actionsStr], operator: IN}]}, orderBy: [{column: "id", order: DESC}]) {
          edges { node {
            action created_at
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
              ... on Upload { id title user { id username } }
              ... on Comment { id user { id username } object { __typename ... on Song { id title slug } ... on Folk { id title slug } ... on Instrumental { id title slug } ... on Poem { id title slug } ... on Karaoke { id title slug } ... on Document { id title slug } ... on Discussion { id title slug } } }
            }
          } }
        }
      }''';
      final data = await ApiClient.query(q);
      final edges = (data['activities']?['edges'] ?? []) as List;
      final nodes = edges.map((e) => Map<String, dynamic>.from(e['node'] as Map)).toList();
      if (!mounted) return;
      setState(() { _items = nodes; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _objectRoute(Map<String, dynamic>? obj) {
    if (obj == null) return null;
    final type = (obj['__typename'] ?? '').toString().toLowerCase();
    if (type == 'song' || type == 'folk' || type == 'instrumental' || type == 'poem' || type == 'karaoke') return '/song/${obj['id']}';
    if (type == 'sheet') return '/sheet/${obj['id']}';
    if (type == 'document') return '/tu-lieu/chi-tiet/${obj['id']}';
    if (type == 'discussion') return '/dien-dan/${obj['id']}';
    return null;
  }

  void _openObject(Map<String, dynamic>? obj) {
    if (obj == null) return;
    var target = obj;
    if (obj['__typename'] == 'Comment' && obj['object'] != null) target = Map<String, dynamic>.from(obj['object'] as Map);
    final r = _objectRoute(target);
    if (r != null) context.push(r);
  }

  String _shortTimeAgo(String? ts) {
    if (ts == null) return '';
    final dt = DateTime.tryParse(ts)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes}p';
    if (diff.inHours < 24) return '${diff.inHours}g';
    if (diff.inDays < 7) return '${diff.inDays}n';
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.accent)));
    }
    if (_items.isEmpty) {
      return Center(child: Text('Chưa có hoạt động', style: body(const TextStyle(color: AppColors.textMuted))));
    }
    final list = RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: _fetch,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _items.length,
        itemBuilder: (ctx, i) => _ActivityTile(
          activity: _items[i],
          actionLabel: _actionLabels[_items[i]['action']?.toString()] ?? (_items[i]['action']?.toString() ?? ''),
          actionIcon: _actionIcons[_items[i]['action']?.toString()] ?? Icons.access_time,
          shortTimeAgo: _shortTimeAgo,
          onTap: () => _openObject(_items[i]['object'] != null ? Map<String, dynamic>.from(_items[i]['object'] as Map) : null),
        ),
      ),
    );

    if (widget.embedded) return list;
    // Standalone variant — wrap with own surface/header (rarely used).
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: list,
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final Map<String, dynamic> activity;
  final String actionLabel;
  final IconData actionIcon;
  final String Function(String?) shortTimeAgo;
  final VoidCallback onTap;
  const _ActivityTile({
    required this.activity,
    required this.actionLabel,
    required this.actionIcon,
    required this.shortTimeAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final user = activity['user'];
    final username = user?['username']?.toString() ?? '';
    final avatar = user?['avatar']?['url']?.toString();
    final action = (activity['action'] ?? '').toString();
    final obj = activity['object'] != null ? Map<String, dynamic>.from(activity['object'] as Map) : null;
    final isComment = obj?['__typename'] == 'Comment';
    final isUpload = obj?['__typename'] == 'Upload';
    Map<String, dynamic>? innerObj;
    if (isComment && obj?['object'] != null) innerObj = Map<String, dynamic>.from(obj!['object'] as Map);
    final objTitle = (innerObj ?? obj)?['title']?.toString();

    // Connector word between action and target title — matches web's
    // ActivityClient logic. Comment-like actions get "trong" (in
    // <song>); Upload pulls the title before the "của <user>" suffix.
    final usesIn = action == 'comment' || action == 'love_comment' || isComment;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipOval(
            child: SizedBox(
              width: 28, height: 28,
              child: avatar != null && avatar.isNotEmpty
                  ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, errorWidget: (_, _, _) => _placeholder(username))
                  : _placeholder(username),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            RichText(
              maxLines: 3, overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: body(const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
                children: _buildSpans(
                  username: username,
                  actionLabel: actionLabel,
                  isComment: isComment,
                  isUpload: isUpload,
                  obj: obj,
                  innerObj: innerObj,
                  objTitle: objTitle,
                  usesIn: usesIn,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(shortTimeAgo(activity['created_at']?.toString()), style: body(const TextStyle(fontSize: 10, color: AppColors.textMuted))),
          ])),
          const SizedBox(width: 6),
          Container(
            width: 22, height: 22, margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(6)),
            child: Icon(actionIcon, size: 12, color: AppColors.accentLight),
          ),
        ]),
      ),
    );
  }

  List<InlineSpan> _buildSpans({
    required String username,
    required String actionLabel,
    required bool isComment,
    required bool isUpload,
    required Map<String, dynamic>? obj,
    required Map<String, dynamic>? innerObj,
    required String? objTitle,
    required bool usesIn,
  }) {
    final spans = <InlineSpan>[];
    if (username.isNotEmpty) {
      spans.add(TextSpan(text: username, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)));
      spans.add(const TextSpan(text: ' '));
    }
    spans.add(TextSpan(text: actionLabel));

    if (isComment && obj?['user']?['username'] != null) {
      // "[user] bình luận của [obj.user] trong [innerObj.title]"
      spans.add(const TextSpan(text: ' của '));
      spans.add(TextSpan(
        text: obj!['user']['username'].toString(),
        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text),
      ));
    }

    if (isUpload && obj?['user']?['username'] != null) {
      // "[user] duyệt bài gửi [obj.title] của [obj.user]"
      if (objTitle != null && objTitle.isNotEmpty) {
        spans.add(const TextSpan(text: ' '));
        spans.add(TextSpan(text: objTitle, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.accentLight)));
      }
      spans.add(const TextSpan(text: ' của '));
      spans.add(TextSpan(
        text: obj!['user']['username'].toString(),
        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text),
      ));
      return spans;
    }

    if (objTitle != null && objTitle.isNotEmpty && !isUpload) {
      spans.add(TextSpan(text: usesIn ? ' trong ' : ' '));
      spans.add(TextSpan(text: objTitle, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.accentLight)));
    }
    return spans;
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
