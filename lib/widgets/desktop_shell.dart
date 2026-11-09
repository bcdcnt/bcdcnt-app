import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'hover_effects.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../services/theme_provider.dart';
import 'brand_logo.dart';
import 'command_palette.dart';
import 'desktop_now_panel.dart';
import 'desktop_player_bar.dart';
import 'mini_player.dart';
import 'notifications_dropdown.dart';
import 'playlist_cover.dart';
import '../services/friendly_error.dart';
import '../main.dart' show TabReselect;

/// Desktop shell (canvas "Desktop — làm mới: Phòng lưu trữ đang hát"):
///   - Left menu 240 (76 under 1280px, icon + small label, never icon-only):
///     Trang chủ · Khám phá · Dòng thời gian · Cộng đồng · Thư viện, then the
///     member's playlists, account at the foot.
///   - Top bar 64: back, search (opens the Ctrl K palette), Aa, bell.
///   - Side panel 360 beside the song playing (Lời · Bình luận · Hàng đợi);
///     under 1280px it floats over the page instead of squeezing it.
///   - Player bar 96 across the bottom: the outermost layer, so changing
///     page never stops the music. Per-screen MiniPlayers are muted.
class DesktopShell extends StatefulWidget {
  final Widget child;
  const DesktopShell({super.key, required this.child});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

/// Side panel open/closed — the keyboard handler (⌘I) flips it too.
final ValueNotifier<bool> desktopPanelOpen = ValueNotifier<bool>(true);

class _DesktopShellState extends State<DesktopShell> {
  bool _sized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Opens by itself only where it doesn't squeeze the page.
    if (!_sized) {
      _sized = true;
      desktopPanelOpen.value = MediaQuery.sizeOf(context).width >= 1680;
    }
  }

  void _panel(String tab) {
    if (desktopPanelOpen.value && desktopPanelTab.value == tab) {
      desktopPanelOpen.value = false;
    } else {
      desktopPanelTab.value = tab;
      desktopPanelOpen.value = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 1280;
    final hasSong = context.select<PlayerProvider, bool>((p) => p.currentSong != null);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<bool>(
        valueListenable: desktopPanelOpen,
        builder: (context, open, _) {
          final panel = SizedBox(width: 360, child: DesktopNowPanel(onClose: () => desktopPanelOpen.value = false));
          return Column(children: [
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                compact ? const _RailNav() : const _SideNav(),
                Expanded(
                  child: Stack(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const _TopBar(),
                      Expanded(child: MiniPlayerScope(child: widget.child)),
                    ]),
                    if (open && compact)
                      Positioned(
                        top: 0, right: 0, bottom: 0,
                        child: Material(elevation: 16, shadowColor: Colors.black45, child: panel),
                      ),
                  ]),
                ),
                if (open && !compact) ...[
                  VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
                  panel,
                ],
              ]),
            ),
            if (hasSong) DesktopPlayerBar(panelOpen: open, onPanel: _panel),
          ]);
        },
      ),
    );
  }
}

/// "Tìm kiếm" puts the cursor in the search box, also when already there.
void _goNav(BuildContext context, _NavItem item) {
  context.go(item.path);
  if (item.path == '/search') WidgetsBinding.instance.addPostFrameCallback((_) => TabReselect.notify(1));
}

class _NavItem {
  final String label;
  final String short;
  final String path;
  final IconData icon;
  final IconData activeIcon;
  /// Other paths that light this item up.
  final List<String> also;
  const _NavItem(this.label, this.short, this.path, this.icon, this.activeIcon, [this.also = const []]);
}

const _nav = <_NavItem>[
  _NavItem('Trang chủ', 'Trang chủ', '/', Icons.home_outlined, Icons.home_rounded),
  _NavItem('Tìm kiếm', 'Tìm kiếm', '/search', Icons.search_outlined, Icons.search_rounded, ['/nghe-si', '/nhac-si', '/nha-tho', '/soan-gia', '/the-loai', '/tag', '/bang-xep-hang', '/dan-ca', '/lan-dieu', '/the-loai-dan-ca', '/bai-hat']),
  _NavItem('Dòng thời gian', 'Thời gian', '/dong-thoi-gian', Icons.timeline_outlined, Icons.timeline_rounded),
  _NavItem('Cộng đồng', 'Cộng đồng', '/cong-dong', Icons.people_outline_rounded, Icons.people_rounded, ['/binh-luan', '/thao-luan', '/dien-dan', '/user']),
  _NavItem('Cá nhân', 'Cá nhân', '/library', Icons.person_outline_rounded, Icons.person_rounded, ['/yeu-thich', '/nghe-gan-day', '/da-tai-ve', '/playlist-cua-toi', '/bai-gui-cua-toi', '/profile']),
];

