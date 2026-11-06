import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import 'constants/theme.dart';
import 'services/auth.dart';
import 'services/push.dart';
import 'services/api.dart';
import 'services/player.dart';
import 'services/media_session.dart';
import 'services/realtime.dart';
import 'services/theme_provider.dart';
import 'services/offline_store.dart';
import 'widgets/ui.dart' show goBackFallback;
import 'widgets/onboarding.dart';
import 'screens/contribute_screen.dart';
import 'screens/home_screen.dart';
import 'screens/home_mobile_screen.dart';
import 'screens/search_screen.dart';
import 'screens/library_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/song_detail_screen.dart';
import 'screens/person_detail_screen.dart';
import 'screens/category_detail_screen.dart';
import 'screens/user_song_list_screen.dart';
import 'screens/my_playlists_screen.dart';
import 'screens/document_archive_screen.dart';
import 'screens/comments_screen.dart';
import 'screens/community_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/support_screen.dart';
import 'screens/faq_screen.dart';
import 'screens/person_list_screen.dart';
import 'screens/decade_songs_screen.dart';
import 'screens/playlist_list_screen.dart';
import 'screens/tag_list_screen.dart';
import 'screens/playlist_detail_screen.dart';
import 'screens/tag_detail_screen.dart';
import 'screens/my_uploads_screen.dart';
import 'screens/sheet_list_screen.dart';
import 'screens/sheet_detail_screen.dart';
import 'screens/static_page_screen.dart';
import 'screens/ranking_screen.dart';
import 'screens/activity_screen.dart';
import 'screens/discussion_list_screen.dart';
import 'screens/discussion_detail_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/my_comments_screen.dart';
import 'screens/my_topics_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/user_detail_screen.dart';
import 'screens/document_detail_screen.dart';
import 'screens/forum_detail_screen.dart';
import 'screens/melody_detail_screen.dart';
import 'screens/folk_index_screen.dart';
import 'screens/folk_category_screen.dart';
import 'screens/upload_detail_screen.dart';
import 'widgets/mini_player.dart';
import 'widgets/full_player.dart';
import 'widgets/auth_dialogs.dart';
import 'widgets/desktop_shell.dart';
import 'widgets/keyboard_shortcuts.dart';
import 'widgets/update_banner.dart';
// Conditional import — just_audio_media_kit pulls in libmpv via
// media_kit_libs_audio, which we only want on Windows/Linux. The actual
// gate lives in main() below so this import is harmless on all
// platforms.
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:audio_session/audio_session.dart';
import 'services/analytics.dart';

void main() async {
  // window_manager is desktop-only (used for the FullPlayer fullscreen
  // toggle). Skip the bind on mobile/web so the app starts the same way
  // it did before the dep was added.
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    // Screenshot/automation hook: BCDCNT_SHOT_SIZE="1280x820" pins the window
    // to an exact size + centers it so the capture script gets identical,
    // reproducible frames every run. No-op in normal use.
    final shotSize = Platform.environment['BCDCNT_SHOT_SIZE'];
    if (shotSize == 'max') {
      // Fill the screen's visible frame — the largest window this display
      // supports (a true 1920x1080 can't fit a 1728x1080-logical panel).
      await windowManager.waitUntilReadyToShow(const WindowOptions(), () async {
        await windowManager.maximize();
        await windowManager.show();
      });
    } else if (shotSize != null && shotSize.contains('x')) {
      final parts = shotSize.split('x');
      final w = double.tryParse(parts[0]);
      final h = double.tryParse(parts[1]);
      if (w != null && h != null) {
        await windowManager.waitUntilReadyToShow(
          WindowOptions(size: Size(w, h), center: true),
          () async {
            await windowManager.setSize(Size(w, h));
            await windowManager.center();
            await windowManager.show();
          },
        );
      }
    }
  }
  // just_audio has native backends for iOS/Android/macOS/Web only; on
  // Windows + Linux the player would load tracks but report duration 0
  // and never emit audio. Route those two platforms through
  // just_audio_media_kit (libmpv-backed) so playback actually works.
  // macOS keeps the native AVPlayer backend.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    JustAudioMediaKit.ensureInitialized();
  }
  // iOS defaults to the soloAmbient session category, which iOS silences
  // as soon as the app leaves the foreground. The "music" preset switches
  // to playback so songs keep going on the lock screen / home screen
  // (paired with UIBackgroundModes=audio in Info.plist).
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    WidgetsFlutterBinding.ensureInitialized();
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }
  // Kick off the analytics persistent client_id load before runApp so
  // the first screen_view fired by the GoRouter listener has it ready.
  // No await — Analytics.logEvent waits on the same future internally.
  Analytics.init();
  Analytics.logEvent("app_open");
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final info = await PackageInfo.fromPlatform();
    ApiClient.appVersion = '${info.version}+${info.buildNumber}';
  } catch (_) {}
  await MediaSession.init();
  OfflineStore.instance.load();
  runApp(const BcdcntApp());
  _maybeAutoOpenFullPlayer();
  _maybeOpenAuthDialog();
}

