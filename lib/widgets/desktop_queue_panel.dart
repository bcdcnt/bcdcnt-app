import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/player.dart';

/// Right-docked queue panel — Spotify desktop equivalent of the Now Playing
/// queue button. Lists the current PlayerProvider queue, highlights the
/// active track, and lets users jump to any item by tapping.
class DesktopQueuePanel extends StatelessWidget {
  /// When `true`, renders only the body (skips the chrome — surrounding
  /// container, width, and the "Danh sách phát" title row). Used inside
  /// the unified right-panel container in DesktopShell, which provides its
  /// own header.
  final bool embedded;
  const DesktopQueuePanel({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final queue = player.queue;
    final current = player.currentSong;

    final col = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                Text('Danh sách phát', style: display(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text))),
                const Spacer(),
                if (queue.isNotEmpty)
                  Text('${queue.length} bài', style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
              ],
            ),
          ),
        if (current != null) _NowPlayingBlock(song: current),
        Divider(height: 1, color: AppColors.borderSubtle),
        if (queue.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Text('Chưa có bài nào trong danh sách', style: body(TextStyle(color: AppColors.textMuted, fontSize: 12)), textAlign: TextAlign.center),
            ),
          )
        else
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
              buildDefaultDragHandles: false,
              itemCount: queue.length,
              onReorder: (oldIndex, newIndex) => player.reorderQueue(oldIndex, newIndex),
              proxyDecorator: (child, _, _) => Material(
                color: Colors.transparent,
                elevation: 6,
                shadowColor: Colors.black.withValues(alpha: 0.4),
                child: child,
              ),
              itemBuilder: (_, i) {
                final s = queue[i];
                final isActive = i == player.currentIndex;
                return _QueueRow(
                  key: ValueKey('q-${s['id']}-$i'),
                  song: s,
                  index: i,
                  active: isActive,
                  onTap: () => player.playAtIndex(i),
                );
              },
            ),
          ),
      ],
    );

    if (embedded) return col;
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: col,
    );
  }
}

class _NowPlayingBlock extends StatelessWidget {
  final Map<String, dynamic> song;
  const _NowPlayingBlock({required this.song});

  @override
  Widget build(BuildContext context) {
    final thumb = song['thumbnail']?['url'];
    final artists = song['artists'] is List ? song['artists'] : (song['artists']?['data'] ?? []);
    final artistText = (artists as List).map((a) => a['title'] ?? '').join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: thumb != null
                ? CachedNetworkImage(imageUrl: thumb, width: 56, height: 56, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(width: 56, height: 56, color: AppColors.surfaceLight))
                : Container(width: 56, height: 56, color: AppColors.surfaceLight, child: Icon(Icons.music_note, size: 24, color: AppColors.textMuted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ĐANG PHÁT',
                  style: body(TextStyle(fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: AppColors.accentLight)),
                ),
                const SizedBox(height: 4),
                Text(
                  song['title']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
                ),
                if (artistText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    artistText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final Map<String, dynamic> song;
  final int index;
  final bool active;
  final VoidCallback onTap;
  const _QueueRow({super.key, required this.song, required this.index, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumb = song['thumbnail']?['url'];
    final artists = song['artists'] is List ? song['artists'] : (song['artists']?['data'] ?? []);
    final artistText = (artists as List).map((a) => a['title'] ?? '').join(', ');
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.accentSoft : Colors.transparent,
          border: Border(
            left: BorderSide(color: active ? AppColors.accent : Colors.transparent, width: 3),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Center(
                child: active
                    ? Icon(Icons.graphic_eq, size: 13, color: AppColors.accentLight)
                    : Text('${index + 1}', style: body(TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
              ),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: thumb != null
                  ? CachedNetworkImage(imageUrl: thumb, width: 32, height: 32, fit: BoxFit.cover)
                  : Container(width: 32, height: 32, color: AppColors.surface, child: Icon(Icons.music_note, size: 14, color: AppColors.textMuted)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song['title']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? AppColors.accentLight : AppColors.text)),
                  ),
                  if (artistText.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      artistText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    ),
                  ],
                ],
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.drag_indicator, size: 16, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
