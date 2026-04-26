import 'dart:convert';
import 'package:flutter/material.dart';
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
  const WaveformPlayer({
    super.key,
    required this.audioUrl,
    this.seed = 0,
    this.waveform,
    this.autoPlay = false,
    this.showTimestamp = true,
    this.height = 68,
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

  @override
  void initState() {
    super.initState();
    _bars = parseBars(widget.waveform, widget.seed);
    _player = AudioPlayer();
    _player.playingStream.listen((p) { if (mounted) setState(() => _playing = p); });
    _player.positionStream.listen((p) { if (mounted) setState(() => _position = p); });
    _player.durationStream.listen((d) { if (mounted) setState(() => _duration = d ?? Duration.zero); });
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    try {
      await _player.setUrl(widget.audioUrl);
      if (mounted) setState(() => _loaded = true);
      if (widget.autoPlay) await _player.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _toggle() {
    if (_playing) _player.pause(); else _player.play();
  }

  void _seekAt(Offset local, double width) {
    if (_duration == Duration.zero) return;
    final frac = (local.dx / width).clamp(0.0, 1.0);
    _player.seek(Duration(milliseconds: (frac * _duration.inMilliseconds).toInt()));
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0.0;
    return Row(
      children: [
        GestureDetector(
          onTap: _loaded ? _toggle : null,
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: _loaded
                ? Icon(_playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 22)
                : const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
          ),
        ),
        const SizedBox(width: 12),
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
                  playedColor: AppColors.accent,
                  unplayedColor: AppColors.textMuted.withValues(alpha: 0.35),
                  currentLabel: widget.showTimestamp ? _fmt(_position) : null,
                  durationLabel: widget.showTimestamp && _duration > Duration.zero ? _fmt(_duration) : null,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final String? currentLabel;
  final String? durationLabel;
  _WaveformPainter({required this.bars, required this.progress, required this.playedColor, required this.unplayedColor, this.currentLabel, this.durationLabel});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, totalH = size.height;
    final halfH = totalH / 2;
    final mid = halfH;
    final barW = (w / bars.length).clamp(2.0, double.infinity);
    const barGap = 2.0;
    final splitX = progress * w;

    for (var i = 0; i < bars.length; i++) {
      final x = i * barW;
      final bw = (barW - barGap).clamp(2.0, double.infinity);
      final h = (bars[i] * (halfH - 2)).clamp(3.0, double.infinity);
      final r = Radius.circular((bw / 2).clamp(0.0, 2.0));
      final color = (x + bw) <= splitX ? playedColor : unplayedColor;
      // Upper bar
      final upper = RRect.fromRectAndRadius(Rect.fromLTWH(x, mid - h, bw, h), r);
      canvas.drawRRect(upper, Paint()..color = color);
      // Lower mirror bar (faded)
      final lower = RRect.fromRectAndRadius(Rect.fromLTWH(x, mid + 2, bw, h * 0.7), r);
      canvas.drawRRect(lower, Paint()..color = color.withValues(alpha: color.a * 0.35));
    }

    void drawPill(String text, double x, bool alignLeft) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      final pw = tp.width + 10, ph = 18.0, py = mid - ph / 2;
      final px = alignLeft ? x - 3 : x - pw + 3;
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(px, py, pw, ph), const Radius.circular(4));
      canvas.drawRRect(rect, Paint()..color = const Color(0x8C000000));
      tp.paint(canvas, Offset(alignLeft ? x + 2 : x - 2 - tp.width, py + (ph - tp.height) / 2));
    }

    if (currentLabel != null) drawPill(currentLabel!, 4, true);
    if (durationLabel != null) drawPill(durationLabel!, w - 4, false);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.bars != bars || old.currentLabel != currentLabel || old.durationLabel != durationLabel;
}
