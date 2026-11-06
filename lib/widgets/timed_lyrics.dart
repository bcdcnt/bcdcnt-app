import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:provider/provider.dart';
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
///
/// [large] scales font + spacing for the FullPlayer fullscreen "karaoke"
/// view (Apple Music / Spotify Now Playing pattern). At default size the
/// active line is 20pt; large = 38pt active.
class TimedLyrics extends StatefulWidget {
  final String? raw;
  final Widget fallback;
  final bool large;
  /// Multiplier applied to all line font sizes — lets the parent
  /// (full player toolbar) offer A- / A+ controls without owning the
  /// active/inactive size logic. 1.0 = canonical sizing above.
  final double fontScale;
  /// When false the active-line tracker still updates colours but
  /// the list doesn't auto-scroll — user can read at their own pace
  /// without losing the highlight.
  final bool autoScroll;
  /// Overrides for hosts with their own surface (the wine FullPlayer):
  /// active-line colour, the colour far lines fade toward, alignment.
  final Color? activeColor;
  final Color? fadeColor;
  final TextAlign textAlign;
  const TimedLyrics({
    super.key,
    required this.raw,
    required this.fallback,
    this.large = false,
    this.fontScale = 1.0,
    this.autoScroll = true,
    this.activeColor,
    this.fadeColor,
    this.textAlign = TextAlign.center,
  });

  /// True when the input contains enough LRC tags to render the timed UI.
  /// Lets callers (FullPlayer) decide to auto-switch panels.
  static bool hasLrc(String? raw) => _parseLrc(raw) != null;

  @override
  State<TimedLyrics> createState() => _TimedLyricsState();
}

class _TimedLyricsState extends State<TimedLyrics> {
  List<_LrcLine>? _lines;
  final ScrollController _scroll = ScrollController();
  int _activeIndex = -1;
  StreamSubscription<Duration>? _posSub;
  // One key per line so auto-scroll uses the real laid-out position: at
  // large system text a line wraps to 2–3 rows and any fixed per-line
  // height estimate drifts further off with every line.
  List<GlobalKey> _keys = const [];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(TimedLyrics old) {
    super.didUpdateWidget(old);
    // The full player keeps this widget alive across songs; without a
    // re-parse the previous song's lyrics would stay on screen.
    if (old.raw != widget.raw) {
      _parse();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  void _parse() {
    _lines = _parseLrc(widget.raw);
    _activeIndex = -1;
    _keys = List.generate(_lines?.length ?? 0, (_) => GlobalKey());
    if (_lines == null) {
      _posSub?.cancel();
      _posSub = null;
    } else {
      _posSub ??= context.read<PlayerProvider>().audioPlayer.positionStream.listen(_onTick);
    }
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
      if (t > pos) break;
      idx = i;
    }
    if (idx != _activeIndex) {
      setState(() => _activeIndex = idx);
      // After the frame, so the active line's new (bigger) size is laid out.
      if (widget.autoScroll) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  void _scrollToActive() {
    if (!mounted || _activeIndex < 0 || _activeIndex >= _keys.length) return;
    final box = _keys[_activeIndex].currentContext?.findRenderObject();
    if (box == null || !_scroll.hasClients) return;
    // Only this list scrolls. Scrollable.ensureVisible would also scroll
    // every scrollable above it — on the phone player that dragged the whole
    // page down to the lyrics card on each new line.
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final target = viewport.getOffsetToReveal(box, 0.4).offset;
    final pos = _scroll.position;
    _scroll.animateTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent), duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  void _seekTo(Duration t) {
    context.read<PlayerProvider>().seek(t);
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    if (lines == null) return widget.fallback;
    return LayoutBuilder(builder: (ctx, c) {
      // A Column (not ListView.builder) so every line is laid out and its
      // offset known; lyrics are at most a few hundred short lines.
      return SingleChildScrollView(
        controller: _scroll,
        padding: EdgeInsets.symmetric(vertical: c.maxHeight * 0.45),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (var i = 0; i < lines.length; i++) _line(lines[i], i)],
        ),
      );
    });
  }

  Widget _line(_LrcLine l, int i) {
    final active = i == _activeIndex;
    // Distance-based fade for non-active lines, à la Apple Music.
    final dist = (_activeIndex < 0) ? 1.0 : ((i - _activeIndex).abs().clamp(0, 4) / 4);
    final on = widget.activeColor ?? AppColors.text;
    final off = widget.fadeColor ?? AppColors.textMuted;
    final color = active ? on : Color.lerp(on, off, 0.3 + dist * 0.7) ?? off;
    // Scale up for the fullscreen "karaoke" variant — larger active
    // line + more breathing room between lines so the focal text
    // reads at viewing distance (Apple Music / Spotify pattern).
    final fontSize = (widget.large
        ? (active ? 38.0 : 24.0)
        : (active ? 20.0 : 16.0)) * widget.fontScale;
    final fontWeight = active ? FontWeight.w800 : FontWeight.w500;
    final entry = Padding(
      key: _keys[i],
      padding: EdgeInsets.symmetric(vertical: widget.large ? 12 : 6, horizontal: 16),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 220),
        style: body(TextStyle(
          fontSize: fontSize, fontWeight: fontWeight, color: color, height: 1.35,
          letterSpacing: widget.large ? -0.3 : 0,
        )),
        child: Text(l.text, textAlign: widget.textAlign),
      ),
    );
    if (l.time == null) return entry;
    return InkWell(
      onTap: () => _seekTo(l.time!),
      child: entry,
    );
  }
}
