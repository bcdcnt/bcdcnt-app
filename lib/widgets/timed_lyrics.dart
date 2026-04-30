import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import '../constants/theme.dart';
import '../services/player.dart';

/// One line of timed lyrics — when [time] is null the line is untimed
/// (header / blank / decorative) and isn't a seek target.
class _LrcLine {
  final Duration? time;
  final String text;
  const _LrcLine(this.time, this.text);
}

/// Parses an LRC-style block of lyrics out of arbitrary text or HTML.
/// LRC tags supported: `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]`, `[m:ss.xx]`,
/// repeated per line for shared lines (e.g. `[0:10][1:20]chorus`). Lines
/// without a timestamp keep their text but render as static (decorative).
///
/// Returns `null` if fewer than 3 timestamped lines are found — too few to
/// justify the timed UI; the caller falls back to the HTML renderer.
List<_LrcLine>? _parseLrc(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  // Strip the most common HTML wrappers — CKEditor stores `<p>...</p>` lines
  // and `<br>` separators. Newlines preserved.
  final stripped = raw
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</\s*p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"');

  final tagRx = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  final lines = <_LrcLine>[];
  int timed = 0;
  for (final raw in stripped.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final matches = tagRx.allMatches(line).toList();
    if (matches.isEmpty) {
      lines.add(_LrcLine(null, line));
      continue;
    }
    final text = line.replaceAll(tagRx, '').trim();
    for (final m in matches) {
      final mins = int.parse(m.group(1)!);
      final secs = int.parse(m.group(2)!);
      final fracStr = m.group(3);
      int millis = 0;
      if (fracStr != null) {
        // LRC fractional digits can be 1–3 — pad to ms.
        final padded = fracStr.padRight(3, '0').substring(0, 3);
        millis = int.parse(padded);
      }
      final t = Duration(minutes: mins, seconds: secs, milliseconds: millis);
      lines.add(_LrcLine(t, text));
      timed++;
    }
  }
  if (timed < 3) return null;
  // Sort by time so out-of-order tags still render correctly.
  lines.sort((a, b) {
    if (a.time == null && b.time == null) return 0;
    if (a.time == null) return -1;
    if (b.time == null) return 1;
    return a.time!.compareTo(b.time!);
  });
  return lines;
}

/// Highlights the currently-playing line of synced lyrics and auto-scrolls
/// it into view. Click any line to seek there. When the lyrics aren't in
/// LRC format, [fallback] is rendered instead.
class TimedLyrics extends StatefulWidget {
  final String? raw;
  final Widget fallback;
  const TimedLyrics({super.key, required this.raw, required this.fallback});

  @override
  State<TimedLyrics> createState() => _TimedLyricsState();
}

class _TimedLyricsState extends State<TimedLyrics> {
  late final List<_LrcLine>? _lines = _parseLrc(widget.raw);
  final ScrollController _scroll = ScrollController();
  int _activeIndex = -1;
  StreamSubscription<Duration>? _posSub;
  // Average per-line height — used to compute scroll target. Refined on
  // first layout via a key on the active line, but a sensible default keeps
  // initial jumps reasonable.
  double _lineHeight = 36;

  @override
  void initState() {
    super.initState();
    if (_lines == null) return;
    final player = context.read<PlayerProvider>();
    _posSub = player.audioPlayer.positionStream.listen(_onTick);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onTick(Duration pos) {
    final lines = _lines;
    if (lines == null || !mounted) return;
    int idx = -1;
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].time;
      if (t == null) continue;
      if (t <= pos) idx = i; else break;
    }
    if (idx != _activeIndex) {
      setState(() => _activeIndex = idx);
      _scrollToActive();
    }
  }

  void _scrollToActive() {
    if (!_scroll.hasClients || _activeIndex < 0) return;
    final viewport = _scroll.position.viewportDimension;
    final target = (_activeIndex * _lineHeight) - (viewport / 2) + (_lineHeight / 2);
    final clamped = target.clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(clamped, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  void _seekTo(Duration t) {
    context.read<PlayerProvider>().seek(t);
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    if (lines == null) return widget.fallback;
    return LayoutBuilder(builder: (ctx, c) {
      return ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.symmetric(vertical: c.maxHeight * 0.45),
        itemCount: lines.length,
        itemBuilder: (_, i) {
          final l = lines[i];
          final active = i == _activeIndex;
          // Distance-based fade for non-active lines, à la Apple Music.
          final dist = (_activeIndex < 0) ? 1.0 : ((i - _activeIndex).abs().clamp(0, 4) / 4);
          final color = active
              ? AppColors.text
              : Color.lerp(AppColors.text, AppColors.textMuted, 0.3 + dist * 0.7) ?? AppColors.textMuted;
          final fontSize = active ? 20.0 : 16.0;
          final fontWeight = active ? FontWeight.w800 : FontWeight.w500;
          final entry = Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: body(TextStyle(
                fontSize: fontSize, fontWeight: fontWeight, color: color, height: 1.45,
              )),
              child: Text(l.text, textAlign: TextAlign.center),
            ),
          );
          if (l.time == null) return entry;
          return InkWell(
            onTap: () => _seekTo(l.time!),
            child: entry,
          );
        },
      );
    });
  }
}