// Screenshot/automation hook: BCDCNT_OPEN_AUTH=login|register (desktop only)
// pops the corresponding auth dialog once the navigator is ready. Pair with a
// logged-out app + BCDCNT_INITIAL_ROUTE=/profile to capture the login/register
// forms. No-op in normal use.
void _maybeOpenAuthDialog() {
  if (kIsWeb || !(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
  final which = Platform.environment['BCDCNT_OPEN_AUTH'];
  if (which != 'login' && which != 'register') return;
  var tries = 0;
  void attempt() {
    tries++;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null) {
      showDialog(
        context: ctx,
        builder: (_) => which == 'register' ? const RegisterDialog() : const LoginDialog(),
      );
      return;
    }
    if (tries < 40) Future.delayed(const Duration(milliseconds: 300), attempt);
  }
  Future.delayed(const Duration(milliseconds: 800), attempt);
}

// Screenshot/automation hook: when BCDCNT_OPEN_FULLPLAYER=1 (desktop only),
// poll until a track is playing then push the FullPlayer onto the root
// navigator — same affordance as tapping the mini player. Lets the capture
// script grab the "Trình phát" screen after deep-linking to a playing song
// (e.g. BCDCNT_INITIAL_ROUTE=/song/446). No-op in normal use.
void _maybeAutoOpenFullPlayer() {
  if (kIsWeb || !(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
  if (Platform.environment['BCDCNT_OPEN_FULLPLAYER'] != '1') return;
  var tries = 0;
  void attempt() {
    tries++;
    final ctx = rootNavigatorKey.currentContext;
    final player = ctx != null ? Provider.of<PlayerProvider>(ctx, listen: false) : null;
    if (player != null && player.currentSong != null) {
      player.setFullPlayerOpen(true);
      rootNavigatorKey.currentState?.push(
        PageRouteBuilder(opaque: true, pageBuilder: (_, __, ___) => const FullPlayer()),
      );
      return;
    }
    if (tries < 40) Future.delayed(const Duration(milliseconds: 300), attempt);
  }
  Future.delayed(const Duration(milliseconds: 600), attempt);
}

class BcdcntApp extends StatelessWidget {
  const BcdcntApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: OfflineStore.instance),
      ],
      child: const _AuthPlayerBridge(
        child: KeyboardShortcuts(
          child: _AppRoot(),
        ),
      ),
    );
  }
}

