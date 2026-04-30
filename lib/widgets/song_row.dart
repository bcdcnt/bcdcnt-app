import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import 'hover_effects.dart';
import 'playlist_dialog.dart';

class SongRow extends StatelessWidget {
  final Map<String, dynamic> song;
  final int? index;
  final bool showIndex;
  final bool isPlaying;
  final VoidCallback? onTap;

  const SongRow({super.key, required this.song, this.index, this.showIndex = false, this.isPlaying = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final artists = song['artists'] is List ? song['artists'] : (song['artists']?['data'] ?? []);
    final artistText = (artists as List).map((a) => a['title'] ?? a['username'] ?? '').join(', ');
    final thumb = song['thumbnail']?['url'];
    final views = song['weeklyListens'] ?? song['views'] ?? 0;

    return HoverHighlight(
      borderRadius: BorderRadius.zero,
      child: GestureDetector(
        onSecondaryTapDown: (d) => _showContextMenu(context, d.globalPosition),
        child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderSubtle, width: 1)),
          ),
        child: Row(
          children: [
            if (showIndex)
              SizedBox(width: 22, child: Text('${(index ?? 0) + 1}', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isPlaying ? AppColors.accent : AppColors.textMuted))),
            if (showIndex) const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: thumb != null
                  ? CachedNetworkImage(imageUrl: thumb, width: 48, height: 48, fit: BoxFit.cover, placeholder: (_, __) => Container(width: 48, height: 48, color: AppColors.surfaceLight))
                  : Container(width: 48, height: 48, color: AppColors.surfaceLight, child: const Icon(Icons.music_note, color: AppColors.textMuted, size: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(song['title'] ?? '', style: AppText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (artistText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(artistText, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            if (views > 0) ...[
              const SizedBox(width: 8),
              const Icon(Icons.headphones, size: 11, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(formatViews(views), style: AppText.caption),
            ],
          ],
        ),
        ),
      ),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset pos) async {
    final firstArtist = (song['artists'] is List
        ? (song['artists'] as List)
        : ((song['artists']?['data'] ?? []) as List));
    final hasArtist = firstArtist.isNotEmpty && firstArtist.first is Map && firstArtist.first['slug'] != null;
    final fileType = (song['file_type'] ?? 'song').toString();
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      items: [
        _menuItem('play',     Icons.play_arrow,        'Phát'),
        _menuItem('queue',    Icons.playlist_play,     'Thêm vào hàng đợi'),
        _menuItem('playlist', Icons.playlist_add,      'Thêm vào playlist...'),
        const PopupMenuDivider(),
        _menuItem('detail',   Icons.info_outline,      'Mở chi tiết'),
        if (hasArtist)
          _menuItem('artist', Icons.person_outline,    'Đến nghệ sĩ'),
      ],
    );
    if (selected == null || !context.mounted) return;
    switch (selected) {
      case 'play':
        if (onTap != null) onTap!();
        break;
      case 'queue':
        // Append to queue without interrupting current playback.
        final player = context.read<PlayerProvider>();
        if (player.queue.where((s) => s['id'].toString() == song['id'].toString()).isEmpty) {
          player.setQueue([...player.queue, Map<String, dynamic>.from(song)]);
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã thêm "${song['title']}" vào hàng đợi'), duration: const Duration(seconds: 2)));
        break;
      case 'playlist':
        showDialog(context: context, builder: (_) => PlaylistDialog(songId: song['id'].toString(), type: fileType));
        break;
      case 'detail':
        context.push('/song/${song['id']}', extra: Map<String, dynamic>.from(song));
        break;
      case 'artist':
        final a = firstArtist.first as Map;
        if (fileType == 'karaoke' && a['id'] != null) {
          context.push('/user/${a['id']}');
        } else if (a['slug'] != null) {
          context.push('/nghe-si/${a['slug']}');
        }
        break;
    }
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      height: 38,
      child: Row(children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Text(label, style: body(const TextStyle(fontSize: 13, color: AppColors.text))),
      ]),
    );
  }
}
