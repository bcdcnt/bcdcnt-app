import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import '../services/player.dart';
import 'mini_player.dart';
import 'desktop_comment_sidebar.dart';
import 'desktop_queue_panel.dart';
import 'desktop_activity_sidebar.dart';
import 'notifications_dropdown.dart';

/// Native macOS-style shell — Apple Music / Spotify pattern:
///   - Left sidebar (220px) holds primary navigation + library shortcuts.
///   - Main area fills the rest of the window (no max-width cap).
///   - Right inspector panel — opt-in via single toggle button. When open,
///     a segmented control inside the panel header switches between Hàng đợi
///     and Bình luận. Last selected tab is persisted across sessions; the
///     open/closed state resets each launch (default: closed).
///   - Bottom-anchored MiniPlayer spans the full width when something is
///     playing.
/// Active when MainShell detects viewport >= 900px.
class DesktopShell extends StatefulWidget {
  final Widget child;
  const DesktopShell({super.key, required this.child});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

enum _RightPanelTab { queue, comments, activity }

/// Global toggle for the desktop right inspector panel — exposed so the
/// keyboard handler (above the navigator) can flip the panel without
/// reaching into [_DesktopShellState]. The shell binds to this notifier
/// as its source of truth.
final ValueNotifier<bool> desktopPanelOpen = ValueNotifier<bool>(true);

class _DesktopShellState extends State<DesktopShell> {
  // Which sub-tab is selected when panel is open. Persisted to prefs so a
  // user who always wants Hàng đợi gets it back next launch.
  _RightPanelTab _panelTab = _RightPanelTab.comments;
  static const _prefsKey = 'desktop_panel_tab';
  static const _prefsWidthKey = 'desktop_panel_width';
  // Right panel width — persisted across sessions. Clamped on read so a
  // bad/stale value can't break the layout.
  double _panelWidth = 320;
  static const _minPanelWidth = 240.0;
  static const _maxPanelWidth = 480.0;

  // Sub-screens already overlay their own MiniPlayer in a Stack. Only the
  // top-level routes rely on the shell to render the bottom player bar.
  static const _shellOwnedMiniPlayerPaths = {
    '/', '/binh-luan', '/search', '/library', '/profile',
    '/cong-dong/hoat-dong-thanh-vien', '/bang-xep-hang',
  };

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final w = prefs.getDouble(_prefsWidthKey);
    if (!mounted) return;
    setState(() {
      if (raw == 'queue') {
        _panelTab = _RightPanelTab.queue;
      } else if (raw == 'activity') {
        _panelTab = _RightPanelTab.activity;
      } else if (raw == 'comments') {
        _panelTab = _RightPanelTab.comments;
      }
      if (w != null) {
        _panelWidth = w.clamp(_minPanelWidth, _maxPanelWidth);
      }
    });
  }

