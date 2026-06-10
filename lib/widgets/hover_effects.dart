import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../constants/theme.dart';

bool get _isDesktop {
  return defaultTargetPlatform == TargetPlatform.macOS
      || defaultTargetPlatform == TargetPlatform.windows
      || defaultTargetPlatform == TargetPlatform.linux;
}

/// Hover treatment for poster-style carousel cards (tag / video / playlist /
/// decade) that must NOT change size. A soft accent border + faint scrim fade
/// in ON the card's existing bounds — unlike `HoverScale`, nothing scales or
/// casts a shadow, so the hover never overflows the carousel's edge clip and
/// gets cut at the first / last item ("cắt đầu đuôi").
class HoverGlow extends StatefulWidget {
  final Widget child;
  final double radius;
  const HoverGlow({super.key, required this.child, this.radius = 14});

  @override
  State<HoverGlow> createState() => _HoverGlowState();
}

class _HoverGlowState extends State<HoverGlow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return widget.child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: const Duration(milliseconds: 130),
                curve: Curves.easeOut,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.radius),
                    border: Border.all(color: AppColors.accentLight.withValues(alpha: 0.9), width: 2),
                    color: Colors.white.withValues(alpha: 0.07),
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
    // surfaceLight reads as a clear hover on the dark palettes, but on the
    // light theme it's nearly identical to the background — so there use a
    // subtle dark scrim instead to keep the hover visible.
    final fill = widget.color ??
        (AppColors.bg.computeLuminance() > 0.5
            ? Colors.black.withValues(alpha: 0.10)
            : AppColors.surfaceLight);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        // Fade IN softly, but clear INSTANTLY on exit. With a symmetric fade,
        // moving from one row to the next left the old row mid-fade-out while
        // the new one faded in — so two adjacent items looked highlighted at
        // once. Instant exit means only the row under the cursor is ever lit.
        duration: _hover ? const Duration(milliseconds: 110) : Duration.zero,
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
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.35 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))]
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
                      boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.5 * AppColors.shadowMul), blurRadius: 12, offset: const Offset(0, 4))],
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

/// Propagates a card's hover state to descendants so an inner reveal/zoom
/// doesn't need its own MouseRegion (nesting them caused a hover feedback
/// loop → flickering artwork). HoverCard provides it.
class _HoverScope extends InheritedWidget {
  final bool hovered;
  const _HoverScope({required this.hovered, required super.child});

  static bool? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HoverScope>()?.hovered;

  @override
  bool updateShouldNotify(_HoverScope old) => old.hovered != hovered;
}

/// Hover-reveal play button + artwork zoom for media cards in horizontal
/// carousels. On desktop the artwork zooms slightly within its fixed rounded
/// frame (clipped, so it never overflows the carousel edge) and a circular
/// play button fades in at the bottom-right. On touch the play button is
/// always visible. Used on the homepage song/playlist carousels and the
/// Library carousels so every carousel card behaves identically.
///
/// When wrapped by a [HoverCard] it reacts to that card's hover (single, outer
/// MouseRegion); standalone it falls back to its own MouseRegion.
class HoverRevealPlay extends StatefulWidget {
  final double size;
  final Widget child;
  final VoidCallback onPlay;
  const HoverRevealPlay({super.key, required this.size, required this.child, required this.onPlay});

  @override
  State<HoverRevealPlay> createState() => _HoverRevealPlayState();
}

class _HoverRevealPlayState extends State<HoverRevealPlay> {
  bool _localHover = false;

  @override
  Widget build(BuildContext context) {
    // Prefer an enclosing HoverCard's hover (one MouseRegion for the whole
    // card); only run our own when used standalone.
    final scoped = _HoverScope.maybeOf(context);
    final hover = scoped ?? _localHover;
    final visible = !_isDesktop || hover;
    // Hover zooms the artwork within its fixed rounded frame (clipped, so the
    // zoom never grows the card past the carousel edge). IgnorePointer keeps the
    // (scaled) artwork out of hit-testing entirely, and `hover` comes from the
    // enclosing HoverCard's single MouseRegion — so the zoom is purely visual
    // and can't feed back into hover detection.
    final art = IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AnimatedScale(
          scale: (_isDesktop && hover) ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
    final inner = Stack(children: [
      art,
      Positioned(
        bottom: 6, right: 6,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          opacity: visible ? 1.0 : 0.0,
          child: IgnorePointer(
            ignoring: !visible,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              shadowColor: Colors.black.withValues(alpha: 0.4),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onPlay,
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Icon(Icons.play_arrow, size: 18, color: AppColors.accent),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
    // Hover comes from the enclosing HoverCard (or touch) — no own MouseRegion,
    // so there's no nested-region feedback loop.
    if (!_isDesktop || scoped != null) return inner;
    return MouseRegion(
      onEnter: (_) => setState(() => _localHover = true),
      onExit: (_) => setState(() => _localHover = false),
      child: inner,
    );
  }
}

/// Unified hover treatment for song/media cards in horizontal carousels.
/// On desktop, a soft padded card (fill + 1px border, rounded) fades in on
/// hover — giving each item clear breathing room instead of a cramped,
/// sharp-cornered highlight. The padding is CONSTANT (only colour/border
/// animate) so hovering never shifts layout. The same padding is applied on
/// touch builds so card footprints match across platforms.
class HoverCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  /// Lift the whole card up a touch on hover. Default 1.0 (disabled): scaling
  /// the whole card makes it overflow / protrude past the carousel's clip at
  /// the first/last item, so carousels keep this off and zoom the artwork
  /// inside its fixed frame instead (see _HoverRevealPlay).
  final double scale;
  const HoverCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(6),
    this.radius = 14,
    this.scale = 1.0,
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // The visual card (fill + border), shrink-wrapped to its content.
    final Widget visual = AnimatedScale(
      scale: _hover ? widget.scale : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        padding: widget.padding,
        decoration: BoxDecoration(
          // Fade from the SAME colour at alpha 0 — NOT Colors.transparent.
          // Colors.transparent is transparent *black*, so animating to/from it
          // lerps the RGB through black → a dark-gray flash mid-fade before it
          // settles to the light fill. alpha-0 surfaceLight keeps the RGB light
          // the whole way, so the hover fades in cleanly.
          color: _hover ? AppColors.surfaceLight : AppColors.surfaceLight.withValues(alpha: 0),
          border: Border.all(color: _hover ? AppColors.border : AppColors.border.withValues(alpha: 0)),
          borderRadius: BorderRadius.circular(widget.radius),
          // No drop shadow: its blur always spills past the carousel's clip.
        ),
        // One hover state shared with descendants (the reveal-play button) — no
        // nested MouseRegion, which previously caused a hover feedback loop.
        child: _HoverScope(hovered: _hover, child: widget.child),
      ),
    );
    // A horizontal ListView forces every item to the full viewport height
    // (cross-axis TIGHT). topCenter + widthFactor:1 lets the *fill* hug the
    // card instead of stretching into a tall box below the text.
    final Widget aligned =
        Align(alignment: Alignment.topCenter, widthFactor: 1, child: visual);

    if (!_isDesktop) {
      return Align(
        alignment: Alignment.topCenter,
        widthFactor: 1,
        child: Padding(padding: widget.padding, child: widget.child),
      );
    }
    // Detect hover over the FULL item (incl. the empty area the ListView pads
    // below the card), not just the shrink-wrapped content. Otherwise the
    // region's bottom edge lands right on the card's last text line, where a
    // resting cursor's micro-movements toggled hover on/off — the blink.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: aligned,
    );
  }
}
