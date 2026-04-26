import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/player.dart';
import 'full_player.dart';

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
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: LinearProgressIndicator(
              value: player.progress,
              minHeight: 3,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          InkWell(
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder(
                opaque: false,
                barrierColor: Colors.black54,
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
                        : Container(width: 44, height: 44, color: AppColors.surfaceLight, child: const Icon(Icons.music_note, size: 16, color: AppColors.textMuted)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(song['title'] ?? '', style: AppText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (artistText.isNotEmpty) Text(artistText, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.skip_previous, color: AppColors.text), onPressed: player.playPrev, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  Container(
                    width: 36, height: 36,
                    decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                    child: IconButton(
                      icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 20),
                      onPressed: player.togglePlay,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.skip_next, color: AppColors.text), onPressed: player.playNext, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
