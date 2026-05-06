import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:go_router/go_router.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:window_manager/window_manager.dart';
import 'timed_lyrics.dart';
import '../constants/theme.dart';
import '../services/player.dart';
import '../services/auth.dart';
import '../services/api.dart';
import '../services/theme_provider.dart';

class FullPlayer extends StatefulWidget {
  const FullPlayer({super.key});

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

enum _PanelMode { vinyl, lyrics, queue }

class _FullPlayerState extends State<FullPlayer> with SingleTickerProviderStateMixin, WindowListener {
  late AnimationController _rotation;
  // Stable focus node so the F key keyboard listener doesn't leak a new
  // node each rebuild (creating a fresh FocusNode in build() spammed focus
  // requests + caused the listener to drop key events on rapid setState).
  final FocusNode _shortcutFocus = FocusNode(debugLabel: 'FullPlayer F shortcut');
  _PanelMode _panel = _PanelMode.vinyl;
  // Mirrored locally so the icon flip is instant; window_manager itself
  // is queried on the next build via _isDesktop guard.
  bool _isFullScreen = false;
  // Chrome auto-hide while in fullscreen + idle (no mouse movement). 3s
  // delay matches Spotify / Apple Music Now Playing fullscreen behaviour.
  // Header + footer fade out, cursor hides; mouse movement brings them
  // back. Always visible when not fullscreen.
  bool _chromeVisible = true;
  Timer? _idleTimer;
  static const _idleDelay = Duration(seconds: 3);

  bool _liked = false;
  List<dynamic> _lovers = [];
  bool _downloading = false;
  bool _loversFetchedForId = false;
  String? _songLyrics;
  String? _lyricsFetchedForId;
  // Composer + poet credits, fetched alongside the lyrics. Traditional
  // music on BCĐCNT often hangs on the songwriter / poet identity, so
  // we surface them as a dedicated row in the player chrome instead
  // of the artist-only line we used to show.
  List<Map<String, dynamic>> _composers = [];
  List<Map<String, dynamic>> _poets = [];

  // Lyrics panel display preferences. Persist across panel toggles
  // within the same session; reset on reload.
  double _lyricsScale = 1.0;
  bool _lyricsAutoScroll = true;

  bool get _isDesktopOS => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  Future<void> _toggleFullScreen() async {
    if (!_isDesktopOS) return;
    final next = !_isFullScreen;
    await windowManager.setFullScreen(next);
    if (!mounted) return;
    setState(() {
      _isFullScreen = next;
      // Reset idle state on each toggle so re-entering fullscreen doesn't
      // start hidden.
      _chromeVisible = true;
      // Auto-switch to the karaoke lyrics view on enter when the song has
      // LRC timestamps — the whole point of the fullscreen mode for music.
      // Only switch from vinyl (don't override an explicit queue choice).
      if (next && _panel == _PanelMode.vinyl && TimedLyrics.hasLrc(_songLyrics)) {
        _panel = _PanelMode.lyrics;
      }
    });
    if (next) {
      _scheduleHideChrome();
    } else {
      _idleTimer?.cancel();
      _idleTimer = null;
    }
  }

