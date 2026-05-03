import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../constants/theme.dart';

bool get _isDesktop {
  return defaultTargetPlatform == TargetPlatform.macOS
      || defaultTargetPlatform == TargetPlatform.windows
      || defaultTargetPlatform == TargetPlatform.linux;
}

/// Hover row highlight — subtle fill + pointer cursor on desktop.
/// On mobile (touch) it's a no-op so the build behaves identically.
class HoverHighlight extends StatefulWidget {
  final Widget child;
  final Color? color;
  final BorderRadius? borderRadius;
  const HoverHighlight({super.key, required this.child, this.color, this.borderRadius});

  @override
  State<HoverHighlight> createState() => _HoverHighlightState();
}

class _HoverHighlightState extends State<HoverHighlight> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return widget.child;
    final fill = widget.color ?? AppColors.surfaceLight;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _hover ? fill : Colors.transparent,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Hover scale — for poster-style cards (album, artist, playlist tiles).
/// Lifts the card with a small scale + subtle shadow.
class HoverScale extends StatefulWidget {
  final Widget child;
  final double scale;
  const HoverScale({super.key, required this.child, this.scale = 1.03});

  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return widget.child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: _hover
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))]
                : const [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Hover-only "Play" overlay — shows a circular play button over a card on
/// hover, like Spotify/Apple Music album cards. The child is the artwork.
class HoverPlayOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPlay;
  final double size;
  const HoverPlayOverlay({super.key, required this.child, this.onPlay, this.size = 44});

  @override
  State<HoverPlayOverlay> createState() => _HoverPlayOverlayState();
}

class _HoverPlayOverlayState extends State<HoverPlayOverlay> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop || widget.onPlay == null) return widget.child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned(
            right: 8, bottom: 8,
            child: AnimatedOpacity(
              opacity: _hover ? 1 : 0,
              duration: const Duration(milliseconds: 140),
              child: AnimatedSlide(
                offset: _hover ? Offset.zero : const Offset(0, 0.3),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: GestureDetector(
                  onTap: widget.onPlay,
                  child: Container(
                    width: widget.size, height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                      boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Icon(Icons.play_arrow, color: Colors.white, size: widget.size * 0.55),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
