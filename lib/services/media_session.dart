import 'dart:io' show Platform;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
      final artistText = (artists as List).map((a) => a['title'] ?? a['username'] ?? '').where((s) => s.toString().isNotEmpty).join(', ');
      final thumb = song['thumbnail']?['url']?.toString();
      mediaItem.add(MediaItem(
        id: id,
        title: (song['title'] ?? '').toString(),
        artist: artistText.isEmpty ? null : artistText,
        album: p.sourceLabel ?? 'BCĐCNT',
        artUri: thumb != null ? Uri.tryParse(thumb) : null,
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
