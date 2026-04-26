import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../constants/theme.dart';
import 'waveform_player.dart';
import 'comment_section.dart';
import 'package:provider/provider.dart';
import '../services/auth.dart';

/// Shared top+bottom chrome for any lightbox item.
class _Chrome extends StatelessWidget {
  final int index;
  final int total;
  final VoidCallback onClose;
  final Map<String, dynamic> doc;
  const _Chrome({required this.index, required this.total, required this.onClose, required this.doc});

  Future<void> _share(BuildContext context) async {
    final url = '$siteUrl/tu-lieu/${doc['slug']}-${doc['id']}.html';
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã sao chép link'), backgroundColor: AppColors.success, duration: const Duration(seconds: 2)));
    } catch (_) {}
  }

  Future<void> _download(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng đăng nhập để tải')));
      return;
    }
    try {
      final data = await auth.authedMutate(
        r'''mutation($objectType: String!, $objectId: ID!) { download(object_type: $objectType, object_id: $objectId) { url } }''',
        {'objectType': 'document', 'objectId': doc['id'].toString()},
      );
      final url = data['download']?['url'];
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bạn đã tải quá nhiều, thử lại sau'), backgroundColor: AppColors.error));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải: $e'), backgroundColor: AppColors.error));
    }
  }

  void _openComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtl) => Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.textMuted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtl,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: CommentSection(type: 'document', id: doc['id'].toString()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _commentCount(Map<String, dynamic> doc) {
    final n = doc['comments']?['paginatorInfo']?['total'];
    if (n is num && n > 0) return _shortNum(n.toInt());
    return null;
  }

  String? _downloadCount(Map<String, dynamic> doc) {
    final n = doc['downloads'];
    if (n is num && n > 0) return _shortNum(n.toInt());
    return null;
  }

  String _shortNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final uploader = doc['uploader'];
    return Stack(
      children: [
        // Top-left grouped chrome: Close + counter pill
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Align(
              alignment: Alignment.topLeft,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: onClose,
                          behavior: HitTestBehavior.opaque,
                          child: const Padding(
                            padding: EdgeInsets.fromLTRB(10, 8, 8, 8),
                            child: Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ),
                        if (total > 1) Container(
                          width: 1, height: 18,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        if (total > 1) Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
                          child: Text(
                            '${index + 1} / $total',
                            style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Bottom-right action column (above title overlay)
        Positioned(
          right: 12, bottom: 100,
          child: SafeArea(
            child: Column(
              children: [
                _ActionBtn(
                  icon: Icons.chat_bubble_outline,
                  badge: _commentCount(doc),
                  onTap: () => _openComments(context),
                ),
                const SizedBox(height: 12),
                _ActionBtn(
                  icon: Icons.download_outlined,
                  badge: _downloadCount(doc),
                  onTap: () => _download(context),
                ),
                const SizedBox(height: 12),
                _ActionBtn(icon: Icons.share, onTap: () => _share(context)),
                const SizedBox(height: 12),
                _ActionBtn(
                  icon: Icons.open_in_new,
                  onTap: () { onClose(); context.push('/tu-lieu/chi-tiet/${doc['id']}'); },
                ),
              ],
            ),
          ),
        ),
        // Bottom overlay: title + uploader
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 50, 84, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Color(0xCC000000), Color(0x66000000), Colors.transparent],
                stops: [0.0, 0.6, 1.0],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc['title'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: display(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, height: 1.25)),
                ),
                if (uploader?['username'] != null) Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    const Icon(Icons.account_circle_outlined, size: 13, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text('@${uploader['username']}', style: body(const TextStyle(fontSize: 12, color: Colors.white70))),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;
  const _ActionBtn({required this.icon, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
            ),
          ),
          if (badge != null) Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(badge!, style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
          ),
        ],
      ),
    );
  }
}

// --- Image Lightbox ---

typedef LoadMoreFn = Future<List<dynamic>> Function();

mixin _PagedLightbox<T extends StatefulWidget> on State<T> {
  late List<dynamic> items;
  bool _canLoad = false;
  bool _loadingMore = false;
  LoadMoreFn? get loadMoreFn;

  void initPaging(List<dynamic> initial) {
    items = List<dynamic>.from(initial);
    _canLoad = loadMoreFn != null;
  }

  Future<void> maybeLoadMore(int currentIdx) async {
    if (_loadingMore || !_canLoad) return;
    if (currentIdx < items.length - 3) return;
    _loadingMore = true;
    try {
      final more = await loadMoreFn!();
      if (more.isEmpty) {
        _canLoad = false;
      } else {
        final ids = items.map((d) => d['id'].toString()).toSet();
        final fresh = more.where((d) => !ids.contains(d['id'].toString())).toList();
        if (fresh.isEmpty) {
          _canLoad = false;
        } else {
          if (mounted) setState(() => items.addAll(fresh));
        }
      }
    } catch (_) {
      // Retry on next swipe
    }
    _loadingMore = false;
  }
}

class ImageLightbox extends StatefulWidget {
  final List<dynamic> docs;
  final int initialIndex;
  final LoadMoreFn? onLoadMore;
  const ImageLightbox({super.key, required this.docs, required this.initialIndex, this.onLoadMore});

