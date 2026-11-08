import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/theme.dart';
import '../services/imgcdn.dart';

/// A playlist's cover: its own picture, else the first four songs' pictures
/// in a 2×2 grid (one song: that picture), else a music icon.
class PlaylistCover extends StatelessWidget {
  final String? thumb;
  final List<String> songThumbs;
  final double size;
  final double radius;
  const PlaylistCover({super.key, this.thumb, this.songThumbs = const [], required this.size, this.radius = 12});

  /// The pictures of the first songs in `items { data { object { thumbnail } } }`.
  static List<String> thumbsOf(dynamic items) => [
        for (final e in ((items?['data'] ?? const []) as List))
          if (e is Map && e['object']?['thumbnail']?['url'] != null) e['object']['thumbnail']['url'].toString(),
      ];

  @override
  Widget build(BuildContext context) {
    final px = (size * 2).round();
    Widget pic(String url, double s) => CachedNetworkImage(
          imageUrl: cdnImg(url, s * 2 > 160 ? 640 : 160),
          width: s, height: s, fit: BoxFit.cover,
          errorWidget: (_, _, _) => Container(width: s, height: s, color: AppColors.surfaceLight),
        );
    final Widget child;
    if (thumb != null && thumb!.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: cdnImg(thumb!, px > 160 ? 640 : 160),
        width: size, height: size, fit: BoxFit.cover,
        errorWidget: (_, _, _) => _empty(),
      );
    } else if (songThumbs.length >= 4) {
      final h = size / 2;
      child = SizedBox(
        width: size, height: size,
        child: Column(children: [
          Row(children: [pic(songThumbs[0], h), pic(songThumbs[1], h)]),
          Row(children: [pic(songThumbs[2], h), pic(songThumbs[3], h)]),
        ]),
      );
    } else if (songThumbs.isNotEmpty) {
      child = pic(songThumbs.first, size);
    } else {
      child = _empty();
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }

  Widget _empty() => Container(
        width: size, height: size, color: AppColors.surface,
        child: Icon(Icons.queue_music_rounded, color: AppColors.textMuted, size: size * 0.45),
      );
}
