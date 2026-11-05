import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../services/player.dart';
import '../constants/theme.dart';

/// True for songs published as video (play_type = video) that have an mp4.
bool isVideoSong(Map? song) =>
    song != null &&
    song['play_type']?.toString() == 'video' &&
    (song['file']?['video_url']?.toString().isNotEmpty ?? false);

/// The picture of a video song, kept in step with the music player.
///
/// Sound always comes from PlayerProvider (the song's mp3, same length as
/// the mp4), so it keeps playing with the screen off and shows on the lock
/// screen like any song. This widget plays the mp4 muted on top: it follows
/// play/pause, re-seeks when it drifts more than 350 ms, and catches up when
/// the app comes back to the foreground.
class SyncedVideo extends StatefulWidget {
  final PlayerProvider player;
  final Map song;
  final BoxFit fit;
  const SyncedVideo({super.key, required this.player, required this.song, this.fit = BoxFit.contain});

  @override
  State<SyncedVideo> createState() => _SyncedVideoState();
}

class _SyncedVideoState extends State<SyncedVideo> with WidgetsBindingObserver {
  VideoPlayerController? _vc;
  bool _ready = false;
  // Screen off / app in background: sound continues on the music player,
  // the picture rests (nobody sees it, saves battery) until we're back.
  bool _foreground = true;
  DateTime _lastSeek = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
    widget.player.positionNotifier.addListener(_sync);
    widget.player.addListener(_sync);
  }

  @override
  void didUpdateWidget(SyncedVideo old) {
    super.didUpdateWidget(old);
    if (old.song['id'] != widget.song['id']) {
      _close();
      _open();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.player.positionNotifier.removeListener(_sync);
    widget.player.removeListener(_sync);
    _close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _sync(force: true);
    } else {
      _vc?.pause();
    }
  }

  Future<void> _open() async {
    final url = widget.song['file']?['video_url']?.toString();
    if (url == null || url.isEmpty) return;
    // mixWithOthers: don't take over the audio session the music player owns.
    final vc = VideoPlayerController.networkUrl(Uri.parse(url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _vc = vc;
    try {
      await vc.initialize();
      await vc.setVolume(0);
      if (!mounted || _vc != vc) {
        vc.dispose();
        return;
      }
      setState(() => _ready = true);
      _sync(force: true);
    } catch (_) {}
  }

  void _close() {
    final vc = _vc;
    _vc = null;
    _ready = false;
    vc?.dispose();
  }

  void _sync({bool force = false}) {
    final vc = _vc;
    if (vc == null || !_ready || !mounted || !_foreground) return;
    final p = widget.player;
    if (p.currentSong?['id']?.toString() != widget.song['id']?.toString()) {
      if (vc.value.isPlaying) vc.pause();
      return;
    }
    if (p.isPlaying && !vc.value.isPlaying) vc.play();
    if (!p.isPlaying && vc.value.isPlaying) vc.pause();
    final diff = (vc.value.position - p.position).inMilliseconds.abs();
    final sinceSeek = DateTime.now().difference(_lastSeek).inMilliseconds;
    if ((force || diff > 350) && sinceSeek > 800) {
      _lastSeek = DateTime.now();
      vc.seekTo(p.position);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vc = _vc;
    if (vc == null || !_ready) {
      return const ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2)));
    }
    final ar = vc.value.aspectRatio;
    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: widget.fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: vc.value.size.width > 0 ? vc.value.size.width : 1600,
          height: vc.value.size.height > 0 ? vc.value.size.height : 1600 / ((ar.isFinite && ar > 0) ? ar : 16 / 9),
          child: VideoPlayer(vc),
        ),
      ),
    );
  }
}

/// Full-screen picture for a video song (turn the phone for landscape). Sound stays on
/// the music player, so leaving this screen doesn't interrupt anything.
Future<void> openFullScreenVideo(BuildContext context, PlayerProvider player, Map song) async {
  await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    opaque: true,
    pageBuilder: (_, __, ___) => _FullScreenVideo(player: player, song: song),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _FullScreenVideo extends StatelessWidget {
  final PlayerProvider player;
  final Map song;
  const _FullScreenVideo({required this.player, required this.song});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: player.togglePlay,
            child: Stack(children: [
              Positioned.fill(child: SyncedVideo(player: player, song: song)),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    tooltip: 'Thu nhỏ',
                    iconSize: 30,
                    icon: const Icon(Icons.close_fullscreen_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ListenableBuilder(
                      listenable: player,
                      builder: (_, __) => Icon(player.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, size: 56, color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// Small "VIDEO" badge for covers of video songs.
class VideoBadge extends StatelessWidget {
  const VideoBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.play_circle_outline_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 3),
          Text('VIDEO', style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5))),
        ]),
      );
}