  Future<void> _saveWidth(double w) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsWidthKey, w);
  }

  Future<void> _saveTab(_RightPanelTab tab) async {
    final prefs = await SharedPreferences.getInstance();
    final key = switch (tab) {
      _RightPanelTab.queue => 'queue',
      _RightPanelTab.activity => 'activity',
      _RightPanelTab.comments => 'comments',
    };
    await prefs.setString(_prefsKey, key);
  }

  void _setTab(_RightPanelTab tab) {
    if (_panelTab == tab) return;
    setState(() => _panelTab = tab);
    _saveTab(tab);
  }

  /// Header icon button click. Three flows:
  ///   * panel closed → open it and switch to this tab
  ///   * panel open + same tab active → close panel (toggle off)
  ///   * panel open + different tab active → just switch the tab
  void _onHeaderTab(_RightPanelTab tab, bool isOpen) {
    if (!isOpen) {
      desktopPanelOpen.value = true;
      _setTab(tab);
    } else if (_panelTab == tab) {
      desktopPanelOpen.value = false;
    } else {
      _setTab(tab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPlayer = context.watch<PlayerProvider>().currentSong != null;
    final path = GoRouterState.of(context).uri.path;
    final shellShouldShowMiniPlayer = hasPlayer && _shellOwnedMiniPlayerPaths.contains(path);
    final effectiveTab = _panelTab;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: desktopPanelOpen,
              builder: (ctx, isOpen, _) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Sidebar(),
                  Expanded(
                    // Soft cap so song lists / forms don't span 2000+px on
                    // ultrawide displays. Matches Apple Music's behaviour where
                    // content is centred with breathing room rather than
                    // stretched edge-to-edge.
                    child: Stack(
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1400),
                            child: widget.child,
                          ),
                        ),
                        // Apple Music-style header icon strip — each
                        // button opens the panel + selects its tab; tap
                        // again to close. Replaces the previous single
                        // toggle + in-panel tab switcher.
                        Positioned(
                          top: 8, right: 12,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            _HeaderTabBtn(
                              tooltip: 'Bình luận',
                              icon: Icons.chat_bubble_outline,
                              active: isOpen && _panelTab == _RightPanelTab.comments,
                              onTap: () => _onHeaderTab(_RightPanelTab.comments, isOpen),
                            ),
                            const SizedBox(width: 4),
                            _HeaderTabBtn(
                              tooltip: 'Hoạt động',
                              icon: Icons.timeline,
                              active: isOpen && _panelTab == _RightPanelTab.activity,
                              onTap: () => _onHeaderTab(_RightPanelTab.activity, isOpen),
                            ),
                            const SizedBox(width: 4),
                            _HeaderTabBtn(
                              tooltip: 'Hàng đợi  ⌘I',
                              icon: Icons.queue_music,
                              active: isOpen && _panelTab == _RightPanelTab.queue,
                              onTap: () => _onHeaderTab(_RightPanelTab.queue, isOpen),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  if (isOpen) ...[
                    // Drag splitter — 6px wide invisible hit area on the
                    // panel's left edge. Drag to resize; double-click to
                    // reset to default 320.
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: () {
                          setState(() => _panelWidth = 320);
                          _saveWidth(320);
                        },
                        onHorizontalDragUpdate: (d) {
                          setState(() {
                            _panelWidth = (_panelWidth - d.delta.dx).clamp(_minPanelWidth, _maxPanelWidth);
                          });
                        },
                        onHorizontalDragEnd: (_) => _saveWidth(_panelWidth),
                        child: Container(
                          width: 6,
                          color: Colors.transparent,
                          // Subtle 1px guide line — only visible when the
                          // user hovers (Material's InkWell handles cursor;
                          // here we just suggest the splitter exists).
                          child: const VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _panelWidth,
                      child: _RightPanelContainer(
                        activeTab: effectiveTab,
                        onSelectTab: _setTab,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (shellShouldShowMiniPlayer)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: MiniPlayer(),
            ),
        ],
      ),
    );
  }
}

class _RightPanelContainer extends StatelessWidget {
  final _RightPanelTab activeTab;
  final ValueChanged<_RightPanelTab> onSelectTab;
  const _RightPanelContainer({
    required this.activeTab,
    required this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    // Width controlled by parent via SizedBox (resizable splitter on left
    // edge — drag to resize, double-click to reset). Persists across
    // sessions in SharedPreferences.
    //
    // Tab switcher moved out to the main-area header (Apple Music
    // style icon strip) so the panel itself just shows: Now Playing
    // strip → small tab title → content.
    final title = switch (activeTab) {
      _RightPanelTab.comments => 'Bình luận',
      _RightPanelTab.activity => 'Hoạt động',
      _RightPanelTab.queue => 'Hàng đợi',
    };
    // Now-playing strip removed — duplicated the bottom MiniPlayer (same
    // thumb + title + artist, no extra controls). Bottom player is always
    // visible while audio is active, so the strip was dead weight.
    return Container(
      decoration: const BoxDecoration(color: AppColors.bg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 10),
            child: Text(
              title,
              style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: switch (activeTab) {
              _RightPanelTab.queue => const DesktopQueuePanel(embedded: true),
              _RightPanelTab.activity => const DesktopActivitySidebar(embedded: true),
              _RightPanelTab.comments => const DesktopCommentSidebar(embedded: true),
            },
          ),
        ],
      ),
    );
  }
}

