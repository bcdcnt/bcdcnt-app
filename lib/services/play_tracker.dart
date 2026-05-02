import 'dart:math';

/// Mirrors the web `PlayTracker` (packages/core/playTracker.js) — accumulates
/// per-session playback time, fires `LogListen` when the user has played a
/// song long enough to count as an intentional listen.
///
/// Source labels distinguish how the track started:
///   * `manual` — user explicitly tapped Phát or a song row's play action
///   * `queue` — queue auto-advanced to this song after the previous one
///                ended; backend treats this similarly to manual since the
///                user did set up the queue
///   * `autoplay` — host opened a detail page that triggered playback
///                  without an explicit user click. We DO NOT log these so
///                  the user's "Nghe gần đây" reflects intentional plays
///                  only. (Currently auto-play on detail navigation is
///                  removed, but the source is reserved for future use.)
typedef LogListenFn = Future<void> Function(LogListenPayload payload);

class PlayTracker {
  static const _thresholdSeconds = 30;
  static const _rateLimitMs = 3 * 60 * 1000; // 3 min between logs of same song

  final LogListenFn _logFn;
  _Session? _session;
  final Map<String, int> _rateLimit = {}; // songId -> last logged ms

  PlayTracker(this._logFn);

  /// Begin tracking a new song. Ends any in-flight session first.
  void startSession({
    required String songId,
    required String objectType,
    double? songDuration,
    String source = 'manual',
  }) {
    if (_session != null) {
      _finalize('new-song');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _session = _Session(
      eventId: _genEventId(now),
      songId: songId,
      objectType: objectType,
      songDuration: songDuration ?? 0,
      source: source,
      startedAtMs: now,
      lastResumeMs: now,
    );
  }

  /// Audio reported a new position. We accumulate elapsed wall-clock time
  /// since last resume — using wall-clock instead of audio currentTime so
  /// pauses / seeks don't artificially inflate playback.
  void onTimeUpdate() {
    final s = _session;
    if (s == null || s.paused) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (s.lastResumeMs != null) {
      s.accumulatedSec += (now - s.lastResumeMs!) / 1000.0;
      s.lastResumeMs = now;
    }
    if (!s.thresholdReached && s.accumulatedSec >= _threshold(s)) {
      s.thresholdReached = true;
    }
  }

  void onPause() {
    final s = _session;
    if (s == null || s.paused) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (s.lastResumeMs != null) {
      s.accumulatedSec += (now - s.lastResumeMs!) / 1000.0;
      s.lastResumeMs = null;
    }
    s.paused = true;
  }

  void onResume() {
    final s = _session;
    if (s == null) return;
    s.paused = false;
    s.lastResumeMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// End the active session. `reason` becomes `completed=true` when equal
  /// to "completed" (track played to the end naturally).
  void endSession({String reason = 'skip'}) {
    _finalize(reason);
  }

  void _finalize(String reason) {
    final s = _session;
    if (s == null) return;

    if (s.lastResumeMs != null && !s.paused) {
      final now = DateTime.now().millisecondsSinceEpoch;
      s.accumulatedSec += (now - s.lastResumeMs!) / 1000.0;
      s.lastResumeMs = null;
    }
    s.completed = reason == 'completed';

    if (!s.thresholdReached && s.accumulatedSec >= _threshold(s)) {
      s.thresholdReached = true;
    }

    // Mirror the web tracker: every 30s+ session logs, regardless of
    // source. The `source` label is still passed so backend / analytics
    // can break listens down by trigger (manual / queue / autoplay).
    if (s.thresholdReached && !s.logged) {
      _send(s);
    }
    _session = null;
  }

  void _send(_Session s) {
    final last = _rateLimit[s.songId];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last != null && now - last < _rateLimitMs) {
      s.logged = true;
      return;
    }
    s.logged = true;
    _rateLimit[s.songId] = now;
    _logFn(LogListenPayload(
      eventId: s.eventId,
      objectType: s.objectType,
      objectId: s.songId,
      durationPlayed: s.accumulatedSec.round(),
      songDuration: s.songDuration > 0 ? s.songDuration : null,
      source: s.source,
      completed: s.completed,
    ));
  }

  double _threshold(_Session s) {
    if (s.songDuration > 0 && s.songDuration < _thresholdSeconds) {
      return s.songDuration * 0.8;
    }
    return _thresholdSeconds.toDouble();
  }

  String _genEventId(int seedMs) {
    final r = Random().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '$seedMs-$r';
  }
}

class _Session {
  final String eventId;
  final String songId;
  final String objectType;
  final double songDuration;
  final String source;
  final int startedAtMs;
  int? lastResumeMs;
  double accumulatedSec = 0;
  bool thresholdReached = false;
  bool logged = false;
  bool completed = false;
  bool paused = false;

  _Session({
    required this.eventId,
    required this.songId,
    required this.objectType,
    required this.songDuration,
    required this.source,
    required this.startedAtMs,
    this.lastResumeMs,
  });
}

/// Payload built by [PlayTracker] when it decides to log a listen. The
/// outer host wires [LogListenFn] to actually post this against the
/// `logListen` mutation.
class LogListenPayload {
  final String eventId;
  final String objectType;
  final String objectId;
  final int durationPlayed;
  final double? songDuration;
  final String source;
  final bool completed;

  LogListenPayload({
    required this.eventId,
    required this.objectType,
    required this.objectId,
    required this.durationPlayed,
    this.songDuration,
    required this.source,
    required this.completed,
  });

  Map<String, dynamic> toVariables() => {
        'event_id': eventId,
        'object_type': objectType,
        'object_id': objectId,
        'duration_played': durationPlayed,
        if (songDuration != null) 'song_duration': songDuration,
        'source': source,
        'completed': completed,
      };
}

