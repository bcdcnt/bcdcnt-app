import '../services/imgcdn.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import 'song_row.dart' show GeneratedCover;
import '../services/player.dart';
import '../main.dart' show rootNavigatorKey;
import 'full_player.dart';

/// Tạm ẩn nút "Thu gọn" trên mini-player. Tính năng (toggleMiniCollapsed) vẫn
/// giữ nguyên — đổi thành `true` để bật lại nút.
const bool _kShowMiniCollapse = false;

/// Slides the FullPlayer up over everything, from the ROOT navigator so it
/// sits above the ShellRoute (desktop sidebar/panels stay hidden behind it).
/// `fullPlayerOpen` flips BEFORE the push so the root-level collapsed pill
/// disappears in the same frame the slide begins.
void openFullPlayer(PlayerProvider player) {
  player.setFullPlayerOpen(true);
  rootNavigatorKey.currentState?.push(
    PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, anim, __) => SlideTransition(
        position: anim.drive(Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic))),
        child: const FullPlayer(),
      ),
    ),
  );
}

/// Marks a subtree whose phone shell already draws the mini player above
/// its tab bar. Screens still drop their own `MiniPlayer()` into their
/// Stacks (desktop and older layouts rely on that); inside the scope those
/// copies render nothing so the bar never shows twice.
class MiniPlayerScope extends InheritedWidget {
  const MiniPlayerScope({super.key, required super.child});
  static bool active(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MiniPlayerScope>() != null;
  @override
  bool updateShouldNotify(MiniPlayerScope oldWidget) => false;
}

/// Wine-red card pinned above the tab bar: cover, title, artist, pause and
/// next. Tap or swipe up opens the FullPlayer. The 3px line along the bottom
/// edge is the only part that follows playback position.
class MiniPlayer extends StatelessWidget {
  /// True for the shell's own copy (drawn even inside [MiniPlayerScope]).
  final bool fromShell;
  const MiniPlayer({super.key, this.fromShell = false});

  @override
  Widget build(BuildContext context) {
    if (!fromShell && MiniPlayerScope.active(context)) return const SizedBox.shrink();
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();

    // Collapsed pill is rendered by `MiniPlayerOverlay` at the root
    // (MaterialApp.builder) so it can be dragged freely across the
    // whole screen. Hide the per-screen mini bar in that mode to
    // avoid double-rendering.
    if (player.miniCollapsed) return const SizedBox.shrink();

    final artists = song['artists'] is List ? song['artists'] : (song['artists']?['data'] ?? []);
    final artistText = (artists as List).map((a) => a['title'] ?? a['username'] ?? '').where((s) => s.toString().isNotEmpty && s != 'Đang cập nhật').join(', ');
    final thumb = song['thumbnail']?['url'];
    final hasNext = player.queue.length > player.currentIndex + 1;
    final nextTitle = hasNext ? player.queue[player.currentIndex + 1]['title']?.toString() : null;
    const fg = Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openFullPlayer(player),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -250) openFullPlayer(player);
        },
        child: Semantics(
          button: true,
          label: 'Đang phát ${song['title'] ?? ''}. Chạm để mở trình phát',
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.wine,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: AppColors.wine.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: thumb != null
                            ? CachedNetworkImage(imageUrl: cdnImg((thumb).toString(), 144), width: 48, height: 48, memCacheWidth: 144, fit: BoxFit.cover)
                            : GeneratedCover(title: '${song['title'] ?? ''}', size: 48, radius: 0),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(song['title'] ?? '', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg)), maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (artistText.isNotEmpty)
                              Text(artistText, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.75))), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      if (player.isLoading)
                        const SizedBox(width: 48, height: 48, child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))))
                      else
                        IconButton(
                          tooltip: player.isPlaying ? 'Tạm dừng' : 'Phát',
                          icon: Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: fg, size: 30),
                          onPressed: player.togglePlay,
                        ),
                      IconButton(
                        tooltip: nextTitle != null && nextTitle.isNotEmpty ? 'Tiếp: $nextTitle' : 'Bài tiếp theo',
                        icon: const Icon(Icons.skip_next_rounded, color: fg, size: 28),
                        onPressed: hasNext ? player.playNext : null,
                      ),
                      if (_kShowMiniCollapse)
                        IconButton(
                          tooltip: 'Thu gọn',
                          icon: const Icon(Icons.unfold_less, color: fg, size: 18),
                          onPressed: player.toggleMiniCollapsed,
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 14, right: 14, bottom: 0,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: player.positionNotifier,
                      builder: (context, _, _) => Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: player.progress.clamp(0.0, 1.0),
                          child: Container(decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(2))),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Tiny pill version of the mini player — thumbnail + play/pause +