/// Apple Music-style header icon button — compact, transparent by
/// default, accent-tinted bg + filled icon when its tab is active.
class _HeaderTabBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  const _HeaderTabBtn({required this.icon, required this.tooltip, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? AppColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 18, color: active ? AppColors.accentLight : AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final String path;
  final IconData icon;
  const _NavItem(this.label, this.path, this.icon);
}

/// Sidebar nav grouped into clusters with section labels — 13 flat items
/// were too long to scan. Mirror the "THƯ VIỆN" group label style for the
/// other clusters so the typography hierarchy is consistent.
class _NavGroup {
  final String? label;
  final List<_NavItem> items;
  const _NavGroup({this.label, required this.items});
}

const _primaryNavGroups = <_NavGroup>[
  _NavGroup(items: [
    _NavItem('Trang chủ', '/', Icons.home_outlined),
    _NavItem('Tìm kiếm', '/search', Icons.search),
    _NavItem('Bình luận', '/binh-luan', Icons.chat_bubble_outline),
  ]),
  _NavGroup(label: 'THỂ LOẠI', items: [
    _NavItem('Nghệ sĩ', '/nghe-si', Icons.mic_outlined),
    _NavItem('Nhạc sĩ', '/nhac-si', Icons.piano_outlined),
    _NavItem('Nhà thơ', '/nha-tho', Icons.menu_book_outlined),
    _NavItem('Soạn giả', '/soan-gia', Icons.edit_note),
    _NavItem('Tân nhạc', '/the-loai/tan-nhac', Icons.music_note),
    _NavItem('Dân ca', '/the-loai/dan-ca', Icons.queue_music),
    _NavItem('Khí nhạc', '/the-loai/khi-nhac', Icons.piano),
    _NavItem('Tiếng thơ', '/the-loai/tieng-tho', Icons.auto_stories_outlined),
    _NavItem('Thành viên hát', '/the-loai/thanh-vien-hat', Icons.mic),
  ]),
];

/// Always-visible bottom anchor — `Thư viện` hub link must be reachable
/// whether or not the user is logged in (shortcuts below it are
/// auth-gated).
const _libraryAnchor = _NavItem('Thư viện', '/library', Icons.library_music_outlined);

// Library shortcuts — only shown when authenticated
const _libraryShortcuts = <_NavItem>[
  _NavItem('Yêu thích', '/yeu-thich', Icons.favorite_outline),
  _NavItem('Nghe gần đây', '/nghe-gan-day', Icons.history),
  _NavItem('Playlist của tôi', '/playlist-cua-toi', Icons.queue_music),
  _NavItem('Bài gửi của tôi', '/bai-gui-cua-toi', Icons.upload_outlined),
];

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  bool _isActive(String currentPath, String navPath) {
    if (navPath == '/') return currentPath == '/';
    return currentPath == navPath || currentPath.startsWith('$navPath/');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final path = GoRouterState.of(context).uri.path;
    final isAuth = auth.isAuthenticated;

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Text(
                  'BCĐCNT',
                  style: brand(const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800,
                    letterSpacing: 0.5, color: AppColors.text,
                  )),
                ),
                const Spacer(),
                if (isAuth)
                  _NotifBell(unread: (auth.user?['unread'] ?? 0) as int),
              ],
            ),
          ),
          // Nav + library
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (var g = 0; g < _primaryNavGroups.length; g++) ...[
                  if (_primaryNavGroups[g].label != null) ...[
                    SizedBox(height: g == 0 ? 0 : 14),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                      child: Text(
                        _primaryNavGroups[g].label!,
                        style: body(const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          letterSpacing: 1.2, color: AppColors.textMuted,
                        )),
                      ),
                    ),
                  ],
                  for (final item in _primaryNavGroups[g].items)
                    _SidebarLink(item: item, active: _isActive(path, item.path)),
                ],
                const SizedBox(height: 14),
                _SidebarLink(item: _libraryAnchor, active: _isActive(path, _libraryAnchor.path)),
                if (isAuth) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Text(
                      'THƯ VIỆN CỦA TÔI',
                      style: body(const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        letterSpacing: 1.2, color: AppColors.textMuted,
                      )),
                    ),
                  ),
                  for (final item in _libraryShortcuts)
                    _SidebarLink(item: item, active: _isActive(path, item.path)),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
          // Account / login footer
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: isAuth ? _AccountFooter(auth: auth) : _LoginFooter(),
          ),
        ],
      ),
    );
  }
}

class _SidebarLink extends StatelessWidget {
  final _NavItem item;
  final bool active;
  const _SidebarLink({required this.item, required this.active});

  @override
  Widget build(BuildContext context) {
    // Active row gets a 2px accent stripe on the left + bg surfaceLight,
    // mirrors Apple Music's sidebar active marker. Stripe is implemented
    // via a left border on the inner row so the rounded corners on the
    // outer Material still clip nicely.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: active ? AppColors.surfaceLight : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(item.path),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: active ? AppColors.accentLight : Colors.transparent, width: 2),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: active ? AppColors.accentLight : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: body(TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? AppColors.text : AppColors.textSecondary,
                    )),
                  ),
                ),
              ],
            ),
          ),
        ),
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
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Thông báo',
            icon: const Icon(Icons.notifications_none, size: 20, color: AppColors.textSecondary),
            onPressed: openDropdown,
          ),
          if (unread > 0)
            Positioned(
              top: 4, right: 4,
              child: Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
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
      itemBuilder: (_) => [
        PopupMenuItem(value: 'profile', child: _menuRow(Icons.person_outline, 'Hồ sơ')),
        PopupMenuItem(value: 'comments', child: _menuRow(Icons.chat_bubble_outline, 'Bình luận của tôi')),
        PopupMenuItem(value: 'discussions', child: _menuRow(Icons.forum_outlined, 'Thảo luận của tôi')),
        PopupMenuItem(value: 'stats', child: _menuRow(Icons.bar_chart, 'Thống kê')),
        PopupMenuItem(value: 'settings', child: _menuRow(Icons.settings_outlined, 'Cài đặt')),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'logout', child: _menuRow(Icons.logout, 'Đăng xuất', danger: true)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 30, height: 30,
                child: avatar != null && avatar.isNotEmpty
                    ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, errorWidget: (_, __, ___) => _placeholder(username))
                    : _placeholder(username),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
              ),
            ),
            const Icon(Icons.expand_less, size: 16, color: AppColors.textMuted),
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
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(label, style: body(TextStyle(color: color, fontSize: 13))),
      ],
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
