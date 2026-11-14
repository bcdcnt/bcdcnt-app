import '../services/imgcdn.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'share_card.dart' show showSongShareSheet;
import '../services/friendly_error.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:go_router/go_router.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:window_manager/window_manager.dart';
import 'timed_lyrics.dart';
import '../constants/theme.dart';
import '../services/player.dart';
import '../services/auth.dart';
import 'ui.dart' show UserAvatar, keyTip;
import 'song_row.dart' show GeneratedCover, saveForOffline;
import 'brand_logo.dart';
import 'synced_video.dart';
import 'lyrics_text.dart';
import '../services/api.dart';

/// Fixed "now playing" palette: the logo's wine red with cream type, used
/// whatever app theme is active (so the player reads as its own room, like
/// the mockup). Everything in this file colours through _PC, never AppColors
/// surfaces directly. Sheets opened from here need solid fills, hence the
/// opaque surface tones.
class _PC {
  static const bg = Color(0xFF2A0C0C);
  static const surface = Color(0xFF341111);
  static const surfaceLight = Color(0xFF401616);
  static const surfaceHover = Color(0xFF4C1C1C);
  static const accent = Color(0xFFFFFFFF);
  static const accentLight = Color(0xFFE0AEAC);
  static const accentSoft = Color(0x1FFFFFFF);
  static const text = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xC7FFFFFF);
  static const textMuted = Color(0x8CFFFFFF);
  static const border = Color(0x40FFFFFF);
  static const borderSubtle = Color(0x1FFFFFFF);
  static const wine = Color(0xFF711313);
}

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
  // Phone layout's outer scroll (player page + lyrics card below).
  final ScrollController _mobileScroll = ScrollController();
  bool _closingByPull = false;
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
  String? _songLyrics;
  // "kind-id" of the song the lyrics/likes/credits below belong to. A
  // response for any other key arrived after the user skipped: dropped.
  String? _lyricsFetchedForId;
  // Composer + poet credits, fetched alongside the lyrics. Traditional
  // music on BCĐCNT often hangs on the songwriter / poet identity, so
  // we surface them as a dedicated row in the player chrome instead
  // of the artist-only line we used to show.
  List<Map<String, dynamic>> _composers = [];
  List<Map<String, dynamic>> _poets = [];
  List<Map<String, dynamic>> _recomposers = [];
  // Performers with avatars for the "Thực hiện" card (queue items often
  // carry artists without images).
  List<Map<String, dynamic>> _creditArtists = [];
  // Phone player cards below the controls: song story, year, the most
  // liked comment and the comment count.
  String? _story;
  String? _year;
  Map<String, dynamic>? _topComment;
  int _commentCount = 0;

  // Lyrics panel display preferences. Persist across panel toggles
  // within the same session; reset on reload.
  double _lyricsScale = 1.0;
  bool _lyricsAutoScroll = true;

  final ScrollController _roomScroll = ScrollController();
  // Desktop: the right column (lyrics, comments, credits) stays closed
  // until "Lời bài hát" is pressed, so the player has the whole width.
  bool _roomOpen = false;
  bool get _isDesktopOS => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  bool get _isPhoneOS => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

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

  // Dominant color extracted from the current artwork. Drives the top
  // radial-gradient backdrop so it looks colour-coordinated with the song,
  // matching Spotify's "now playing" vibe.
  Color? _artworkAccent;
  String? _artworkAccentForUrl;
  // Cached so `dispose()` can clear `fullPlayerOpen` without going
  // through `context.read` after the element has been detached.
  PlayerProvider? _playerRef;

  static const List<double> _speedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    // Started by build() only for the desktop layout; the phone layout has
    // no disc, and a running controller would tick 60fps for nothing.
    _rotation = AnimationController(vsync: this, duration: const Duration(seconds: 32));
    // Khôi phục cỡ chữ lời đã lưu (đồng bộ trải nghiệm với web).
    SharedPreferences.getInstance().then((p) {
      final v = p.getDouble('lyrics_scale');
      if (v != null && mounted) setState(() => _lyricsScale = v.clamp(0.7, 1.6));
    });
    // Cache the provider for `dispose()` — and re-assert the
    // open flag in case we were pushed by code that didn't flip
    // it (deep links, keyboard shortcuts, etc.). The setter
    // no-ops if the value is already `true`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playerRef = context.read<PlayerProvider>();
      _playerRef!.setFullPlayerOpen(true);
      // Phones have no mute button here (volume keys do that job), so a
      // mute left from an older build must not leave the song silent.
      if (_isPhoneOS) _playerRef!.ensureUnmuted();
    });
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
    _mobileScroll.dispose();
    _roomScroll.dispose();
    _idleTimer?.cancel();
    // Restore the pill via the cached reference — `context.read`
    // here is unreliable since the element is mid-teardown.
    _playerRef?.setFullPlayerOpen(false);
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
        CachedNetworkImageProvider(cdnImg((url).toString(), 320)),
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

  /// Person pages live in the app's navigator, under this full-screen
  /// player — close the player first or the page opens out of sight.
  void _openPerson(String route) {
    Navigator.of(context).pop();
    context.push(route);
  }

  void _openArtistDetail(Map artist) {
    // Karaoke singers are members, whatever shape the list gave them.
    final current = context.read<PlayerProvider>().currentSong;
    if (songKind(current) == 'karaoke' && artist['id'] != null) {
      _openPerson('/user/${artist['id']}');
      return;
    }
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
            hoverColor: _PC.surfaceHover,
            icon: Icon(
              muted ? Icons.volume_off : (value < 0.4 ? Icons.volume_down : Icons.volume_up),
              color: muted ? _PC.accentLight : _PC.textSecondary,
            ),
            onPressed: player.toggleMute,
          ),
          SizedBox(
            width: 80,
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: _PC.accent,
                inactiveTrackColor: _PC.border,
                thumbColor: _PC.accent,
                overlayColor: _PC.accent.withValues(alpha: 0.18),
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






  String _songType(Map<String, dynamic> song) => songKind(song);
  String _songKey(Map song) => '${songKind(song)}-${song['id']}';

  Future<void> _fetchLovesAndLyrics(Map<String, dynamic> song) async {
    final id = song['id'].toString();
    final type = _songType(song);
    final key = _songKey(song);
    if (_lyricsFetchedForId != key) {
      _lyricsFetchedForId = key;
      // Clear the previous song's data at once: otherwise its lyrics, heart
      // and credits stay on screen under the new title until (or if) the
      // new request answers.
      if (mounted) {
        setState(() {
          _liked = false;
          _lovers = [];
          _songLyrics = null;
          _composers = [];
          _poets = [];
          _recomposers = [];
          _creditArtists = [];
        });
      }
      // Composers + poets are first-class metadata for traditional
      // music; fetched alongside lyrics so the player can show
      // "Sáng tác: X · Thơ: Y" right under the title.
      // Karaoke songs don't have composers/poets at the top level —
      // narrow the field set to avoid GraphQL "Cannot query field"
      // errors on those routes.
      // Each song type exposes different credit relations; asking for one
      // it doesn't have makes the API reject the whole query (folk /
      // instrumental / poem used to lose lyrics and likes this way).
      const person = '{ data { id title slug avatar { url } } }';
      final creditFields = switch (type) {
        // Some recordings only credit the composer on their sheet.
        'song' => 'composers(first: 5) $person poets(first: 5) $person artists(first: 10) $person sheet { composers(first: 5) $person poets(first: 5) $person }',
        'folk' => 'composers(first: 5) $person recomposers(first: 5) $person artists(first: 10) $person',
        'instrumental' => 'composers(first: 5) $person artists(first: 10) $person',
        'poem' => 'poets(first: 5) $person artists(first: 10) $person',
        // Karaoke: the composition's authors sit on the sheet, the singers are members.
        'karaoke' => 'sheet { composers(first: 5) $person poets(first: 5) $person } users(first: 10) { data { id username avatar { url } } }',
        _ => '',
      };
      try {
        final data = await ApiClient.query(
          'query(\$id: ID!) { $type(id: \$id) { content $creditFields loves(first: 50) { data { user_id user { id username avatar { url } } } } } }',
          {'id': id},
        );
        final obj = data[type];
        final lovesData = (obj?['loves']?['data'] ?? []) as List;
        List<Map<String, dynamic>> people(String key) {
          final own = obj?[key]?['data'] as List?;
          return ((own != null && own.isNotEmpty ? own : obj?['sheet']?[key]?['data']) as List? ?? const [])
              .map((c) => Map<String, dynamic>.from(c as Map))
              .toList();
        }
        final composers = people('composers');
        final poets = people('poets');
        final recomposers = ((obj?['recomposers']?['data']) as List? ?? const [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        final creditArtists = type == 'karaoke'
            ? ((obj?['users']?['data']) as List? ?? const [])
                .map((u) => <String, dynamic>{'id': u['id'], 'title': u['username'], 'username': u['username'], 'avatar': u['avatar']})
                .toList()
            : people('artists');
        if (!mounted || _lyricsFetchedForId != key) return;
        setState(() {
          _lovers = lovesData;
          _songLyrics = obj?['content'];
          _composers = composers;
          _poets = poets;
          _creditArtists = creditArtists;
          _recomposers = recomposers;
          final userId = context.read<AuthProvider>().user?['id'];
          if (userId != null) {
            _liked = lovesData.any((l) => l['user_id'].toString() == userId.toString());
          }
        });
      } catch (_) {}
      if (mounted && _lyricsFetchedForId == key) _fetchStory(type, id, key);
    }
  }

  /// Story / year / best comment for the phone player's cards. Separate
  /// from the main fetch: not every song type has every field, and a
  /// failure here must not cost the lyrics.
  Future<void> _fetchStory(String type, String id, String key) async {
    if (!mounted) return;
    setState(() {
      _story = null;
      _year = null;
      _topComment = null;
      _commentCount = 0;
    });
    final sheet = type == 'song' ? 'year sheet { year description }' : '';
    try {
      final d = await ApiClient.query(
        'query(\$id: ID!) { $type(id: \$id) { description $sheet comments(first: 1, orderBy: [{column: "likes", order: DESC}]) { data { content likes user { username avatar { url } } } paginatorInfo { total } } } }',
        {'id': id},
      );
      final o = d[type];
      if (!mounted || o == null || _lyricsFetchedForId != key) return;
      String clean(dynamic h) => (h ?? '').toString()
          .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
      final story = clean(o['description']).isNotEmpty ? clean(o['description']) : clean(o['sheet']?['description']);
      final year = (o['sheet']?['year'] ?? o['year'])?.toString();
      final cm = ((o['comments']?['data'] ?? []) as List).whereType<Map>().toList();
      setState(() {
        _story = story.isEmpty ? null : story;
        _year = (year == null || year.isEmpty || year == '0') ? null : year;
        _topComment = cm.isNotEmpty && clean(cm.first['content']).isNotEmpty ? {...Map<String, dynamic>.from(cm.first), 'text': clean(cm.first['content'])} : null;
        _commentCount = (o['comments']?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _handleLove(Map<String, dynamic> song) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      askLogin(context);
      return;
    }
    final type = _songType(song);
    final key = _songKey(song);
    final newLiked = !_liked;
    final prevLovers = _lovers;
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
      lovesChanged.value++;
    } catch (e) {
      if (!mounted) return;
      // Only undo if the user is still on that song; the heart now shows
      // another song's state.
      if (_lyricsFetchedForId == key) {
        setState(() {
          _liked = !newLiked;
          _lovers = prevLovers;
        });
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(friendlyError(e, fallback: newLiked ? 'Chưa thích được bài này, vui lòng thử lại.' : 'Chưa bỏ thích được, vui lòng thử lại.')),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _handleDownload(Map<String, dynamic> song) async {
    // Phones: save inside the app ("Đã tải về") — opening the mp3 in Safari
    // left older users on a bare audio page with no way back.
    if (!kIsWeb && !_isDesktopOS) {
      await saveForOffline(context, song);
      return;
    }
    if (_downloading) return;
    setState(() => _downloading = true);
    final auth = context.read<AuthProvider>();
    // Always send the mutation — let the backend's "Vui lòng đăng
    // nhập để tải" message bubble back through the GraphQL error
    // path. Mirrors the web flow so the auth gate lives in one
    // place (server-side).
    try {
      final tok = auth.token;
      final data = await ApiClient.mutate(
        r'''mutation($t: String!, $i: ID!) { download(object_type: $t, object_id: $i) { url } }''',
        {'t': _songType(song), 'i': song['id'].toString()},
        tok,
      );
      final url = data['download']?['url'];
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bạn đã tải quá nhiều'), backgroundColor: AppColors.error));
      }
    } catch (e) {
      // friendlyError keeps the server's Vietnamese message ("Vui lòng
      // đăng nhập để tải") and hides raw network exceptions.
      final msg = friendlyError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.error));
    }
    if (mounted) setState(() => _downloading = false);
  }

  /// Same share sheet as the song page (Zalo, Facebook, picture card…)
  /// instead of an empty mail draft.
  Future<void> _handleShare(Map<String, dynamic> song) => showSongShareSheet(context, song);

  void _showMoreSheet(BuildContext ctx, Map<String, dynamic> song, PlayerProvider player) {
    final speedLabel = '${player.playbackRate.toStringAsFixed(player.playbackRate == player.playbackRate.roundToDouble() ? 0 : 2)}x';
    final hasQueue = player.queue.isNotEmpty;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: _PC.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Heart + panel toggles live in the main UI now (inline
          // title + tab strip above the panel). This sheet keeps the
          // less common actions: queue, share, download, speed, mute, sleep.
          if (hasQueue)
            ListTile(
              leading: Icon(Icons.queue_music_rounded, color: _PC.textSecondary),
              title: Text('Danh sách phát', style: body(TextStyle(color: _PC.text))),
              trailing: Text('${player.queue.length} bài', style: body(TextStyle(color: _PC.textMuted, fontSize: 13))),
              onTap: () { Navigator.pop(sheetCtx); _showQueueSheet(); },
            ),
          ListTile(
            leading: Icon(Icons.ios_share, color: _PC.textSecondary),
            title: Text('Chia sẻ', style: body(TextStyle(color: _PC.text))),
            onTap: () { Navigator.pop(sheetCtx); _handleShare(song); },
          ),
          ListTile(
            leading: Icon(_downloading ? Icons.hourglass_empty : Icons.download_outlined, color: _PC.textSecondary),
            title: Text(_downloading ? 'Đang tải...' : 'Tải về', style: body(TextStyle(color: _PC.text))),
            onTap: () { Navigator.pop(sheetCtx); _handleDownload(song); },
          ),
          Divider(height: 1, color: _PC.borderSubtle),
          ListTile(
            leading: Icon(Icons.speed, color: player.playbackRate != 1.0 ? _PC.accentLight : _PC.textSecondary),
            title: Text('Tốc độ phát', style: body(TextStyle(color: _PC.text))),
            trailing: Text(speedLabel, style: body(TextStyle(
              color: player.playbackRate != 1.0 ? _PC.accentLight : _PC.textMuted,
              fontSize: 13, fontWeight: FontWeight.w700,
            ))),
            onTap: () { Navigator.pop(sheetCtx); _showSpeedSheet(); },
          ),
          // Phones and the web use the device's own volume keys.
          if (_isDesktopOS)
          ListTile(
            leading: Icon(player.muted ? Icons.volume_off : Icons.volume_up, color: _PC.textSecondary),
            title: Text(player.muted ? 'Bật âm thanh' : 'Tắt âm thanh', style: body(TextStyle(color: _PC.text))),
            onTap: () { Navigator.pop(sheetCtx); player.toggleMute(); },
          ),
          ListTile(
            leading: Icon(Icons.bedtime_outlined, color: player.hasSleepTimer ? _PC.accentLight : _PC.textSecondary),
            title: Text(
              player.hasSleepTimer ? 'Hẹn giờ tắt' : 'Hẹn giờ tắt',
              style: body(TextStyle(color: player.hasSleepTimer ? _PC.accentLight : _PC.text)),
            ),
            trailing: player.hasSleepTimer
                // Re-read the countdown on each position tick (the provider
                // no longer notifies per tick).
                ? ValueListenableBuilder<Duration>(
                    valueListenable: player.positionNotifier,
                    builder: (context, _, _) => Text(_sleepTimerLabel(player), style: body(TextStyle(color: _PC.accentLight, fontSize: 13, fontWeight: FontWeight.w700))),
                  )
                : null,
            onTap: () { Navigator.pop(sheetCtx); _showSleepSheet(); },
          ),
          // Visible way to stop for good (the mini player's long-press is hidden).
          ListTile(
            leading: Icon(Icons.stop_circle_outlined, color: _PC.textSecondary),
            title: Text('Dừng phát', style: body(TextStyle(color: _PC.text))),
            onTap: () {
              Navigator.pop(sheetCtx);
              player.stop();
              Navigator.of(context).maybePop();
            },
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
      backgroundColor: _PC.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(children: [
                Icon(Icons.bedtime_outlined, size: 18, color: _PC.accentLight),
                const SizedBox(width: 8),
                Text('Hẹn giờ tắt', style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _PC.text))),
                const Spacer(),
                if (player.hasSleepTimer)
                  TextButton(
                    onPressed: () { player.cancelSleepTimer(); Navigator.pop(ctx); },
                    child: Text('Huỷ', style: body(TextStyle(color: _PC.accentLight, fontWeight: FontWeight.w700))),
                  ),
              ]),
            ),
            ...presets.map((p) {
              final active = !player.sleepEndOfSong && player.sleepRemaining != null
                  && (player.sleepRemaining!.inSeconds - p.$1.inSeconds).abs() < 60;
              return ListTile(
                title: Text(p.$2, style: body(TextStyle(color: active ? _PC.accentLight : _PC.text, fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
                trailing: active ? Icon(Icons.check, color: _PC.accentLight) : null,
                onTap: () { player.setSleepTimer(p.$1); Navigator.pop(ctx); },
              );
            }),
            ListTile(
              title: Text('Hết bài này', style: body(TextStyle(color: player.sleepEndOfSong ? _PC.accentLight : _PC.text, fontWeight: player.sleepEndOfSong ? FontWeight.w700 : FontWeight.w500))),
              trailing: player.sleepEndOfSong ? Icon(Icons.check, color: _PC.accentLight) : null,
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
      backgroundColor: _PC.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text('Tốc độ phát', style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _PC.text))),
              ),
              ..._speedPresets.map((s) {
                final active = (player.playbackRate - s).abs() < 0.01;
                return ListTile(
                  title: Text('${s}x', style: body(TextStyle(color: active ? _PC.accentLight : _PC.text, fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
                  trailing: active ? Icon(Icons.check, color: _PC.accentLight) : null,
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
    if (_lyricsFetchedForId != _songKey(song)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchLovesAndLyrics(song));
    }
    // Re-extract artwork accent when the thumbnail URL changes.
    final _thumbForAccent = song['thumbnail']?['url']?.toString();
    if (_thumbForAccent != _artworkAccentForUrl) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeExtractAccent(_thumbForAccent));
    }


    final artists = (song['artists'] is List
        ? song['artists']
        : ((song['artists'] as Map?)?['data'] ?? [])) as List;
    final thumb = song['thumbnail']?['url'];
    final isInstrumental = songKind(song) == 'instrumental';
    final screen = MediaQuery.of(context).size;
    final narrow = screen.width < 600; // mobile/cửa sổ hẹp → rút gọn 1 dòng
    // The spinning disc only exists in the desktop layout.
    final spin = player.isPlaying && !(narrow && !_isFullScreen);
    if (spin && !_rotation.isAnimating) {
      _rotation.repeat();
    } else if (!spin && _rotation.isAnimating) {
      _rotation.stop();
    }
    // Use the shortest viewport dimension so the vinyl stays a circle on
    // wide-screen desktop (where width × 0.72 would overflow the height,
    // clipping the disc into an ellipse-looking slice).
    // Hẹp (mobile): to gần bằng web (~0.82×bề ngang, chặn 0.46×chiều cao để vẫn tròn).
    // Rộng (desktop): giữ 0.6×cạnh ngắn nhất.
    final vinylSize = math.min(
      narrow
          ? math.min(screen.width * 0.82, screen.height * 0.46)
          : math.min(screen.width, screen.height) * 0.6,
      480.0,
    );
    final queue = player.queue;

    if (narrow && !_isFullScreen) {
      return _buildMobile(context, player, song, thumb, artists, isInstrumental);
    }
    return _buildRoom(context, player, song, thumb, artists, isInstrumental);
  }

  // ---------------------------------------------------------------------
  // Desktop (canvas "Desktop · Đang phát toàn màn"): the phone player laid
  // out side by side — cover, title + heart, scrubber, transport and the
  // three labelled pills on the left; the cards the phone keeps below the
  // fold (Lời, Câu chuyện, Cảm nhận hay, Thực hiện) scroll on the right.
  // ---------------------------------------------------------------------
  Widget _buildRoom(BuildContext context, PlayerProvider player, Map<String, dynamic> song, String? thumb, List artists, bool isInstrumental) {
    bool ok(dynamic s) => s != null && s.toString().isNotEmpty && s != 'Đang cập nhật';
    final artistText = artists.map((a) => a is Map ? a['title'] : null).where(ok).join(', ');
    final isPoem = songKind(song) == 'poem';
    final isKaraoke = songKind(song) == 'karaoke';
    final composerText = (isPoem ? _poets : _composers).map((c) => c['title']).where(ok).join(', ');
    final subline = [artistText, composerText, if (_year != null) _year!].where((s) => s.isNotEmpty).join(' · ');
    final hasLyrics = !isInstrumental && (_songLyrics?.trim().isNotEmpty ?? false);
    final label = player.sourceLabel;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.night,
        body: KeyboardListener(
          focusNode: _shortcutFocus,
          autofocus: true,
          onKeyEvent: (e) {
            if (!_isDesktopOS || e is! KeyDownEvent) return;
            if (e.logicalKey == LogicalKeyboardKey.keyF && !HardwareKeyboard.instance.isMetaPressed && !HardwareKeyboard.instance.isControlPressed) _toggleFullScreen();
            if (e.logicalKey == LogicalKeyboardKey.escape && !_isFullScreen) Navigator.pop(context);
          },
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.55, 1],
                colors: [Color(0xFF5A1414), Color(0xFF2A0C0C), AppColors.night],
              ),
            ),
            child: SafeArea(
              child: Column(children: [
                SizedBox(
                  height: 72,
                  child: Row(children: [
                    const SizedBox(width: 16),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30, color: Colors.white),
                      label: Text('Thu nhỏ', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white))),
                    ),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('ĐANG PHÁT TỪ', style: body(const TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: Color(0xB3FFFFFF)))),
                        Text(label != null && label.isNotEmpty ? label : 'BCĐCNT', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
                      ]),
                    ),
                    if (_isDesktopOS) _buildVolumeControl(player),
                    if (_isDesktopOS)
                      IconButton(
                        tooltip: keyTip(context, _isFullScreen ? 'Thoát toàn màn hình' : 'Toàn màn hình', 'F'),
                        onPressed: _toggleFullScreen,
                        icon: Icon(_isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white, size: 26),
                      ),
                    IconButton(tooltip: 'Tuỳ chọn', icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 26), onPressed: () => _showMoreSheet(context, song, player)),
                    const SizedBox(width: 16),
                  ]),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(64, 4, 48, 28),
                    child: LayoutBuilder(builder: (context, box) {
                      // The cover gives way first, so the controls always fit.
                      final art = _roomOpen
                          ? (box.maxHeight - 345).clamp(220.0, math.min(480.0, box.maxWidth * 0.42)).toDouble()
                          : (box.maxHeight - 345).clamp(200.0, 460.0).toDouble();
                      final center = !_roomOpen;
                      final titleRow = Row(children: [
                              // Balances the heart so the title sits mid-screen.
                              if (center) const SizedBox(width: 50),
                              Expanded(
                                child: InkWell(
                                  onTap: () => _openSongDetail(song),
                                  child: Column(crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
                                    Text(song['title'] ?? '', textAlign: center ? TextAlign.center : TextAlign.start, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 32, height: 1.15, letterSpacing: -0.6, fontWeight: FontWeight.w800, color: Colors.white))),
                                    if (subline.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(subline, textAlign: center ? TextAlign.center : TextAlign.start, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xBFFFFFFF)))),
                                    ],
                                  ]),
                                ),
                              ),
                              IconButton(
                                tooltip: _liked ? 'Bỏ yêu thích' : 'Yêu thích',
                                iconSize: 34,
                                icon: Icon(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: _liked ? AppColors.love : Colors.white),
                                onPressed: () => _handleLove(song),
                              ),
                            ]);
                      final controls = Row(mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween, spacing: center ? 40 : 0, children: [
                              _ShuffleButton(active: player.shuffle, onTap: player.toggleShuffle),
                              IconButton(tooltip: keyTip(context, 'Bài trước', '⇧←'), iconSize: 42, icon: const Icon(Icons.skip_previous_rounded, color: Colors.white), onPressed: player.playPrev),
                              Material(
                                color: Colors.white,
                                shape: const CircleBorder(),
                                elevation: 8,
                                shadowColor: Colors.black54,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: player.togglePlay,
                                  child: SizedBox(
                                    width: 84, height: 84,
                                    child: player.isLoading
                                        ? const Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.wine)))
                                        : Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 44, color: AppColors.wine),
                                  ),
                                ),
                              ),
                              IconButton(tooltip: keyTip(context, 'Bài tiếp', '⇧→'), iconSize: 42, icon: const Icon(Icons.skip_next_rounded, color: Colors.white), onPressed: player.playNext),
                              _RepeatButton(mode: player.repeat, onTap: player.toggleRepeat),
                            ]);
                      final pills = [
                        _pill(hasLyrics ? Icons.notes_rounded : Icons.info_outline_rounded, hasLyrics ? 'Lời bài hát' : 'Thông tin bài', () => setState(() => _roomOpen = !_roomOpen), on: _roomOpen),
                        _pill(Icons.bedtime_outlined, player.hasSleepTimer ? 'Đang hẹn' : 'Hẹn giờ', _showSleepSheet, active: player.hasSleepTimer),
                        _pill(Icons.queue_music_rounded, 'Danh sách', _showQueueSheet),
                      ];
                      final artwork = isVideoSong(song) ? _mobileVideo(player, song, art) : _mobileArtwork(thumb, art, player.isPlaying, song);
                      // Lời tắt: one centred column, the scrubber running the width.
                      if (!_roomOpen) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 56),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            SizedBox(width: art, child: artwork),
                            const SizedBox(height: 26),
                            titleRow,
                            const SizedBox(height: 12),
                            _mobileScrubber(player),
                            const SizedBox(height: 6),
                            controls,
                            const SizedBox(height: 20),
                            Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 10, children: [for (final p in pills) SizedBox(width: 160, child: p)]),
                          ]),
                        );
                      }
                      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(
                          width: art,
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            artwork,
                            const SizedBox(height: 26),
                            titleRow,
                            const SizedBox(height: 12),
                            _mobileScrubber(player),
                            const SizedBox(height: 6),
                            controls,
                            const SizedBox(height: 20),
                            Row(spacing: 8, children: [for (final p in pills) Expanded(child: p)]),
                          ]),
                        ),
                        const SizedBox(width: 56),
                        Expanded(
                          child: ListView(controller: _roomScroll, padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
                            if (hasLyrics)
                              _card(
                                title: 'Lời bài hát',
                                trailing: composerText.isNotEmpty ? composerText : null,
                                child: TimedLyrics.hasLrc(_songLyrics) ? SizedBox(height: box.maxHeight * 0.66, child: _buildLyricsPanel(bare: true)) : _buildFlowingLyrics(),
                              ),
                            if (_story != null)
                              _card(
                                title: 'Câu chuyện bài hát',
                                onTap: () => _openSongDetail(song),
                                child: Text(_story!.length > 900 ? '${_story!.substring(0, 900)}…' : _story!, style: body(const TextStyle(fontSize: 16, height: 1.6, fontWeight: FontWeight.w500, color: Color(0xE6FFFFFF)))),
                              ),
                            if (_topComment != null)
                              _card(
                                title: 'Cảm nhận hay',
                                trailing: _commentCount > 0 ? '$_commentCount bình luận' : null,
                                onTap: () => _openSongDetail(song),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('“${_topComment!['text']}”', maxLines: 8, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 17, height: 1.55, fontWeight: FontWeight.w600, color: Colors.white))),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    UserAvatar(url: _topComment!['user']?['avatar']?['url']?.toString(), name: (_topComment!['user']?['username'] ?? '').toString(), size: 26),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text((_topComment!['user']?['username'] ?? '').toString(), style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xB3FFFFFF))))),
                                    Text('Xem tất cả', style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFE0AEAC)))),
                                  ]),
                                ]),
                              ),
                            if (_composers.isNotEmpty || _poets.isNotEmpty || artists.isNotEmpty)
                              _card(
                                title: 'Thực hiện',
                                child: Column(children: [
                                  for (final c in _composers) _creditRow(c, 'Sáng tác', () => _openPerson('/nhac-si/${c['slug']}')),
                                  for (final c in _recomposers) _creditRow(c, 'Soạn giả', () => _openPerson('/soan-gia/${c['slug']}')),
                                  for (final c in _poets) _creditRow(c, isPoem ? 'Sáng tác' : 'Lời thơ', () => _openPerson('/nha-tho/${c['slug']}')),
                                  for (final a in (_creditArtists.isNotEmpty ? _creditArtists : artists).whereType<Map>().where((a) => ok(a['title'])))
                                    isKaraoke
                                        ? _creditRow(Map<String, dynamic>.from(a), 'Thể hiện', () => _openPerson('/user/${a['id']}'))
                                        : _creditRow(Map<String, dynamic>.from(a), 'Trình bày', () => _openArtistDetail(a)),
                                ]),
                              ),
                          ]),
                        ),
                      ]);
                    }),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Phone layout (2026-11): one calm screen — disc, title + artists, heart,
  // scrubber, transport. Lyrics sit right below; their card peeks from the
  // bottom edge so a scroll reveals them. Queue lives behind the header
  // button. Desktop/fullscreen keep the panel layout below.
  // ---------------------------------------------------------------------
  Widget _buildMobile(BuildContext context, PlayerProvider player, Map<String, dynamic> song, String? thumb, List artists, bool isInstrumental) {
    bool ok(dynamic s) => s != null && s.toString().isNotEmpty && s != 'Đang cập nhật';
    final artistText = artists.map((a) => a is Map ? a['title'] : null).where(ok).join(', ');
    // Tiếng thơ has no composer: the poet is the author, shown in the same place.
    final isPoem = songKind(song) == 'poem';
    final isKaraoke = songKind(song) == 'karaoke';
    final composerText = (isPoem ? _poets : _composers).map((c) => c['title']).where(ok).join(', ');
    final subline = [artistText, composerText, if (_year != null) _year!].where((s) => s.isNotEmpty).join(' · ');
    final hasLyrics = !isInstrumental && (_songLyrics?.trim().isNotEmpty ?? false);
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.night,
        body: DecoratedBox(
          // Brand room: wine at the top fading to near-black.
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.44, 0.76],
              colors: [Color(0xFF5A1414), Color(0xFF2A0C0C), AppColors.night],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, box) {
                final pageH = math.max(box.maxHeight, 600.0);
                final art = math.min(box.maxWidth - 56, pageH * 0.44);
                return NotificationListener<ScrollUpdateNotification>(
                  // Pull down past the top (bounce) to close, like
                  // Apple Music / Spotify.
                  onNotification: (n) {
                    if (!_closingByPull && n.dragDetails != null && n.metrics.pixels < -90) {
                      _closingByPull = true;
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    controller: _mobileScroll,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        // The first screen is a fixed-height page; at the
                        // largest system text its chrome would overflow, so
                        // cap scaling there (like the mini player). Lyrics
                        // and cards below keep the full text size.
                        child: MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.4,
                          child: SizedBox(
                          height: pageH - 24,
                          child: Column(
                            children: [
                              _mobileHeader(player, song),
                              // Cover takes whatever height the text leaves,
                              // so a long title or big text shrinks the
                              // picture instead of pushing buttons off-screen.
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, area) {
                                    final room = math.max(area.maxHeight - 24, 80.0);
                                    return Center(
                                      child: isVideoSong(song)
                                          ? _mobileVideo(player, song, math.min(box.maxWidth - 32, room * 16 / 9))
                                          : _mobileArtwork(thumb, math.min(art, room), player.isPlaying, song),
                                    );
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 28),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => _openSongDetail(song),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(song['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                                                style: display(const TextStyle(fontSize: 24, height: 1.2, fontWeight: FontWeight.w800, color: Colors.white))),
                                            if (subline.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(subline, maxLines: 1, overflow: TextOverflow.ellipsis,
                                                  style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xBFFFFFFF)))),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: _liked ? 'Bỏ yêu thích' : 'Yêu thích',
                                      iconSize: 30,
                                      icon: Icon(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: _liked ? AppColors.love : Colors.white),
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        _handleLove(song);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              _mobileScrubber(player),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _ShuffleButton(active: player.shuffle, onTap: player.toggleShuffle),
                                    IconButton(tooltip: 'Bài trước', iconSize: 40, icon: const Icon(Icons.skip_previous_rounded, color: Colors.white), onPressed: () { HapticFeedback.selectionClick(); player.playPrev(); }),
                                    Material(
                                      color: Colors.white,
                                      shape: const CircleBorder(),
                                      elevation: 8,
                                      shadowColor: Colors.black54,
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () { HapticFeedback.lightImpact(); player.togglePlay(); },
                                        child: SizedBox(
                                          width: 76, height: 76,
                                          child: player.isLoading
                                              ? const Center(child: SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.wine)))
                                              : Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 40, color: AppColors.wine),
                                        ),
                                      ),
                                    ),
                                    IconButton(tooltip: 'Bài tiếp', iconSize: 40, icon: const Icon(Icons.skip_next_rounded, color: Colors.white), onPressed: () { HapticFeedback.selectionClick(); player.playNext(); }),
                                    _RepeatButton(mode: player.repeat, onTap: player.toggleRepeat),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Row(
                                  children: [
                                    if (hasLyrics) Expanded(child: _pill(Icons.notes_rounded, 'Lời bài hát', () => _mobileScroll.animateTo(pageH - 70, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic))),
                                    if (hasLyrics) const SizedBox(width: 8),
                                    Expanded(child: _pill(Icons.bedtime_outlined, player.hasSleepTimer ? 'Đang hẹn' : 'Hẹn giờ', _showSleepSheet, active: player.hasSleepTimer)),
                                    const SizedBox(width: 8),
                                    Expanded(child: _pill(Icons.queue_music_rounded, 'Danh sách', _showQueueSheet)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                            ],
                          ),
                        ),
                        ),
                      ),
                      if (hasLyrics)
                        SliverToBoxAdapter(
                          child: _card(
                            title: 'Lời bài hát',
                            trailing: composerText.isNotEmpty ? composerText : null,
                            child: TimedLyrics.hasLrc(_songLyrics)
                                ? SizedBox(height: box.maxHeight * 0.66, child: _buildLyricsPanel(bare: true))
                                : _buildFlowingLyrics(),
                          ),
                        ),
                      if (_story != null)
                        SliverToBoxAdapter(
                          child: _card(
                            title: 'Câu chuyện bài hát',
                            child: Text(_story!.length > 700 ? '${_story!.substring(0, 700)}…' : _story!, style: body(const TextStyle(fontSize: 15, height: 1.6, fontWeight: FontWeight.w500, color: Color(0xE6FFFFFF)))),
                            onTap: () => _openSongDetail(song),
                          ),
                        ),
                      if (_topComment != null)
                        SliverToBoxAdapter(
                          child: _card(
                            title: 'Cảm nhận hay',
                            trailing: _commentCount > 0 ? '$_commentCount bình luận' : null,
                            onTap: () => _openSongDetail(song),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('“${(_topComment!['text'] as String).length > 220 ? '${(_topComment!['text'] as String).substring(0, 220)}…' : _topComment!['text']}”',
                                    style: body(const TextStyle(fontSize: 16, height: 1.55, fontWeight: FontWeight.w600, color: Colors.white))),
                                const SizedBox(height: 12),
                                Row(children: [
                                  UserAvatar(url: _topComment!['user']?['avatar']?['url']?.toString(), name: (_topComment!['user']?['username'] ?? '').toString(), size: 26),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text((_topComment!['user']?['username'] ?? '').toString(), style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xB3FFFFFF))))),
                                  Text('Xem tất cả', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFE0AEAC)))),
                                ]),
                              ],
                            ),
                          ),
                        ),
                      if (_composers.isNotEmpty || _poets.isNotEmpty || artists.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _card(
                            title: 'Thực hiện',
                            child: Column(
                              children: [
                                for (final c in _composers) _creditRow(c, 'Sáng tác', () => _openPerson('/nhac-si/${c['slug']}')),
                                for (final c in _recomposers) _creditRow(c, 'Soạn giả', () => _openPerson('/soan-gia/${c['slug']}')),
                                for (final c in _poets) _creditRow(c, isPoem ? 'Sáng tác' : 'Lời thơ', () => _openPerson('/nha-tho/${c['slug']}')),
                                for (final a in (_creditArtists.isNotEmpty ? _creditArtists : artists).whereType<Map>().where((a) => ok(a['title'])))
                                  isKaraoke
                                      ? _creditRow(Map<String, dynamic>.from(a), 'Thể hiện', () => _openPerson('/user/${a['id']}'))
                                      : _creditRow(Map<String, dynamic>.from(a), 'Trình bày', () => _openArtistDetail(a)),
                              ],
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(child: SizedBox(height: 28 + bottomPad)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // [on]: a toggle that is switched on (light pill, wine text).
  Widget _pill(IconData icon, String label, VoidCallback onTap, {bool active = false, bool on = false}) => Material(
        color: on ? const Color(0xFFF3ECEA) : (active ? const Color(0x33FFFFFF) : const Color(0x1AFFFFFF)),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: on ? AppColors.wine : Colors.white),
                const SizedBox(width: 6),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? AppColors.wine : Colors.white)))),
              ],
            ),
          ),
        ),
      );

  Widget _card({required String title, String? trailing, required Widget child, VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Material(
          color: const Color(0x1FE0AEAC),
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(title.toUpperCase(), style: body(const TextStyle(fontSize: 12, letterSpacing: 0.9, fontWeight: FontWeight.w800, color: Color(0x99FFFFFF))))),
                    if (trailing != null) Padding(padding: const EdgeInsets.only(left: 12), child: Text(trailing.toUpperCase(), maxLines: 1, style: body(const TextStyle(fontSize: 12, letterSpacing: 0.9, fontWeight: FontWeight.w800, color: Color(0x99FFFFFF))))),
                  ]),
                  const SizedBox(height: 12),
                  child,
                ],
              ),
            ),
          ),
        ),
      );

  Widget _creditRow(Map<String, dynamic> p, String role, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            UserAvatar(url: p['avatar']?['url']?.toString(), name: (p['title'] ?? '').toString(), size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((p['title'] ?? '').toString(), style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white))),
                Text(role, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xB3FFFFFF)))),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0x99FFFFFF)),
          ]),
        ),
      );

  /// Square cover with the spinning cassette mark in the corner while
  /// playing. Swipe left/right on it for next/previous.
  /// Video songs: the picture (muted, synced to the music player's sound)
  /// replaces the cover. Tap for full screen.
  Widget _mobileVideo(PlayerProvider player, Map<String, dynamic> song, double width) => GestureDetector(
        onTap: () => openFullScreenVideo(context, player, song),
        child: Container(
          width: width,
          height: width * 9 / 16,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0xB3000000), blurRadius: 50, spreadRadius: -20, offset: Offset(0, 24))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(fit: StackFit.expand, children: [
              SyncedVideo(player: player, song: song),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                  child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 24),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _mobileArtwork(String? thumb, double size, bool playing, Map<String, dynamic> song) => GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 300) return;
          HapticFeedback.selectionClick();
          final player = context.read<PlayerProvider>();
          v < 0 ? player.playNext() : player.playPrev();
        },
        child: AnimatedScale(
          scale: playing ? 1 : 0.9,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Color(0xB3000000), blurRadius: 60, spreadRadius: -20, offset: Offset(0, 30))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumb != null
                      ? CachedNetworkImage(imageUrl: cdnImg((thumb).toString(), 900), fit: BoxFit.cover, memCacheWidth: 900, errorWidget: (_, __, ___) => GeneratedCover(title: (song['title'] ?? '').toString(), size: size, radius: 0))
                      : GeneratedCover(title: (song['title'] ?? '').toString(), size: size, radius: 0),
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          width: 46,
                          height: 46,
                          color: const Color(0x8C0E0A0A),
                          alignment: Alignment.center,
                          child: SpinningReel(size: 30, spinning: playing),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _mobileHeader(PlayerProvider player, Map<String, dynamic> song) {
    final label = player.sourceLabel;
    // Min height, not fixed: two text lines at large system text must push
    // the header taller rather than overflow.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          IconButton(tooltip: 'Thu nhỏ', iconSize: 32, icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white), onPressed: () => Navigator.pop(context)),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('ĐANG PHÁT TỪ', style: body(const TextStyle(fontSize: 12, letterSpacing: 0.9, fontWeight: FontWeight.w700, color: Color(0xB3FFFFFF)))),
                Text(
                  label != null && label.isNotEmpty ? label : 'BCĐCNT',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ),
          ),
          IconButton(tooltip: 'Tuỳ chọn', icon: const Icon(Icons.more_horiz_rounded, color: Colors.white), onPressed: () => _showMoreSheet(context, song, player)),
        ],
      ),
    );
  }

  Widget _mobileScrubber(PlayerProvider player) {
    // Bigger, brighter times than desktop: read at arm's length.
    final timeStyle = body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xE6FFFFFF), fontFeatures: [FontFeature.tabularFigures()]));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SliderTheme(
        data: SliderThemeData(
          activeTrackColor: Colors.white,
          inactiveTrackColor: const Color(0x33FFFFFF),
          thumbColor: Colors.white,
          overlayColor: Colors.white.withValues(alpha: 0.15),
          trackHeight: 5,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        ),
        child: _SeekSlider(
          player: player,
          timeBuilder: (pos, total) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(pos), style: timeStyle),
                Text(_fmt(total), style: timeStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showQueueSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _PC.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
              child: Row(children: [
                Text('Danh sách phát', style: display(const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _PC.text))),
              ]),
            ),
            Expanded(
              child: Consumer<PlayerProvider>(
                builder: (_, p, _) => _buildQueuePanel(p, p.queue),
              ),
            ),
            SizedBox(height: 12 + MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }



  Widget _buildLyricsPanel({bool bare = false}) {
    // In fullscreen we drop the framed surface + use the karaoke variant
    // so the lyrics fill the screen edge-to-edge for a Now Playing feel.
    // `bare` (phone layout): no card, lyrics sit straight on the wine.
    final useLarge = _isFullScreen;
    // Base chữ lời responsive (giống web): ~15px mobile → ~20px desktop, ở 100%.
    // Áp cho fallback Html (lyrics thường); TimedLyrics đã 16-20px sẵn nên giữ nguyên.
    final lyricsBase = (MediaQuery.sizeOf(context).width * 0.012 + 11).clamp(15.0, 20.0);
    final hasLyrics = _songLyrics != null && _songLyrics!.isNotEmpty;
    final lyricsBody = !hasLyrics
        ? Center(child: Text('Chưa có lời bài hát', style: body(TextStyle(color: _PC.textMuted, fontSize: 14))))
        : TimedLyrics(
            raw: _songLyrics,
            large: useLarge,
            fontScale: bare ? 1.15 : _lyricsScale,
            autoScroll: bare || _lyricsAutoScroll,
            activeColor: _PC.text,
            fadeColor: const Color(0x59FFFFFF),
            textAlign: bare ? TextAlign.left : TextAlign.center,
            fallback: SingleChildScrollView(
              primary: false,
              child: Html(
                data: _songLyrics!,
                style: {
                  'body': Style(
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                    fontSize: FontSize(lyricsBase * _lyricsScale),
                    lineHeight: const LineHeight(2.0),
                    color: _PC.textSecondary,
                    textAlign: TextAlign.center,
                    fontFamily: body().fontFamily,
                  ),
                  'p': Style(margin: Margins.only(bottom: 8)),
                },
              ),
            ),
          );
    final inner = Column(children: [
      if (hasLyrics && !bare) _buildLyricsToolbar(),
      Expanded(child: lyricsBody),
    ]);
    if (bare) {
      // TimedLyrics pads its lines by 16, so 12 here lines them up with
      // the title's 28px edge.
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: inner);
    }
    return Container(
      margin: useLarge ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 24),
      padding: useLarge ? EdgeInsets.zero : const EdgeInsets.all(16),
      decoration: useLarge ? null : BoxDecoration(
        color: _PC.surfaceLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: inner,
    );
  }

  /// Plain lyrics for the phone layout, rendered line by line: verse
  /// markers typed into the lyrics ("1, 3-", "ĐK:") become small labels
  /// ("LỜI 1 & 3", "ĐIỆP KHÚC") instead of showing as raw text.
  Widget _buildFlowingLyrics() => LyricsText(
        html: _songLyrics ?? '',
        fontSize: 19,
        weight: FontWeight.w600,
        color: const Color(0xEBFFFFFF),
        labelColor: const Color(0x8CFFFFFF),
      );

  void _setLyricsScale(double v) {
    setState(() => _lyricsScale = v);
    SharedPreferences.getInstance().then((p) => p.setDouble('lyrics_scale', v));
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
            icon: Icon(Icons.text_decrease, color: _PC.textSecondary),
            onPressed: _lyricsScale > 0.7
                ? () => _setLyricsScale((_lyricsScale - 0.1).clamp(0.7, 1.6))
                : null,
          ),
          Text(scaleLabel, style: body(TextStyle(fontSize: 12, color: _PC.textMuted, fontFeatures: [FontFeature.tabularFigures()]))),
          IconButton(
            tooltip: 'Cỡ chữ lớn hơn',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.text_increase, color: _PC.textSecondary),
            onPressed: _lyricsScale < 1.6
                ? () => _setLyricsScale((_lyricsScale + 0.1).clamp(0.7, 1.6))
                : null,
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: _lyricsAutoScroll ? 'Tắt cuộn theo nhạc' : 'Bật cuộn theo nhạc',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _lyricsAutoScroll ? Icons.lock_open_outlined : Icons.lock_outline,
              color: _lyricsAutoScroll ? _PC.accentLight : _PC.textSecondary,
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
        color: _PC.surfaceLight,
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
                color: _PC.accent.withValues(alpha: 0.85),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
              ),
              secondaryBackground: Container(
                color: _PC.accent.withValues(alpha: 0.85),
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
                    color: isActive ? _PC.accentSoft : Colors.transparent,
                    border: Border(left: BorderSide(color: isActive ? _PC.accent : Colors.transparent, width: 3)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Center(
                          child: isActive
                              ? Icon(Icons.graphic_eq, size: 14, color: _PC.accentLight)
                              : Text('${idx + 1}', style: body(TextStyle(fontSize: 12, color: _PC.textMuted, fontWeight: FontWeight.w600))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: thumb != null
                            ? CachedNetworkImage(imageUrl: cdnImg((thumb).toString(), 90), width: 36, height: 36, fit: BoxFit.cover)
                            : Container(width: 36, height: 36, color: _PC.surface, child: Icon(Icons.music_note, size: 16, color: _PC.textMuted)),
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
                              style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isActive ? _PC.accentLight : _PC.text)),
                            ),
                            if (artistText.isNotEmpty)
                              Text(
                                artistText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: body(TextStyle(fontSize: 12, color: isActive ? _PC.accentLight.withValues(alpha: 0.8) : _PC.textSecondary)),
                              ),
                          ],
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: idx,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.drag_indicator, size: 18, color: _PC.textMuted),
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
        hoverColor: _PC.surfaceHover,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(Icons.shuffle, size: 22, color: active ? _PC.accentLight : _PC.textSecondary),
              if (active)
                Positioned(
                  bottom: -5,
                  child: Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(color: _PC.accentLight, shape: BoxShape.circle),
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
        hoverColor: _PC.surfaceHover,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(Icons.repeat, size: 22, color: active ? _PC.accentLight : _PC.textSecondary),
              if (mode == PlayerRepeatMode.all)
                Positioned(
                  bottom: -5,
                  child: Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(color: _PC.accentLight, shape: BoxShape.circle),
                  ),
                ),
              if (mode == PlayerRepeatMode.one)
                Positioned(
                  top: -4, right: -5,
                  child: Text('1', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _PC.accentLight))),
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

