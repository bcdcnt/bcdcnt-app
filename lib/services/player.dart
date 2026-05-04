import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'play_tracker.dart';

enum PlayerRepeatMode { off, all, one }

typedef FetchMoreFn = Future<List<Map<String, dynamic>>> Function(List<Map<String, dynamic>> currentQueue);

/// Optional callback invoked when shuffle/repeat changes so the host app
/// can persist the change (e.g. via the updateMe GraphQL mutation).
typedef OnPlayerSettingChanged = Future<void> Function(String key, Object value);

class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  Map<String, dynamic>? _currentSong;
  List<Map<String, dynamic>> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _shuffle = false;
  PlayerRepeatMode _repeat = PlayerRepeatMode.off;
  double _volume = 1.0;
  bool _muted = false;
  double _playbackRate = 1.0;
  FetchMoreFn? _fetchMore;
  bool _isFetchingMore = false;
  OnPlayerSettingChanged? _onSettingChanged;
  // Track which user's settings we've already applied so we don't re-apply
  // (and re-trigger sync to server) on every notifyListeners.
  String? _appliedForUserId;
  PlayTracker? _tracker;
  // Sleep timer — either a fixed duration timer (5/10/15/30/60 min) or the
  // sentinel "end of current song" mode (we wait for natural song completion
  // and pause instead of advancing). UI binds to these getters.
  Timer? _sleepTimer;
  DateTime? _sleepFiresAt;
  bool _sleepEndOfSong = false;

  Map<String, dynamic>? get currentSong => _currentSong;
  List<Map<String, dynamic>> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get progress => _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0;
  bool get shuffle => _shuffle;
  PlayerRepeatMode get repeat => _repeat;
  double get volume => _volume;
  bool get muted => _muted;
  double get playbackRate => _playbackRate;
  bool get hasSleepTimer => _sleepTimer != null || _sleepEndOfSong;
  bool get sleepEndOfSong => _sleepEndOfSong;
  // Remaining time on the fixed-duration sleep timer (null when no timer or
  // when in end-of-song mode). UI uses this for the live countdown label.
  Duration? get sleepRemaining {
    if (_sleepFiresAt == null) return null;
    final r = _sleepFiresAt!.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  AudioPlayer get audioPlayer => _player;

  PlayerProvider() {
    _player.playingStream.listen((playing) {
      _isPlaying = playing;
      // Hand pause/resume signals to the play tracker so accumulated time
      // reflects only foreground listening.
      if (playing) {
        _tracker?.onResume();
      } else {
        _tracker?.onPause();
      }
      notifyListeners();
    });
    _player.positionStream.listen((pos) {
      _position = pos;
      _tracker?.onTimeUpdate();
      notifyListeners();
    });
    _player.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      notifyListeners();
    });
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _tracker?.endSession(reason: 'completed');
        _onSongEnded();
      }
    });
  }

  /// Wire the listen-tracker. Called once from the auth bridge on app
  /// start. Pass `null` to disable tracking (e.g. user signed out).
  void setLogListenFn(LogListenFn? fn) {
    _tracker = fn == null ? null : PlayTracker(fn);
  }

  Future<void> _onSongEnded() async {
    // Sleep timer "end of song" mode — pause when this track finishes
    // instead of auto-advancing. Clear the flag once consumed.
    if (_sleepEndOfSong) {
      _sleepEndOfSong = false;
      notifyListeners();
      await _player.pause();
      return;
    }
    if (_repeat == PlayerRepeatMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    if (_queue.isEmpty) return;
    final next = _currentIndex + 1;
    if (next < _queue.length) {
      await playAtIndex(next, source: 'queue');
    } else if (_repeat == PlayerRepeatMode.all) {
      await playAtIndex(0, source: 'queue');
    }
  }

  /// Start a fixed-duration sleep timer. Cancels any previous timer first.
  /// Pass [Duration.zero] / negative to clear.
  void setSleepTimer(Duration d) {
    _sleepTimer?.cancel();
    _sleepEndOfSong = false;
    if (d <= Duration.zero) {
      _sleepTimer = null;
      _sleepFiresAt = null;
      notifyListeners();
      return;
    }
    _sleepFiresAt = DateTime.now().add(d);
    _sleepTimer = Timer(d, () {
      _player.pause();
      _sleepTimer = null;
      _sleepFiresAt = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Sleep at the end of the currently-playing song. No fixed countdown —
  /// `_onSongEnded` consumes the flag and pauses instead of advancing.
  void setSleepEndOfSong(bool on) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepFiresAt = null;
    _sleepEndOfSong = on;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepFiresAt = null;
    _sleepEndOfSong = false;
    notifyListeners();
  }

  Future<void> playSong(Map<String, dynamic> song, [List<Map<String, dynamic>>? list, String source = 'manual']) async {
    _currentSong = song;
    if (list != null) {
      _queue = list;
      _currentIndex = list.indexWhere((s) => s['id'].toString() == song['id'].toString());
      if (_currentIndex < 0) _currentIndex = 0;
    }
    notifyListeners();

    final url = song['audioUrl'] ?? song['file']?['audio_url'];
    if (url == null) return;

    // Begin a tracking session before audio loads so we accumulate time
    // from the very first frame. `source=manual` means the user actively
    // chose to play this song; `queue` is auto-advance; `autoplay` is the
    // (now-removed) detail-page auto-start, which never logs.
    final id = song['id']?.toString();
    final type = (song['file_type'] ?? 'song').toString();
    final dur = (song['file']?['duration'] is num) ? (song['file']['duration'] as num).toDouble() : null;
    if (id != null) {
      _tracker?.startSession(songId: id, objectType: type, songDuration: dur, source: source);
    }

    try {
      await _player.setUrl(url);
      await _player.play();
    } catch (_) {}
    _maybeRefillQueue();
  }

  /// Replace the queue without changing the currently-playing song.
  /// If the current song is in the new queue, sync currentIndex to its position;
  /// otherwise leave the player as-is.
  void setQueue(List<Map<String, dynamic>> list, {int startIndex = 0}) {
    _queue = list;
    if (_currentSong != null) {
      final idx = list.indexWhere((s) => s['id'].toString() == _currentSong!['id'].toString());
      _currentIndex = idx >= 0 ? idx : startIndex.clamp(0, list.isEmpty ? 0 : list.length - 1);
    } else {
      _currentIndex = startIndex.clamp(0, list.isEmpty ? 0 : list.length - 1);
    }
    notifyListeners();
  }

  Future<void> playAtIndex(int index, {String source = 'manual'}) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await playSong(_queue[index], null, source);
    _maybeRefillQueue();
  }

  /// Register a callback to extend the queue when we get near the end.
  /// Passing null disables auto-refill.
  void setFetchMore(FetchMoreFn? fn) {
    _fetchMore = fn;
  }

  /// If we're within 3 songs of the end, fetch more and append.
  Future<void> _maybeRefillQueue() async {
    if (_fetchMore == null || _isFetchingMore || _queue.isEmpty) return;
    if (_currentIndex < _queue.length - 3) return;
    _isFetchingMore = true;
    try {
      final more = await _fetchMore!(List<Map<String, dynamic>>.from(_queue));
      if (more.isEmpty) {
        // No more songs available; drop the callback so we stop trying.
        _fetchMore = null;
      } else {
        // Deduplicate by id against current queue
        final ids = _queue.map((s) => s['id'].toString()).toSet();
        final filtered = more.where((s) => !ids.contains(s['id'].toString())).toList();
        if (filtered.isEmpty) {
          _fetchMore = null;
        } else {
          _queue = [..._queue, ...filtered];
          notifyListeners();
        }
      }
    } catch (_) {
      // Swallow errors; retry on next trigger
    } finally {
      _isFetchingMore = false;
    }
  }

  Future<void> togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> playNext() async {
    if (_queue.isEmpty) return;
    int next;
    if (_shuffle) {
      if (_queue.length <= 1) return;
      final rand = Random();
      do { next = rand.nextInt(_queue.length); } while (next == _currentIndex);
    } else {
      next = _currentIndex + 1;
      if (next >= _queue.length) {
        if (_repeat == PlayerRepeatMode.all) next = 0;
        else return;
      }
    }
    await playAtIndex(next);
  }

  Future<void> playPrev() async {
    if (_queue.isEmpty) return;
    final prev = _currentIndex - 1;
    if (prev >= 0) {
      await playAtIndex(prev);
    }
  }

  Future<void> seek(Duration pos) async {
    await _player.seek(pos);
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    notifyListeners();
    _onSettingChanged?.call('player_shuffle', _shuffle);
  }

  void toggleRepeat() {
    _repeat = PlayerRepeatMode.values[(_repeat.index + 1) % 3];
    notifyListeners();
    _onSettingChanged?.call('player_repeat', _repeat.name);
  }

  /// Hook for the host app to persist shuffle/repeat changes (e.g. updateMe).
  void setOnSettingChanged(OnPlayerSettingChanged? fn) {
    _onSettingChanged = fn;
  }

  /// Reorder the queue, keeping the current song's playback uninterrupted.
  /// `newIndex` follows Flutter's ReorderableListView convention where it
  /// refers to the position the item will end up in after removal — it can
  /// be one past the end of the list.
  void reorderQueue(int oldIndex, int newIndex) {
    if (_queue.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0) target = 0;
    if (target >= _queue.length) target = _queue.length - 1;
    if (target == oldIndex) return;

    // Remember the active song id so we can restore the index after the
    // structural shift — playback isn't interrupted because the underlying
    // AudioPlayer keeps its current source.
    final activeId = _currentSong?['id']?.toString();
    final item = _queue.removeAt(oldIndex);
    _queue.insert(target, item);
    if (activeId != null) {
      final newCur = _queue.indexWhere((s) => s['id'].toString() == activeId);
      if (newCur >= 0) _currentIndex = newCur;
    }
    notifyListeners();
  }

  /// Drop a track from the queue at [index]. If the active track is removed,
  /// jumps to whatever song now sits at that index (or stops if the queue
  /// becomes empty / the removed track was the only one). Used by the queue
  /// panel's swipe-to-remove gesture.
  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    final wasActive = index == _currentIndex;
    _queue.removeAt(index);
    if (_queue.isEmpty) {
      _currentIndex = 0;
      _currentSong = null;
      audioPlayer.stop();
      notifyListeners();
      return;
    }
    if (wasActive) {
      // Resume at whatever shifted into the slot — clamp so the last track
      // removal lands on the new last item instead of indexing past the end.
      final next = index.clamp(0, _queue.length - 1);
      playAtIndex(next);
    } else if (index < _currentIndex) {
      // A track before the active one was removed — keep playback unbroken
      // by sliding the index back so it still points at the same song.
      _currentIndex -= 1;
      notifyListeners();
    } else {
      notifyListeners();
    }
  }

  /// Apply persisted player settings from the authed user payload. No-op when
  /// the same user's settings have already been applied — prevents bouncing
  /// the values when AuthProvider notifies repeatedly.
  void applyUserSettings(Map<String, dynamic>? user) {
    if (user == null) {
      _appliedForUserId = null;
      return;
    }
    final uid = user['id']?.toString();
    if (uid == null || uid == _appliedForUserId) return;
    _appliedForUserId = uid;
    bool changed = false;
    final s = user['player_shuffle'];
    if (s is bool && s != _shuffle) { _shuffle = s; changed = true; }
    final r = user['player_repeat'];
    if (r is String) {
      final mode = PlayerRepeatMode.values.firstWhere(
        (m) => m.name == r,
        orElse: () => _repeat,
      );
      if (mode != _repeat) { _repeat = mode; changed = true; }
    }
    if (changed) notifyListeners();
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    _muted = _volume == 0;
    await _player.setVolume(_muted ? 0 : _volume);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    await _player.setVolume(_muted ? 0 : _volume);
    notifyListeners();
  }

  Future<void> setPlaybackRate(double rate) async {
    _playbackRate = rate.clamp(0.5, 2.0);
    await _player.setSpeed(_playbackRate);
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
