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

enum _RightPanelTab { queue, comments }

class _DesktopShellState extends State<DesktopShell> {
  // Default open — desktop always exposes the inspector panel; the web's
  // show_comment_sidebar setting does not apply here. User can close per
  // session via the ✕ button.
  bool _panelOpen = true;
  // Which sub-tab is selected when panel is open. Persisted to prefs so a
  // user who always wants Hàng đợi gets it back next launch.
  _RightPanelTab _panelTab = _RightPanelTab.comments;
  static const _prefsKey = 'desktop_panel_tab';

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
    if (raw == 'comments' && mounted) {
      setState(() => _panelTab = _RightPanelTab.comments);
    }
  }

  Future<void> _saveTab(_RightPanelTab tab) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, tab == _RightPanelTab.queue ? 'queue' : 'comments');
  }

  void _setTab(_RightPanelTab tab) {
    if (_panelTab == tab) return;
    setState(() => _panelTab = tab);
    _saveTab(tab);
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
            child: Row(
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
                      // Single open-panel button at top-right when panel is
                      // closed. Tooltip says what it does; once open, the
                      // close affordance lives inside the panel header so
                      // the button isn't overlaid on content twice.
                      if (!_panelOpen)
                        Positioned(
                          top: 10, right: 12,
                          child: _PanelToggleBtn(
                            tooltip: 'Mở bảng phụ',
                            icon: Icons.view_sidebar_outlined,
                            onTap: () => setState(() => _panelOpen = true),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_panelOpen)
                  _RightPanelContainer(
                    activeTab: effectiveTab,
                    onSelectTab: _setTab,
                    onClose: () => setState(() => _panelOpen = false),
                  ),
              ],
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
  final VoidCallback onClose;
  const _RightPanelContainer({
    required this.activeTab,
    required this.onSelectTab,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Unified header — segmented tab switch on the left, close on right.
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            child: Row(
              children: [
                Expanded(
                  child: _SegmentedTabs(
                    activeTab: activeTab,
                    onSelect: onSelectTab,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Đóng bảng',
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: activeTab == _RightPanelTab.queue
                ? const DesktopQueuePanel(embedded: true)
                : const DesktopCommentSidebar(embedded: true),
          ),
        ],
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  final _RightPanelTab activeTab;
  final ValueChanged<_RightPanelTab> onSelect;
  const _SegmentedTabs({required this.activeTab, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SegmentBtn(
            icon: Icons.chat_bubble_outline,
            label: 'Bình luận',
            active: activeTab == _RightPanelTab.comments,
            onTap: () => onSelect(_RightPanelTab.comments),
          ),
          _SegmentBtn(
            icon: Icons.queue_music,
            label: 'Hàng đợi',
            active: activeTab == _RightPanelTab.queue,
            onTap: () => onSelect(_RightPanelTab.queue),
          ),
        ],
      ),
    );
  }
}

class _SegmentBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegmentBtn({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: body(TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? Colors.white : AppColors.textSecondary,
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelToggleBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _PanelToggleBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Icon(Icons.view_sidebar_outlined, size: 18, color: AppColors.textSecondary),
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

const _primaryNav = <_NavItem>[
  _NavItem('Trang chủ', '/', Icons.home_outlined),
  _NavItem('Tìm kiếm', '/search', Icons.search),
  _NavItem('Bình luận', '/binh-luan', Icons.chat_bubble_outline),
  _NavItem('Diễn đàn', '/thao-luan', Icons.forum_outlined),
  _NavItem('Hoạt động', '/cong-dong/hoat-dong-thanh-vien', Icons.timeline),
  _NavItem('Bảng xếp hạng', '/bang-xep-hang', Icons.leaderboard_outlined),
  _NavItem('Thư viện', '/library', Icons.library_music_outlined),
];

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
                for (final item in _primaryNav)
                  _SidebarLink(item: item, active: _isActive(path, item.path)),
                if (isAuth) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                    child: Text(
                      'THƯ VIỆN',
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: active ? AppColors.surfaceLight : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(item.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