/// Seek bar that follows playback but, while the finger is down, follows the
/// finger instead and seeks once on release. Seeking on every drag update
/// restarted buffering dozens of times per gesture and made the thumb jump
/// back under the finger.
class _SeekSlider extends StatefulWidget {
  final PlayerProvider player;
  /// Optional time labels under the bar; gets the dragged position while
  /// dragging so the user sees where they will land.
  final Widget Function(Duration pos, Duration total)? timeBuilder;
  const _SeekSlider({required this.player, this.timeBuilder});

  @override
  State<_SeekSlider> createState() => _SeekSliderState();
}

class _SeekSliderState extends State<_SeekSlider> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionNotifier,
      builder: (context, pos, _) {
        final total = player.duration;
        final maxMs = total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
        final value = (_dragMs ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs);
        final slider = Slider(
          value: value,
          max: maxMs,
          onChangeStart: (v) => setState(() => _dragMs = v),
          onChanged: (v) => setState(() => _dragMs = v),
          onChangeEnd: (v) {
            setState(() => _dragMs = null);
            player.seek(Duration(milliseconds: v.toInt()));
          },
        );
        if (widget.timeBuilder == null) return slider;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          slider,
          widget.timeBuilder!(Duration(milliseconds: value.toInt()), total),
        ]);
      },
    );
  }
}
