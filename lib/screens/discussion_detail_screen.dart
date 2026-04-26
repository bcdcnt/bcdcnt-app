import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import '../widgets/comment_section.dart';

class DiscussionDetailScreen extends StatefulWidget {
  final String id;
  const DiscussionDetailScreen({super.key, required this.id});

  @override
  State<DiscussionDetailScreen> createState() => _DiscussionDetailScreenState();
}

class _DiscussionDetailScreenState extends State<DiscussionDetailScreen> {
  Map<String, dynamic>? _d;
  bool _loading = true;

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        discussion(id: $id) {
          id title slug content created_at status is_closed views
          author { id username avatar { url } }
          thumbnail { url }
          forum { id title slug parent { id title slug } }
        }
      }''', {'id': widget.id});
      if (!mounted) return;
      setState(() {
        _d = data['discussion'] != null ? Map<String, dynamic>.from(data['discussion'] as Map) : null;
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (_loading) {
      return const Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    }
    if (_d == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
        body: Center(child: Text('Không tìm thấy thảo luận', style: AppText.bodyText)),
      );
    }
    final d = _d!;
    final author = d['author'];
    final forum = d['forum'];
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text('THẢO LUẬN', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList(delegate: SliverChildListDelegate([
              if (forum != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (forum['parent']?['title'] != null) ...[
                      Text(forum['parent']['title'], style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.chevron_right, size: 12, color: AppColors.textMuted)),
                    ],
                    Text(forum['title'] ?? '', style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
                  ]),
                ),
              Text(d['title'] ?? '', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.3))),
              const SizedBox(height: 12),
              // Author row
              Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accentSoft),
                  child: ClipOval(
                    child: author?['avatar']?['url'] != null
                        ? CachedNetworkImage(imageUrl: author['avatar']['url'], fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.person, color: AppColors.accentLight, size: 16))
                        : const Icon(Icons.person, color: AppColors.accentLight, size: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (author?['username'] != null)
                    InkWell(
                      onTap: () => context.push('/user/${author['id']}'),
                      child: Text(author['username'], style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                    ),
                  Text(timeago(d['created_at']), style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                ])),
                if ((d['views'] ?? 0) > 0) Row(children: [
                  const Icon(Icons.visibility_outlined, size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 3),
                  Text('${d['views']}', style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                ]),
              ]),
              const SizedBox(height: 16),
              // Content
              if ((d['content'] ?? '').toString().isNotEmpty)
                Html(
                  data: d['content'] ?? '',
                  style: {
                    'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero, fontSize: FontSize(14), lineHeight: const LineHeight(1.7), color: AppColors.textSecondary, fontFamily: body().fontFamily),
                    'h1, h2, h3': Style(color: AppColors.text, fontFamily: display().fontFamily),
                    'a': Style(color: AppColors.accentLight, textDecoration: TextDecoration.none),
                    'p': Style(margin: Margins.only(bottom: 10)),
                    'img': Style(width: Width(100, Unit.percent)),
                  },
                  onLinkTap: (url, _, __) {
                    if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                ),
              const SizedBox(height: 24),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 20),
              // Comments
              CommentSection(type: 'discussion', id: widget.id),
              SizedBox(height: player.currentSong != null ? 90 : 20),
            ])),
          ),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