/// expand button. Mounted by the root-level overlay so it can drift
/// freely across the entire screen via drag.
class _CollapsedMiniPlayerPill extends StatelessWidget {
  final Map<String, dynamic> song;
  final String? thumb;
  const _CollapsedMiniPlayerPill({required this.song, required this.thumb});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    // The pill lives in the root `MaterialApp.builder` Stack which
    // sits outside the route's Navigator → no `Overlay`, no
    // `Material`. Stick to plain `GestureDetector` + `Icon` to avoid
    // ripple/tooltip widgets that walk the ancestor chain.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x33711313)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 2))],
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Tap thumbnail → open FullPlayer (same affordance as the
        // expanded card so the gesture stays consistent). Flip
        // `fullPlayerOpen` synchronously so the pill disappears in
        // the same frame the slide-up starts — otherwise it floats
        // on top of the animation.
        GestureDetector(
          onTap: () {
            player.setFullPlayerOpen(true);
            rootNavigatorKey.currentState?.push(
              PageRouteBuilder(
                opaque: true,
                pageBuilder: (_, anim, __) => SlideTransition(
                  position: anim.drive(Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic))),
                  child: const FullPlayer(),
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: thumb != null
                ? CachedNetworkImage(imageUrl: cdnImg((thumb!).toString(), 90), width: 36, height: 36, fit: BoxFit.cover)
                : GeneratedCover(title: '${song['title'] ?? ''}', size: 36, radius: 0),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: player.togglePlay,
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            child: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 18),
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: player.toggleMiniCollapsed,
          child: SizedBox(
            width: 32, height: 32,
            child: Icon(Icons.unfold_more, color: AppColors.textMuted, size: 18),
          ),
        ),
      ]),
    );
  }
}

/// Floating, draggable layer that hosts the collapsed mini-player
/// pill above every route. Mounted once at the root via
/// `MaterialApp.builder` so its offset survives navigation. Drag
/// updates `PlayerProvider.miniOffset`; the offset is clamped on
/// pan-end so the pill never lands fully off-screen.
class MiniPlayerOverlay extends StatefulWidget {
  const MiniPlayerOverlay({super.key});

  @override
  State<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends State<MiniPlayerOverlay> {
  // Approximate pill dimensions used for default-anchor positioning
  // and clamp logic. Real size is intrinsic; these are good-enough
  // upper bounds for the math.
  static const double _w = 150;
  static const double _h = 56;
  static const double _margin = 12;

  // Local drag accumulator — flushed into the provider on pan-end.
  // Updating provider on every onPanUpdate would trigger a rebuild
  // for every pixel of motion across the entire app.
  Offset? _draftOffset;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;
    if (song == null || !player.miniCollapsed || player.fullPlayerOpen) return const SizedBox.shrink();

    final screen = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    // Default anchor: bottom-right with safe-area + 8px margin.
    final defaultLeft = screen.width - _w - _margin;
    final defaultTop = screen.height - padding.bottom - _h - _margin;
    final base = _draftOffset ?? player.miniOffset ?? Offset(defaultLeft, defaultTop);

    final thumb = song['thumbnail']?['url']?.toString();

    return Stack(children: [
      Positioned(
        left: base.dx,
        top: base.dy,
        child: GestureDetector(
          // Make the pill itself drag-handle so the embedded
          // play/expand buttons keep working — Flutter's gesture
          // arena picks taps over pans inside Material/IconButton.
          onPanUpdate: (d) {
            setState(() {
              final next = (_draftOffset ?? base) + d.delta;
              _draftOffset = next;
            });
          },
          onPanEnd: (_) {
            if (_draftOffset == null) return;
            // Clamp to viewport so an over-zealous fling can't lose
            // the pill behind a screen edge.
            final clampedX = _draftOffset!.dx.clamp(_margin, screen.width - _w - _margin);
            final clampedY = _draftOffset!.dy.clamp(padding.top + _margin, screen.height - padding.bottom - _h - _margin);
            player.setMiniOffset(Offset(clampedX, clampedY));
            setState(() => _draftOffset = null);
          },
          child: _CollapsedMiniPlayerPill(song: song, thumb: thumb),
        ),
      ),
    ]);
  }
}
