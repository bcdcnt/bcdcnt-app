import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
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
      r'<img[^>]+src="([^"]+)"[^>]*>|<audio[^>]*>(.*?)</audio>|<video[^>]*>(.*?)</video>|<source[^>]+src="([^"]+)"[^>]*>|<iframe[^>]+src="([^"]+)"[^>]*></iframe>',
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
        if (src != null) blocks.add(_Block.audio(src));
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
        if (url.toLowerCase().contains('.mp3') || url.toLowerCase().contains('audio')) {
          blocks.add(_Block.audio(url));
        } else {
          blocks.add(_Block.video(url));
        }
      }
      // iframe (likely YouTube)
      else if (m.group(5) != null) {
        blocks.add(_Block.video(m.group(5)!));
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
              child: InkWell(
                onTap: () => launchUrl(Uri.parse(b.value), mode: LaunchMode.externalApplication),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Mở video', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)))),
                    Icon(Icons.open_in_new, size: 14, color: AppColors.textMuted),
                  ]),
                ),
              ),
            );
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

enum _BlockKind { text, image, audio, video }

class _Block {
  final _BlockKind kind;
  final String value;
  const _Block._(this.kind, this.value);
  factory _Block.text(String v) => _Block._(_BlockKind.text, v);
  factory _Block.image(String v) => _Block._(_BlockKind.image, v);
  factory _Block.audio(String v) => _Block._(_BlockKind.audio, v);
  factory _Block.video(String v) => _Block._(_BlockKind.video, v);
}
