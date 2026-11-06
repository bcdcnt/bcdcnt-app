import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/offline_store.dart';
import '../widgets/auth_dialogs.dart';
import '../widgets/brand_logo.dart';
import '../widgets/ui.dart';
import '../widgets/listening_profile_card.dart';
import '../main.dart' show TabReselect;

/// Thư viện tab (2026-11): everything "của tôi" in one place — the old
/// Thư viện and Cá nhân tabs merged. Profile card on top, four big tiles,
/// my playlists, then my activity and settings.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Map<String, dynamic>> _playlists = [];
  // People the member follows (♥ on person pages): {type, id, title, slug, avatar}.
  List<Map<String, dynamic>> _following = [];
  bool _loadingPlaylists = false;
  String? _loadedFor;
  AuthProvider? _auth;
  final _scroll = ScrollController();

  void _onReselect() {
    if (TabReselect.tick.value.$1 == 3 && _scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    }
  }

  @override
  void initState() {
    super.initState();
    TabReselect.tick.addListener(_onReselect);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _auth = context.read<AuthProvider>()..addListener(_maybeFetch);
      _maybeFetch();
    });
  }

  @override
  void dispose() {
    TabReselect.tick.removeListener(_onReselect);
    _scroll.dispose();
    _auth?.removeListener(_maybeFetch);
    super.dispose();
  }

  void _maybeFetch() {
    final auth = _auth;
    if (auth == null || auth.loading || !mounted) return;
    final uid = auth.isAuthenticated ? (auth.user?['id']?.toString()) : null;
    if (uid == _loadedFor) return;
    _loadedFor = uid;
    if (uid == null) {
      setState(() {
        _playlists = [];
        _following = [];
      });
      return;
    }
    _fetchPlaylists(auth);
    _fetchFollowing(auth, uid);
  }

  Future<void> _fetchPlaylists(AuthProvider auth) async {
    setState(() => _loadingPlaylists = true);
    const obj = '... on Song { thumbnail { url } } ... on Folk { thumbnail { url } } ... on Instrumental { thumbnail { url } } ... on Poem { thumbnail { url } }';
    try {
      final d = await auth.authedQuery('''query { myPlaylists(first: 6, page: 1, orderBy: [{column: "id", order: DESC}]) {
        data { id title slug thumbnail { url } items(first: 4) { paginatorInfo { total } data { object { $obj } } } }
      } }''', null);
      if (!mounted) return;
      setState(() {
        _playlists = ((d['myPlaylists']?['data'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loadingPlaylists = false;
      });
      _playlistsFailed = false;
    } catch (_) {
      if (mounted) setState(() { _loadingPlaylists = false; _playlistsFailed = true; });
    }
  }

  bool _playlistsFailed = false;

  Future<void> _fetchFollowing(AuthProvider auth, String uid) async {
    // `myFollowing` (API 2026-11): people this member ♥'d on person pages.
    // On older API builds the query fails and the section stays hidden.
    try {
      final d = await auth.authedQuery('query { myFollowing(first: 30) { id title slug object_type avatar { url } } }', null);
      final list = ((d['myFollowing'] ?? []) as List).whereType<Map>().map((p) => {...Map<String, dynamic>.from(p), 'type': p['object_type']}).toList();
      if (mounted) setState(() => _following = list);
    } catch (_) {}
  }

  static const _personRoutes = {'composer': '/nhac-si/', 'artist': '/nghe-si/', 'poet': '/nha-tho/', 'recomposer': '/soan-gia/'};

  void _open(String route) {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      showDialog(context: context, builder: (_) => const LoginDialog());
      return;
    }
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.isAuthenticated ? auth.user : null;
    final name = (user?['username'] ?? '').toString();

    return ColoredBox(
      color: AppColors.bg,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          PageTitle(
            'Thư viện',
            leading: user != null
                ? GestureDetector(onTap: () => context.push('/user/${user['id']}'), child: UserAvatar(url: user['avatar']?.toString(), name: name, size: 44))
                : null,
            actions: [RoundIcon(icon: Icons.settings_outlined, tooltip: 'Cài đặt', onTap: () => context.push('/cai-dat'))],
          ),
          const SizedBox(height: 16),
          if (user != null) ...[
            _ProfileCard(user: user),
            const SizedBox(height: 12),
            ListeningProfileCard(key: ValueKey('lp-${user['id']}')),
          ] else if (!auth.loading)
            const _GuestCard(),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Tile(icon: Icons.favorite_rounded, title: 'Yêu thích', subtitle: 'Bài đã thả tim', onTap: () => _open('/yeu-thich')),
                _Tile(icon: Icons.history_rounded, title: 'Nghe gần đây', subtitle: 'Lịch sử nghe', onTap: () => _open('/nghe-gan-day')),
                Consumer<OfflineStore>(builder: (_, store, __) => _Tile(icon: Icons.download_for_offline_rounded, title: 'Đã tải về', subtitle: store.items.isEmpty ? 'Nghe không cần mạng' : '${store.items.length} bài · nghe offline', onTap: () => context.push('/da-tai-ve'))),
                _Tile(icon: Icons.upload_rounded, title: 'Bài gửi', subtitle: 'Bài tôi đã gửi', onTap: () => _open('/bai-gui-cua-toi')),
              ],
            ),
          ),
          if (user != null) ...[
            SectionTitle('Playlist của tôi', action: 'Tất cả', onAction: () => context.push('/playlist-cua-toi')),
            if (_loadingPlaylists)
              for (var i = 0; i < 3; i++) const SkeletonSongRow()
            else if (_playlistsFailed && _playlists.isEmpty)
              // A failed load must not read as "you have no playlists".
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Expanded(child: Text('Chưa tải được playlist của bạn. Kiểm tra mạng.', style: AppText.bodyText)),
                  TextButton(
                    onPressed: () { final a = context.read<AuthProvider>(); _fetchPlaylists(a); },
                    style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                    child: Text('Tải lại', style: body(TextStyle(fontWeight: FontWeight.w800, color: AppColors.accentLight))),
                  ),
                ]),
              )
            else if (_playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Bạn chưa có playlist. Bấm ⋮ ở một bài hát rồi chọn "Thêm vào playlist" để tạo.', style: AppText.bodyText),
              )
            else
              for (final p in _playlists) _PlaylistRow(playlist: p),
            if (_following.isNotEmpty) ...[
              SectionTitle('Đang theo dõi', action: null),
              Rail(
                height: 136,
                gap: 14,
                count: _following.length,
                builder: (_, i) {
                  final p = _following[i];
                  return PersonBubble(
                    name: (p['title'] ?? '').toString(),
                    image: p['avatar']?['url']?.toString(),
                    tint: true,
                    onTap: () => context.push('${_personRoutes[p['type']]}${p['slug']}'),
                  );
                },
              ),
            ],
            const GroupLabel('Hoạt động của tôi'),
            ListItem(icon: Icons.chat_bubble_outline_rounded, title: 'Bình luận của tôi', onTap: () => context.push('/binh-luan-cua-toi')),
            ListItem(icon: Icons.forum_outlined, title: 'Chủ đề thảo luận', onTap: () => context.push('/thao-luan-cua-toi')),
            ListItem(icon: Icons.insights_rounded, title: 'Điểm & thống kê nghe', onTap: () => context.push('/thong-ke')),
            ListItem(icon: Icons.volunteer_activism_outlined, title: 'Góp tay cho kho nhạc', subtitle: 'Bổ sung tác giả, năm sáng tác… được cộng điểm', onTap: () => context.push('/gop-tay')),
            ListItem(icon: Icons.notifications_none_rounded, title: 'Thông báo', trailingText: (user['unread'] ?? 0) > 0 ? '${user['unread']}' : null, onTap: () => context.push('/thong-bao')),
          ],
          const GroupLabel('Khác'),
          ListItem(icon: Icons.settings_outlined, title: 'Cài đặt', subtitle: 'Giao diện, cỡ chữ, nghe nhạc', onTap: () => context.push('/cai-dat')),
          ListItem(icon: Icons.info_outline_rounded, title: 'Giới thiệu BCĐCNT', onTap: () => context.push('/gioi-thieu')),
          ListItem(icon: Icons.help_outline_rounded, title: 'Câu hỏi thường gặp', subtitle: 'Nghe, tải nhạc, tài khoản, đóng góp', onTap: () => context.push('/faq')),
          ListItem(icon: Icons.support_agent_rounded, title: 'Góp ý & hỗ trợ', subtitle: 'Gửi riêng cho BQT', onTap: () => context.push('/ho-tro')),
          if (user != null)
            ListItem(
              icon: Icons.logout_rounded,
              title: 'Đăng xuất',
              titleColor: AppColors.error,
              trailing: const SizedBox.shrink(),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Đăng xuất'),
                    content: const Text('Bạn có chắc muốn đăng xuất?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đăng xuất', style: TextStyle(color: AppColors.error))),
                    ],
                  ),
                );
                if (ok == true) auth.logout();
              },
            ),
          const SizedBox(height: 24),
          const Center(child: BrandLogo(height: 26)),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final Map<String, dynamic> user;
  const _ProfileCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final point = user['point'] is num ? (user['point'] as num).toInt() : null;
    final listen = user['listen'] is num ? (user['listen'] as num).toInt() : null;
    final meta = [
      if (point != null && point > 0) '${formatViews(point)} điểm',
      if (listen != null && listen > 0) '${formatViews(listen)} lượt nghe',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/user/${user['id']}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((user['username'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
                  if (meta.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text(meta, style: AppText.meta)),
                ]),
              ),
              Text('Hồ sơ ›', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)])),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const BrandLogo(height: 28, onDark: true),
            const SizedBox(height: 14),
            Text('Đăng nhập để lưu bài yêu thích, tạo playlist và tiếp tục nghe trên mọi thiết bị.',
                style: body(const TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w600, color: Colors.white))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(25),
                    onTap: () => showDialog(context: context, builder: (_) => const LoginDialog()),
                    child: SizedBox(height: 50, child: Center(child: Text('Đăng nhập', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.wine))))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Material(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(25),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(25),
                    onTap: () => showDialog(context: context, builder: (_) => const RegisterDialog()),
                    child: SizedBox(height: 50, child: Center(child: Text('Đăng ký', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white))))),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool strong;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final fg = strong ? Colors.white : AppColors.text;
    return Material(
      color: strong ? AppColors.wine : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: strong ? Colors.white.withValues(alpha: 0.16) : AppColors.bg, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 22, color: strong ? Colors.white : AppColors.accentLight),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg))),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.7)))),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  final Map<String, dynamic> playlist;
  const _PlaylistRow({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final own = playlist['thumbnail']?['url']?.toString();
    final thumbs = ((playlist['items']?['data'] ?? []) as List)
        .whereType<Map>()
        .map((i) => i['object']?['thumbnail']?['url']?.toString())
        .whereType<String>()
        .toList();
    final total = playlist['items']?['paginatorInfo']?['total'];
    Widget cover;
    if (own != null) {
      cover = NetImage(url: own, width: 52, height: 52, radius: 12);
    } else if (thumbs.length >= 4) {
      cover = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 52,
          height: 52,
          child: GridView.count(crossAxisCount: 2, padding: EdgeInsets.zero, physics: const NeverScrollableScrollPhysics(), children: [for (final u in thumbs.take(4)) NetImage(url: u)]),
        ),
      );
    } else {
      cover = Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.queue_music_rounded, color: AppColors.accentLight),
      );
    }
    return InkWell(
      onTap: () => context.push('/playlist/${playlist['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [
          cover,
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((playlist['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title),
              if (total != null) Text('$total bài', style: AppText.meta),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}
