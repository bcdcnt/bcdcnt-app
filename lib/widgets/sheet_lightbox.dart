import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/theme.dart';

class SheetLightbox extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  /// Optional caption shown beneath each image (e.g. "Ảnh: <username>",
  /// "Bản nhạc: <username>"). Length must match [images] when provided.
  final List<String?>? captions;
  const SheetLightbox({super.key, required this.images, this.initialIndex = 0, this.captions});

  @override
  State<SheetLightbox> createState() => _SheetLightboxState();
}

class _SheetLightboxState extends State<SheetLightbox> {
  late PageController _controller;
  late int _currentIndex;
  // One TransformationController per image so zoom state survives page swipes.
  // Lazy-init via the map.
  final Map<int, TransformationController> _zoomCtls = {};

  static const _minScale = 1.0;
  static const _maxScale = 5.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final c in _zoomCtls.values) { c.dispose(); }
    super.dispose();
  }

  TransformationController _ctlFor(int i) {
    return _zoomCtls.putIfAbsent(i, () => TransformationController());
  }

  double _scaleFor(int i) {
    final m = _ctlFor(i).value;
    return m.row0.x;
  }

  void _setScale(int i, double scale) {
    final clamped = scale.clamp(_minScale, _maxScale);
    final ctl = _ctlFor(i);
    final size = MediaQuery.of(context).size;
    // Anchor zoom around viewport centre — the matrix is scale-then-translate
    // so we offset by half of (newSize - viewport) on each axis.
    final tx = -size.width * (clamped - 1) / 2;
    final ty = -size.height * (clamped - 1) / 2;
    ctl.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(clamped);
    setState(() {});
  }

  void _toggleZoom() {
    final cur = _scaleFor(_currentIndex);
    _setScale(_currentIndex, cur > 1.5 ? 1.0 : 2.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            // Lock horizontal swipe while zoomed in so panning the image
            // doesn't accidentally flip pages.
            physics: _scaleFor(_currentIndex) > 1.05
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (ctx, i) => GestureDetector(
              onDoubleTap: i == _currentIndex ? _toggleZoom : null,
              child: InteractiveViewer(
                transformationController: _ctlFor(i),
                minScale: _minScale,
                maxScale: _maxScale,
                onInteractionEnd: (_) => setState(() {}),
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.images[i],
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const Center(child: CircularProgressIndicator(color: Colors.white70)),
                    errorWidget: (_, _, _) => const Center(child: Icon(Icons.broken_image, color: Colors.white38, size: 48)),
                  ),
                ),
              ),
            ),
          ),
          // Top gradient scrim + controls
          Positioned(
            top: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: 100,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 26),
                      tooltip: 'Đóng',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.images.length}',
                      style: body(const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          // Caption (image credit) — shown directly above the zoom toolbar
          // when the parent supplied a credit string for the active image.
          if (widget.captions != null && _currentIndex < widget.captions!.length && (widget.captions![_currentIndex]?.isNotEmpty ?? false))
            Positioned(
              left: 0, right: 0, bottom: 64,
              child: SafeArea(
                top: false,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      widget.captions![_currentIndex]!,
                      style: body(const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
              ),
            ),
          // Zoom toolbar — bottom-centre, mirrors PDF readers (Apple Preview,
          // Adobe). Pinch / scroll-wheel still work; this is for when there's
          // no trackpad gesture available.
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _zoomBtn(Icons.remove, 'Thu nhỏ', () {
                        _setScale(_currentIndex, _scaleFor(_currentIndex) - 0.5);
                      }),
                      InkWell(
                        onTap: () => _setScale(_currentIndex, 1.0),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text(
                            '${(_scaleFor(_currentIndex) * 100).round()}%',
                            style: body(const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                          ),
                        ),
                      ),
                      _zoomBtn(Icons.add, 'Phóng to', () {
                        _setScale(_currentIndex, _scaleFor(_currentIndex) + 0.5);
                      }),
                      Container(width: 1, height: 16, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 4)),
                      _zoomBtn(Icons.fit_screen_outlined, 'Vừa khung hình', () {
                        _setScale(_currentIndex, 1.0);
                      }),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoomBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 18,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: Colors.white),
      onPressed: onTap,
    );
  }
}
