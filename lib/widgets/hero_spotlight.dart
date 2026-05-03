import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/theme.dart';

/// Full-bleed rotating hero card. Pass a list of song-like maps with
/// `title`, `artists` (list w/ title), `thumbnail.url`, optional `weeklyListens`.
class HeroSpotlight extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> item)? onTap;
  /// Optional inline play callback — wires the "Phát" CTA on each card so
  /// users can start playback without leaving the home feed. When null
  /// the CTA falls back to [onTap].
  final void Function(Map<String, dynamic> item)? onPlay;
  const HeroSpotlight({super.key, required this.items, this.onTap, this.onPlay});

  @override
  State<HeroSpotlight> createState() => _HeroSpotlightState();
}

class _HeroSpotlightState extends State<HeroSpotlight> {
  final PageController _ctl = PageController();
  int _idx = 0;
  Timer? _timer;
  bool _userInteracting = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.items.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || _userInteracting) return;
      final next = (_idx + 1) % widget.items.length;
      _ctl.animateToPage(next, duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  String _fmt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return n < 0 ? '-$buf' : buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    return Listener(
      onPointerDown: (_) => _userInteracting = true,
      onPointerUp: (_) {
        _userInteracting = false;
        _startTimer();
      },
      child: SizedBox(
        height: 230,
        child: Stack(
          children: [
            PageView.builder(
              controller: _ctl,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _idx = i),
              itemBuilder: (ctx, i) => _SpotlightCard(
                item: items[i],
                onTap: widget.onTap == null ? null : () => widget.onTap!(items[i]),
                onPlay: widget.onPlay == null ? null : () => widget.onPlay!(items[i]),
                fmt: _fmt,
              ),
            ),
            // Page dots
            if (items.length > 1) Positioned(
              left: 0, right: 0, bottom: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(items.length, (i) {
                  final active = i == _idx;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 22 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : Colors.white.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final String Function(int) fmt;
  const _SpotlightCard({required this.item, required this.onTap, this.onPlay, required this.fmt});

  @override
  State<_SpotlightCard> createState() => _SpotlightCardState();
}

class _SpotlightCardState extends State<_SpotlightCard> {
  bool _pressed = false;

  Map<String, dynamic> get item => widget.item;
  VoidCallback? get onTap => widget.onTap;
  String Function(int) get fmt => widget.fmt;

  @override
  Widget build(BuildContext context) {
    final title = item['title']?.toString() ?? '';
    final subtitle = item['subtitle']?.toString();
    final thumbUrl = item['thumbnail']?['url'] as String?;
    final artistsRaw = item['artists'];
    final artists = artistsRaw is List
        ? artistsRaw
        : (artistsRaw is Map ? (artistsRaw['data'] ?? []) : []);
    final artistText = (artists as List).map((a) => a['title'] ?? a['username'] ?? '').where((s) => (s as String).isNotEmpty).join(', ');
    final weekly = item['weeklyListens'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.25), blurRadius: 28, spreadRadius: -8, offset: const Offset(0, 14))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Blurred BG image
                if (thumbUrl != null) CachedNetworkImage(imageUrl: thumbUrl, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppColors.accent)),
                if (thumbUrl != null) BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(color: Colors.black.withValues(alpha: 0.38)),
                ),
                // Overlay gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [
                        AppColors.accent.withValues(alpha: 0.5),
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
                // Foreground
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 28),
                  child: Row(
                    children: [
                      // Crisp thumbnail
                      Container(
                        width: 130, height: 130,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 22, offset: const Offset(0, 10))],
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: thumbUrl != null
                              ? CachedNetworkImage(imageUrl: thumbUrl, fit: BoxFit.cover)
                              : Container(color: Colors.white.withValues(alpha: 0.1), child: const Icon(Icons.music_note, color: Colors.white, size: 48)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(children: [
                              const Icon(Icons.local_fire_department, color: Colors.amberAccent, size: 12),
                              const SizedBox(width: 4),
                              Text('NỔI BẬT', style: body(const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 2))),
                            ]),
                            const SizedBox(height: 6),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: display(const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, height: 1.15, letterSpacing: -0.3)),
                            ),
                            if (subtitle != null && subtitle.isNotEmpty) Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 11, color: Colors.white60, fontStyle: FontStyle.italic))),
                            ),
                            if (artistText.isNotEmpty) Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(artistText, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, color: Colors.white70))),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                // Inline Phát CTA — taps here trigger playback
                                // directly via onPlay (falling back to onTap
                                // when no separate handler is wired). Material
                                // wrap stops the gesture from bubbling to the
                                // parent card-open handler.
                                Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  elevation: 2,
                                  shadowColor: Colors.black.withValues(alpha: 0.25),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: widget.onPlay ?? widget.onTap,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.play_arrow, size: 16, color: AppColors.accent),
                                        const SizedBox(width: 4),
                                        Text('Phát', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent))),
                                      ]),
                                    ),
                                  ),
                                ),
                                if (weekly != null && weekly is num && weekly.toInt() > 0) ...[
                                  const SizedBox(width: 8),
                                  Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.headphones, size: 11, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Text(fmt(weekly.toInt()), style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70))),
                                  ]),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}
