import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../constants/theme.dart';
import 'waveform_player.dart';

/// Renders comment HTML with proper handling for images, audio, video and
/// other text — instead of just stripping tags. Images display via
/// CachedNetworkImage, audio shows the WaveformPlayer, video opens externally.
class CommentMedia extends StatefulWidget {
  final String html;
  /// Username of the comment / discussion author. When provided, image
  /// popups show "Ảnh: <username>" credit (parity with sheet music
  /// captions on song detail).
  final String? authorName;
  const CommentMedia({super.key, required this.html, this.authorName});

  @override
  State<CommentMedia> createState() => _CommentMediaState();
}

class _CommentMediaState extends State<CommentMedia> {
  late List<_Block> _blocks;

  @override
  void initState() {
    super.initState();
    _blocks = _parse(widget.html);
  }

  @override
  void didUpdateWidget(CommentMedia old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html) _blocks = _parse(widget.html);
  }

  // Parse HTML into ordered blocks: text / image / audio / video.
  // Naive but practical: regex-based, no heavy DOM parsing.
  List<_Block> _parse(String html) {
    if (html.isEmpty) return [];
    final blocks = <_Block>[];
    // Match image / audio / video / iframe in order
    final pattern = RegExp(
      r'<img[^>]+src="([^"]+)"[^>]*>|<audio[^>]*>(.*?)</audio>|<video[^>]*>(.*?)</video>|<source[^>]+src="([^"]+)"[^>]*>|<iframe[^>]+src="([^"]+)"[^>]*></iframe>|<oembed[^>]+url="([^"]+)"[^>]*></oembed>',
      caseSensitive: false, dotAll: true,
    );
    int cursor = 0;
    for (final m in pattern.allMatches(html)) {
      // Text segment before this media
      if (m.start > cursor) {
        final seg = html.substring(cursor, m.start);
        if (seg.replaceAll(RegExp(r'<[^>]+>'), '').trim().isNotEmpty) {
          blocks.add(_Block.text(seg));
        }
      }
      // Image
      if (m.group(1) != null) {
        blocks.add(_Block.image(m.group(1)!));
      }
      // Audio
      else if (m.group(2) != null) {
        final inner = m.group(2)!;
        final src = RegExp(r'src="([^"]+)"', caseSensitive: false).firstMatch(inner)?.group(1);
        if (src != null) {
          // Web inserts <audio> for mp4 too because Lambda mis-tags video
          // files as `type=audio` (everything shares the `uploads/mp3/`
          // prefix). Treat the tag as video when the URL extension says
          // so, so the comment renders a real video player.
          blocks.add(_isVideoUrl(src) ? _Block.video(src) : _Block.audio(src));
        }
      }
      // Video
      else if (m.group(3) != null) {
        final inner = m.group(3)!;
        final src = RegExp(r'src="([^"]+)"', caseSensitive: false).firstMatch(inner)?.group(1);
        if (src != null) blocks.add(_Block.video(src));
      }
      // Standalone <source>
      else if (m.group(4) != null) {
        final url = m.group(4)!;
        if (_isVideoUrl(url)) {
          blocks.add(_Block.video(url));
        } else if (url.toLowerCase().contains('.mp3') || url.toLowerCase().contains('audio')) {
          blocks.add(_Block.audio(url));
        } else {
          blocks.add(_Block.video(url));
        }
      }
      // iframe (likely YouTube)
      else if (m.group(5) != null) {
        blocks.add(_Block.video(m.group(5)!));
      }
      // oembed — CKEditor bọc nhiều loại media vào <figure class="media">
      // <oembed url="..."> mà <oembed> không tự render. Phân loại: YouTube →
      // card; audio (.mp3 / #audio) → WaveformPlayer; video (.mp4 / #video) →
      // player inline; còn lại → mở ngoài. (Bỏ qua được #audio/#video ở src.)
      else if (m.group(6) != null) {
        final raw = m.group(6)!.replaceAll('&amp;', '&');
        final src = raw.replaceAll(RegExp(r'#(audio|video)$', caseSensitive: false), '');
        final lower = raw.toLowerCase();
        if (_youtubeId(raw) != null) {
          blocks.add(_Block.youtube(raw));
        } else if (_isVideoUrl(raw) || lower.endsWith('#video')) {
          blocks.add(_Block.video(src));
        } else if (_isAudioUrl(raw) || lower.endsWith('#audio')) {
          blocks.add(_Block.audio(src));
        } else {
          blocks.add(_Block.video(src));
        }
      }
      cursor = m.end;
    }
    if (cursor < html.length) {
      final seg = html.substring(cursor);
      if (seg.replaceAll(RegExp(r'<[^>]+>'), '').trim().isNotEmpty) {
        blocks.add(_Block.text(seg));
      }
    }
    if (blocks.isEmpty) {
      // Fallback: pure text
      final plain = html.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (plain.isNotEmpty) blocks.add(_Block.text(html));
    }
    return blocks;
  }

  @override
  Widget build(BuildContext context) {
    if (_blocks.isEmpty) return const SizedBox.shrink();
    // Threads-style layout: text/audio/video render in document
    // order at the top; every image — no matter where it was in the
    // original HTML — collapses into one horizontal strip at the
    // bottom. Old web comments with images interleaved between
    // paragraphs end up looking the same as new app comments where
    // the user typed text then attached images at the end.
    final nonImageBlocks = _blocks.where((b) => b.kind != _BlockKind.image).toList();
    final imageUrls = _blocks
        .where((b) => b.kind == _BlockKind.image)
        .map((b) => b.value)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...nonImageBlocks.map((b) {
          switch (b.kind) {
          case _BlockKind.text:
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Html(
                data: b.value,
                // flutter_html 3.x bỏ render <table> mặc định → cần extension.
                extensions: const [TableHtmlExtension()],
                style: {
                  'body': Style(
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                    fontSize: FontSize(13),
                    lineHeight: const LineHeight(1.55),
                    color: AppColors.textSecondary,
                    fontFamily: body().fontFamily,
                  ),
                  'a': Style(color: AppColors.accentLight, textDecoration: TextDecoration.none),
                  'p': Style(margin: Margins.only(bottom: 4)),
                  'table': Style(border: Border.all(color: AppColors.border)),
                  'th': Style(padding: HtmlPaddings.all(6), backgroundColor: AppColors.surfaceLight, border: Border.all(color: AppColors.border)),
                  'td': Style(padding: HtmlPaddings.all(6), border: Border.all(color: AppColors.border)),
                },
                onLinkTap: (url, _, __) {
                  if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
              ),
            );
          case _BlockKind.image:
            // Unreachable — handled by the group branch above.
            return const SizedBox.shrink();
          case _BlockKind.audio:
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: WaveformPlayer(
                  audioUrl: b.value,
                  seed: b.value.hashCode.abs(),
                  showTimestamp: true,
                  height: 56,
                ),
              ),
            );
          case _BlockKind.video:
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _VideoCard(url: b.value),
            );
          case _BlockKind.youtube:
            return _YoutubeCard(url: b.value, videoId: _youtubeId(b.value));
        }
      }),
      if (imageUrls.isNotEmpty) _buildImageStrip(context, imageUrls),
      ],
    );
  }

  // Threads-style horizontal image strip. Single image fits inline
  // at a slightly larger size; multiple images become a horizontally
  // scrollable row with uniform height and a tap opens the lightbox
  // already positioned on the tapped image.
  Widget _buildImageStrip(BuildContext context, List<String> urls) {
    const double height = 200;
    if (urls.length == 1) {
      final url = urls.first;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: () => _showImageZoom(context, urls, 0),
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240, maxHeight: height),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(width: 200, height: 140, color: AppColors.surfaceLight),
                  errorWidget: (_, _, _) => Container(width: 200, height: 140, color: AppColors.surfaceLight, alignment: Alignment.center, child: Icon(Icons.broken_image, color: AppColors.textMuted)),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final url = urls[i];
            return InkWell(
              onTap: () => _showImageZoom(context, urls, i),
              borderRadius: BorderRadius.circular(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: url,
                  height: height,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(width: 140, height: height, color: AppColors.surfaceLight),
                  errorWidget: (_, _, _) => Container(width: 140, height: height, color: AppColors.surfaceLight, alignment: Alignment.center, child: Icon(Icons.broken_image, color: AppColors.textMuted)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showImageZoom(BuildContext context, List<String> urls, int initialIndex) {
    final controller = PageController(initialPage: initialIndex);
    final indexNotifier = ValueNotifier<int>(initialIndex);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            // Swipeable gallery — each page wraps an InteractiveViewer
            // so pinch-zoom still works, while horizontal swipe between
            // images advances PageView (the InteractiveViewer's pan
            // takes priority while zoomed in).
            PageView.builder(
              controller: controller,
              itemCount: urls.length,
              onPageChanged: (i) => indexNotifier.value = i,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: InteractiveViewer(
                  minScale: 1, maxScale: 4,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: urls[i],
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.white70)),
                      errorWidget: (_, _, _) => const Padding(padding: EdgeInsets.all(40), child: Icon(Icons.broken_image, color: Colors.white38, size: 48)),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0, right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            // Page counter "2 / 5" pill — only useful when more than
            // one image is in the gallery.
            if (urls.length > 1)
              Positioned(
                top: 12, left: 0, right: 0,
                child: Center(
                  child: ValueListenableBuilder<int>(
                    valueListenable: indexNotifier,
                    builder: (_, idx, _) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text('${idx + 1} / ${urls.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
              ),
            if (widget.authorName != null && widget.authorName!.isNotEmpty)
              Positioned(
                left: 0, right: 0, bottom: 24,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      'Ảnh: ${widget.authorName}',
                      style: body(const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ).whenComplete(() {
      controller.dispose();
      indexNotifier.dispose();
    });
  }
}

/// True when the URL's file extension is a known video format. Used to
/// recover the right player when web inserts `<audio>` for an mp4
/// (Lambda mis-tag — see CommentMedia comments above).
bool _isVideoUrl(String url) {
  final m = RegExp(r'\.(mp4|mov|mkv|webm|avi|wmv|flv|mpg|mpeg|3gp)(\?|#|$)', caseSensitive: false).firstMatch(url);
  return m != null;
}

/// True khi URL là file audio (dùng để nhận diện audio gói trong <oembed>).
bool _isAudioUrl(String url) {
  return RegExp(r'\.(mp3|wav|ogg|flac|aac|m4a)(\?|#|$)', caseSensitive: false).hasMatch(url);
}

/// Trích id video YouTube từ link (youtu.be / watch?v= / embed / shorts).
/// Trả null nếu không phải YouTube.
String? _youtubeId(String url) {
  try {
    final u = Uri.parse(url.replaceAll('&amp;', '&'));
    final host = u.host.replaceFirst(RegExp(r'^www\.'), '');
    String? id;
    if (host == 'youtu.be') {
      id = u.pathSegments.isNotEmpty ? u.pathSegments.first : null;
    } else if (host == 'youtube.com' || host == 'm.youtube.com' || host == 'music.youtube.com') {
      if (u.path == '/watch') {
        id = u.queryParameters['v'];
      } else if ((u.path.startsWith('/embed/') || u.path.startsWith('/shorts/')) && u.pathSegments.length > 1) {
        id = u.pathSegments[1];
      }
    }
    return (id != null && RegExp(r'^[\w-]{11}$').hasMatch(id)) ? id : null;
  } catch (_) {
    return null;
  }
}

enum _BlockKind { text, image, audio, video, youtube }

class _Block {
  final _BlockKind kind;
  final String value;
  const _Block._(this.kind, this.value);
  factory _Block.text(String v) => _Block._(_BlockKind.text, v);
  factory _Block.image(String v) => _Block._(_BlockKind.image, v);
  factory _Block.audio(String v) => _Block._(_BlockKind.audio, v);
  factory _Block.video(String v) => _Block._(_BlockKind.video, v);
  factory _Block.youtube(String v) => _Block._(_BlockKind.youtube, v);
}

/// Card YouTube: thumbnail + nút play → mở YouTube ngoài app.
/// (YouTube chặn nhúng embed trong webview bằng anti-bot "sign in to confirm"
/// nên không phát inline được tin cậy; mở ngoài là cách luôn chạy.)
class _YoutubeCard extends StatelessWidget {
  final String url;
  final String? videoId;
  const _YoutubeCard({required this.url, required this.videoId});

  @override
  Widget build(BuildContext context) {
    final id = videoId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: InkWell(
            onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            borderRadius: BorderRadius.circular(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (id != null)
                      CachedNetworkImage(
                        imageUrl: 'https://img.youtube.com/vi/$id/hqdefault.jpg',
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: AppColors.surfaceLight),
                        errorWidget: (_, __, ___) => Container(color: AppColors.surfaceLight),
                      )
                    else
                      Container(color: AppColors.surfaceLight),
                    Container(color: Colors.black.withValues(alpha: 0.18)),
                    Center(
                      child: Container(
                        width: 54,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF0000),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                      ),
                    ),
                    const Positioned(
                      right: 6, bottom: 6,
                      child: Icon(Icons.open_in_new, color: Colors.white70, size: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Card video internal (bcdcnt mp4): bấm → phát INLINE bằng Chewie (controls
/// đầy đủ). Chỉ khởi tạo controller khi bấm. Nếu init lỗi (URL không phải video
/// trực tiếp) → fallback mở ngoài.
class _VideoCard extends StatefulWidget {
  final String url;
  const _VideoCard({required this.url});

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  VideoPlayerController? _videoCtl;
  ChewieController? _chewieCtl;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start(); // auto-init: hiện khung player ngay (frame đầu + controls)
  }

  @override
  void dispose() {
    _chewieCtl?.dispose();
    _videoCtl?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final v = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await v.initialize();
      if (!mounted) { v.dispose(); return; }
      setState(() {
        _videoCtl = v;
        _chewieCtl = ChewieController(
          videoPlayerController: v,
          autoPlay: false,
          looping: false,
          aspectRatio: v.value.aspectRatio == 0 ? 16 / 9 : v.value.aspectRatio,
        );
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget inner;
    if (_chewieCtl != null) {
      inner = Chewie(controller: _chewieCtl!);
    } else if (_failed) {
      // Init lỗi (URL không phải video trực tiếp) → mở ngoài.
      inner = InkWell(
        onTap: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
        child: Container(
          color: AppColors.surfaceLight,
          alignment: Alignment.center,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.open_in_new, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Text('Mở video', style: body(const TextStyle(fontSize: 12, color: Colors.white70))),
          ]),
        ),
      );
    } else {
      // Đang tải → khung tối + nút play mờ (trông như player sắp hiện).
      inner = Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Container(
          width: 54, height: 38,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.play_arrow, color: Colors.white70, size: 28),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: (_videoCtl?.value.aspectRatio ?? 0) == 0 ? 16 / 9 : _videoCtl!.value.aspectRatio,
            child: inner,
          ),
        ),
      ),
    );
  }
}