class _AppRoot extends StatelessWidget {
  const _AppRoot();
  @override
  Widget build(BuildContext context) {
    // Watch ThemeProvider so MaterialApp rebuilds with fresh ThemeData when
    // the user picks a new accent. The palette name is also baked into a
    // ValueKey on MaterialApp so the *entire* GoRouter widget tree gets
    // re-mounted — without this, existing pages keep their rendered state
    // and don't pick up the new AppColors statics until you navigate away
    // and back.
    final theme = context.watch<ThemeProvider>();
    return MaterialApp.router(
      key: ValueKey('app-${theme.name}'),
      title: 'BCĐCNT',
      theme: appTheme(),
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      // Stack the collapsed-mini-player pill above every route. The
      // pill is mounted once at the root so its drag offset survives
      // navigation; it self-hides when no song is playing or the
      // player isn't in collapsed mode.
      //
      // UpdateBanner wraps the route so the "new version available"
      // bar pins above every screen instead of being tied to a
      // specific page that the user might not visit.
      builder: (context, child) {
        // "Cỡ chữ" preference multiplies on top of the OS text size.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear((mq.textScaler.scale(16) / 16 * theme.textScale).clamp(0.9, 2.0))),
          child: UpdateBanner(
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                const MiniPlayerOverlay(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Wires AuthProvider <-> PlayerProvider:
/// - Loads player_shuffle/player_repeat from the authed user into the player
/// - Persists shuffle/repeat changes back via updateMe
class _AuthPlayerBridge extends StatefulWidget {
  final Widget child;
  const _AuthPlayerBridge({required this.child});

  @override
  State<_AuthPlayerBridge> createState() => _AuthPlayerBridgeState();
}

class _AuthPlayerBridgeState extends State<_AuthPlayerBridge> {
  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final player = context.read<PlayerProvider>();
    player.setOnSettingChanged(auth.updatePlayerSetting);
    // Wire the listen-tracker so PlayTracker can fire `logListen` when a
    // user-initiated play crosses the 30s threshold. Web does the same via
    // `PlayerContext` → playTracker.js.
    player.setLogListenFn((p) async {
      if (!auth.isAuthenticated) return;
      try {
        await auth.authedMutate(
          r'''mutation($event_id: String!, $object_type: String!, $object_id: ID!, $duration_played: Float!, $song_duration: Float, $source: String, $completed: Boolean) {
            logListen(event_id: $event_id, object_type: $object_type, object_id: $object_id, duration_played: $duration_played, song_duration: $song_duration, source: $source, completed: $completed) { id }
          }''',
          p.toVariables(),
        );
      } catch (_) {}
    });
    // Lock-screen / Control Center Now Playing card follows this player.
    MediaSession.bind(player);
    // Apply current cached user (if already restored from prefs) immediately.
    player.applyUserSettings(auth.user);
    // Boot the realtime socket — Pusher protocol over a raw WebSocket.
    // Subscribes to the public new-comments channel immediately and to
    // the private notification channel once the user is authed.
    realtimeService = RealtimeService(apiBase: apiBase, auth: auth);
    realtimeService!.connect();
    // Phone push: token registration + opening tapped notifications.
    PushService.instance.init(auth: auth, router: _router);
  }

  @override
  void dispose() {
    realtimeService?.dispose();
    realtimeService = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-apply whenever the authed user changes (login, /me refresh, logout).
    final user = context.watch<AuthProvider>().user;
    // applyUserSettings can call notifyListeners(); firing that synchronously
    // here would markNeedsBuild on every PlayerProvider consumer *during the
    // build phase* — illegal, and it crashed the whole tree whenever auth
    // settled mid-route-build (the "setState during build" → cascading
    // "No Overlay"/overflow errors). Defer to after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PlayerProvider>().applyUserSettings(user);
    });
    // Re-bootstrap private notification subscription whenever auth flips
    // — login pushes us into the private channel; logout drops us out.
    realtimeService?.onAuthChanged();
    return widget.child;
  }
}

/// Exposed so widgets that need to push routes from outside the navigator
/// tree (e.g. global keyboard shortcuts firing CommandPalette) can do so via
/// `rootNavigatorKey.currentState!.push(...)` instead of a fragile context.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// Fire a GA4 screen_view whenever GoRouter pushes a new route. Using
// onException would miss successful navigations; the listener on the
// router's routerDelegate gets called on every change.
class _AnalyticsObserver extends NavigatorObserver {
  void _report(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    Analytics.logScreenView(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _report(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _report(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _report(previousRoute);
  }
}

// Screenshot/automation hook: when the BCDCNT_INITIAL_ROUTE env var is set
// (desktop only), the app boots straight onto that route instead of '/'.
// Lets the capture script deep-link to any screen — e.g.
// BCDCNT_INITIAL_ROUTE=/nghe-si/thanh-huyen — without synthetic clicks.
// No-op on web (Platform.environment is unavailable there) and in normal use.
String _initialLocation() {
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    final r = Platform.environment['BCDCNT_INITIAL_ROUTE'];
    if (r != null && r.isNotEmpty) return r;
  }
  return '/';
}

final _router = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: _initialLocation(),
  observers: [_AnalyticsObserver()],
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        // Phone widths get the redesigned home; desktop (>=900, DesktopShell) keeps HomeScreen.
        // The four tabs. On phones they live in _MobileShell's IndexedStack
        // (kept alive, switched instantly); the route itself is only a
        // transparent slot. Desktop renders the screen in the route as before.
        GoRoute(path: '/', pageBuilder: (c, s) => _tabPage(c, s, const HomeScreen())),
        GoRoute(path: '/binh-luan', redirect: (c, s) => MediaQuery.sizeOf(c).width >= 900 ? null : '/cong-dong', builder: (c, s) => const CommentsScreen()),
        GoRoute(path: '/cong-dong', pageBuilder: (c, s) => _tabPage(c, s, const CommentsScreen())),
        GoRoute(
          path: '/search',
          pageBuilder: (c, s) {
            // A search opened with a query (chip, deep link) is a real page
            // on top of the tabs; the plain tab stays in the stack.
            final q = s.extra is String ? s.extra as String : s.uri.queryParameters['q'];
            if (q != null && q.isNotEmpty) return MaterialPage(key: s.pageKey, child: SearchScreen(initialQuery: q));
            return _tabPage(c, s, const SearchScreen());
          },
        ),
        GoRoute(path: '/library', pageBuilder: (c, s) => _tabPage(c, s, const LibraryScreen())),
        GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
        GoRoute(
          path: '/song/:id',
          builder: (c, s) {
            final extra = s.extra as Map<String, dynamic>?;
            // `highlightCommentId` is opt-in: only deep-links from
            // surfaces like Cảm nhận hay set it. Strip it before
            // passing the rest to the screen as initialSong so we
            // don't pollute the song map with UI hints.
            final hi = extra?['highlightCommentId']?.toString();
            return SongDetailScreen(
              songId: s.pathParameters['id']!,
              initialSong: extra,
              highlightCommentId: hi,
              scrollToComments: extra?['scrollToComments'] == true,
            );
          },
        ),
        GoRoute(
          path: '/nghe-si/:slug',
          builder: (c, s) => PersonDetailScreen(type: PersonType.artist, slug: s.pathParameters['slug']!),
        ),
        GoRoute(
          path: '/nhac-si/:slug',
          builder: (c, s) => PersonDetailScreen(type: PersonType.composer, slug: s.pathParameters['slug']!),
        ),
        GoRoute(
          path: '/nha-tho/:slug',
          builder: (c, s) => PersonDetailScreen(type: PersonType.poet, slug: s.pathParameters['slug']!),
        ),
        GoRoute(
          path: '/soan-gia/:slug',
          builder: (c, s) => PersonDetailScreen(type: PersonType.recomposer, slug: s.pathParameters['slug']!),
        ),
        GoRoute(
          path: '/the-loai/:slug',
          builder: (c, s) => CategoryDetailScreen(slug: s.pathParameters['slug']!),
        ),
        GoRoute(path: '/da-tai-ve', builder: (c, s) => const DownloadsScreen()),
        GoRoute(path: '/yeu-thich', builder: (c, s) => const UserSongListScreen(kind: UserListKind.favorites)),
        GoRoute(path: '/nghe-gan-day', builder: (c, s) => const UserSongListScreen(kind: UserListKind.history)),
        GoRoute(path: '/playlist-cua-toi', builder: (c, s) => const MyPlaylistsScreen()),
        GoRoute(
          path: '/tu-lieu/:type',
          builder: (c, s) {
            final t = archiveTypeFromSlug(s.pathParameters['type']!);
            if (t == null) return const DocumentArchiveScreen(type: ArchiveType.image);
            return DocumentArchiveScreen(type: t);
          },
        ),
        // Person lists (no slug = list view; with slug = detail view above)
        GoRoute(path: '/nghe-si', builder: (c, s) => const PersonListScreen(type: PersonType.artist)),
        GoRoute(path: '/nhac-si', builder: (c, s) => const PersonListScreen(type: PersonType.composer)),
        GoRoute(path: '/nha-tho', builder: (c, s) => const PersonListScreen(type: PersonType.poet)),
        GoRoute(path: '/soan-gia', builder: (c, s) => const PersonListScreen(type: PersonType.recomposer)),
        GoRoute(path: '/playlist', builder: (c, s) => const PlaylistListScreen()),
        GoRoute(path: '/playlist/:id', builder: (c, s) => PlaylistDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/tag', builder: (c, s) => const TagListScreen()),
        GoRoute(path: '/tag/:slug', builder: (c, s) => TagDetailScreen(slug: s.pathParameters['slug']!)),
        GoRoute(path: '/bai-gui-cua-toi', builder: (c, s) => const MyUploadsScreen()),
        GoRoute(
          path: '/bai-hat/thap-nien/:decade',
          builder: (c, s) => DecadeSongsScreen(decade: int.tryParse(s.pathParameters['decade']!) ?? 1990),
        ),
        GoRoute(path: '/sheet', builder: (c, s) => const SheetListScreen()),
        GoRoute(path: '/sheet/:id', builder: (c, s) => SheetDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/bang-xep-hang', builder: (c, s) => const RankingScreen()),
        GoRoute(path: '/bang-xep-hang/:slug', builder: (c, s) => RankingDetailScreen(slug: s.pathParameters['slug']!)),
        GoRoute(path: '/cong-dong/hoat-dong-thanh-vien', builder: (c, s) => const ActivityScreen()),
        GoRoute(path: '/thao-luan', builder: (c, s) => const DiscussionListScreen()),
        GoRoute(path: '/thao-luan/:id', builder: (c, s) => DiscussionDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/gioi-thieu', builder: (c, s) => const StaticPageScreen(slug: 'gioi-thieu')),
        GoRoute(path: '/yeu-cau', builder: (c, s) => const StaticPageScreen(slug: 'yeu-cau')),
        // Góp ý now goes to BQT privately through support tickets.
        GoRoute(path: '/gop-y', redirect: (c, s) => '/ho-tro'),
        GoRoute(path: '/ho-tro', builder: (c, s) => const SupportScreen()),
        GoRoute(path: '/faq', builder: (c, s) => const FaqScreen()),
        GoRoute(path: '/ho-tro/:id', builder: (c, s) => TicketDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/p/:slug', builder: (c, s) => StaticPageScreen(slug: s.pathParameters['slug']!)),
        GoRoute(path: '/thong-bao', builder: (c, s) => const NotificationsScreen()),
        GoRoute(path: '/cai-dat', builder: (c, s) => SettingsScreen(initialSection: s.extra is String ? s.extra as String : null)),
        GoRoute(path: '/binh-luan-cua-toi', builder: (c, s) => const MyCommentsScreen()),
        GoRoute(path: '/thao-luan-cua-toi', builder: (c, s) => const MyTopicsScreen()),
        GoRoute(path: '/thong-ke', builder: (c, s) => const StatsScreen()),
        GoRoute(path: '/gop-tay', builder: (c, s) => const ContributeScreen()),
        GoRoute(path: '/user/:id', builder: (c, s) => UserDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/tu-lieu/chi-tiet/:id', builder: (c, s) => DocumentDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/dien-dan/:id', builder: (c, s) => ForumDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/lan-dieu/:slug', builder: (c, s) => MelodyDetailScreen(slug: s.pathParameters['slug']!)),
        GoRoute(path: '/dan-ca/:slug', builder: (c, s) => FolkCategoryScreen(slug: s.pathParameters['slug']!)),
        GoRoute(path: '/dan-ca-tu-vung', builder: (c, s) => const FolkIndexScreen()),
        GoRoute(path: '/lan-dieu', builder: (c, s) => const FolkIndexScreen(mode: FolkIndexMode.melody)),
        GoRoute(path: '/the-loai-dan-ca', builder: (c, s) => const FolkIndexScreen(mode: FolkIndexMode.fcat)),
        GoRoute(path: '/bai-gui/:id', builder: (c, s) => UploadDetailScreen(id: s.pathParameters['id']!)),
      ],
    ),
  ],
);

Page<void> _tabPage(BuildContext c, GoRouterState s, Widget desktop) => NoTransitionPage(
      key: s.pageKey,
      child: MediaQuery.sizeOf(c).width >= 900 ? desktop : const SizedBox.shrink(),
    );

/// Picks between mobile and desktop chrome based on viewport width.
/// 900px breakpoint matches typical desktop tablet boundary; below that we
/// keep the bottom nav (mobile-friendly), above we render the web-style
/// top header (DesktopShell).
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) return DesktopShell(child: child);
    return _MobileShell(child: child);
  }
}

class _MobileShell extends StatefulWidget {
  final Widget child;
  const _MobileShell({required this.child});

  @override
  State<_MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<_MobileShell> {
  // Tab screens, built on first visit and then kept alive so switching
  // tabs is instant and keeps data + scroll position (Spotify/Apple Music).
  final Map<int, Widget> _tabScreens = {};
  int _activeTab = 0;
  PlayerProvider? _player;

  static Widget _buildTab(int i) => switch (i) {
        0 => const HomeMobileScreen(),
        1 => const SearchScreen(),
        2 => const CommunityScreen(),
        _ => const LibraryScreen(),
      };

  static const _tabPaths = {'/': 0, '/search': 1, '/cong-dong': 2, '/library': 3};

  static const _tabs = [
    ('/', Icons.home_outlined, Icons.home_rounded, 'Trang chủ'),
    ('/search', Icons.explore_outlined, Icons.explore_rounded, 'Khám phá'),
    ('/cong-dong', Icons.people_outline_rounded, Icons.people_rounded, 'Cộng đồng'),
    ('/library', Icons.library_music_outlined, Icons.library_music_rounded, 'Thư viện'),
  ];

  @override
  void initState() {
    super.initState();
    _player = context.read<PlayerProvider>();
    _player!.playErrorTick.addListener(_onPlayError);
    // First launch on a phone: 3-step intro (text size, how to play, login).
    // Skipped for scripted screenshot runs.
    if (!kIsWeb && !Platform.environment.containsKey('BCDCNT_SHOT_SIZE')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && MediaQuery.sizeOf(context).width < 900) maybeShowOnboarding(context);
      });
    }
  }

  @override
  void dispose() {
    _player?.playErrorTick.removeListener(_onPlayError);
    super.dispose();
  }

  /// Last page open inside each tab (location, extra), restored when the
  /// user comes back to that tab.
  final Map<int, (String, Object?)> _lastPage = {};

  void _onPlayError() {
    if (!mounted) return;
    final player = _player!;
    final hasNext = player.queue.length > player.currentIndex + 1;
    final missing = player.currentSong?['empty_file'] == 1;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    // Stays until dismissed: an older listener who looked away still needs
    // to know why the music stopped and what to do about it.
    messenger.showSnackBar(SnackBar(
      duration: const Duration(days: 1),
      showCloseIcon: true,
      closeIconColor: Colors.white70,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Không phát được bài này', style: TextStyle(fontWeight: FontWeight.w700)),
        Text(
          missing ? 'Bài này chưa có file nghe.' : 'Có thể mạng yếu, hoặc bản nghe của bài đang lỗi.',
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
        const SizedBox(height: 6),
        Row(children: [
          if (!missing) TextButton(
            onPressed: () { messenger.hideCurrentSnackBar(); player.retryCurrent(); },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE0AEAC), padding: EdgeInsets.zero, minimumSize: const Size(72, 48)),
            child: const Text('Thử lại', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (hasNext) ...[
            if (!missing) const SizedBox(width: 16),
            TextButton(
              onPressed: () { messenger.hideCurrentSnackBar(); player.playNext(); },
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFE0AEAC), padding: EdgeInsets.zero, minimumSize: const Size(72, 48)),
              child: const Text('Bài tiếp', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = GoRouterState.of(context);
    final path = state.uri.path;
    final hasQuery = state.extra is String || (state.uri.queryParameters['q']?.isNotEmpty ?? false);
    final tab = _tabPaths[path];
    final onTab = tab != null && !(tab == 1 && hasQuery);
    if (onTab) _activeTab = tab;
    _tabScreens.putIfAbsent(_activeTab, () => _buildTab(_activeTab));
    final child = widget.child;
    final hasPlayer = context.select<PlayerProvider, bool>((p) => p.currentSong != null);
    goBackFallback = () => _tabs[_activeTab].$1;
    final unreadRaw = context.select<AuthProvider, Object?>((a) => a.user?['unread']);
    final unread = unreadRaw is num ? unreadRaw.toInt() : 0;

    return MiniPlayerScope(
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // Kept-alive tabs underneath; the route navigator on top
                    // shows a transparent slot for tab routes and covers them
                    // with real pages for everything else (and slides those
                    // in/out over the live tab).
                    IndexedStack(
                      index: _activeTab,
                      sizing: StackFit.expand,
                      children: [
                        for (var i = 0; i < 4; i++)
                          TickerMode(enabled: onTab && i == _activeTab, child: _tabScreens[i] ?? const SizedBox.shrink()),
                      ],
                    ),
                    // On a tab the route is just a transparent slot, but its
                    // modal barrier would still swallow every touch meant for
                    // the live tab below — let pointers pass through.
                    IgnorePointer(ignoring: onTab, child: child),
                  ],
                ),
              ),
              // One mini player for every phone screen, right above the
              // tab bar; per-screen copies are muted by MiniPlayerScope.
              if (hasPlayer) const Padding(padding: EdgeInsets.only(top: 6, bottom: 8), child: MiniPlayer(fromShell: true)),
            ],
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.bg,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: SafeArea(
            top: false,
            // Tab labels stay readable but capped (as iOS does) so 200% text
            // can't push the icons out of the bar.
            child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.6,
            child: Builder(builder: (context) => SizedBox(
              // Grows with the labels so large text never clips them.
              height: 42 + MediaQuery.textScalerOf(context).scale(18),
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == _activeTab,
                        label: _tabs[i].$4,
                        child: InkResponse(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            if (onTab && i == _activeTab) {
                              TabReselect.notify(i);
                              return;
                            }
                            final here = GoRouterState.of(context);
                            if (i == _activeTab) {
                              // Same tab from a page inside it: back to its top.
                              _lastPage.remove(i);
                              context.go(_tabs[i].$1);
                              return;
                            }
                            // Remember where this tab was (a song page, a
                            // composer…) and bring the other tab back to
                            // where the user left it.
                            if (!onTab) {
                              // One-shot hints (scroll to comments, highlight) must not replay.
                              final extra = here.extra is Map
                                  ? (Map<String, dynamic>.from(here.extra as Map)..remove('scrollToComments')..remove('highlightCommentId'))
                                  : here.extra;
                              _lastPage[_activeTab] = (here.uri.toString(), extra);
                            } else {
                              _lastPage.remove(_activeTab);
                            }
                            final back = _lastPage.remove(i);
                            context.go(_tabs[i].$1);
                            if (back != null) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) GoRouter.of(context).push(back.$1, extra: back.$2);
                              });
                            }
                          },
                          radius: 40,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Badge(
                                // Replies and likes waiting: show them on Cộng đồng.
                                isLabelVisible: i == 2 && unread > 0,
                                label: Text(unread > 99 ? '99+' : '$unread'),
                                backgroundColor: AppColors.accent,
                                child: Icon(i == _activeTab ? _tabs[i].$3 : _tabs[i].$2, size: 26, color: i == _activeTab ? (AppColors.isLight ? AppColors.wine : Colors.white) : AppColors.textMuted),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(fit: BoxFit.scaleDown, child: Text(_tabs[i].$4, maxLines: 1, style: body(TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: i == _activeTab ? (AppColors.isLight ? AppColors.wine : Colors.white) : AppColors.textMuted,
                              )))),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )),
            )
          ),
        ),
      ),
    );
  }
}

/// Tapping the tab you are already on: tab screens listen and scroll back
/// to the top (Apple Music / Spotify behaviour).
class TabReselect {
  static final ValueNotifier<(int, int)> tick = ValueNotifier((-1, 0));
  static void notify(int tab) => tick.value = (tab, tick.value.$2 + 1);
}
