import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/player.dart';
import '../main.dart' show rootNavigatorKey;
import 'full_player.dart';

String _fmtTs(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();

    final artists = song['artists'] is List ? song['artists'] : (song['artists']?['data'] ?? []);
    final artistText = (artists as List).map((a) => a['title'] ?? a['username'] ?? '').join(', ');
    final thumb = song['thumbnail']?['url'];

    // "Up next" preview — surfaces the queue item that will play after the
    // current one, mirroring Spotify's tooltip hint. Wired into the
    // skip-next button tooltip so it stays contextual without cluttering
    // the row.
    final hasNext = player.queue.length > player.currentIndex + 1;
    final nextSong = hasNext ? player.queue[player.currentIndex + 1] : null;
    final nextTitle = nextSong?['title']?.toString();
    final nextTooltip = nextTitle != null && nextTitle.isNotEmpty
        ? 'Tiếp: $nextTitle  ⇧ →'
        : 'Bài tiếp theo  ⇧ →';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x33711313)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 15, offset: Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tap-to-seek progress bar — bumped to 5px so it's an obvious
          // hit target without dominating the row, and registers a tap
          // anywhere along its width to seek to that position. Spotify /
          // Apple Music desktop pattern.
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                final w = (context.findRenderObject() as RenderBox?)?.size.width ?? 0;
                if (w <= 0) return;
                final ratio = (d.localPosition.dx / w).clamp(0.0, 1.0);
                final ms = (player.duration.inMilliseconds * ratio).toInt();
                player.seek(Duration(milliseconds: ms));
              },
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: LinearProgressIndicator(
                  value: player.progress,
                  minHeight: 5,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
            ),
          ),
          InkWell(
            // Push to ROOT navigator so the FullPlayer sits above the
            // ShellRoute — otherwise the desktop sidebar + right-panel
            // toggle/collapse stay visible behind the player and the
            // player's "..." doesn't line up with anything.
            onTap: () => rootNavigatorKey.currentState?.push(
              PageRouteBuilder(
                opaque: true,
                pageBuilder: (_, anim, __) => SlideTransition(
                  position: anim.drive(Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic))),
                  child: const FullPlayer(),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: thumb != null
                        ? CachedNetworkImage(imageUrl: thumb, width: 44, height: 44, fit: BoxFit.cover)
                        : Container(width: 44, height: 44, color: AppColors.surfaceLight, child: Icon(Icons.music_note, size: 16, color: AppColors.textMuted)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(song['title'] ?? '', style: AppText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        // Artist + timestamp share a single row — artist
                        // ellipsizes when the row is tight so the
                        // tabular timestamp on the right always reads
                        // cleanly. Tabular figures keep digit width
                        // stable so the slash doesn't jitter as the
                        // position ticks.
                        Row(children: [
                          if (artistText.isNotEmpty)
                            Flexible(
                              child: Text(
                                artistText,
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (artistText.isNotEmpty && player.duration.inMilliseconds > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text('·', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ),
                          if (player.duration.inMilliseconds > 0)
                            Text(
                              '${_fmtTs(player.position)} / ${_fmtTs(player.duration)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                        ]),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Bài trước  ⇧ ←', icon: Icon(Icons.skip_previous, color: AppColors.text), onPressed: player.playPrev, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                    child: IconButton(
                      tooltip: player.isPlaying ? 'Tạm dừng  Space' : 'Phát  Space',
                      icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 20),
                      onPressed: player.togglePlay,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  IconButton(tooltip: nextTooltip, icon: Icon(Icons.skip_next, color: AppColors.text), onPressed: player.playNext, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