bool _isActive(String path, _NavItem item) {
  if (item.path == '/') return path == '/';
  for (final p in [item.path, ...item.also]) {
    if (path == p || path.startsWith('$p/')) return true;
  }
  return false;
}

class _SideNav extends StatefulWidget {
  const _SideNav();
  @override
  State<_SideNav> createState() => _SideNavState();
}

class _SideNavState extends State<_SideNav> {
  List<Map<String, dynamic>> _playlists = [];
  String? _for;

  void _load(AuthProvider auth) {
    final uid = auth.user?['id']?.toString();
    if (auth.loading || uid == _for) return;
    _for = uid;
    if (uid == null) {
      _playlists = [];
      return;
    }
    const q = r'''query { myPlaylists(first: 6, page: 1, orderBy: [{column: "id", order: DESC}]) { data { id title thumbnail { url }
      items(first: 4, orderBy: [{column: "position", order: ASC}]) { data { object { ... on Song { thumbnail { url } } ... on Folk { thumbnail { url } } ... on Instrumental { thumbnail { url } } ... on Poem { thumbnail { url } } ... on Karaoke { thumbnail { url } } } } }
    } } }''';
    auth.authedQuery(q).then((d) {
      final list = ((d['myPlaylists']?['data'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (mounted && _for == uid) setState(() => _playlists = list);
    }).catchError((_) {});
  }

  Future<void> _addTo(Map<String, dynamic> pl, Map<String, dynamic> song) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await context.read<AuthProvider>().authedMutate(
        r'''mutation($playlist_id: ID!, $object_id: ID!, $object_type: String!) { addToPlaylist(playlist_id: $playlist_id, object_id: $object_id, object_type: $object_type) { id } }''',
        {'playlist_id': '${pl['id']}', 'object_id': '${song['id']}', 'object_type': songKind(song)},
      );
      messenger?.showSnackBar(SnackBar(content: Text('Đã thêm “${song['title'] ?? ''}” vào ${pl['title'] ?? 'playlist'}'), duration: const Duration(seconds: 2)));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    _load(auth);
    final path = GoRouterState.of(context).uri.path;
    return Container(
      width: 240,
      decoration: BoxDecoration(color: AppColors.surface, border: Border(right: BorderSide(color: AppColors.border))),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 0, 16),
          child: Align(alignment: Alignment.centerLeft, child: InkWell(onTap: () => context.go('/'), child: const BrandLogo(height: 32))),
        ),
        for (final item in _nav) _NavRow(item: item, active: _isActive(path, item)),
        // BQT only: the uploads waiting for a decision.
        if (auth.hasPermission('manage_upload')) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Divider(height: 1, color: AppColors.border)),
          _NavRow(item: const _NavItem('Bàn làm việc', 'Làm việc', '/ban-lam-viec', Icons.assignment_outlined, Icons.assignment_rounded), active: path.startsWith('/ban-lam-viec')),
        ],
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            if (auth.isAuthenticated) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 22, 4, 6),
                child: Row(children: [
                  Expanded(child: Text('PLAYLIST CỦA TÔI', style: body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted)))),
                  IconButton(
                    tooltip: 'Tất cả playlist của tôi',
                    onPressed: () => context.push('/playlist-cua-toi'),
                    icon: Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textSecondary),
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ]),
              ),
              // A song dragged from any list drops onto a playlist here.
              for (final pl in _playlists)
                DragTarget<Map<String, dynamic>>(
                  onAcceptWithDetails: (d) => _addTo(pl, d.data),
                  builder: (context, cand, _) => Container(
                    decoration: BoxDecoration(
                      color: cand.isNotEmpty ? AppColors.accentSoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cand.isNotEmpty ? AppColors.wine : Colors.transparent, width: 2),
                    ),
                    child: HoverHighlight(
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => context.push('/playlist/${pl['id']}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Row(children: [
                            PlaylistCover(thumb: pl['thumbnail']?['url']?.toString(), songThumbs: PlaylistCover.thumbsOf(pl['items']), size: 32, radius: 7),
                            const SizedBox(width: 12),
                            Expanded(child: Text(cand.isNotEmpty ? 'Thả để thêm vào ‘${pl['title'] ?? ''}’' : '${pl['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cand.isNotEmpty ? AppColors.accentFg : AppColors.text)))),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ]),
        ),
        Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
          child: auth.isAuthenticated ? _AccountFooter(auth: auth) : _LoginFooter(),
        ),
      ]),
    );
  }
}