  @override
  State<ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends State<ImageLightbox> with _PagedLightbox {
  late PageController _ctl;
  late int _idx;

  @override
  LoadMoreFn? get loadMoreFn => widget.onLoadMore;

  @override
  void initState() {
    super.initState();
    initPaging(widget.docs);
    _idx = widget.initialIndex;
    _ctl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() { _ctl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _ctl,
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            onPageChanged: (i) { setState(() => _idx = i); maybeLoadMore(i); },
            itemBuilder: (ctx, i) {
              final doc = items[i];
              final url = doc['thumbnail']?['url'];
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: url != null
                      ? CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.white70)),
                          errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white30, size: 48)),
                        )
                      : const Icon(Icons.broken_image, color: Colors.white30, size: 48),
                ),
              );
            },
          ),
          _Chrome(index: _idx, total: items.length, onClose: () => Navigator.pop(context), doc: Map<String, dynamic>.from(items[_idx] as Map)),
        ],
      ),
    );
  }
}

// --- Audio Lightbox ---

class AudioLightbox extends StatefulWidget {
  final List<dynamic> docs;
  final int initialIndex;
  final LoadMoreFn? onLoadMore;
  const AudioLightbox({super.key, required this.docs, required this.initialIndex, this.onLoadMore});

  @override
  State<AudioLightbox> createState() => _AudioLightboxState();
}

class _AudioLightboxState extends State<AudioLightbox> with _PagedLightbox {
  late PageController _ctl;
  late int _idx;

  @override
  LoadMoreFn? get loadMoreFn => widget.onLoadMore;

  @override
  void initState() {
    super.initState();
    initPaging(widget.docs);
    _idx = widget.initialIndex;
    _ctl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() { _ctl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _ctl,
            scrollDirection: Axis.vertical,
            itemCount: items.length,
            onPageChanged: (i) { setState(() => _idx = i); maybeLoadMore(i); },
            itemBuilder: (ctx, i) {
              final doc = items[i];
              final url = doc['file']?['audio_url'];
              final isActive = i == _idx;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 120, height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.4), blurRadius: 32, spreadRadius: -4)],
                        ),
                        child: const Icon(Icons.music_note, color: Colors.white, size: 56),
                      ),
                      const SizedBox(height: 40),
                      if (url != null && isActive)
                        WaveformPlayer(
                          key: ValueKey('audio-${doc['id']}'),
                          audioUrl: url,
                          seed: int.tryParse(doc['id']?.toString() ?? '0') ?? i,
                          autoPlay: true,
                          showTimestamp: true,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          _Chrome(index: _idx, total: items.length, onClose: () => Navigator.pop(context), doc: Map<String, dynamic>.from(items[_idx] as Map)),
        ],
      ),
    );
  }
}

// --- Video Lightbox ---

class VideoLightbox extends StatefulWidget {
  final List<dynamic> docs;
  final int initialIndex;
  final LoadMoreFn? onLoadMore;
  const VideoLightbox({super.key, required this.docs, required this.initialIndex, this.onLoadMore});

  @override
  State<VideoLightbox> createState() => _VideoLightboxState();
}

class _VideoLightboxState extends State<VideoLightbox> with _PagedLightbox {
  late PageController _ctl;
  late int _idx;
  VideoPlayerController? _videoCtl;
  ChewieController? _chewieCtl;
  int? _activeFor;

  @override
  LoadMoreFn? get loadMoreFn => widget.onLoadMore;

  @override
  void initState() {
    super.initState();
    initPaging(widget.docs);
    _idx = widget.initialIndex;
    _ctl = PageController(initialPage: widget.initialIndex);
    _activate(_idx);
  }

  @override
  void dispose() {
    _ctl.dispose();
    _chewieCtl?.dispose();
    _videoCtl?.dispose();
    super.dispose();
  }

  Future<void> _activate(int i) async {
    if (_activeFor == i) return;
    _activeFor = i;
    final prevC = _chewieCtl;
    final prevV = _videoCtl;
    _chewieCtl = null; _videoCtl = null;
    if (mounted) setState(() {});
    prevC?.dispose();
    await prevV?.dispose();

    if (i < 0 || i >= items.length) return;
    final url = items[i]['file']?['video_url'];
    if (url == null) return;
    try {
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      await vc.initialize();
      if (!mounted || _activeFor != i) { vc.dispose(); return; }
      final cc = ChewieController(
        videoPlayerController: vc,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.accent,
          handleColor: AppColors.accentLight,
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white10,
        ),
      );
      setState(() { _videoCtl = vc; _chewieCtl = cc; });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _ctl,
            scrollDirection: Axis.vertical,
            itemCount: items.length,
            onPageChanged: (i) { setState(() => _idx = i); _activate(i); maybeLoadMore(i); },
            itemBuilder: (ctx, i) {
              final doc = items[i];
              final isActive = i == _idx;
              final thumb = doc['thumbnail']?['url'];
              if (isActive && _chewieCtl != null) {
                return Center(child: AspectRatio(aspectRatio: _videoCtl!.value.aspectRatio, child: Chewie(controller: _chewieCtl!)));
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (thumb != null) CachedNetworkImage(imageUrl: thumb, fit: BoxFit.contain, errorWidget: (_, __, ___) => Container(color: Colors.black)),
                  if (isActive) const Center(child: CircularProgressIndicator(color: Colors.white70)),
                ],
              );
            },
          ),
          _Chrome(index: _idx, total: items.length, onClose: () => Navigator.pop(context), doc: Map<String, dynamic>.from(items[_idx] as Map)),
        ],
      ),
    );
  }
}
