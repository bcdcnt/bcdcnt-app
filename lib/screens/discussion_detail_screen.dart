import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/activity.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import '../widgets/comment_media.dart';
import '../widgets/waveform_player.dart';
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
          file { audio_url video_url duration type }
          polls(first: 5) { data { id title options { id name total_answer percent position answers(first: 12) { data { id user { id username avatar { url } } } } } } }
        }
      }''', {'id': widget.id});
      if (!mounted) return;
      setState(() {
        _d = data['discussion'] != null ? Map<String, dynamic>.from(data['discussion'] as Map) : null;
        _loading = false;
      });
      if (_d?['id'] != null) {
        logActivity(context.read<AuthProvider>(), 'view', 'discussion', _d!['id']);
      }
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (_loading) {
      return Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    }
    if (_d == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
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
            title: Text('THẢO LUẬN', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList(delegate: SliverChildListDelegate([
              if (forum != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (forum['parent']?['title'] != null) ...[
                      Text(forum['parent']['title'], style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.chevron_right, size: 12, color: AppColors.textMuted)),
                    ],
                    Text(forum['title'] ?? '', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
                  ]),
                ),
              Text(d['title'] ?? '', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.3))),
              const SizedBox(height: 12),
              // Author row
              Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accentSoft),
                  child: ClipOval(
                    child: author?['avatar']?['url'] != null
                        ? CachedNetworkImage(imageUrl: author['avatar']['url'], fit: BoxFit.cover, errorWidget: (_, __, ___) => Icon(Icons.person, color: AppColors.accentLight, size: 16))
                        : Icon(Icons.person, color: AppColors.accentLight, size: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (author?['username'] != null)
                    InkWell(
                      onTap: () => context.push('/user/${author['id']}'),
                      child: Text(author['username'], style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                    ),
                  Text(timeago(d['created_at']), style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
                ])),
                if ((d['views'] ?? 0) > 0) Row(children: [
                  Icon(Icons.visibility_outlined, size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 3),
                  Text('${d['views']}', style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
                ]),
              ]),
              const SizedBox(height: 16),
              // Attached file (audio/video) on the discussion itself —
              // renders before the body. Audio uses the waveform player;
              // video opens externally for now.
              if (d['file'] != null) ..._buildFileBlock(Map<String, dynamic>.from(d['file'] as Map)),

              // Content — rendered via CommentMedia so embedded audio shows
              // a waveform player and images use CachedNetworkImage (parity
              // with how the same author's posts render in song comments).
              if ((d['content'] ?? '').toString().isNotEmpty)
                CommentMedia(html: d['content'] ?? '', authorName: author?['username']?.toString()),

              // Polls / "đánh giá" — render each poll with its options and
              // current vote counts. Voting itself is read-only here for now.
              ..._buildPolls(d['polls']?['data']),
              const SizedBox(height: 24),
              Divider(color: AppColors.border, height: 1),
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

  List<Widget> _buildFileBlock(Map<String, dynamic> file) {
    final audio = file['audio_url']?.toString();
    final video = file['video_url']?.toString();
    if (audio != null && audio.isNotEmpty) {
      return [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: WaveformPlayer(audioUrl: audio, seed: audio.hashCode),
        ),
      ];
    }
    if (video != null && video.isNotEmpty) {
      return [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: InkWell(
            onTap: () => launchUrl(Uri.parse(video), mode: LaunchMode.externalApplication),
            child: Row(children: [
              Icon(Icons.play_circle_outline, color: AppColors.accentLight),
              const SizedBox(width: 10),
              Expanded(child: Text('Mở video kèm theo', style: body(TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)))),
              Icon(Icons.open_in_new, size: 14, color: AppColors.textMuted),
            ]),
          ),
        ),
      ];
    }
    return [];
  }

  List<Widget> _buildPolls(dynamic polls) {
    if (polls is! List || polls.isEmpty) return [];
    return polls.map<Widget>((p) {
      final pp = Map<String, dynamic>.from(p as Map);
      final options = (pp['options'] ?? []) as List;
      final total = options.fold<int>(0, (sum, o) {
        if (o is Map) return sum + ((o['total_answer'] as num?)?.toInt() ?? 0);
        return sum;
      });
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.how_to_vote_outlined, size: 16, color: AppColors.accentLight),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                (pp['title'] ?? 'Đánh giá').toString(),
                style: display(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
              ),
            ),
            Text('$total bình chọn', style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
          ]),
          const SizedBox(height: 10),
          ...options.map((o) {
            final oo = Map<String, dynamic>.from(o as Map);
            final votes = (oo['total_answer'] as num?)?.toInt() ?? 0;
            final pct = ((oo['percent'] as num?)?.toDouble() ?? (total > 0 ? votes / total : 0)) / (oo['percent'] != null ? 100.0 : 1.0);
            final answers = (oo['answers']?['data'] ?? []) as List;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text((oo['name'] ?? '').toString(), style: body(TextStyle(fontSize: 13, color: AppColors.text)))),
                  Text('$votes', style: body(TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceLight,
                    valueColor: AlwaysStoppedAnimation(AppColors.accentLight),
                  ),
                ),
                if (answers.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final a in answers.take(12))
                        Builder(builder: (_) {
                          final aa = Map<String, dynamic>.from(a as Map);
                          final user = aa['user'] as Map?;
                          if (user == null) return const SizedBox.shrink();
                          final avatar = (user['avatar'] as Map?)?['url']?.toString();
                          final username = user['username']?.toString() ?? '';
                          return Tooltip(
                            message: username,
                            child: InkWell(
                              onTap: () => context.push('/user/${user['id']}'),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceLight,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  ClipOval(
                                    child: SizedBox(
                                      width: 16, height: 16,
                                      child: avatar != null && avatar.isNotEmpty
                                          ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppColors.accent))
                                          : Container(color: AppColors.accent, alignment: Alignment.center, child: Text(username.isNotEmpty ? username[0].toUpperCase() : '?', style: body(const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)))),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(username, style: body(TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
                                ]),
                              ),
                            ),
                          );
                        }),
                      if (votes > answers.length)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text('+${votes - answers.length}', style: body(TextStyle(fontSize: 10, color: AppColors.textMuted))),
                        ),
                    ],
                  ),
                ],
              ]),
            );
          }),
        ]),
      );
    }).toList();
  }
}
