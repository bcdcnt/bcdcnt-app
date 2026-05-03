import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import '../widgets/login_dialog.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: body(const TextStyle(color: Colors.white))),
      backgroundColor: AppColors.surface,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  void _go(BuildContext context, String route, {bool requireAuth = false}) {
    final auth = context.read<AuthProvider>();
    if (requireAuth && !auth.isAuthenticated) {
      _toast(context, 'Vui lòng đăng nhập để tiếp tục');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (context.mounted) showDialog(context: context, builder: (_) => const LoginDialog());
      });
      return;
    }
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        // Hero header
        if (auth.isAuthenticated && auth.user != null)
          _userHero(context, auth.user!)
        else
          _guestHero(context, auth.loading),
        const SizedBox(height: 22),

        // Menu
        if (auth.isAuthenticated) ...[
          _menuItem(context, Icons.notifications_outlined, 'Thông báo', '/thong-bao', badge: auth.user?['unread'] ?? 0),
          _menuItem(context, Icons.upload_outlined, 'Gửi bài', null, onTap: () {
            _toast(context, 'Tính năng gửi bài đang được phát triển');
          }),
          _menuItem(context, Icons.description_outlined, 'Bài tôi gửi', '/bai-gui-cua-toi'),
          _menuItem(context, Icons.access_time, 'Nghe gần đây', '/nghe-gan-day'),
          _menuItem(context, Icons.favorite_outline, 'Yêu thích', '/yeu-thich'),
          _menuItem(context, Icons.queue_music_outlined, 'Playlist của tôi', '/playlist-cua-toi'),
          _menuItem(context, Icons.chat_bubble_outline, 'Bình luận của tôi', '/binh-luan-cua-toi'),
          _menuItem(context, Icons.forum_outlined, 'Thảo luận của tôi', '/thao-luan-cua-toi'),
          _menuItem(context, Icons.bar_chart_outlined, 'Thống kê', '/thong-ke'),
          _menuItem(context, Icons.settings_outlined, 'Cài đặt', '/cai-dat'),
          const SizedBox(height: 14),
          _logoutItem(context, auth),
        ] else ...[
          _menuItem(context, Icons.notifications_outlined, 'Thông báo', '/thong-bao', requireAuth: true),
          _menuItem(context, Icons.favorite_outline, 'Yêu thích', '/yeu-thich', requireAuth: true),
          _menuItem(context, Icons.access_time, 'Nghe gần đây', '/nghe-gan-day', requireAuth: true),
          _menuItem(context, Icons.queue_music_outlined, 'Playlist của tôi', '/playlist-cua-toi', requireAuth: true),
        ],
        const SizedBox(height: 20),

        // Footer signature (sync with home)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(child: Column(children: [
            Text('BCĐCNT', style: display(TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textMuted, letterSpacing: 4))),
            const SizedBox(height: 4),
            Text('Bài ca đi cùng năm tháng', style: body(TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic))),
          ])),
        ),
      ],
    );
  }

  Widget _userHero(BuildContext context, Map<String, dynamic> user) {
    return Column(children: [
      // Background + avatar overlap
      SizedBox(
        height: 165,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          Container(
            height: 120,
            margin: const EdgeInsets.symmetric(horizontal: 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
              image: user['background'] != null
                  ? DecorationImage(image: CachedNetworkImageProvider(user['background']), fit: BoxFit.cover)
                  : null,
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent]),
            ),
          ),
          // Avatar overlapping bg bottom
          Positioned(
            top: 75,
            child: InkWell(
              onTap: () => context.push('/user/${user['id']}'),
              borderRadius: BorderRadius.circular(45),
              child: Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bg, width: 4),
                  gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                ),
                child: ClipOval(
                  child: user['avatar'] != null
                      ? CachedNetworkImage(imageUrl: user['avatar'], fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.person, color: Colors.white, size: 36))
                      : const Icon(Icons.person, color: Colors.white, size: 36),
                ),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Text(user['username'] ?? '', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
      if (user['email'] != null)
        Padding(padding: const EdgeInsets.only(top: 2), child: Text(user['email'], style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary)))),
      const SizedBox(height: 10),
      InkWell(
        onTap: () => context.push('/user/${user['id']}'),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: AppColors.accentSoft, border: Border.all(color: AppColors.accent.withValues(alpha: 0.3))),
          child: Text('Xem trang cá nhân', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
        ),
      ),
    ]);
  }

  Widget _guestHero(BuildContext context, bool loading) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Color(0xFF4A0D0D), Color(0xFF711313)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(children: [
        Container(
          width: 70, height: 70,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.18)),
          child: const Icon(Icons.music_note, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 14),
        Text('BCĐCNT', style: display(const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white))),
        const SizedBox(height: 4),
        Text('Bài ca đi cùng năm tháng', style: body(const TextStyle(fontSize: 12, color: Colors.white70))),
        const SizedBox(height: 18),
        if (!loading)
          ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => const LoginDialog()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Đăng nhập', style: body(const TextStyle(fontWeight: FontWeight.w700))),
          ),
      ]),
    );
  }

  Widget _menuItem(BuildContext context, IconData icon, String label, String? route, {int badge = 0, VoidCallback? onTap, bool requireAuth = false}) {
    return InkWell(
      onTap: onTap ?? (route != null ? () => _go(context, route, requireAuth: requireAuth) : null),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: body(TextStyle(fontSize: 15, color: AppColors.text, fontWeight: FontWeight.w500)))),
          if (badge > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(10)),
              constraints: const BoxConstraints(minWidth: 18),
              alignment: Alignment.center,
              child: Text(badge > 99 ? '99+' : '$badge', style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
            ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
        ]),
      ),
    );
  }

  Widget _logoutItem(BuildContext context, AuthProvider auth) {
    return InkWell(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('Đăng xuất', style: display(TextStyle(color: AppColors.text))),
            content: Text('Bạn có chắc muốn đăng xuất?', style: body(TextStyle(color: AppColors.textSecondary))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đăng xuất', style: TextStyle(color: AppColors.error))),
            ],
          ),
        );
        if (confirm == true) auth.logout();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.logout, size: 18, color: AppColors.error),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text('Đăng xuất', style: body(const TextStyle(fontSize: 15, color: AppColors.error, fontWeight: FontWeight.w500)))),
        ]),
      ),
    );
  }
}
