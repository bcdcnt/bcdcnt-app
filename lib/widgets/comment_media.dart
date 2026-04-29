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
  const CommentMedia({super.key, required this.html});

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _blocks.map((b) {
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
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => _showImageZoom(context, b.value),
                  borderRadius: BorderRadius.circular(10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240, maxHeight: 200),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: b.value,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(width: 200, height: 140, color: AppColors.surfaceLight),
                        errorWidget: (_, _, _) => Container(width: 200, height: 140, color: AppColors.surfaceLight, alignment: Alignment.center, child: const Icon(Icons.broken_image, color: AppColors.textMuted)),
                      ),
                    ),
                  ),
                ),
              ),
            );
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
                      decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Mở video', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)))),
                    const Icon(Icons.open_in_new, size: 14, color: AppColors.textMuted),
                  ]),
                ),
              ),
            );
        }
      }).toList(),
    );
  }

  void _showImageZoom(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 1, maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.white70)),
                    errorWidget: (_, _, _) => const Padding(padding: EdgeInsets.all(40), child: Icon(Icons.broken_image, color: Colors.white38, size: 48)),
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
            ],
          ),
        ),
      ),
    );
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
