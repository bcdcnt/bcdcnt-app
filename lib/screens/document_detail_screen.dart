import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/activity.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import '../widgets/comment_section.dart';
import '../widgets/waveform_player.dart';

class DocumentDetailScreen extends StatefulWidget {
  final String id;
  const DocumentDetailScreen({super.key, required this.id});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  Map<String, dynamic>? _doc;
  List<Map<String, dynamic>> _related = [];
  bool _loading = true;
  VideoPlayerController? _videoCtl;
  ChewieController? _chewieCtl;

  static const _typeLabels = {'audio': 'Âm thanh', 'video': 'Video', 'image': 'Hình ảnh', 'news': 'Bài viết'};
  static const _typeIcons = {'audio': Icons.audiotrack, 'video': Icons.videocam_outlined, 'image': Icons.image_outlined, 'news': Icons.article_outlined};

  @override
  void initState() { super.initState(); _fetch(); }

  @override
  void dispose() {
    _chewieCtl?.dispose();
    _videoCtl?.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        document(id: $id) {
          id title slug content type views downloads created_at
          thumbnail { url }
          file { audio_url video_url type }
          uploader { id username avatar { url } }
        }
      }''', {'id': widget.id});
      final d = data['document'];
      if (!mounted) return;
      if (d != null) {
        final doc = Map<String, dynamic>.from(d as Map);
        final videoUrl = doc['file']?['video_url'];
        if (videoUrl != null) {
          _videoCtl = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
          await _videoCtl!.initialize();
          if (!mounted) return;
          _chewieCtl = ChewieController(
            videoPlayerController: _videoCtl!,
            autoPlay: false,
            looping: false,
            aspectRatio: _videoCtl!.value.aspectRatio,
          );
        }
        setState(() { _doc = doc; _loading = false; });
        logActivity(context.read<AuthProvider>(), 'view', 'document', doc['id']);
        _fetchRelated(doc['type']?.toString());
      } else {
        setState(() => _loading = false);
      }
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _fetchRelated(String? type) async {
    if (type == null) return;
    try {
      final data = await ApiClient.query(r'''query($type: Mixed, $excludeId: Mixed) {
        documents(first: 6, where: {AND: [{column: "type", value: $type}, {column: "id", value: $excludeId, operator: NEQ}]}, orderBy: [{column: "id", order: DESC}]) {
          data { id slug title thumbnail { url } type created_at }
        }
      }''', {'type': type, 'excludeId': widget.id});
      final list = ((data['documents']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() => _related = list);
    } catch (_) {}
  }

  Future<void> _download() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng đăng nhập để tải')));
      return;
    }
    try {
      final data = await auth.authedMutate(r'''mutation($objectType: String!, $objectId: ID!) {
        download(object_type: $objectType, object_id: $objectId) { url }
      }''', {'objectType': 'document', 'objectId': widget.id});
      final url = data['download']?['url'];
      if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể tải xuống')));
    }
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
    if (_doc == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
        body: Center(child: Text('Không tìm thấy tư liệu', style: AppText.bodyText)),
      );
    }
    final d = _doc!;
    final type = (d['type'] ?? '').toString();
    final typeLabel = _typeLabels[type] ?? 'Tư liệu';
    final hasFile = d['file']?['audio_url'] != null || d['file']?['video_url'] != null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text(typeLabel.toUpperCase(), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList(delegate: SliverChildListDelegate([
              // Thumbnail (image / news)
              if ((type == 'image' || type == 'news') && d['thumbnail']?['url'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CachedNetworkImage(imageUrl: d['thumbnail']['url'], fit: BoxFit.cover),
                  ),
                ),

              // Audio
              if (type == 'audio' && d['file']?['audio_url'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: AppColors.surface, border: Border.all(color: AppColors.border)),
                    child: WaveformPlayer(audioUrl: d['file']['audio_url'], seed: int.tryParse('${d['id']}') ?? 0),
                  ),
                ),

              // Video
              if (type == 'video' && _chewieCtl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: _videoCtl!.value.aspectRatio,
                      child: Chewie(controller: _chewieCtl!),
                    ),
                  ),
                ),

              // Title
              Text(d['title'] ?? '', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.3))),
              const SizedBox(height: 10),

              // Type / time / uploader
              Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(10)),
                  child: Text(typeLabel, style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent))),
                ),
                Text(timeago(d['created_at']), style: body(TextStyle(fontSize: 12, color: AppColors.textMuted))),
                if (d['uploader']?['username'] != null)
                  InkWell(
                    onTap: () => context.push('/user/${d['uploader']['id']}'),
                    child: Text(d['uploader']['username'], style: body(TextStyle(fontSize: 12, color: AppColors.accentLight))),
                  ),
              ]),
              const SizedBox(height: 16),

              // Stats bar
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border), bottom: BorderSide(color: AppColors.border))),
                child: Row(children: [
                  Expanded(child: Wrap(spacing: 16, runSpacing: 4, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.visibility_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text('${_formatInt(d['views'] is num ? (d['views'] as num).toInt() : 0)} lượt xem', style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                    ]),
                    if ((d['downloads'] ?? 0) > 0)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.download_outlined, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text('${_formatInt(d['downloads'] is num ? (d['downloads'] as num).toInt() : 0)} lượt tải', style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                      ]),
                  ])),
                  if (hasFile || (type == 'image' && d['thumbnail']?['url'] != null))
                    InkWell(
                      onTap: _download,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceLight),
                        child: Icon(Icons.download, size: 18, color: AppColors.textSecondary),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 20),

              // Content HTML
              if ((d['content'] ?? '').toString().isNotEmpty)
                Html(
                  data: d['content'],
                  style: {
                    'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero, fontSize: FontSize(14), lineHeight: const LineHeight(1.8), color: AppColors.textSecondary, fontFamily: body().fontFamily),
                    'h1, h2, h3': Style(color: AppColors.text, fontFamily: display().fontFamily),
                    'a': Style(color: AppColors.accentLight, textDecoration: TextDecoration.none),
                    'p': Style(margin: Margins.only(bottom: 10)),
                    'img': Style(width: Width(100, Unit.percent)),
                    'figure': Style(margin: Margins.only(bottom: 6)),
                  },
                  onLinkTap: (url, _, __) {
                    if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                ),

              // Related documents
              if (_related.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(children: [
                  Icon(_typeIcons[type] ?? Icons.folder_outlined, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text('Tư liệu khác', style: display(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
                ]),
                const SizedBox(height: 10),
                ..._related.map((r) => InkWell(
                  onTap: () => context.push('/tu-lieu/chi-tiet/${r['id']}'),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: r['thumbnail']?['url'] != null
                            ? CachedNetworkImage(imageUrl: r['thumbnail']['url'], width: 60, height: 60, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(width: 60, height: 60, color: AppColors.surface, child: Icon(_typeIcons[type] ?? Icons.folder_outlined, color: AppColors.textMuted)))
                            : Container(width: 60, height: 60, decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)), child: Icon(_typeIcons[type] ?? Icons.folder_outlined, color: AppColors.textMuted)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.4))),
                        const SizedBox(height: 4),
                        Text(timeago(r['created_at']), style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
                      ])),
                    ]),
                  ),
                )),
              ],

              const SizedBox(height: 24),
              Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 20),
              CommentSection(type: 'document', id: widget.id),
              SizedBox(height: player.currentSong != null ? 90 : 20),
            ])),
          ),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