  void _scheduleHideChrome() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleDelay, () {
      if (mounted && _isFullScreen) setState(() => _chromeVisible = false);
    });
  }

  void _onPointerActivity() {
    if (!_isFullScreen) return;
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _scheduleHideChrome();
  }
  // Dominant color extracted from the current artwork. Drives the top
  // radial-gradient backdrop so it looks colour-coordinated with the song,
  // matching Spotify's "now playing" vibe.
  Color? _artworkAccent;
  String? _artworkAccentForUrl;

  static const List<double> _speedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    if (_isDesktopOS) {
      windowManager.addListener(this);
      windowManager.isFullScreen().then((v) {
        if (mounted) {
          setState(() => _isFullScreen = v);
          // If user opened the FullPlayer while the window was already
          // fullscreen (from a prior toggle / macOS green button), arm the
          // idle hide so it behaves the same as if they'd just pressed F.
          if (v) _scheduleHideChrome();
        }
      });
    }
  }

  @override
  void dispose() {
    if (_isDesktopOS) windowManager.removeListener(this);
    _rotation.dispose();
    _shortcutFocus.dispose();
    _idleTimer?.cancel();
    super.dispose();
  }

  // Keep _isFullScreen in lock-step with the OS — covers macOS green
  // traffic light, Cmd+Ctrl+F, Mission Control swipes, etc. Without these
  // hooks, exiting fullscreen via the system would leave _isFullScreen=true
  // and the chrome would auto-hide in windowed mode. Bug surfaced in
  // testing.
  @override
  void onWindowEnterFullScreen() {
    if (!mounted) return;
    setState(() {
      _isFullScreen = true;
      _chromeVisible = true;
      if (_panel == _PanelMode.vinyl && TimedLyrics.hasLrc(_songLyrics)) {
        _panel = _PanelMode.lyrics;
      }
    });
    _scheduleHideChrome();
  }

  @override
  void onWindowLeaveFullScreen() {
    if (!mounted) return;
    _idleTimer?.cancel();
    _idleTimer = null;
    setState(() { _isFullScreen = false; _chromeVisible = true; });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _maybeExtractAccent(String? url) async {
    if (url == null || url.isEmpty) {
      if (_artworkAccent != null && mounted) setState(() { _artworkAccent = null; _artworkAccentForUrl = null; });
      return;
    }
    if (url == _artworkAccentForUrl) return;
    _artworkAccentForUrl = url;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url),
        size: const Size(96, 96),
        maximumColorCount: 6,
      );
      // Prefer vibrant > muted > dominant — vibrant gives the most
      // "Spotify-like" backdrop. Falls back gracefully when colours are dull.
      final picked = palette.vibrantColor?.color
          ?? palette.lightVibrantColor?.color
          ?? palette.mutedColor?.color
          ?? palette.dominantColor?.color;
      if (!mounted || picked == null || _artworkAccentForUrl != url) return;
      setState(() => _artworkAccent = picked);
    } catch (_) {
      // Network or decode error — leave previous accent in place.
    }
  }

  void _openSongDetail(Map<String, dynamic> song) {
    final id = song['id']?.toString();
    if (id == null || id.isEmpty) return;
    Navigator.of(context).pop();
    context.push('/song/$id', extra: song);
  }

  void _openArtistDetail(Map artist) {
    final slug = artist['slug']?.toString();
    if (slug != null && slug.isNotEmpty && artist['title'] != null) {
      Navigator.of(context).pop();
      context.push('/nghe-si/$slug');
      return;
    }
    // Karaoke "artists" entries are actually users — fall back to user route.
    final id = artist['id']?.toString();
    if (id != null && id.isNotEmpty && artist['username'] != null) {
      Navigator.of(context).pop();
      context.push('/user/$id');
    }
  }

  Widget _buildArtistRow(List artists) {
    final entries = <Map>[];
    for (final a in artists) {
      if (a is Map) {
        final label = (a['title'] ?? a['username'] ?? '').toString();
        if (label.isNotEmpty) entries.add(a);
      }
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    final style = body(TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.accentLight));
    final sepStyle = body(TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textMuted));
    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final a = entries[i];
      final label = (a['title'] ?? a['username']).toString();
      children.add(InkWell(
        onTap: () => _openArtistDetail(a),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text(label, style: style),
        ),
      ));
      if (i < entries.length - 1) {
        children.add(Text(',', style: sepStyle));
      }
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  /// Single-line credits row: "Sáng tác: X · Thơ: Y · Thể hiện: Z".
  /// Each name tappable; segments collapse out when their role has no
  /// data. Wraps onto multiple lines when the viewport is narrow.
  Widget _buildCreditsBlock(List artists) {
    final muted = body(TextStyle(fontSize: 13, color: AppColors.textMuted));
    final accent = body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentLight));

    void Function() openOf(Map m, String routePrefix) => () {
      final slug = m['slug']?.toString();
      final id = m['id']?.toString();
      if (routePrefix == '/user/' && id != null && id.isNotEmpty) {
        Navigator.of(context).pop();
        context.push('/user/$id');
      } else if (slug != null && slug.isNotEmpty) {
        Navigator.of(context).pop();
        context.push('$routePrefix$slug');
      }
    };

    /// Builds the inline widgets for one role. Returns empty when no
    /// entries → caller skips the segment + dot separator.
    List<Widget> seg(String label, List entries, String routePrefix) {
      final cleaned = entries.where((a) => a is Map && (a['title'] ?? a['username'] ?? '').toString().isNotEmpty).toList();
      if (cleaned.isEmpty) return const [];
      final out = <Widget>[
        Text(label, style: muted),
        const SizedBox(width: 4),
      ];
      for (var i = 0; i < cleaned.length; i++) {
        final m = cleaned[i] as Map;
        final name = (m['title'] ?? m['username']).toString();
        out.add(InkWell(
          onTap: openOf(m, routePrefix),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Text(name, style: accent),
          ),
        ));
        if (i < cleaned.length - 1) out.add(Text(', ', style: muted));
      }
      return out;
    }

    final isKaraoke = artists.isNotEmpty && artists.first is Map && (artists.first['username'] != null);
    final segments = <List<Widget>>[
      seg('Sáng tác:', _composers, '/nhac-si/'),
      seg('Thơ:', _poets, '/nha-tho/'),
      seg(isKaraoke ? 'Thành viên hát:' : 'Trình bày:', artists, isKaraoke ? '/user/' : '/nghe-si/'),
    ].where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('·', style: muted),
        ));
      }
      children.addAll(segments[i]);
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  /// Speaker icon + horizontal slider — desktop-only chrome in the
  /// header. Tap the icon to toggle mute; drag the slider to set
  /// volume. Hidden on mobile where OS-level volume keys handle this.
  Widget _buildVolumeControl(PlayerProvider player) {
    final muted = player.muted || player.volume <= 0.001;
    final value = muted ? 0.0 : player.volume;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: muted ? 'Bật âm thanh' : 'Tắt âm thanh',
            iconSize: 18,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
            icon: Icon(
              muted ? Icons.volume_off : (value < 0.4 ? Icons.volume_down : Icons.volume_up),
              color: muted ? AppColors.accentLight : AppColors.textSecondary,
            ),
            onPressed: player.toggleMute,
          ),
          SizedBox(
            width: 80,
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: AppColors.border,
                thumbColor: AppColors.accent,
                overlayColor: AppColors.accent.withValues(alpha: 0.18),
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: value,
                onChanged: (v) => player.setVolume(v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact "Tiếp theo: …" chip rendered just above the transport.
  /// Computes the next track honouring shuffle (PlayerProvider keeps
  /// the original index so we walk the natural sequence; this could
  /// drift from the actual auto-advance pick once shuffle is on, but
  /// the visual hint is still useful and avoids querying the
  /// shuffled order). Tap → flip the panel to queue for the full
  /// view.
  Widget _buildNextUpChip(PlayerProvider player) {
    final q = player.queue;
    if (q.length < 2) return const SizedBox.shrink();
    final nextIdx = (player.currentIndex + 1) % q.length;
    if (nextIdx == player.currentIndex) return const SizedBox.shrink();
    final next = q[nextIdx];
    final title = (next['title'] ?? '').toString();
    if (title.isEmpty) return const SizedBox.shrink();
    final artists = next['artists'] is List
        ? next['artists']
        : (next['artists']?['data'] ?? const []);
    final artistText = (artists as List)
        .map((a) => a is Map ? (a['title'] ?? a['username'] ?? '') : '')
        .where((s) => (s as String).isNotEmpty)
        .join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: InkWell(
          onTap: () => setState(() => _panel = _panel == _PanelMode.queue ? _PanelMode.vinyl : _PanelMode.queue),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.skip_next, size: 14, color: AppColors.accentLight),
              const SizedBox(width: 6),
              Text(
                'Tiếp theo:',
                style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textMuted)),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  artistText.isNotEmpty ? '$title — $artistText' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Pill-shaped segmented control for switching between vinyl /
  /// lyrics / queue panels. Sits between the header and the panel
  /// area so the toggle has its own clear band — no more mixing into
  /// the transport row. Tabs collapse out for content that doesn't
  /// have data (no lyrics tab on instrumentals; no queue tab when
  /// the queue is empty).
  Widget _buildPanelSwitcher(PlayerProvider player, bool isInstrumental, bool hasQueue) {
    final tabs = <(_PanelMode, IconData, String, String?)>[
      (_PanelMode.vinyl, Icons.album_outlined, 'Đĩa than', null),
      // Square-ish icons for the other two so the trio reads as a
      // balanced segmented strip (album is round; subject + list are
      // both rectangular blocks of horizontal lines).
      if (!isInstrumental) (_PanelMode.lyrics, Icons.subject, 'Lời bài hát', null),
      if (hasQueue) (_PanelMode.queue, Icons.format_list_bulleted, 'Hàng đợi', '${player.queue.length}'),
    ];
    if (tabs.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: tabs.map((t) {
              final active = _panel == t.$1;
              return InkWell(
                onTap: active ? null : () => setState(() => _panel = t.$1),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: active ? AppColors.accent.withValues(alpha: 0.85) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(t.$2, size: 14, color: active ? Colors.white : AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      t.$3,
                      style: body(TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : AppColors.textSecondary,
                      )),
                    ),
                    if (t.$4 != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: active ? Colors.white.withValues(alpha: 0.25) : AppColors.surfaceHover,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          t.$4!,
                          style: body(TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: active ? Colors.white : AppColors.textMuted,
                          )),
                        ),
                      ),
                    ],
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// Inline heart button — sits to the right of the title so the
  /// most-frequent action stays one tap. Tiny love count appears
  /// underneath the icon when ≥ 1 person has liked the song,
  /// borrowing the social-proof pattern from song detail.
  Widget _buildInlineHeart(Map<String, dynamic> song) {
    final count = _lovers.length;
    return InkWell(
      onTap: () => _handleLove(song),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _liked ? Icons.favorite : Icons.favorite_border,
              size: 22,
              color: _liked ? AppColors.accent : AppColors.textSecondary,
            ),
            if (count > 0) ...[
              const SizedBox(height: 2),
              Text(
                _formatCompact(count),
                style: body(TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _liked ? AppColors.accent : AppColors.textMuted,
                )),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Compact number formatter used by the heart count: 999 → "999",
  /// 1500 → "1.5K", 12000 → "12K". Vietnamese decimal separator.
  String _formatCompact(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) {
      final v = n / 1000;
      final s = v.toStringAsFixed(1).replaceAll('.', ',');
      return '${s.endsWith(',0') ? s.substring(0, s.length - 2) : s}K';
    }
    return '${(n / 1000).round()}K';
  }

  /// Old icon-row builder retained for now in case we revert; not
  /// referenced from the build tree any more.
  // ignore: unused_element
  Widget _buildSecondaryControls(BuildContext context, PlayerProvider player, Map<String, dynamic> song, bool isInstrumental, bool hasQueue) {
    Widget btn({
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
      bool active = false,
      Color? activeColor,
      String? badge,
    }) {
      final color = active ? (activeColor ?? AppColors.accentLight) : AppColors.textSecondary;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? AppColors.accentSoft : Colors.transparent,
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              Icon(icon, size: 20, color: color),
              if (badge != null) Positioned(
                right: -6, top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.bg, width: 1),
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  alignment: Alignment.center,
                  child: Text(badge, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, height: 1.2)),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    return Padding(
      // Sits at the top of the chrome footer, so vertical breathing
      // room above isn't needed — the panel area already provides it.
      padding: const EdgeInsets.fromLTRB(48, 4, 48, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                btn(
                  icon: _liked ? Icons.favorite : Icons.favorite_border,
                  tooltip: _liked ? 'Bỏ thích' : 'Yêu thích',
                  active: _liked,
                  activeColor: AppColors.accent,
                  onTap: () => _handleLove(song),
                ),
                if (!isInstrumental)
                  btn(
                    icon: Icons.lyrics_outlined,
                    tooltip: _panel == _PanelMode.lyrics ? 'Ẩn lời bài hát' : 'Lời bài hát',
                    active: _panel == _PanelMode.lyrics,
                    onTap: () => setState(() => _panel = _panel == _PanelMode.lyrics ? _PanelMode.vinyl : _PanelMode.lyrics),
                  ),
                if (hasQueue)
                  btn(
                    icon: Icons.queue_music,
                    tooltip: _panel == _PanelMode.queue ? 'Ẩn hàng đợi' : 'Hàng đợi',
                    active: _panel == _PanelMode.queue,
                    badge: '${player.queue.length}',
                    onTap: () => setState(() => _panel = _panel == _PanelMode.queue ? _PanelMode.vinyl : _PanelMode.queue),
                  ),
                btn(
                  icon: Icons.ios_share,
                  tooltip: 'Chia sẻ',
                  onTap: () => _handleShare(song),
                ),
                btn(
                  icon: _downloading ? Icons.hourglass_empty : Icons.download_outlined,
                  tooltip: _downloading ? 'Đang tải...' : 'Tải xuống',
                  onTap: () => _handleDownload(song),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _songType(Map<String, dynamic> song) {
    final ft = song['file_type'] ?? 'song';
    return ft == 'audio' ? 'song' : ft;
  }

  Future<void> _fetchLovesAndLyrics(Map<String, dynamic> song) async {
    final id = song['id'].toString();
    if (_loversFetchedForId == false || (song['id'].toString() != (_lyricsFetchedForId ?? ''))) {
      _lyricsFetchedForId = id;
      final type = _songType(song);
      // Composers + poets are first-class metadata for traditional
      // music; fetched alongside lyrics so the player can show
      // "Sáng tác: X · Thơ: Y" right under the title.
      // Karaoke songs don't have composers/poets at the top level —
      // narrow the field set to avoid GraphQL "Cannot query field"
      // errors on those routes.
      final wantsCredits = type != 'karaoke';
      final creditFields = wantsCredits
          ? 'composers(first: 5) { data { id title slug } } poets(first: 5) { data { id title slug } }'
          : '';
      try {
        final data = await ApiClient.query(
          'query(\$id: ID!) { $type(id: \$id) { content $creditFields loves(first: 50) { data { user_id user { id username avatar { url } } } } } }',
          {'id': id},
        );
        final obj = data[type];
        final lovesData = (obj?['loves']?['data'] ?? []) as List;
        final composers = ((obj?['composers']?['data']) as List? ?? const [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        final poets = ((obj?['poets']?['data']) as List? ?? const [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        if (!mounted) return;
        setState(() {
          _lovers = lovesData;
          _songLyrics = obj?['content'];
          _composers = composers;
          _poets = poets;
          final userId = context.read<AuthProvider>().user?['id'];
          if (userId != null) {
            _liked = lovesData.any((l) => l['user_id'].toString() == userId.toString());
          }
          _loversFetchedForId = true;
        });
      } catch (_) {}
    }
  }

  Future<void> _handleLove(Map<String, dynamic> song) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    final type = _songType(song);
    final newLiked = !_liked;
    setState(() {
      _liked = newLiked;
      final user = auth.user;
      if (user != null) {
        if (newLiked) {
          _lovers = [{'user_id': user['id'], 'user': user}, ..._lovers];
        } else {
          _lovers = _lovers.where((l) => l['user_id'].toString() != user['id'].toString()).toList();
        }
      }
    });
    try {
      final mutation = newLiked
          ? 'mutation(\$id: ID!) { love(lovable_id: \$id, lovable_type: "$type") { id } }'
          : 'mutation(\$id: ID!) { unlove(lovable_id: \$id, lovable_type: "$type") { id } }';
      await auth.authedMutate(mutation, {'id': song['id'].toString()});
    } catch (_) {
      setState(() => _liked = !newLiked);
    }
  }

  Future<void> _handleDownload(Map<String, dynamic> song) async {
    if (_downloading) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng đăng nhập để tải'), backgroundColor: AppColors.error));
      return;
    }
    setState(() => _downloading = true);
    try {
      final data = await auth.authedMutate(
        r'''mutation($t: String!, $i: ID!) { download(object_type: $t, object_id: $i) { url } }''',
        {'t': _songType(song), 'i': song['id'].toString()},
      );
      final url = data['download']?['url'];
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bạn đã tải quá nhiều'), backgroundColor: AppColors.error));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải: $e'), backgroundColor: AppColors.error));
    }
    if (mounted) setState(() => _downloading = false);
  }

  Future<void> _handleShare(Map<String, dynamic> song) async {
    final slug = song['slug'] ?? '';
    final id = song['id'];
    final url = slug.isNotEmpty ? '$siteUrl/bai-hat/$slug-$id' : '$siteUrl/bai-hat/$id';
    final artistNames = ((song['artists']?['data'] ?? song['artists'] ?? []) as List).map((a) => a['title'] ?? '').join(', ');
    final subject = artistNames.isNotEmpty ? '${song['title']} - $artistNames' : song['title'];
    try {
      await launchUrl(Uri.parse('mailto:?subject=${Uri.encodeComponent(subject ?? '')}&body=${Uri.encodeComponent(url)}'));
    } catch (_) {}
  }

  void _showMoreSheet(BuildContext ctx, Map<String, dynamic> song, PlayerProvider player) {
    final speedLabel = '${player.playbackRate.toStringAsFixed(player.playbackRate == player.playbackRate.roundToDouble() ? 0 : 2)}x';
    final loveCount = _lovers.length > 99 ? '99+' : (_lovers.isEmpty ? null : '${_lovers.length}');
    final isInstrumental = song['file_type'] == 'instrumental';
    final hasQueue = player.queue.isNotEmpty;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Heart + panel toggles live in the main UI now (inline
          // title + tab strip above the panel). This sheet keeps the
          // less common actions: share, download, speed, mute, sleep.
          ListTile(
            leading: Icon(Icons.ios_share, color: AppColors.textSecondary),
            title: Text('Chia sẻ', style: body(TextStyle(color: AppColors.text))),
            onTap: () { Navigator.pop(sheetCtx); _handleShare(song); },
          ),
          ListTile(
            leading: Icon(_downloading ? Icons.hourglass_empty : Icons.download_outlined, color: AppColors.textSecondary),
            title: Text(_downloading ? 'Đang tải...' : 'Tải xuống', style: body(TextStyle(color: AppColors.text))),
            onTap: () { Navigator.pop(sheetCtx); _handleDownload(song); },
          ),
          Divider(height: 1, color: AppColors.borderSubtle),
          ListTile(
            leading: Icon(Icons.speed, color: player.playbackRate != 1.0 ? AppColors.accentLight : AppColors.textSecondary),
            title: Text('Tốc độ phát', style: body(TextStyle(color: AppColors.text))),
            trailing: Text(speedLabel, style: body(TextStyle(
              color: player.playbackRate != 1.0 ? AppColors.accentLight : AppColors.textMuted,
              fontSize: 13, fontWeight: FontWeight.w700,
            ))),
            onTap: () { Navigator.pop(sheetCtx); _showSpeedSheet(); },
          ),
          ListTile(
            leading: Icon(player.muted ? Icons.volume_off : Icons.volume_up, color: AppColors.textSecondary),
            title: Text(player.muted ? 'Bật âm thanh' : 'Tắt âm thanh', style: body(TextStyle(color: AppColors.text))),
            onTap: () { Navigator.pop(sheetCtx); player.toggleMute(); },
          ),
          ListTile(
            leading: Icon(Icons.bedtime_outlined, color: player.hasSleepTimer ? AppColors.accentLight : AppColors.textSecondary),
            title: Text(
              player.hasSleepTimer ? 'Hẹn giờ tắt' : 'Hẹn giờ tắt',
              style: body(TextStyle(color: player.hasSleepTimer ? AppColors.accentLight : AppColors.text)),
            ),
            trailing: player.hasSleepTimer
                ? Text(_sleepTimerLabel(player), style: body(TextStyle(color: AppColors.accentLight, fontSize: 13, fontWeight: FontWeight.w700)))
                : null,
            onTap: () { Navigator.pop(sheetCtx); _showSleepSheet(); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  String _sleepTimerLabel(PlayerProvider player) {
    if (player.sleepEndOfSong) return 'Hết bài này';
    final r = player.sleepRemaining;
    if (r == null) return '';
    final m = r.inMinutes;
    final s = r.inSeconds.remainder(60);
    return m > 0 ? '${m}p${s.toString().padLeft(2, '0')}' : '${s}s';
  }

  void _showSleepSheet() {
    final player = context.read<PlayerProvider>();
    final presets = const [
      (Duration(minutes: 5), '5 phút'),
      (Duration(minutes: 10), '10 phút'),
      (Duration(minutes: 15), '15 phút'),
      (Duration(minutes: 30), '30 phút'),
      (Duration(minutes: 60), '60 phút'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(children: [
                Icon(Icons.bedtime_outlined, size: 18, color: AppColors.accentLight),
                const SizedBox(width: 8),
                Text('Hẹn giờ tắt', style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
                const Spacer(),
                if (player.hasSleepTimer)
                  TextButton(
                    onPressed: () { player.cancelSleepTimer(); Navigator.pop(ctx); },
                    child: Text('Huỷ', style: body(TextStyle(color: AppColors.accentLight, fontWeight: FontWeight.w700))),
                  ),
              ]),
            ),
            ...presets.map((p) {
              final active = !player.sleepEndOfSong && player.sleepRemaining != null
                  && (player.sleepRemaining!.inSeconds - p.$1.inSeconds).abs() < 60;
              return ListTile(
                title: Text(p.$2, style: body(TextStyle(color: active ? AppColors.accentLight : AppColors.text, fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
                trailing: active ? Icon(Icons.check, color: AppColors.accentLight) : null,
                onTap: () { player.setSleepTimer(p.$1); Navigator.pop(ctx); },
              );
            }),
            ListTile(
              title: Text('Hết bài này', style: body(TextStyle(color: player.sleepEndOfSong ? AppColors.accentLight : AppColors.text, fontWeight: player.sleepEndOfSong ? FontWeight.w700 : FontWeight.w500))),
              trailing: player.sleepEndOfSong ? Icon(Icons.check, color: AppColors.accentLight) : null,
              onTap: () { player.setSleepEndOfSong(true); Navigator.pop(ctx); },
            ),
          ]),
        ),
      ),
    );
  }

  void _showSpeedSheet() {
    final player = context.read<PlayerProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text('Tốc độ phát', style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
              ),
              ..._speedPresets.map((s) {
                final active = (player.playbackRate - s).abs() < 0.01;
                return ListTile(
                  title: Text('${s}x', style: body(TextStyle(color: active ? AppColors.accentLight : AppColors.text, fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
                  trailing: active ? Icon(Icons.check, color: AppColors.accentLight) : null,
                  onTap: () { player.setPlaybackRate(s); Navigator.pop(ctx); },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();

    // Fetch lovers & lyrics lazily
    if (_lyricsFetchedForId != song['id'].toString()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchLovesAndLyrics(song));
    }
    // Re-extract artwork accent when the thumbnail URL changes.
    final _thumbForAccent = song['thumbnail']?['url']?.toString();
    if (_thumbForAccent != _artworkAccentForUrl) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeExtractAccent(_thumbForAccent));
    }

    if (player.isPlaying && !_rotation.isAnimating) {
      _rotation.repeat();
    } else if (!player.isPlaying && _rotation.isAnimating) {
      _rotation.stop();
    }

    final artists = (song['artists'] is List
        ? song['artists']
        : ((song['artists'] as Map?)?['data'] ?? [])) as List;
    final thumb = song['thumbnail']?['url'];
    final isInstrumental = song['file_type'] == 'instrumental';
    final screen = MediaQuery.of(context).size;
    // Use the shortest viewport dimension so the vinyl stays a circle on
    // wide-screen desktop (where width × 0.72 would overflow the height,
    // clipping the disc into an ellipse-looking slice).
    final vinylSize = math.min(math.min(screen.width, screen.height) * 0.6, 480.0);
    final queue = player.queue;

    return Scaffold(
      backgroundColor: AppColors.bg,
      // Auto-focus + KeyboardListener so 'F' (with no modifier) toggles
      // fullscreen anywhere inside the player. Only swallows F; other keys
      // bubble up to the parent shortcut handler. Disabled on mobile/web
      // where there's no hardware keyboard / OS fullscreen.
      body: KeyboardListener(
        focusNode: _shortcutFocus,
        autofocus: true,
        onKeyEvent: (e) {
          if (!_isDesktopOS) return;
          if (e is! KeyDownEvent) return;
          if (e.logicalKey == LogicalKeyboardKey.keyF &&
              !HardwareKeyboard.instance.isMetaPressed &&
              !HardwareKeyboard.instance.isControlPressed) {
            _toggleFullScreen();
          }
        },
        child: MouseRegion(
          onHover: (_) => _onPointerActivity(),
          // Hide cursor while idle in fullscreen, like Spotify / Apple
          // Music's Now Playing fullscreen — minimises visual noise on
          // top of the artwork.
          cursor: (_isFullScreen && !_chromeVisible) ? SystemMouseCursors.none : MouseCursor.defer,
          child: Stack(
        children: [
          Positioned(
            top: -100, left: 0, right: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              height: 400,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, 0),
                  radius: 0.8,
                  colors: [
                    (_artworkAccent ?? context.watch<ThemeProvider>().palette.accent).withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header — Stack so the centred title is independent of
                // the icon-cluster width: back at left, fullscreen + more
                // at right (Apple Music / Spotify pattern — fullscreen is
                // a primary action, deserves a header slot, not buried in
                // the overflow). Title stays perfectly centred regardless
                // of how many trailing icons are visible (mobile = no
                // fullscreen icon).
                _FadeChrome(
                  visible: _chromeVisible,
                  child: SizedBox(
                    height: 44,
                    child: Stack(
                      children: [
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 120),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'ĐANG PHÁT',
                                  textAlign: TextAlign.center,
                                  style: body(TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: AppColors.textMuted)),
                                ),
                                if (player.sourceLabel != null && player.sourceLabel!.isNotEmpty) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    player.sourceLabel!,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 6, top: 0, bottom: 0,
                          child: Center(
                            child: IconButton(
                              iconSize: 22,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.keyboard_arrow_down, color: AppColors.text),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 6, top: 0, bottom: 0,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (_isDesktopOS) _buildVolumeControl(player),
                            if (_isDesktopOS)
                              IconButton(
                                tooltip: _isFullScreen ? 'Thoát toàn màn hình  F' : 'Toàn màn hình  F',
                                iconSize: 20,
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                  color: _isFullScreen ? AppColors.accentLight : AppColors.textSecondary,
                                ),
                                onPressed: _toggleFullScreen,
                              ),
                            IconButton(
                              iconSize: 20,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.more_horiz, color: AppColors.textSecondary),
                              onPressed: () => _showMoreSheet(context, song, player),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),

                // Panel switcher — segmented tab between Vinyl / Lời /
                // Hàng đợi. Replaces the standalone icon row that was
                // crowding the bottom; chunks panel toggling into a
                // dedicated band so it's no longer mixed in with the
                // transport.
                _FadeChrome(
                  visible: _chromeVisible,
                  child: _buildPanelSwitcher(player, isInstrumental, queue.isNotEmpty),
                ),

                // Panel area (vinyl / lyrics / queue)
                Expanded(
                  child: Center(
                    child: _buildPanel(context, player, song, thumb, vinylSize, isInstrumental, queue),
                  ),
                ),

                // Song info + progress + transport — all fade together
                // when the cursor goes idle in fullscreen, leaving the
                // vinyl / lyrics / queue panel as the sole focus.
                _FadeChrome(
                  visible: _chromeVisible,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Song info — tap title to open song detail.
                      // Heart icon sits to the right of the title block
                      // so the most-frequent secondary action stays
                      // one tap without crowding a separate icon row
                      // at the bottom.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Symmetric spacer so the title stays
                                // optically centred with the heart on
                                // the opposite side.
                                const SizedBox(width: 38),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _openSongDetail(song),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Column(
                                        children: [
                                          Text(
                                            song['title'] ?? '',
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
                                          ),
                                          if (song['subtitle'] != null && (song['subtitle'] as String).isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(song['subtitle'], style: body(TextStyle(fontSize: 14, color: AppColors.textMuted))),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                _buildInlineHeart(song),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _buildCreditsBlock(artists),
                          ],
                        ),
                      ),

                      // Progress bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          children: [
                            SliderTheme(
                              data: SliderThemeData(
                                activeTrackColor: AppColors.accent,
                                inactiveTrackColor: AppColors.border,
                                thumbColor: AppColors.accent,
                                overlayColor: AppColors.accent.withValues(alpha: 0.2),
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: player.position.inMilliseconds.toDouble().clamp(0, player.duration.inMilliseconds.toDouble()),
                                max: player.duration.inMilliseconds.toDouble() > 0 ? player.duration.inMilliseconds.toDouble() : 1,
                                onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_fmt(player.position), style: body(TextStyle(fontSize: 12, color: AppColors.textMuted, fontFeatures: [FontFeature.tabularFigures()]))),
                                  Text(_fmt(player.duration), style: body(TextStyle(fontSize: 12, color: AppColors.textMuted, fontFeatures: [FontFeature.tabularFigures()]))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Next-up chip — peeks the upcoming queue item so
                      // the user knows what's coming without flipping
                      // to the queue panel. Falls back silently when
                      // the queue is empty or there's no next track.
                      _buildNextUpChip(player),

                      // Main transport controls
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _ShuffleButton(active: player.shuffle, onTap: player.toggleShuffle),
                            IconButton(tooltip: 'Bài trước  ⇧ ←', icon: Icon(Icons.skip_previous, size: 36, color: AppColors.text), onPressed: player.playPrev),
                            Container(
                              width: 68, height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                                boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 8))],
                              ),
                              child: IconButton(
                                tooltip: player.isPlaying ? 'Tạm dừng  Space' : 'Phát  Space',
                                icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow, size: 34, color: Colors.white),
                                onPressed: player.togglePlay,
                              ),
                            ),
                            IconButton(tooltip: 'Bài tiếp theo  ⇧ →', icon: Icon(Icons.skip_next, size: 36, color: AppColors.text), onPressed: player.playNext),
                            _RepeatButton(mode: player.repeat, onTap: player.toggleRepeat),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context, PlayerProvider player, Map<String, dynamic> song, String? thumb, double vinylSize, bool isInstrumental, List<Map<String, dynamic>> queue) {
    if (_panel == _PanelMode.lyrics && !isInstrumental) {
      return _buildLyricsPanel();
    }
    if (_panel == _PanelMode.queue && queue.isNotEmpty) {
      return _buildQueuePanel(player, queue);
    }
    return _buildVinyl(thumb, vinylSize);
  }

  Widget _buildVinyl(String? thumb, double vinylSize) {
    return RotationTransition(
      turns: _rotation,
      child: Container(
        width: vinylSize,
        height: vinylSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [AppColors.accent, AppColors.accentLight],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 24)),
            BoxShadow(color: AppColors.accent.withValues(alpha: 0.4), blurRadius: 60, spreadRadius: -10),
          ],
          border: Border.all(color: AppColors.border, width: 4),
        ),
        child: ClipOval(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (thumb != null)
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: thumb,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceLight, child: const Icon(Icons.music_note, size: 80, color: Colors.white38)),
                  ),
                ),
              for (int i = 0; i < 8; i++)
                Container(
                  width: vinylSize - (i * 30),
                  height: vinylSize - (i * 30),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 0.5),
                  ),
                ),
              // Center logo label
              Container(
                width: 62, height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bg,
                  border: Border.all(color: AppColors.border, width: 2),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(10),
                child: SvgPicture.asset('assets/logo-on-dark.svg', width: 36, height: 36),
              ),
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsPanel() {
    // In fullscreen we drop the framed surface + use the karaoke variant
    // so the lyrics fill the screen edge-to-edge for a Now Playing feel.
    final useLarge = _isFullScreen;
    final hasLyrics = _songLyrics != null && _songLyrics!.isNotEmpty;
    final lyricsBody = !hasLyrics
        ? Center(child: Text('Chưa có lời bài hát', style: body(TextStyle(color: AppColors.textMuted, fontSize: 14))))
        : TimedLyrics(
            raw: _songLyrics,
            large: useLarge,
            fontScale: _lyricsScale,
            autoScroll: _lyricsAutoScroll,
            fallback: SingleChildScrollView(
              child: Html(
                data: _songLyrics!,
                style: {
                  'body': Style(
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                    fontSize: FontSize(14 * _lyricsScale),
                    lineHeight: const LineHeight(2.0),
                    color: AppColors.textSecondary,
                    textAlign: TextAlign.center,
                    fontFamily: body().fontFamily,
                  ),
                  'p': Style(margin: Margins.only(bottom: 8)),
                },
              ),
            ),
          );
    final inner = Column(children: [
      if (hasLyrics) _buildLyricsToolbar(),
      Expanded(child: lyricsBody),
    ]);
    return Container(
      margin: useLarge ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 24),
      padding: useLarge ? EdgeInsets.zero : const EdgeInsets.all(16),
      decoration: useLarge ? null : BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: inner,
    );
  }

  Widget _buildLyricsToolbar() {
    final scaleLabel = '${(_lyricsScale * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Cỡ chữ nhỏ hơn',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.text_decrease, color: AppColors.textSecondary),
            onPressed: _lyricsScale > 0.7
                ? () => setState(() => _lyricsScale = (_lyricsScale - 0.1).clamp(0.7, 1.6))
                : null,
          ),
          Text(scaleLabel, style: body(TextStyle(fontSize: 11, color: AppColors.textMuted, fontFeatures: [FontFeature.tabularFigures()]))),
          IconButton(
            tooltip: 'Cỡ chữ lớn hơn',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.text_increase, color: AppColors.textSecondary),
            onPressed: _lyricsScale < 1.6
                ? () => setState(() => _lyricsScale = (_lyricsScale + 0.1).clamp(0.7, 1.6))
                : null,
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: _lyricsAutoScroll ? 'Tắt cuộn theo nhạc' : 'Bật cuộn theo nhạc',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _lyricsAutoScroll ? Icons.lock_open_outlined : Icons.lock_outline,
              color: _lyricsAutoScroll ? AppColors.accentLight : AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _lyricsAutoScroll = !_lyricsAutoScroll),
          ),
        ],
      ),
    );
  }

  Widget _buildQueuePanel(PlayerProvider player, List<Map<String, dynamic>> queue) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        // Reorderable + dismissible: drag the handle to reorder, swipe
        // either direction to remove. Reorder/remove route through the
        // PlayerProvider so playback survives an active-track shuffle.
        child: ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: queue.length,
          buildDefaultDragHandles: false,
          onReorder: (o, n) => player.reorderQueue(o, n),
          proxyDecorator: (child, _, _) => Material(
            color: Colors.transparent,
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.4),
            child: child,
          ),
          itemBuilder: (ctx, idx) {
            final s = queue[idx];
            final isActive = idx == player.currentIndex;
            final artists = s['artists'] is List ? s['artists'] : (s['artists']?['data'] ?? []);
            final artistText = (artists as List).map((a) => a['title'] ?? '').join(', ');
            final thumb = s['thumbnail']?['url'];
            return Dismissible(
              key: ValueKey('fp-q-${s['id']}-$idx'),
              direction: DismissDirection.horizontal,
              background: Container(
                color: AppColors.accent.withValues(alpha: 0.85),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
              ),
              secondaryBackground: Container(
                color: AppColors.accent.withValues(alpha: 0.85),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
              ),
              onDismissed: (_) => player.removeFromQueue(idx),
              child: InkWell(
                onTap: () => player.playAtIndex(idx),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.accentSoft : Colors.transparent,
                    border: Border(left: BorderSide(color: isActive ? AppColors.accent : Colors.transparent, width: 3)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Center(
                          child: isActive
                              ? Icon(Icons.graphic_eq, size: 14, color: AppColors.accentLight)
                              : Text('${idx + 1}', style: body(TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: thumb != null
                            ? CachedNetworkImage(imageUrl: thumb, width: 36, height: 36, fit: BoxFit.cover)
                            : Container(width: 36, height: 36, color: AppColors.surface, child: Icon(Icons.music_note, size: 16, color: AppColors.textMuted)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s['title'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isActive ? AppColors.accentLight : AppColors.text)),
                            ),
                            if (artistText.isNotEmpty)
                              Text(
                                artistText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: body(TextStyle(fontSize: 11, color: isActive ? AppColors.accentLight.withValues(alpha: 0.8) : AppColors.textSecondary)),
                              ),
                          ],
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: idx,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.drag_indicator, size: 18, color: AppColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}


class _ShuffleButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _ShuffleButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active ? 'Đảo: bật' : 'Đảo: tắt',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(Icons.shuffle, size: 22, color: active ? AppColors.accentLight : AppColors.textSecondary),
              if (active)
                Positioned(
                  bottom: -5,
                  child: Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepeatButton extends StatelessWidget {
  final PlayerRepeatMode mode;
  final VoidCallback onTap;
  const _RepeatButton({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = mode != PlayerRepeatMode.off;
    final tooltip = mode == PlayerRepeatMode.off ? 'Lặp: tắt' : mode == PlayerRepeatMode.all ? 'Lặp: tất cả' : 'Lặp: 1 bài';
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(Icons.repeat, size: 22, color: active ? AppColors.accentLight : AppColors.textSecondary),
              if (mode == PlayerRepeatMode.all)
                Positioned(
                  bottom: -5,
                  child: Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
                  ),
                ),
              if (mode == PlayerRepeatMode.one)
                Positioned(
                  top: -4, right: -5,
                  child: Text('1', style: body(TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header / footer wrapper that fades + ignores pointer when [visible] is
/// false. Used to auto-hide the player chrome on idle in fullscreen mode
/// without affecting layout (the slot still occupies its space so the
/// vinyl panel doesn't jump when chrome reappears).
class _FadeChrome extends StatelessWidget {
  final bool visible;
  final Widget child;
  const _FadeChrome({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      child: IgnorePointer(ignoring: !visible, child: child),
    );
  }
}
