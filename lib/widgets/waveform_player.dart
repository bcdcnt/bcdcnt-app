import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/player.dart';
import 'package:just_audio/just_audio.dart';
import '../constants/theme.dart';

List<double> generateBars(int seed, {int count = 120}) {
  final raw = <double>[];
  var x = (seed.abs() * 2654435761) % 2147483647;
  if (x == 0) x = 1;
  for (var i = 0; i < count; i++) {
    x = (x * 16807) % 2147483647;
    raw.add(x / 2147483647);
  }
  var vals = raw;
  for (var pass = 0; pass < 4; pass++) {
    final next = List<double>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      double sum = 0, weight = 0;
      for (var j = -3; j <= 3; j++) {
        final idx = (i + j).clamp(0, count - 1);
        final w = 1 / (1 + j.abs());
        sum += vals[idx] * w;
        weight += w;
      }
      next[i] = sum / weight;
    }
    vals = next;
  }
  double lo = double.infinity, hi = double.negativeInfinity;
  for (final v in vals) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  final range = (hi - lo) == 0 ? 1 : (hi - lo);
  return vals.map((v) => 0.1 + ((v - lo) / range) * 0.9).toList();
}

List<double> parseBars(String? waveformJson, int seed) {
  if (waveformJson != null && waveformJson.isNotEmpty) {
    try {
      final parsed = jsonDecode(waveformJson);
      if (parsed is List && parsed.isNotEmpty) {
        return parsed.map((e) => (e as num).toDouble()).toList();
      }
    } catch (_) {}
  }
  return generateBars(seed);
}

class WaveformPlayer extends StatefulWidget {
  final String audioUrl;
  final int seed;
  final String? waveform;
  final bool autoPlay;
  final bool showTimestamp;
  final double height;
  /// Play button diameter (36 in compact lists).
  final double buttonSize;
  /// Known length before the file loads (seconds), so "3:41" shows at once.
  final double? durationHint;
  /// Extra text after the time, e.g. "192 kbps".
  final String? trailing;
  /// Playback volume 0–1 (Nghe cân bằng lowers the louder of two recordings).
  final double volume;
  const WaveformPlayer({
    super.key,
    required this.audioUrl,
    this.seed = 0,
    this.waveform,
    this.autoPlay = false,
    this.showTimestamp = true,
    this.height = 56,
    this.buttonSize = 52,
    this.durationHint,
    this.trailing,
    this.volume = 1.0,
  });

  @override
  State<WaveformPlayer> createState() => _WaveformPlayerState();
}

class _WaveformPlayerState extends State<WaveformPlayer> {
  late final AudioPlayer _player;
  late List<double> _bars;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _loaded = false;
  bool _loading = false;

  @override
  void didUpdateWidget(WaveformPlayer old) {
    super.didUpdateWidget(old);
    if (old.volume != widget.volume) _player.setVolume(widget.volume);
  }

  @override
  void initState() {
    super.initState();
    _bars = parseBars(widget.waveform, widget.seed);
    _player = AudioPlayer();
    if (widget.volume != 1.0) _player.setVolume(widget.volume);
    _player.playingStream.listen((p) { if (mounted) setState(() => _playing = p); });
    _player.positionStream.listen((p) { if (mounted) setState(() => _position = p); });
    _player.durationStream.listen((d) { if (mounted) setState(() => _duration = d ?? Duration.zero); });
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });
    // Load on first tap (or autoPlay): a long comment list must not
    // pre-buffer every recording.
    if (widget.autoPlay) _loadUrl();
  }

  Future<bool> _loadUrl() async {
    if (_loaded) return true;
    if (_loading) return false;
    if (mounted) setState(() => _loading = true);
    try {
      await _player.setUrl(widget.audioUrl);
      if (!mounted) return false;
      setState(() { _loaded = true; _loading = false; });
      if (widget.autoPlay) await _player.play();
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Không mở được bản ghi âm, vui lòng thử lại.')),
        );
      }
      return false;
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inMinutes}:$s';
  }

  /// "1:12 / 3:48 · 192 kbps" while playing, "3:48 · 192 kbps" before.
  String get _timeText {
    final total = _duration > Duration.zero
        ? _duration
        : (widget.durationHint != null && widget.durationHint! > 0 ? Duration(milliseconds: (widget.durationHint! * 1000).round()) : null);
    final started = _loaded && (_playing || _position > Duration.zero);
    final t = total == null ? (started ? _fmt(_position) : '') : (started ? '${_fmt(_position)} / ${_fmt(total)}' : _fmt(total));
    return [if (t.isNotEmpty) t, if ((widget.trailing ?? '').isNotEmpty) widget.trailing!].join(' · ');
  }

  Future<void> _toggle() async {
    if (_playing) {
      _player.pause();
      return;
    }
    // One sound at a time: pause the song before playing the comment audio.
    try { context.read<PlayerProvider>().pause(); } catch (_) {}
    if (!_loaded) {
      final ok = await _loadUrl();
      if (!ok || !mounted) return;
    }
    _player.play();
  }

  void _seekAt(Offset local, double width) {
    if (_duration == Duration.zero) return;
    final frac = (local.dx / width).clamp(0.0, 1.0);
    _player.seek(Duration(milliseconds: (frac * _duration.inMilliseconds).toInt()));
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0.0;
    final b = widget.buttonSize;
    final time = widget.showTimestamp ? _timeText : '';
    return Row(
      children: [
        Semantics(
          button: true,
          label: _playing ? 'Tạm dừng ghi âm' : 'Phát ghi âm',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _loading ? null : _toggle,
            child: Container(
              width: b, height: b,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.wine),
              child: _loading
                  ? Padding(padding: EdgeInsets.all(b * 0.28), child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                  : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: b * 0.55),
            ),
          ),
        ),
        SizedBox(width: b * 0.3),
        Expanded(
          child: LayoutBuilder(builder: (ctx, constraints) {
            return GestureDetector(
              onTapDown: (d) => _seekAt(d.localPosition, constraints.maxWidth),
              onHorizontalDragUpdate: (d) => _seekAt(d.localPosition, constraints.maxWidth),
              child: CustomPaint(
                size: Size(constraints.maxWidth, widget.height),
                painter: _WaveformPainter(
                  bars: _bars,
                  progress: progress,
                  playedColor: AppColors.wine,
                  unplayedColor: AppColors.wine.withValues(alpha: 0.22),
                ),
              ),
            );
          }),
        ),
        if (time.isNotEmpty) ...[
          const SizedBox(width: 14),
          Text(time, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]))),
        ],
      ],
    );
  }
}

/// Rounded vertical bars around the middle line (canvas "sóng nhạc"):
/// played part in wine, the rest a light tint of it. Bars are ~4px with a
/// 3px gap whatever the width; the data is resampled to fit.
class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  _WaveformPainter({required this.bars, required this.progress, required this.playedColor, required this.unplayedColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    const bw = 4.0, gap = 3.0;
    final n = ((size.width + gap) / (bw + gap)).floor().clamp(1, 1000);
    final splitX = progress * size.width;
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      final v = bars[(i * bars.length / n).floor().clamp(0, bars.length - 1)];
      final h = (v * size.height).clamp(6.0, size.height);
      final x = i * (bw + gap);
      final paint = Paint()..color = x + bw / 2 <= splitX ? playedColor : unplayedColor;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, mid - h / 2, bw, h), const Radius.circular(2)), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.progress != progress || old.bars != bars || old.playedColor != playedColor;
}