class _NavRow extends StatelessWidget {
  final _NavItem item;
  final bool active;
  const _NavRow({required this.item, required this.active});

  @override
  Widget build(BuildContext context) {
    final c = active ? AppColors.accentFg : AppColors.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? AppColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: AppColors.surfaceHover,
          onTap: () => _goNav(context, item),
          child: SizedBox(
            height: 48,
            child: Row(children: [
              const SizedBox(width: 14),
              Icon(active ? item.activeIcon : item.icon, size: 22, color: active ? AppColors.accentFg : AppColors.textSecondary),
              const SizedBox(width: 14),
              Expanded(child: Text(item.label, style: body(TextStyle(fontSize: 16, fontWeight: active ? FontWeight.w800 : FontWeight.w700, color: c)))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Narrow windows: icon + 11px label, 76 wide.
class _RailNav extends StatelessWidget {
  const _RailNav();

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final auth = context.watch<AuthProvider>();
    return Container(
      width: 76,
      decoration: BoxDecoration(color: AppColors.surface, border: Border(right: BorderSide(color: AppColors.border))),
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Column(children: [
        InkWell(onTap: () => context.go('/'), child: const BrandLogo(height: 30, full: false)),
        const SizedBox(height: 14),
        for (final item in _nav)
          Builder(builder: (context) {
            final active = _isActive(path, item);
            final c = active ? AppColors.accentFg : AppColors.textSecondary;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: active ? AppColors.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _goNav(context, item),
                  child: SizedBox(
                    width: 64,
                    height: 60,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(active ? item.activeIcon : item.icon, size: 24, color: c),
                      const SizedBox(height: 3),
                      Text(item.short, maxLines: 1, style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c))),
                    ]),
                  ),
                ),
              ),
            );
          }),
        const Spacer(),
        if (auth.isAuthenticated)
          IconButton(tooltip: 'Cài đặt', onPressed: () => context.push('/cai-dat'), icon: Icon(Icons.settings_outlined, color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final router = GoRouter.of(context);
    final compact = MediaQuery.sizeOf(context).width < 1280;
    final onSearch = GoRouterState.of(context).uri.path == '/search';
    Widget round(Widget child) => Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: child,
        );
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 32),
      decoration: BoxDecoration(color: AppColors.bg, border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
      child: Row(children: [
        Tooltip(
          message: 'Quay lại (Alt+←)',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: router.canPop() ? () => router.pop() : null,
            child: round(Icon(Icons.chevron_left_rounded, size: 28, color: router.canPop() ? AppColors.text : AppColors.textMuted.withValues(alpha: 0.5))),
          ),
        ),
        const SizedBox(width: 14),
        // The Tìm kiếm page has its own big box; one search box at a time.
        if (!onSearch)
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => CommandPalette.show(context),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Icon(Icons.search_rounded, size: 22, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Tìm bài, nhạc sĩ, nghệ sĩ, câu hát…', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMuted)))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
                      child: Text('Ctrl K', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textMuted))),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        const _TextSizeButton(),
        const SizedBox(width: 8),
        if (auth.isAuthenticated) _NotifBell(unread: (auth.user?['unread'] ?? 0) as int),
      ]),
    );
  }
}

