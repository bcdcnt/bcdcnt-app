import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import 'constants/theme.dart';
import 'services/auth.dart';
import 'services/player.dart';
import 'services/realtime.dart';
import 'services/theme_provider.dart';
import 'screens/home_screen.dart';
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
import 'widgets/desktop_shell.dart';
import 'widgets/keyboard_shortcuts.dart';
import 'widgets/update_banner.dart';
// Conditional import — just_audio_media_kit pulls in libmpv via
// media_kit_libs_audio, which we only want on Windows/Linux. The actual
// gate lives in main() below so this import is harmless on all
// platforms.
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'services/analytics.dart';

void main() async {
  // window_manager is desktop-only (used for the FullPlayer fullscreen
  // toggle). Skip the bind on mobile/web so the app starts the same way
  // it did before the dep was added.
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
  }
  // just_audio has native backends for iOS/Android/macOS/Web only; on
  // Windows + Linux the player would load tracks but report duration 0
  // and never emit audio. Route those two platforms through
  // just_audio_media_kit (libmpv-backed) so playback actually works.
  // macOS keeps the native AVPlayer backend.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    JustAudioMediaKit.ensureInitialized();
  }
  // Kick off the analytics persistent client_id load before runApp so
  // the first screen_view fired by the GoRouter listener has it ready.
  // No await — Analytics.logEvent waits on the same future internally.
  Analytics.init();
  Analytics.logEvent("app_open");
  runApp(const BcdcntApp());
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
      builder: (context, child) => UpdateBanner(
        child: Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const MiniPlayerOverlay(),
          ],
        ),
      ),
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
    // Apply current cached user (if already restored from prefs) immediately.
    player.applyUserSettings(auth.user);
    // Boot the realtime socket — Pusher protocol over a raw WebSocket.
    // Subscribes to the public new-comments channel immediately and to
    // the private notification channel once the user is authed.
    realtimeService = RealtimeService(apiBase: apiBase, auth: auth);
    realtimeService!.connect();
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
    context.read<PlayerProvider>().applyUserSettings(user);
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

final _router = GoRouter(
  navigatorKey: rootNavigatorKey,
  observers: [_AnalyticsObserver()],
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (c, s) => const HomeScreen()),
        GoRoute(path: '/binh-luan', builder: (c, s) => const CommentsScreen()),
        GoRoute(path: '/search', builder: (c, s) => SearchScreen(initialQuery: s.extra is String ? s.extra as String : null)),
        GoRoute(path: '/library', builder: (c, s) => const LibraryScreen()),
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
        GoRoute(path: '/gop-y', builder: (c, s) => const StaticPageScreen(slug: 'gop-y')),
        GoRoute(path: '/p/:slug', builder: (c, s) => StaticPageScreen(slug: s.pathParameters['slug']!)),
        GoRoute(path: '/thong-bao', builder: (c, s) => const NotificationsScreen()),
        GoRoute(path: '/cai-dat', builder: (c, s) => const SettingsScreen()),
        GoRoute(path: '/binh-luan-cua-toi', builder: (c, s) => const MyCommentsScreen()),
        GoRoute(path: '/thao-luan-cua-toi', builder: (c, s) => const MyTopicsScreen()),
        GoRoute(path: '/thong-ke', builder: (c, s) => const StatsScreen()),
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

class _MobileShell extends StatelessWidget {
  final Widget child;
  const _MobileShell({required this.child});

  // Routes that show the bottom nav. All other routes (detail screens etc.)
  // get full-screen immersion with no bottom nav, matching the previous
  // out-of-shell behaviour before everything was unified under ShellRoute.
  static const _topLevelPaths = {'/', '/binh-luan', '/search', '/library', '/profile'};

  int _indexFromPath(String path) {
    if (path == '/binh-luan') return 1;
    if (path == '/search') return 2;
    if (path == '/library') return 3;
    if (path == '/profile') return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final showBottomNav = _topLevelPaths.contains(path);
    final index = _indexFromPath(path);
    final hasPlayer = context.watch<PlayerProvider>().currentSong != null;
    // Sub-screens render their own MiniPlayer overlay; only the 5 top-level
    // routes rely on the shell to show it.
    final shellShouldShowMiniPlayer = hasPlayer && showBottomNav;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(child: child),
            if (shellShouldShowMiniPlayer) const Padding(padding: EdgeInsets.only(bottom: 8), child: MiniPlayer()),
          ],
        ),
      ),
      bottomNavigationBar: !showBottomNav ? null : BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.accentLight,
        unselectedItemColor: AppColors.textMuted,
        currentIndex: index,
        showUnselectedLabels: true,
        selectedFontSize: 10,
        unselectedFontSize: 10,
        onTap: (i) {
          switch (i) {
            case 0: context.go('/'); break;
            case 1: context.go('/binh-luan'); break;
            case 2: context.go('/search'); break;
            case 3: context.go('/library'); break;
            case 4: context.go('/profile'); break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Trang chủ'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), activeIcon: Icon(Icons.chat_bubble), label: 'Bình luận'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Tìm kiếm'),
          BottomNavigationBarItem(icon: Icon(Icons.library_music_outlined), activeIcon: Icon(Icons.library_music), label: 'Thư viện'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Cá nhân'),
        ],
      ),
    );
  }
}
