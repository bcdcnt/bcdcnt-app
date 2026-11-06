import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/share.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../services/auth.dart';
import '../services/offline_store.dart';
import 'hover_effects.dart';
import 'playlist_dialog.dart';
import 'synced_video.dart';

bool _hasAudio(Map s) => (s['file']?['audio_url'] ?? s['audioUrl']) != null;

/// Tap on a song anywhere in the app: play it with [list] as the queue.
/// Video-only items have no audio track, so those open the song page.
void playOrOpen(BuildContext context, Map<String, dynamic> song, List<Map<String, dynamic>> list, [String? label]) {
  if (!_hasAudio(song)) {
    context.push('/song/${song['id']}', extra: song);
    return;
  }
  final queue = list.where(_hasAudio).map((s) {
    final m = Map<String, dynamic>.from(s);
    m['audioUrl'] ??= m['file']?['audio_url'];
    return m;
  }).toList();
  final m = Map<String, dynamic>.from(song);
  m['audioUrl'] ??= m['file']?['audio_url'];
  context.read<PlayerProvider>().playSong(m, queue.isEmpty ? [m] : queue, 'manual', label);
}

List<Map> _people(dynamic v) => (v is List ? v : (v?['data'] ?? [])).whereType<Map>().toList();

/// Names to show under a title, without the "Đang cập nhật" placeholder.
String songByline(Map song, {bool withComposer = false}) {
  bool ok(dynamic n) => n != null && n.toString().isNotEmpty && n != 'Đang cập nhật';
  final artists = _people(song['artists']).map((a) => a['title'] ?? a['username']).where(ok).join(', ');
  if (!withComposer) return artists;
  final comps = _people(song['composers']).isNotEmpty ? _people(song['composers']) : _people(song['sheet']?['composers']);
  final c = comps.map((a) => a['title']).where(ok).join(', ');
  return [c, artists].where((x) => x.isNotEmpty).join(' · ');
}

/// Generated cover for songs without artwork: brand-red gradient with the
/// title's first letter, so lists never show empty grey boxes.
class GeneratedCover extends StatelessWidget {
  final String title;
  final double size;
  final double radius;
  const GeneratedCover({super.key, required this.title, required this.size, this.radius = 12});

  static const _tones = [Color(0xFF711313), Color(0xFF8C3B3A), Color(0xFF5A1D1D), Color(0xFF9C5E5C), Color(0xFF3B0F0F)];

  @override
  Widget build(BuildContext context) {
    final t = title.trim();
    final letter = t.isEmpty ? 'B' : t.characters.first.toUpperCase();
    final tone = _tones[t.hashCode.abs() % _tones.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tone, const Color(0xFF1B0909)]),
      ),
      padding: EdgeInsets.all(size > 90 ? 12 : 0),
      child: size > 90
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('BCĐCNT', style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Color(0xCCFFFFFF)))),
                Text(letter, style: display(TextStyle(fontSize: size * 0.3, fontWeight: FontWeight.w800, color: Colors.white, height: 1))),
              ],
            )
          : Center(child: Text(letter, style: display(TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, color: Colors.white, height: 1)))),
    );
  }
}

/// Song artwork with the generated cover as fallback.
class SongCover extends StatelessWidget {
  final Map song;
  final double size;
  final double radius;
  const SongCover({super.key, required this.song, this.size = 52, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final thumb = song['thumbnail']?['url']?.toString();
    final fallback = GeneratedCover(title: (song['title'] ?? '').toString(), size: size, radius: radius);
    if (thumb == null || thumb.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: cdnImgFor(thumb, size),
        width: size,
        height: size,
        memCacheWidth: (size * 3).round(),
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(width: size, height: size, color: AppColors.surfaceLight),
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}

/// Animated equalizer bars for the row that is playing.
class NowPlayingBars extends StatefulWidget {
  final Color color;
  final bool animate;
  const NowPlayingBars({super.key, required this.color, this.animate = true});
  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat(reverse: true);
  }
  @override
  void didUpdateWidget(NowPlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.animate && _c.isAnimating) _c.stop();
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final v = _c.value;
          final hs = [0.45 + 0.55 * v, 1 - 0.6 * v, 0.6 + 0.4 * (1 - v)];
          return SizedBox(
            width: 14,
            height: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [for (final h in hs) Container(width: 3, height: 12 * h, decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(1)))],
            ),
          );
        },
      );
}

class SongRow extends StatelessWidget {
  final Map<String, dynamic> song;
  final int? index;
  final bool showIndex;
  /// Forces the playing style; otherwise the row checks the player itself.
  final bool isPlaying;
  /// Overrides the default tap (play with [queue]). Kept for the few
  /// surfaces that need something else.
  final VoidCallback? onTap;
  /// The list this row belongs to — becomes the play queue on tap.
  final List<Map<String, dynamic>>? queue;
  /// Shown in the player header ("Đang phát từ …").
  final String? sourceLabel;
  // Drives the metric appended to the subtitle. Defaults to listens.
  // Set to 'likes' / 'downloads' / 'time' to mirror the active sort tab.
  final String metricKey;
  /// Chart movement: previous rank (from `prev_rank`). With [index] it
  /// draws ▲n / ▼n, or "MỚI" when [chartNew] (not charted last period).
  final int? prevRank;
  final bool chartNew;

