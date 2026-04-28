import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'constants/theme.dart';
import 'services/auth.dart';
import 'services/player.dart';
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
import 'screens/upload_detail_screen.dart';
import 'widgets/mini_player.dart';

void main() {
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
      ],
      child: const _AuthPlayerBridge(
        child: _AppRoot(),
      ),
    );
  }
}

class _AppRoot extends StatelessWidget {
  const _AppRoot();
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'BCĐCNT',
        theme: appTheme(),
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
      );
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
    // Apply current cached user (if already restored from prefs) immediately.
    player.applyUserSettings(auth.user);
  }

  @override
  Widget build(BuildContext context) {
    // Re-apply whenever the authed user changes (login, /me refresh, logout).
    final user = context.watch<AuthProvider>().user;
    context.read<PlayerProvider>().applyUserSettings(user);
    return widget.child;
  }
}

final _router = GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (c, s) => const HomeScreen()),
        GoRoute(path: '/binh-luan', builder: (c, s) => const CommentsScreen()),
        GoRoute(path: '/search', builder: (c, s) => const SearchScreen()),
        GoRoute(path: '/library', builder: (c, s) => const LibraryScreen()),
        GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
      ],
    ),
    GoRoute(
      path: '/song/:id',
      builder: (c, s) => SongDetailScreen(songId: s.pathParameters['id']!, initialSong: s.extra as Map<String, dynamic>?),
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
    GoRoute(path: '/bai-gui/:id', builder: (c, s) => UploadDetailScreen(id: s.pathParameters['id']!)),
  ],
);

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _indexFromPath(String path) {
    if (path.startsWith('/binh-luan')) return 1;
    if (path.startsWith('/search')) return 2;
    if (path.startsWith('/library')) return 3;
    if (path.startsWith('/profile')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final index = _indexFromPath(path);
    final hasPlayer = context.watch<PlayerProvider>().currentSong != null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(child: child),
            if (hasPlayer) const Padding(padding: EdgeInsets.only(bottom: 8), child: MiniPlayer()),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
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