/// "Aa": text size and light/dark right on the top bar, not buried in Cài đặt.
class _TextSizeButton extends StatelessWidget {
  const _TextSizeButton();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return PopupMenuButton<String>(
      tooltip: 'Cỡ chữ và giao diện',
      position: PopupMenuPosition.under,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.border)),
      onSelected: (v) {
        if (v.startsWith('s:')) theme.setTextScale(v.substring(2));
        if (v.startsWith('t:')) theme.setTheme(v.substring(2));
      },
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, height: 32, child: Text('CỠ CHỮ', style: body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted)))),
        for (final e in kTextScaleLabels.entries)
          CheckedPopupMenuItem(value: 's:${e.key}', checked: theme.textScaleKey == e.key, child: Text(e.value, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)))),
        const PopupMenuDivider(),
        PopupMenuItem(enabled: false, height: 32, child: Text('GIAO DIỆN', style: body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted)))),
        for (final p in kAppPalettes)
          CheckedPopupMenuItem(value: 't:${p.name}', checked: theme.name == p.name, child: Text(p.label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)))),
      ],
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text('Aa', style: body(TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text))),
      ),
    );
  }
}

class _NotifBell extends StatelessWidget {
  final int unread;
  const _NotifBell({required this.unread});

  @override
  Widget build(BuildContext context) {
    return NotificationsDropdown(
      builder: (ctx, openDropdown) => Stack(
        clipBehavior: Clip.none,
        children: [
          Tooltip(
            message: 'Thông báo',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: openDropdown,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(Icons.notifications_none_rounded, size: 24, color: AppColors.text),
              ),
            ),
          ),
          if (unread > 0)
            Positioned(
              top: 2, right: 2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: Text(unread > 99 ? '99+' : '$unread', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountFooter extends StatelessWidget {
  final AuthProvider auth;
  const _AccountFooter({required this.auth});

  @override
  Widget build(BuildContext context) {
    final avatar = auth.user?['avatar'] as String?;
    final username = (auth.user?['username'] as String?) ?? '';
    return PopupMenuButton<String>(
      tooltip: username,
      offset: const Offset(0, -8),
      position: PopupMenuPosition.over,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      onSelected: (v) {
        switch (v) {
          case 'profile': context.push('/profile'); break;
          case 'comments': context.push('/binh-luan-cua-toi'); break;
          case 'discussions': context.push('/thao-luan-cua-toi'); break;
          case 'stats': context.push('/thong-ke'); break;
          case 'settings': context.push('/cai-dat'); break;
          case 'logout': auth.logout(); break;
        }
      },
      // Zero item padding so the per-row HoverHighlight fills the full width.
      itemBuilder: (_) => [
        PopupMenuItem(value: 'profile', padding: EdgeInsets.zero, child: _menuRow(Icons.person_outline, 'Hồ sơ')),
        PopupMenuItem(value: 'comments', padding: EdgeInsets.zero, child: _menuRow(Icons.chat_bubble_outline, 'Bình luận của tôi')),
        PopupMenuItem(value: 'discussions', padding: EdgeInsets.zero, child: _menuRow(Icons.forum_outlined, 'Thảo luận của tôi')),
        PopupMenuItem(value: 'stats', padding: EdgeInsets.zero, child: _menuRow(Icons.bar_chart, 'Thống kê')),
        PopupMenuItem(value: 'settings', padding: EdgeInsets.zero, child: _menuRow(Icons.settings_outlined, 'Cài đặt')),
        const PopupMenuDivider(),
        // Theme switch lives in the sidebar footer now (_SidebarThemeSwitch).
        PopupMenuItem(value: 'logout', padding: EdgeInsets.zero, child: _menuRow(Icons.logout, 'Đăng xuất', danger: true)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 30, height: 30,
                child: avatar != null && avatar.isNotEmpty
                    ? CachedNetworkImage(imageUrl: cdnImg((avatar).toString(), 160), fit: BoxFit.cover, errorWidget: (_, __, ___) => _placeholder(username))
                    : _placeholder(username),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
              ),
            ),
            Icon(Icons.expand_less, size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(String username) {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    return Container(
      color: AppColors.accent,
      alignment: Alignment.center,
      child: Text(initial, style: body(const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
    );
  }

  Widget _menuRow(IconData icon, String label, {bool danger = false}) {
    final color = danger ? AppColors.accent : AppColors.text;
    // HoverHighlight gives a visible hover fill (the PopupMenuItem's own ink
    // hover is invisible on the light theme).
    return HoverHighlight(
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Text(label, style: body(TextStyle(color: color, fontSize: 13))),
          ],
        ),
      ),
    );
  }

}

class _LoginFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () => context.push('/profile'),
          style: TextButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text('Đăng nhập', style: body(const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
        ),
      ),
    );
  }
}
