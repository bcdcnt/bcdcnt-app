import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/theme.dart';

class SheetLightbox extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const SheetLightbox({super.key, required this.images, this.initialIndex = 0});

  @override
  State<SheetLightbox> createState() => _SheetLightboxState();
}

class _SheetLightboxState extends State<SheetLightbox> {
  late PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (ctx, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.images[i],
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.white70)),
                  errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white38, size: 48)),
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
        ],
      ),
    );
  }
}
