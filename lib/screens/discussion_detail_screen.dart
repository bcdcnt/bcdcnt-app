import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock, EmptyBlock, UserAvatar;
import '../services/friendly_error.dart';
import 'package:provider/provider.dart';
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
  /// Inside the desktop Cộng đồng page: no app bar (the page has its tabs).
  final bool embedded;
  const DiscussionDetailScreen({super.key, required this.id, this.embedded = false});

  @override
  State<DiscussionDetailScreen> createState() => _DiscussionDetailScreenState();
}

class _DiscussionDetailScreenState extends State<DiscussionDetailScreen> {
  Map<String, dynamic>? _d;
  bool _loading = true, _failed = false;
  /// Desktop side column: who took part, latest activity, other topics in
  /// the same forum. Loaded after the topic so the page shows at once.
  Map<String, dynamic>? _side;

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    if (_failed) setState(() { _failed = false; _loading = true; });
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        discussion(id: $id) {
          id title slug content created_at status is_closed views comment_count last_comment_at
          author_name author { id username avatar { url } roles { alias display_in_comment } }
          thumbnail { url }
          forum { id title slug parent { id title slug } }
          file { audio_url video_url duration type }
          polls(first: 5) { data { ''' + _pollFields + r''' } }
        }
      }''', {'id': widget.id});
      if (!mounted) return;
      setState(() {
        _d = data['discussion'] != null ? Map<String, dynamic>.from(data['discussion'] as Map) : null;
        _loading = false;
      });
      if (_d?['id'] != null) {
        logActivity(context.read<AuthProvider>(), 'view', 'discussion', _d!['id']);
        if (MediaQuery.sizeOf(context).width >= 900) _fetchSide();
      }
    } catch (_) { if (mounted) setState(() { _loading = false; _failed = true; }); }
  }

  Future<void> _fetchSide() async {
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        discussion(id: $id) {
          comments(first: 80, orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: 1}]}) { data { created_at user { id username avatar { url } } } }
          forum { discussions(first: 6, orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: 1}]}) { data { id title comment_count } } }
        }
      }''', {'id': widget.id});
      if (mounted && data['discussion'] is Map) setState(() => _side = Map<String, dynamic>.from(data['discussion'] as Map));
    } catch (_) {}
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
        appBar: AppBar(leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context))),
        body: Center(child: SingleChildScrollView(child: _failed
            ? OfflineBlock(onRetry: _fetch)
            : const EmptyBlock(icon: Icons.forum_outlined, title: 'Không tìm thấy thảo luận', message: 'Chủ đề này không còn hoặc đã bị ẩn.'))),
      );
    }
    final d = _d!;
    final author = d['author'];
    final forum = d['forum'];
    if (MediaQuery.sizeOf(context).width >= 900) return _desktop(d);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          if (!widget.embedded)
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg,
            title: Text('Thảo luận'),
            centerTitle: true,
            leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList(delegate: SliverChildListDelegate([
              if (forum != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (forum['parent']?['title'] != null) ...[
                      _crumb(forum['parent']['title'].toString(), forum['parent']['id'], muted: true),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted)),
                    ],
                    _crumb((forum['title'] ?? '').toString(), forum['id']),
                  ]),
                ),
              Text(d['title'] ?? '', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.3))),
              const SizedBox(height: 12),
              if (_isClosed(d))
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Chủ đề đã khoá — không nhận thêm bình luận.', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)))),
                  ]),
                ),
              // Author row
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accentSoft),
                  child: ClipOval(
                    child: author?['avatar']?['url'] != null
                        ? CachedNetworkImage(imageUrl: cdnImg((author['avatar']['url']).toString(), 160), fit: BoxFit.cover, errorWidget: (_, __, ___) => Icon(Icons.person, color: AppColors.accentLight, size: 16))
                        : Icon(Icons.person, color: AppColors.accentLight, size: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    onTap: author?['id'] == null ? null : () => context.push('/user/${author['id']}'),
                    child: Text(topicAuthorName(d), style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text))),
                  ),
                  Text(timeago(d['created_at']), style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
                ])),
                if ((d['views'] ?? 0) > 0) Row(children: [
                  Icon(Icons.visibility_outlined, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(formatInt((d['views'] as num?)?.toInt() ?? 0), style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
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
                CommentMedia(html: d['content'] ?? '', authorName: topicAuthorName(d), inlineImages: true),

              // Polls / "đánh giá": vote with one tap, see the results.
              for (final p in ((d['polls']?['data'] ?? const []) as List).whereType<Map>())
                _DiscussionPoll(key: ValueKey('poll-${p['id']}'), poll: Map<String, dynamic>.from(p)),
              const SizedBox(height: 24),
              Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 20),
              // Comments
              CommentSection(type: 'discussion', id: widget.id, readOnly: _isClosed(d)),
              SizedBox(height: player.currentSong != null ? 90 : 20),
            ])),
          ),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  /// Desktop: a 760 reading column (post card + comments, composer docked
  /// at the bottom) and, when there is room, a 320 side column.
  Widget _desktop(Map<String, dynamic> d) {
    return Material(
      color: AppColors.bg,
      child: LayoutBuilder(builder: (context, c) {
        final side = c.maxWidth >= 1180;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: CommentSection(type: 'discussion', id: widget.id, readOnly: _isClosed(d), docked: true, sortable: true, lead: _desktopLead(d)),
              ),
            ),
            if (side) ...[
              const SizedBox(width: 40),
              SizedBox(width: 320, child: SingleChildScrollView(padding: const EdgeInsets.only(top: 24, bottom: 24), child: _desktopSide(d))),
            ],
          ]),
        );
      }),
    );
  }

  Widget _desktopLead(Map<String, dynamic> d) {
    final author = d['author'];
    final forum = d['forum'];
    final role = ((author?['roles'] ?? const []) as List).whereType<Map>().where((r) => r['display_in_comment'] == true).map((r) => (r['alias'] ?? '').toString()).firstWhere((a) => a.isNotEmpty, orElse: () => '');
    final views = (d['views'] as num?)?.toInt() ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (forum != null)
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (forum['parent']?['title'] != null) ...[
            _crumb(forum['parent']['title'].toString(), forum['parent']['id'], muted: true),
            Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
          ],
          _crumb((forum['title'] ?? '').toString(), forum['id']),
        ]),
      Text(d['title'] ?? '', style: display(TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.6, height: 1.2))),
      const SizedBox(height: 18),
      if (_isClosed(d))
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text('Chủ đề đã khoá — không nhận thêm bình luận.', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)))),
          ]),
        ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.borderSubtle)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            InkWell(
              onTap: author?['id'] == null ? null : () => context.push('/user/${author['id']}'),
              customBorder: const CircleBorder(),
              child: UserAvatar(url: author?['avatar']?['url']?.toString(), name: topicAuthorName(d), size: 44),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(topicAuthorName(d), overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text)))),
                if (role.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
                    child: Text(role, style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white))),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(timeago(d['created_at']), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            ])),
            if (views > 0) ...[
              Icon(Icons.visibility_outlined, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(formatInt(views), style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
            ],
          ]),
          const SizedBox(height: 16),
          if (d['file'] != null) ..._buildFileBlock(Map<String, dynamic>.from(d['file'] as Map)),
          if ((d['content'] ?? '').toString().isNotEmpty)
            CommentMedia(html: d['content'] ?? '', authorName: topicAuthorName(d), inlineImages: true),
          for (final p in ((d['polls']?['data'] ?? const []) as List).whereType<Map>())
            _DiscussionPoll(key: ValueKey('poll-${p['id']}'), poll: Map<String, dynamic>.from(p)),
        ]),
      ),
    ]);
  }

  Widget _desktopSide(Map<String, dynamic> d) {
    final comments = ((_side?['comments']?['data'] ?? const []) as List).whereType<Map>().toList();
    final people = <String, Map>{};
    for (final c in comments) {
      final u = c['user'];
      if (u is Map && u['id'] != null) people.putIfAbsent('${u['id']}', () => u);
    }
    final shown = people.values.take(8).toList();
    final others = ((_side?['forum']?['discussions']?['data'] ?? const []) as List).whereType<Map>().where((t) => '${t['id']}' != widget.id).take(5).toList();
    final created = DateTime.tryParse('${d['created_at'] ?? ''}');
    final lastAt = comments.isNotEmpty ? comments.first['created_at'] : d['last_comment_at'];
    final count = (d['comment_count'] as num?)?.toInt() ?? 0;
    final label = body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted));
    final value = body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text));
    Widget stat(String k, String v) => Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderSubtle))),
          child: Row(children: [Text(k, style: label), const SizedBox(width: 12), Expanded(child: Text(v, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: value))]),
        );
    final box = BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.borderSubtle));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: box,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('THÔNG TIN CHỦ ĐỀ', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.accentLight))),
          const SizedBox(height: 10),
          if (d['forum']?['title'] != null) stat('Chuyên mục', d['forum']['title'].toString()),
          if ((d['views'] ?? 0) > 0) stat('Lượt xem', formatInt((d['views'] as num).toInt())),
          stat('Bình luận', formatInt(count)),
          if (created != null) stat('Ngày đăng', '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year}'),
          if (lastAt != null) stat('Hoạt động gần nhất', timeago('$lastAt')),
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Người tham gia', style: value),
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < shown.length; i++)
                Align(
                  widthFactor: i == shown.length - 1 ? 1 : 0.75,
                  child: Tooltip(
                    message: (shown[i]['username'] ?? '').toString(),
                    child: InkWell(
                      onTap: () => context.push('/user/${shown[i]['id']}'),
                      customBorder: const CircleBorder(),
                      child: Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 2)),
                        child: UserAvatar(url: shown[i]['avatar']?['url']?.toString(), name: (shown[i]['username'] ?? '').toString(), size: 32),
                      ),
                    ),
                  ),
                ),
              if (people.length > shown.length) ...[
                const SizedBox(width: 8),
                Text('+${people.length - shown.length}', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textMuted))),
              ],
            ]),
          ],
        ]),
      ),
      if (others.isNotEmpty) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.borderSubtle)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Cùng chuyên mục', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text)))),
              if (d['forum']?['id'] != null)
                InkWell(
                  onTap: () => context.push('/dien-dan/${d['forum']['id']}'),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(padding: const EdgeInsets.all(4), child: Text('Tất cả ›', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accentLight)))),
                ),
            ]),
            const SizedBox(height: 6),
            for (final t in others)
              InkWell(
                onTap: () => context.push('/thao-luan/${t['id']}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderSubtle))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text((t['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.4, color: AppColors.text)))),
                    const SizedBox(width: 10),
                    Text('${formatInt((t['comment_count'] as num?)?.toInt() ?? 0)} bl', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textMuted))),
                  ]),
                ),
              ),
          ]),
        ),
      ],
    ]);
  }

  static bool _isClosed(Map d) => d['is_closed'] == true || d['is_closed'] == 1 || d['is_closed'] == '1';

  /// Breadcrumb segment: opens that forum (48pt tall target).
  Widget _crumb(String title, dynamic forumId, {bool muted = false}) {
    final style = body(TextStyle(fontSize: 14, fontWeight: muted ? FontWeight.w500 : FontWeight.w700, color: muted ? AppColors.textSecondary : AppColors.accentLight));
    if (forumId == null) return Text(title, style: style);
    return InkWell(
      onTap: () => context.push('/dien-dan/$forumId'),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Align(widthFactor: 1, child: Text(title, style: style))),
      ),
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
              Expanded(child: Text('Mở video kèm theo', style: body(TextStyle(fontSize: 15, color: AppColors.text, fontWeight: FontWeight.w600)))),
              Icon(Icons.open_in_new, size: 18, color: AppColors.textMuted),
            ]),
          ),
        ),
      ];
    }
    return [];
  }
}

