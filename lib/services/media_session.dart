import 'dart:io' show File, Platform;
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'player.dart';

/// Lock-screen / Control Center "Now Playing" card (cover, title, artist,
/// play-pause, previous/next, scrubbing) on iOS and macOS, and the media
/// notification + lock-screen controls on Android.
///
/// audio_service only mirrors state here: PlayerProvider keeps owning the
/// AudioPlayer and the queue, and the system buttons call straight back
/// into it, so next/prev follow the app's own queue (shuffle, repeat,
/// auto-refill) instead of a separate playlist.
///
/// Android relies on MainActivity extending AudioServiceActivity and the
/// AudioService/MediaButtonReceiver entries in AndroidManifest.xml.
class MediaSession extends BaseAudioHandler with SeekHandler {
  PlayerProvider? _player;
  String? _itemId;
  /// The app icon as a local file: the lock-screen cover for songs
  /// without a picture (the system only takes a URI, not an asset).
  Uri? _logo;
  /// Covers cut square (cover URL → local file): iOS shows the picture at
  /// its own ratio, so a wide photo became a short strip on the lock screen.
  final _square = <String, Uri>{};

  static MediaSession? _instance;

  static bool get supported => !kIsWeb && (Platform.isIOS || Platform.isMacOS || Platform.isAndroid);

  /// Call once before runApp. Never throws: without the session the app
  /// still plays, it just has no lock-screen card.
  static Future<void> init() async {
    if (!supported) return;
    try {
      _instance = await AudioService.init(
        builder: () => MediaSession(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'net.bcdcnt.music.playback',
          androidNotificationChannelName: 'Phát nhạc',
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (_) {
      _instance = null;
    }
    _instance?._loadLogo();
  }

  Future<void> _loadLogo() async {
    try {
      // Rewrite every launch: an older copy (black logo) must not outlive
      // an icon change.
      final f = File('${(await getApplicationSupportDirectory()).path}/now_playing_logo.png');
      final b = await rootBundle.load('assets/app_icon.png');
      await f.writeAsBytes(b.buffer.asUint8List(), flush: true);
      _logo = f.uri;
      // A song without a cover may already be showing.
      _itemId = null;
      _sync();
    } catch (_) {}
  }

  /// Fetch the cover, keep its centre square (600 px) as a PNG, then swap
  /// it into the card if that song is still the one showing.
  Future<void> _cutSquare(String url, String id) async {
    _square[url] = Uri.parse(url); // once per cover, even if it fails
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return;
      final img = (await (await ui.instantiateImageCodec(res.bodyBytes)).getNextFrame()).image;
      final side = img.width < img.height ? img.width : img.height;
      final src = ui.Rect.fromLTWH((img.width - side) / 2, (img.height - side) / 2, side.toDouble(), side.toDouble());
      const out = 600.0;
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawImageRect(img, src, const ui.Rect.fromLTWH(0, 0, out, out), ui.Paint()..filterQuality = ui.FilterQuality.high);
      final sq = await rec.endRecording().toImage(out.toInt(), out.toInt());
      final png = await sq.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return;
      final f = File('${(await getTemporaryDirectory()).path}/now_playing_${url.hashCode.toUnsigned(32)}.png');
      await f.writeAsBytes(png.buffer.asUint8List(), flush: true);
      _square[url] = f.uri;
      final item = mediaItem.value;
      if (item != null && item.id == id) mediaItem.add(item.copyWith(artUri: f.uri));
    } catch (_) {}
  }

  /// Wire the provider in once it exists (it lives in the widget tree).
  static void bind(PlayerProvider player) {
    final s = _instance;
    if (s == null || s._player == player) return;
    s._player = player;
    player.addListener(s._sync);
    s._sync();
  }

  void _sync() {
    final p = _player;
    if (p == null) return;
    final song = p.currentSong;
    if (song == null) {
      playbackState.add(PlaybackState(processingState: AudioProcessingState.idle, playing: false));
      return;
    }

    final id = song['id']?.toString() ?? '';
    final duration = p.duration > Duration.zero ? p.duration : null;
    if (id != _itemId || mediaItem.value?.duration != duration) {
      _itemId = id;
      final artists = song['artists'] is List ? song['artists'] : (song['artists']?['data'] ?? []);
      var artistText = (artists as List).map((a) => a['title'] ?? a['username'] ?? '').where((s) => s.toString().isNotEmpty).join(', ');
      // No singer listed: the composer, so the card never shows a bare title.
      if (artistText.isEmpty) {
        final comps = song['sheet']?['composers']?['data'];
        if (comps is List) artistText = comps.map((c) => c['title'] ?? '').where((s) => s.toString().isNotEmpty && s != 'Đang cập nhật').join(', ');
      }
      final thumb = song['thumbnail']?['url']?.toString();
      final hasThumb = thumb != null && thumb.isNotEmpty;
      final art = hasThumb ? (_square[thumb] ?? Uri.tryParse(thumb)) : _logo;
      if (hasThumb && !_square.containsKey(thumb)) _cutSquare(thumb, id);
      mediaItem.add(MediaItem(
        id: id,
        title: (song['title'] ?? '').toString(),
        artist: artistText.isEmpty ? null : artistText,
        album: p.sourceLabel ?? 'BCĐCNT',
        artUri: art,
        duration: duration,
      ));
    }

    final hasPrev = p.currentIndex > 0 || p.position > const Duration(seconds: 3);
    final hasNext = p.queue.length > p.currentIndex + 1;
    playbackState.add(PlaybackState(
      controls: [
        if (hasPrev) MediaControl.skipToPrevious,
        p.isPlaying ? MediaControl.pause : MediaControl.play,
        if (hasNext) MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.skipToNext, MediaAction.skipToPrevious, MediaAction.playPause},
      androidCompactActionIndices: [for (var i = 0; i < (hasPrev ? 1 : 0) + 1 + (hasNext ? 1 : 0); i++) i],
      processingState: AudioProcessingState.ready,
      playing: p.isPlaying,
      // The system extrapolates from position + speed, so syncing on
      // play/pause/seek/song change (not every tick) keeps it in step.
      updatePosition: p.position,
      speed: p.playbackRate,
    ));
  }

  @override
  Future<void> play() async {
    final p = _player;
    if (p != null && !p.isPlaying) await p.togglePlay();
  }

  @override
  Future<void> pause() async {
    final p = _player;
    if (p != null && p.isPlaying) await p.togglePlay();
  }

  @override
  Future<void> skipToNext() async => _player?.playNext();

  @override
  Future<void> skipToPrevious() async => _player?.playPrev();

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
    _sync();
  }

  @override
  Future<void> stop() async => pause();
}
