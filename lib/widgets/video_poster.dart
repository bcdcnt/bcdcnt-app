import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../constants/theme.dart';

/// Loads the first frame of a video without auto-playing — used as a poster
/// fallback when a document has no thumbnail.
class VideoPoster extends StatefulWidget {
  final String videoUrl;
  final BoxFit fit;
  const VideoPoster({super.key, required this.videoUrl, this.fit = BoxFit.cover});

  @override
  State<VideoPoster> createState() => _VideoPosterState();
}

class _VideoPosterState extends State<VideoPoster> {
  VideoPlayerController? _ctl;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await c.initialize();
      // Seek to half-second to skip black intro frames
      await c.seekTo(const Duration(milliseconds: 500));
      if (!mounted) { c.dispose(); return; }
      setState(() { _ctl = c; _ready = true; });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return Container(color: AppColors.surfaceLight, child: const Icon(Icons.movie, color: AppColors.textMuted));
    if (!_ready || _ctl == null) {
      return Container(color: AppColors.surfaceLight);
    }
    return FittedBox(
      fit: widget.fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: _ctl!.value.size.width,
        height: _ctl!.value.size.height,
        child: VideoPlayer(_ctl!),
      ),
    );
  }
}