  const SongRow({
    super.key,
    required this.song,
    this.index,
    this.showIndex = false,
    this.isPlaying = false,
    this.onTap,
    this.queue,
    this.sourceLabel,
    this.metricKey = 'views',
    this.prevRank,
    this.chartNew = false,
  });

  String? _metric() {
    switch (metricKey) {
      case 'none':
        return null;
      case 'likes': {
        final n = song['likes'];
        return n is num && n > 0 ? '${formatViews(n.toInt())} lượt thích' : null;
      }
      case 'downloads': {
        final n = song['downloads'];
        return n is num && n > 0 ? '${formatViews(n.toInt())} lượt tải' : null;
      }
      case 'time':
      case 'newest': {
        final s = timeago(song['created_at']?.toString());
        return s.isEmpty ? null : s;
      }
      case 'views':
      default: {
        final v = song['weeklyListens'] ?? song['views'] ?? 0;
        return v is num && v > 0 ? '${formatViews(v.toInt())} lượt nghe' : null;
      }
    }
  }

  void _tap(BuildContext context) {
    HapticFeedback.selectionClick();
    if (onTap != null) {
      onTap!();
      return;
    }
    playOrOpen(context, song, queue ?? [song], sourceLabel);
  }

  @override
  Widget build(BuildContext context) {
    final id = song['id']?.toString();
    final current = context.select<PlayerProvider, String?>((p) => p.currentSong?['id']?.toString());
    final playerPlaying = context.select<PlayerProvider, bool>((p) => p.isPlaying);
    final playing = isPlaying || (id != null && id == current);
    final byline = songByline(song);
    final metric = _metric();
    final sub = [byline, if (metric != null) metric].where((s) => s.isNotEmpty).join(' · ');
    final hi = AppColors.accentLight;

    return Semantics(
      // VoiceOver/TalkBack read the row as one item instead of title,
      // byline and a nameless button separately.
      label: [song['title'] ?? '', sub, if (playing) 'đang phát'].where((e) => '$e'.isNotEmpty).join(', '),
      hint: 'Chạm để nghe, nhấn giữ để xem thêm',
      button: true,
      child: HoverHighlight(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onSecondaryTapDown: (d) => showSongActions(context, song),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          showSongActions(context, song);
        },
        child: InkWell(
          onTap: () => _tap(context),
          borderRadius: BorderRadius.circular(12),
          // HoverHighlight already paints the hover fill; suppress the Material
          // ink overlay so the two don't stack into a too-dark band.
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
              child: Row(
                children: [
                  if (showIndex) ...[
                    SizedBox(
                      width: 40,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(index ?? 0) + 1}',
                            textAlign: TextAlign.center,
                            style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: hi, fontFeatures: const [FontFeature.tabularFigures()])),
                          ),
                          if (chartNew)
                            Text('MỚI', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1F7A45))))
                          else if (prevRank != null && prevRank != (index ?? 0) + 1)
                            Builder(builder: (_) {
                              final move = prevRank! - ((index ?? 0) + 1);
                              // One line, shrunk to fit the rank column ("▲99+" used
                              // to wrap its "+" onto a second line).
                              return FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${move > 0 ? '▲' : '▼'}${move.abs() > 99 ? '99+' : move.abs()}',
                                  maxLines: 1,
                                  softWrap: false,
                                  style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: move > 0 ? const Color(0xFF1F7A45) : AppColors.error)),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Stack(children: [
                    SongCover(song: song, size: 52),
                    if (isVideoSong(song))
                      const Positioned(left: 3, bottom: 3, child: Icon(Icons.play_circle_fill_rounded, size: 16, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                  ]),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (playing) ...[NowPlayingBars(color: hi, animate: playerPlaying), const SizedBox(width: 7)],
                            Expanded(
                              child: Text(
                                song['title'] ?? '',
                                style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: playing ? hi : AppColors.text)),
                                // Large text: let long titles wrap rather than
                                // cut to "Bài ca cho…".
                                maxLines: MediaQuery.textScalerOf(context).scale(10) > 11 ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(sub, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tuỳ chọn cho ${song['title'] ?? 'bài hát'}',
                    onPressed: () => showSongActions(context, song),
                    icon: Icon(Icons.more_vert_rounded, color: AppColors.textMuted, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Bottom sheet with every secondary action for a song. Opened from the ⋮
/// button on any song row, long-press, or right-click on desktop.
Future<void> showSongActions(BuildContext context, Map<String, dynamic> song) async {
  final artists = _people(song['artists']);
  final comps = _people(song['composers']).isNotEmpty ? _people(song['composers']) : _people(song['sheet']?['composers']);
  final artist = artists.where((a) => a['slug'] != null && a['title'] != 'Đang cập nhật').firstOrNull;
  final composer = comps.where((a) => a['slug'] != null).firstOrNull;
  final fileType = songKind(song);
  final player = context.read<PlayerProvider>();
  final hasAudio = _hasAudio(song);
  final m = Map<String, dynamic>.from(song);
  m['audioUrl'] ??= m['file']?['audio_url'];

  final choice = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    builder: (ctx) {
      Widget item(String value, IconData icon, String label) => InkWell(
            onTap: () => Navigator.pop(ctx, value),
            child: SizedBox(
              height: 56,
              child: Row(children: [
                const SizedBox(width: 22),
                Icon(icon, size: 24, color: AppColors.textSecondary),
                const SizedBox(width: 16),
                Expanded(child: Text(label, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 20),
              ]),
            ),
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 5, decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(3))),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  SongCover(song: song, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(song['title'] ?? '', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (songByline(song, withComposer: true).isNotEmpty)
                        Text(songByline(song, withComposer: true), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.border),
              const SizedBox(height: 6),
              if (hasAudio) item('next', Icons.playlist_play_rounded, 'Phát tiếp theo'),
              if (hasAudio) item('queue', Icons.queue_music_rounded, 'Thêm vào danh sách phát'),
              item('playlist', Icons.playlist_add_rounded, 'Thêm vào playlist'),
              if (hasAudio)
                OfflineStore.instance.isSaved(song)
                    ? item('unsave', Icons.download_done_rounded, 'Xoá khỏi "Đã tải về"')
                    : item('save', Icons.download_for_offline_outlined, 'Tải về để nghe offline'),
              item('detail', Icons.info_outline_rounded, 'Xem trang bài hát'),
              if (composer != null) item('composer', Icons.edit_note_rounded, 'Đến nhạc sĩ ${composer['title']}'),
              if (artist != null) item('artist', Icons.person_outline_rounded, 'Đến ${fileType == 'karaoke' ? 'thành viên' : 'ca sĩ'} ${artist['title'] ?? artist['username'] ?? ''}'),
              item('share', Icons.ios_share_rounded, 'Chia sẻ (Zalo, Facebook…)'),
            ],
          ),
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void toast(String s) => messenger?.showSnackBar(SnackBar(content: Text(s), duration: const Duration(seconds: 2)));
  switch (choice) {
    case 'next':
      if (player.currentSong == null) {
        player.playSong(m, [m], 'manual');
        break;
      }
      final q = List<Map<String, dynamic>>.from(player.queue)..removeWhere((s) => s['id'].toString() == m['id'].toString());
      final at = q.indexWhere((s) => s['id'].toString() == player.currentSong!['id'].toString());
      q.insert(at < 0 ? q.length : at + 1, m);
      player.setQueue(q);
      toast('Sẽ phát "${song['title']}" tiếp theo');
      break;
    case 'queue':
      if (player.currentSong == null) {
        player.playSong(m, [m], 'manual');
        break;
      }
      if (!player.queue.any((s) => s['id'].toString() == m['id'].toString())) player.setQueue([...player.queue, m]);
      toast('Đã thêm "${song['title']}" vào danh sách phát');
      break;
    case 'playlist':
      showDialog(context: context, builder: (_) => PlaylistDialog(songId: song['id'].toString(), type: fileType));
      break;
    case 'save':
      saveForOffline(context, song);
      break;
    case 'unsave':
      await OfflineStore.instance.remove(song);
      toast('Đã xoá "${song['title']}" khỏi máy');
      break;
    case 'detail':
      context.push('/song/${song['id']}', extra: Map<String, dynamic>.from(song));
      break;
    case 'composer':
      context.push('/nhac-si/${composer!['slug']}');
      break;
    case 'artist':
      if (fileType == 'karaoke' && artist!['id'] != null) {
        context.push('/user/${artist['id']}');
      } else {
        context.push('/nghe-si/${artist!['slug']}');
      }
      break;
    case 'share':
      if (context.mounted) await shareText(context, text: songShareText(song), subject: song['title']?.toString());
      break;
  }
}

/// Normalises a raw GraphQL list into song maps for [SongRow.queue].
List<Map<String, dynamic>> asSongList(dynamic list) =>
    ((list ?? []) as Iterable).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();


/// Saves [song] to "Đã tải về" with snackbar feedback.
Future<void> saveForOffline(BuildContext context, Map<String, dynamic> song) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final auth = context.read<AuthProvider>();
  messenger?.showSnackBar(SnackBar(content: Text('Đang tải "${song['title']}"…'), duration: const Duration(seconds: 2)));
  final err = await OfflineStore.instance.download(song, auth);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    content: Text(err ?? 'Đã tải về máy: nghe được cả khi không có mạng'),
    duration: const Duration(seconds: 3),
  ));
}
