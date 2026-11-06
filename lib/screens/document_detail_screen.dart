import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock, EmptyBlock;
import '../services/friendly_error.dart';
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
  bool _loading = true, _failed = false;
  VideoPlayerController? _videoCtl;
  ChewieController? _chewieCtl;
  /// Video couldn't be opened in-app → show an "Mở video" button instead.
  bool _videoFailed = false;

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
    if (_failed) setState(() { _failed = false; _loading = true; });
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
        // Page first; the video loads on its own and can't block or
        // "not found" the whole page if it fails.
        setState(() { _doc = doc; _loading = false; });
        logActivity(context.read<AuthProvider>(), 'view', 'document', doc['id']);
        final videoUrl = doc['file']?['video_url'];
        if (videoUrl is String && videoUrl.isNotEmpty) _initVideo(videoUrl);
        _fetchRelated(doc['type']?.toString());
      } else {
        setState(() => _loading = false);
      }
    } catch (_) { if (mounted) setState(() { _loading = false; _failed = true; }); }
  }

  Future<void> _initVideo(String url) async {
    final ctl = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await ctl.initialize().timeout(const Duration(seconds: 20));
    } catch (_) {
      ctl.dispose();
      if (mounted) setState(() => _videoFailed = true);
      return;
    }
    if (!mounted) { ctl.dispose(); return; }
    setState(() {
      _videoCtl = ctl;
      _chewieCtl = ChewieController(videoPlayerController: ctl, autoPlay: false, looping: false, aspectRatio: ctl.value.aspectRatio);
    });
  }

  /// Full-screen pinch-to-zoom viewer for a picture in the document.
  void _openImage(String url) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder: (_, _) => const Center(child: CircularProgressIndicator(color: Colors.white70)),
              errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 56),
            )),
          )),
          Positioned(
            top: MediaQuery.paddingOf(ctx).top + 8, right: 12,
            child: IconButton(
              tooltip: 'Đóng',
              style: IconButton.styleFrom(backgroundColor: Colors.black54, fixedSize: const Size(48, 48)),
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
        ]),
      ),
    ));
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
      askLogin(context);
      return;
    }
    try {
      final data = await auth.authedMutate(r'''mutation($objectType: String!, $objectId: ID!) {
        download(object_type: $objectType, object_id: $objectId) { url }
      }''', {'objectType': 'document', 'objectId': widget.id});
      final url = data['download']?['url'];
      if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'Chưa tải về được, vui lòng thử lại.'))));
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
        appBar: AppBar(leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context))),
        body: Center(child: SingleChildScrollView(child: _failed
            ? OfflineBlock(onRetry: _fetch)
            : const EmptyBlock(icon: Icons.folder_off_outlined, title: 'Không tìm thấy tư liệu', message: 'Tư liệu này không còn hoặc đã bị ẩn.'))),
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
            backgroundColor: AppColors.bg,
            title: Text(typeLabel),
            centerTitle: true,
            leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList(delegate: SliverChildListDelegate([
              // Thumbnail (image / news)
              if ((type == 'image' || type == 'news') && d['thumbnail']?['url'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Semantics(
                    button: true,
                    label: 'Phóng to ảnh',
                    child: GestureDetector(
                      onTap: () => _openImage(d['thumbnail']['url'].toString()),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedNetworkImage(imageUrl: cdnImg((d['thumbnail']['url']).toString(), 960), fit: BoxFit.cover),
                      ),
                    ),
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
              if (type == 'video' && d['file']?['video_url'] != null && _videoFailed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(d['file']['video_url'].toString()), mode: LaunchMode.externalApplication),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    icon: const Icon(Icons.play_circle_outline),
                    label: Text('Mở video', style: body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  ),
                )
              else if (type == 'video' && d['file']?['video_url'] != null && _chewieCtl == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AspectRatio(aspectRatio: 16 / 9, child: Container(
                    decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
                  )),
                ),
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
                  child: Text(typeLabel, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent))),
                ),
                Text(timeago(d['created_at']), style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
                if (d['uploader']?['username'] != null)
                  InkWell(
                    onTap: () => context.push('/user/${d['uploader']['id']}'),
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(d['uploader']['username'], style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.accentLight)))),
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
                      Icon(Icons.visibility_outlined, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text('${_formatInt(d['views'] is num ? (d['views'] as num).toInt() : 0)} lượt xem', style: body(TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                    ]),
                    if ((d['downloads'] ?? 0) > 0)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.download_outlined, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text('${_formatInt(d['downloads'] is num ? (d['downloads'] as num).toInt() : 0)} lượt tải', style: body(TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                      ]),
                  ])),
                  if (hasFile || (type == 'image' && d['thumbnail']?['url'] != null))
                    Semantics(
                      button: true,
                      label: 'Tải về tư liệu',
                      excludeSemantics: true,
                      child: TextButton.icon(
                        onPressed: _download,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          backgroundColor: AppColors.surfaceLight,
                          foregroundColor: AppColors.text,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: Text('Tải về', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
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
                    'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero, fontSize: FontSize(16), lineHeight: const LineHeight(1.75), color: AppColors.text, fontFamily: body().fontFamily),
                    'h1, h2, h3': Style(color: AppColors.text, fontFamily: display().fontFamily),
                    'a': Style(color: AppColors.accentLight, textDecoration: TextDecoration.none),
                    'p': Style(margin: Margins.only(bottom: 10)),
                    'img': Style(width: Width(100, Unit.percent)),
                    'figure': Style(margin: Margins.only(bottom: 6)),
                  },
                  onLinkTap: (url, _, __) {
                    if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                  // Old scans/photos are small on a phone: tap to zoom.
                  extensions: [
                    OnImageTapExtension(onImageTap: (src, _, _) {
                      if (src != null && src.startsWith('http')) _openImage(src);
                    }),
                  ],
                ),

              // Related documents
              if (_related.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(children: [
                  Icon(_typeIcons[type] ?? Icons.folder_outlined, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text('Tư liệu khác', style: display(TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text))),
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
                            ? CachedNetworkImage(imageUrl: cdnImg((r['thumbnail']['url']).toString(), 150), width: 60, height: 60, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(width: 60, height: 60, color: AppColors.surface, child: Icon(_typeIcons[type] ?? Icons.folder_outlined, color: AppColors.textMuted)))
                            : Container(width: 60, height: 60, decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)), child: Icon(_typeIcons[type] ?? Icons.folder_outlined, color: AppColors.textMuted)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.4))),
                        const SizedBox(height: 4),
                        Text(timeago(r['created_at']), style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
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