/// Poll fields shared by the discussion query and the answerPoll response.
const _pollFields = r'id title status options(orderBy: [{column: "position", order: ASC}]) { id name total_answer percent position answers(first: 12) { data { id user { id username avatar { url } } } } }';

/// One poll under a discussion. One choice per person (the API replaces the
/// previous answer, so tapping another option changes the vote). Results
/// (bars + percent + who voted) show once you've voted or the poll is closed.
class _DiscussionPoll extends StatefulWidget {
  final Map<String, dynamic> poll;
  const _DiscussionPoll({super.key, required this.poll});

  @override
  State<_DiscussionPoll> createState() => _DiscussionPollState();
}

class _DiscussionPollState extends State<_DiscussionPoll> {
  late Map<String, dynamic> _poll = widget.poll;
  String? _mine;
  String? _sending;
  String? _forUser;
  bool _mineLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload "your answer" on login/logout (wait for the saved login first).
    final auth = context.watch<AuthProvider>();
    if (auth.loading) return;
    final uid = auth.user?['id']?.toString();
    if (!_mineLoaded || uid != _forUser) {
      _forUser = uid;
      _mineLoaded = true;
      _loadMine();
    }
  }

  Future<void> _loadMine() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) { if (_mine != null) setState(() => _mine = null); return; }
    final uid = _forUser;
    try {
      final d = await auth.authedQuery(r'query($p: ID!) { myAnswer(poll_id: $p, first: 10) { data { id option_id } } }', {'p': _poll['id']});
      final list = (d['myAnswer']?['data'] ?? const []) as List;
      if (!mounted || uid != _forUser) return;
      setState(() => _mine = list.isNotEmpty ? '${list.first['option_id']}' : null);
    } catch (_) {}
  }

  bool get _closed => '${_poll['status']}' == 'closed';

  Future<void> _vote(String optionId) async {
    if (_closed || _sending != null || optionId == _mine) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      await askLogin(context);
      return;
    }
    setState(() => _sending = optionId);
    try {
      final d = await auth.authedMutate(
        r'mutation($p: ID!, $o: [ID]!) { answerPoll(poll_id: $p, option_ids: $o) { ' + _pollFields + r' } }',
        {'p': _poll['id'], 'o': [optionId]},
      );
      final updated = d['answerPoll'];
      if (!mounted) return;
      setState(() {
        _mine = optionId;
        if (updated is Map) _poll = {..._poll, ...Map<String, dynamic>.from(updated)};
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'Chưa gửi được bình chọn. Thử lại sau.'))));
      }
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = ((_poll['options'] ?? const []) as List).whereType<Map>().map((o) => Map<String, dynamic>.from(o)).toList();
    if (options.isEmpty) return const SizedBox.shrink();
    final total = options.fold<int>(0, (sum, o) => sum + ((o['total_answer'] as num?)?.toInt() ?? 0));
    final showResults = _mine != null || _closed;
    final isGuest = !context.select<AuthProvider, bool>((a) => a.isAuthenticated);

    String hint;
    if (_closed) {
      hint = 'Bình chọn đã kết thúc · $total người tham gia';
    } else if (_mine != null) {
      hint = 'Cảm ơn bạn! $total người đã bình chọn. Muốn đổi ý, chạm lựa chọn khác.';
    } else if (isGuest) {
      hint = 'Đăng nhập để bình chọn.';
    } else {
      hint = 'Chạm vào một lựa chọn để bình chọn.';
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(_closed ? Icons.lock_outline_rounded : Icons.how_to_vote_outlined, size: 20, color: AppColors.accentLight),
          const SizedBox(width: 8),
          Expanded(child: Text((_poll['title'] ?? 'Bình chọn').toString(), style: display(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text)))),
        ]),
        const SizedBox(height: 12),
        for (final o in options) _optionRow(o, total, showResults),
        const SizedBox(height: 2),
        Text(hint, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
      ]),
    );
  }

  Widget _optionRow(Map<String, dynamic> o, int total, bool showResults) {
    final id = '${o['id']}';
    final name = (o['name'] ?? '').toString();
    final votes = (o['total_answer'] as num?)?.toInt() ?? 0;
    final pct = total > 0 ? votes * 100 / total : 0.0;
    final mine = id == _mine;
    final sending = _sending == id;
    final tappable = !_closed && _sending == null && !mine;
    final answers = ((o['answers']?['data'] ?? const []) as List).whereType<Map>().toList();

    final row = Material(
      color: AppColors.bg,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: mine ? AppColors.accentLight : AppColors.border, width: mine ? 2 : 1.5),
      ),
      child: InkWell(
        onTap: tappable ? () => _vote(id) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Stack(children: [
            if (showResults)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (pct / 100).clamp(0.0, 1.0),
                  child: Container(color: mine ? AppColors.accent.withValues(alpha: 0.22) : AppColors.surfaceHover),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                if (sending)
                  SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent))
                else
                  Icon(
                    mine ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                    size: 24,
                    color: mine ? AppColors.accentLight : AppColors.textMuted,
                  ),
                const SizedBox(width: 12),
                Expanded(child: Text(name, style: body(TextStyle(fontSize: 17, fontWeight: mine ? FontWeight.w800 : FontWeight.w600, color: AppColors.text)))),
                if (showResults) ...[
                  const SizedBox(width: 8),
                  Text('${pct.round()}%', style: body(TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text))),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: tappable,
          selected: mine,
          label: showResults
              ? '$name: ${pct.round()} phần trăm, $votes người${mine ? ', bạn đã chọn' : ''}'
              : 'Chọn $name',
          excludeSemantics: true,
          child: row,
        ),
        if (showResults && answers.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final a in answers.take(12)) _voterChip(a['user'] as Map?),
            if (votes > answers.length)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('+${votes - answers.length}', style: body(TextStyle(fontSize: 14, color: AppColors.textMuted))),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _voterChip(Map? user) {
    if (user == null) return const SizedBox.shrink();
    final avatar = (user['avatar'] as Map?)?['url']?.toString();
    final username = user['username']?.toString() ?? '';
    return InkWell(
      onTap: () => context.push('/user/${user['id']}'),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ClipOval(
            child: SizedBox(
              width: 20, height: 20,
              child: avatar != null && avatar.isNotEmpty
                  ? CachedNetworkImage(imageUrl: cdnImg(avatar, 160), fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: AppColors.accent))
                  : Container(color: AppColors.accent, alignment: Alignment.center, child: Text(username.isNotEmpty ? username[0].toUpperCase() : '?', style: body(const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)))),
            ),
          ),
          const SizedBox(width: 5),
          Text(username, style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}
