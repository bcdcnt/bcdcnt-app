import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/offline_store.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/auth_dialogs.dart';
import '../widgets/brand_logo.dart';
import '../widgets/ui.dart';
import '../widgets/listening_profile_card.dart';
import '../main.dart' show TabReselect;

/// Cá nhân tab (2026-11): everything "của tôi" in one place — the old
/// Thư viện and Cá nhân tabs merged (route stays /library). Profile card on top, four big tiles,
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
    if (TabReselect.tick.value.$1 != 3) return;
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    }
    _refresh();
  }

  /// Pull-to-refresh / tab reselect / back from a sub-page: reload the
  /// member's playlists and follows (they change on other screens).
  Future<void> _refresh() async {
    final auth = _auth;
    if (auth == null || auth.loading || !auth.isAuthenticated || !mounted) return;
    final uid = auth.user?['id']?.toString();
    if (uid == null) return;
    _loadedFor = uid;
    await Future.wait([_fetchPlaylists(auth, quiet: _playlists.isNotEmpty), _fetchFollowing(auth, uid), _fetchCounts(auth, uid)]);
  }

  /// Push a sub-page and refresh when the member comes back to Cá nhân.
  Future<void> _pushThenRefresh(String route) async {
    await context.push(route);
    if (mounted) _refresh();
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
        _counts = {};
      });
      return;
    }
    _fetchPlaylists(auth);
    _fetchFollowing(auth, uid);
    _fetchCounts(auth, uid);
  }

  /// Numbers on the desktop tiles; a tile without one just shows its label.
  Map<String, int> _counts = {};
  Future<void> _fetchCounts(AuthProvider auth, String uid) async {
    try {
      final d = await auth.authedQuery(r'''query($id: ID!) { user(id: $id) {
        loves(first: 1) { paginatorInfo { total } }
        uploads(first: 1) { paginatorInfo { total } }
        comments(first: 1) { paginatorInfo { total } }
      } }''', {'id': uid});
      final u = d['user'];
      int? n(String k) => (u?[k]?['paginatorInfo']?['total'] as num?)?.toInt();
      if (mounted) setState(() => _counts = {for (final k in ['loves', 'uploads', 'comments']) if (n(k) != null) k: n(k)!});
    } catch (_) {}
  }

  Future<void> _fetchPlaylists(AuthProvider auth, {bool quiet = false}) async {
    // quiet: keep the current list on screen while refreshing (no skeleton).
    if (!quiet) setState(() => _loadingPlaylists = true);
    const obj = '... on Song { thumbnail { url } } ... on Folk { thumbnail { url } } ... on Instrumental { thumbnail { url } } ... on Poem { thumbnail { url } }';
    try {
      final d = await auth.authedQuery('''query { myPlaylists(first: 12, page: 1, orderBy: [{column: "id", order: DESC}]) {
        data { id title slug thumbnail { url } items(first: 4) { paginatorInfo { total } data { object { $obj } } } }
      } }''', null);
      if (!mounted) return;
      setState(() {
        _playlists = ((d['myPlaylists']?['data'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loadingPlaylists = false;
      });
      _playlistsFailed = false;
    } catch (_) {
      // A failed quiet refresh keeps the list already shown.
      if (mounted) setState(() { _loadingPlaylists = false; _playlistsFailed = !quiet || _playlists.isEmpty; });
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

    // Tile height grows with the text-size setting so "Rất lớn" never overflows:
    // padding + icon + gap + title line + subtitle line.
    final ts = MediaQuery.textScalerOf(context);
    final tileExtent = (28 + 40 + 10 + ts.scale(16) * 1.35 + ts.scale(13) * 1.35 + 6).clamp(110.0, 260.0);
    if (MediaQuery.sizeOf(context).width >= 900) return _desktop(auth, user, tileExtent);

    return ColoredBox(
      color: AppColors.bg,
      child: RefreshIndicator(
        color: AppColors.accentFg,
        onRefresh: _refresh,
        child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          PageTitle(
            'Cá nhân',
            leading: user != null
                ? Semantics(
                    label: 'Hồ sơ của tôi',
                    button: true,
                    excludeSemantics: true,
                    child: GestureDetector(onTap: () => context.push('/user/${user['id']}'), child: UserAvatar(url: user['avatar']?.toString(), name: name, size: 44)),
                  )
                : null,
            actions: [
              // Canvas "Cá nhân · nút Gửi bài" (chốt 17/11).
              if (auth.hasPermission('upload')) ...[
                PillButton(label: 'Gửi bài', icon: Icons.add_rounded, height: 44, onTap: () => context.push('/gui-bai')),
                const SizedBox(width: 8),
              ],
              RoundIcon(icon: Icons.settings_outlined, tooltip: 'Cài đặt', onTap: () => context.push('/cai-dat')),
            ],
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
            child: GridView(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: tileExtent,
              ),
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Tile(icon: Icons.favorite_rounded, title: 'Yêu thích', subtitle: 'Bài đã thả tim', onTap: () => _open('/yeu-thich')),
                _Tile(icon: Icons.history_rounded, title: 'Nghe gần đây', subtitle: 'Lịch sử nghe', onTap: () => _open('/nghe-gan-day')),
                Consumer<OfflineStore>(builder: (_, store, _) => _Tile(icon: Icons.download_for_offline_rounded, title: 'Đã tải về', subtitle: store.items.isEmpty ? 'Nghe không cần mạng' : '${store.items.length} bài · nghe offline', onTap: () => context.push('/da-tai-ve'))),
                _Tile(icon: Icons.upload_rounded, title: 'Bài gửi', subtitle: 'Bài bạn đã gửi', onTap: () => _open('/bai-gui-cua-toi')),
              ],
            ),
          ),
          if (user != null) ...[
            SectionTitle('Playlist của tôi', action: 'Xem tất cả', onAction: () => _pushThenRefresh('/playlist-cua-toi')),
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
                    child: Text('Tải lại', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
                  ),
                ]),
              )
            else if (_playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Bạn chưa có playlist. Bấm ⋮ ở một bài hát rồi chọn "Thêm vào playlist" để tạo.', style: AppText.bodyText),
              )
            else
              for (final p in _playlists.take(6)) _PlaylistRow(playlist: p, onOpen: () => _pushThenRefresh('/playlist/${p['id']}')),
            if (_following.isNotEmpty) ...[
              SectionTitle('Nghệ sĩ yêu thích', action: null),
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
                    loved: true,
                    onTap: () => _pushThenRefresh('${_personRoutes[p['type']]}${p['slug']}'),
                  );
                },
              ),
            ],
            const GroupLabel('Hoạt động của tôi'),
            ListItem(icon: Icons.chat_bubble_outline_rounded, title: 'Bình luận của tôi', onTap: () => context.push('/binh-luan-cua-toi')),
            ListItem(icon: Icons.forum_outlined, title: 'Thảo luận của tôi', onTap: () => context.push('/thao-luan-cua-toi')),
            ListItem(icon: Icons.insights_rounded, title: 'Điểm & thống kê nghe', onTap: () => context.push('/thong-ke')),
            ListItem(icon: Icons.volunteer_activism_outlined, title: 'Góp tay cho kho nhạc', subtitle: 'Bổ sung tác giả, năm sáng tác… được cộng điểm', onTap: () => context.push('/gop-tay')),
            ListItem(icon: Icons.notifications_none_rounded, title: 'Thông báo', trailingText: (user['unread'] ?? 0) > 0 ? '${user['unread']}' : null, onTap: () => context.push('/thong-bao')),
          ],
          const GroupLabel('Khác'),
          ListItem(icon: Icons.info_outline_rounded, title: 'Giới thiệu BCĐCNT', subtitle: 'Giới thiệu về trang nhạc', onTap: () => context.push('/gioi-thieu')),
          ListItem(icon: Icons.help_outline_rounded, title: 'Câu hỏi thường gặp', subtitle: 'Nghe, tải nhạc, tài khoản, đóng góp', onTap: () => context.push('/faq')),
          ListItem(icon: Icons.support_agent_rounded, title: 'Góp ý & hỗ trợ', subtitle: 'Gửi riêng cho BQT', onTap: () => context.push('/ho-tro')),
          ListItem(icon: Icons.policy_outlined, title: 'Chính sách & điều khoản', subtitle: 'Quyền riêng tư, điều khoản sử dụng', onTap: () => context.push('/p/dieu-khoan')),
          if (user != null)
            ListItem(
              icon: Icons.logout_rounded,
              title: 'Đăng xuất',
              titleColor: AppColors.errorText,
              trailing: const SizedBox.shrink(),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: Text('Đăng xuất?', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text))),
                    // Downloads live in OfflineStore, which logout leaves alone.
                    content: Text('Bài đã tải về vẫn nghe được khi không có mạng. Đăng nhập lại để đồng bộ yêu thích và playlist.',
                        style: body(TextStyle(fontSize: 16, height: 1.5, color: AppColors.textSecondary))),
                    actions: [
                      TextButton(
                        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Huỷ', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
                      ),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFA32020),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text('Đăng xuất', style: body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                        ),
                      ),
                    ],
                  ),
                );
                if (ok == true) auth.logout();
              },
            ),
          const SizedBox(height: 24),
          const Center(child: BrandLogo(height: 26)),
          // "1.4.1+14" → "Phiên bản 1.4.1 (14)": what to quote when asking BQT for help.
          if (ApiClient.appVersion.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Phiên bản ${ApiClient.appVersion.split('+').first}${ApiClient.appVersion.contains('+') ? ' (${ApiClient.appVersion.split('+').last})' : ''}',
                textAlign: TextAlign.center,
                style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
              ),
            ),
        ],
        ),
      ),
    );
  }
}

extension _Desktop on _LibraryScreenState {
  /// Desktop (canvas "Desktop · Cá nhân (tổng quan)"): one header with the
  /// name, the listening taste, six tiles with numbers, playlists and
  /// followed people as grids, small links at the foot. Đăng xuất lives in
  /// the account menu at the foot of the sidebar.
  Widget _desktop(AuthProvider auth, Map<String, dynamic>? user, double tileExtent) {
    final name = (user?['username'] ?? '').toString();
    final point = (user?['point'] as num?)?.toInt() ?? 0;
    final listen = (user?['listen'] as num?)?.toInt() ?? 0;
    String num0(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    String? count(String k, String unit) => _counts[k] == null ? null : '${num0(_counts[k]!)} $unit';
    Widget title(String t, {String? action, VoidCallback? onAction}) => Padding(
          padding: const EdgeInsets.only(top: 36, bottom: 14),
          child: Row(children: [
            Expanded(child: Text(t, style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text)))),
            if (action != null) TextButton(onPressed: onAction, child: Text(action, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
          ]),
        );
    final links = Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final (label, route) in const [('Giới thiệu', '/gioi-thieu'), ('Câu hỏi thường gặp', '/faq'), ('Góp ý & hỗ trợ', '/ho-tro'), ('Chính sách & điều khoản', '/p/dieu-khoan')])
          TextButton(onPressed: () => context.push(route), child: Text(label, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)))),
        if (ApiClient.appVersion.isNotEmpty)
          Padding(padding: const EdgeInsets.only(left: 8), child: Text('Phiên bản ${ApiClient.appVersion.split('+').first}', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted)))),
      ]),
    );
    final children = <Widget>[];
    if (user == null) {
      if (!auth.loading) {
        children.addAll([
          Text('Cá nhân', style: display(TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: AppColors.text))),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              Container(width: 64, height: 64, decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle), child: Icon(Icons.favorite_rounded, size: 30, color: AppColors.accentFg)),
              const SizedBox(width: 22),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Đăng nhập để có trang của riêng bạn', style: body(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
                  const SizedBox(height: 4),
                  Text('Lưu bài yêu thích, tạo playlist, xem gu nghe nhạc và tiếp tục nghe trên mọi thiết bị.', style: body(TextStyle(fontSize: 15, height: 1.5, color: AppColors.textSecondary))),
                ]),
              ),
              const SizedBox(width: 16),
              PillButton(label: 'Đăng nhập', height: 48, onTap: () => showDialog(context: context, builder: (_) => const LoginDialog())),
              const SizedBox(width: 10),
              PillButton(label: 'Đăng ký', height: 48, primary: false, onTap: () => showDialog(context: context, builder: (_) => const RegisterDialog())),
            ]),
          ),
          const SizedBox(height: 16),
          Consumer<OfflineStore>(builder: (_, store, _) => store.items.isEmpty
              ? const SizedBox.shrink()
              : Align(alignment: Alignment.centerLeft, child: PillButton(label: 'Đã tải về · ${store.items.length} bài', icon: Icons.download_for_offline_rounded, height: 44, primary: false, onTap: () => context.push('/da-tai-ve')))),
        ]);
      }
    } else {
      final tiles = <(IconData, String, String?, String)>[
        (Icons.favorite_rounded, 'Yêu thích', count('loves', 'bài'), '/yeu-thich'),
        (Icons.history_rounded, 'Nghe gần đây', 'Lịch sử nghe', '/nghe-gan-day'),
        (Icons.download_for_offline_rounded, 'Đã tải về', null, '/da-tai-ve'),
        (Icons.upload_rounded, 'Bài gửi', count('uploads', 'bài'), '/bai-gui-cua-toi'),
        (Icons.chat_bubble_rounded, 'Bình luận của tôi', count('comments', 'bình luận'), '/binh-luan-cua-toi'),
        (Icons.insights_rounded, 'Điểm & thống kê', point > 0 ? '${num0(point)} điểm' : null, '/thong-ke'),
      ];
      children.addAll([
        Row(children: [
          GestureDetector(onTap: () => context.push('/user/${user['id']}'), child: UserAvatar(url: user['avatar']?.toString(), name: name, size: 76)),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.text))),
              const SizedBox(height: 2),
              Text([if (point > 0) '${num0(point)} điểm', if (listen > 0) '${num0(listen)} lượt nghe'].join(' · '), style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            ]),
          ),
          PillButton(label: 'Hồ sơ', icon: Icons.person_outline_rounded, height: 44, primary: false, onTap: () => context.push('/user/${user['id']}')),
          const SizedBox(width: 10),
          PillButton(label: 'Cài đặt', icon: Icons.settings_outlined, height: 44, primary: false, onTap: () => context.push('/cai-dat')),
        ]),
        const SizedBox(height: 22),
        ListeningProfileCard(key: ValueKey('lp-${user['id']}'), inset: 0),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 1000 ? 6 : 3;
          final w = (c.maxWidth - (cols - 1) * 14) / cols;
          return Wrap(spacing: 14, runSpacing: 14, children: [
            for (final (icon, label, sub, route) in tiles)
              SizedBox(
                width: w,
                // Six across: a two-line name ("Bình luận của tôi") must fit.
                height: tileExtent + MediaQuery.textScalerOf(context).scale(16) * 1.35,
                child: route == '/da-tai-ve'
                    ? Consumer<OfflineStore>(builder: (_, store, _) => _Tile(icon: icon, title: label, subtitle: store.items.isEmpty ? 'Nghe không cần mạng' : '${store.items.length} bài', onTap: () => context.push(route)))
                    : _Tile(icon: icon, title: label, subtitle: sub ?? '', onTap: () => _pushThenRefresh(route)),
              ),
          ]);
        }),
        title('Playlist của tôi', action: 'Xem tất cả', onAction: () => _pushThenRefresh('/playlist-cua-toi')),
        if (_loadingPlaylists)
          const SizedBox(height: 180, child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)))
        else if (_playlistsFailed && _playlists.isEmpty)
          Text('Chưa tải được playlist của bạn. Kiểm tra mạng.', style: AppText.bodyText)
        else
          LayoutBuilder(builder: (context, c) {
            final cols = ((c.maxWidth + 18) / 188).floor().clamp(4, 8);
            final w = (c.maxWidth - (cols - 1) * 18) / cols;
            final shown = _playlists.take(cols - 1).toList();
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: w,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _pushThenRefresh('/playlist-cua-toi'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: w, height: w,
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border, width: 1.5)),
                      child: Icon(Icons.add_rounded, size: 44, color: AppColors.accentFg),
                    ),
                    const SizedBox(height: 8),
                    Text('Tạo playlist', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text))),
                    Text('Ở Playlist của tôi', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                  ]),
                ),
              ),
              for (final p in shown) ...[
                const SizedBox(width: 18),
                SizedBox(width: w, child: _PlaylistCard(playlist: p, size: w, onOpen: () => _pushThenRefresh('/playlist/${p['id']}'))),
              ],
            ]);
          }),
        if (_following.isNotEmpty) ...[
          title('Nghệ sĩ yêu thích'),
          LayoutBuilder(builder: (context, c) {
            final cols = ((c.maxWidth + 16) / 136).floor().clamp(5, 10);
            final w = (c.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(spacing: 16, runSpacing: 18, children: [
              for (final p in _following.take(cols * 2))
                SizedBox(
                  width: w,
                  child: PersonBubble(
                    name: (p['title'] ?? '').toString(),
                    image: p['avatar']?['url']?.toString(),
                    size: w,
                    tint: true,
                    loved: true,
                    onTap: () => _pushThenRefresh('${_LibraryScreenState._personRoutes[p['type']]}${p['slug']}'),
                  ),
                ),
            ]);
          }),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => context.push('/thao-luan-cua-toi'), icon: Icon(Icons.forum_outlined, size: 20, color: AppColors.accentFg), label: Text('Thảo luận của tôi', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg))))),
        ),
      ]);
    }
    return ColoredBox(
      color: AppColors.bg,
      child: LayoutBuilder(builder: (context, c) {
        final pad = c.maxWidth < 1000 ? 28.0 : 40.0;
        return SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(pad, 28, pad, 40),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...children, links]),
            ),
          ),
        );
      }),
    );
  }
}

/// Desktop playlist cover: four song covers, else its own picture.
class _PlaylistCard extends StatelessWidget {
  final Map<String, dynamic> playlist;
  final double size;
  final VoidCallback onOpen;
  const _PlaylistCard({required this.playlist, required this.size, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final own = playlist['thumbnail']?['url']?.toString();
    final thumbs = ((playlist['items']?['data'] ?? []) as List).whereType<Map>().map((i) => i['object']?['thumbnail']?['url']?.toString()).whereType<String>().toList();
    final total = playlist['items']?['paginatorInfo']?['total'];
    final Widget cover = thumbs.length >= 4
        ? GridView.count(crossAxisCount: 2, padding: EdgeInsets.zero, physics: const NeverScrollableScrollPhysics(), children: [for (final u in thumbs.take(4)) NetImage(url: u)])
        : own != null
            ? NetImage(url: own, width: size, height: size)
            : thumbs.isNotEmpty
                ? NetImage(url: thumbs.first, width: size, height: size)
                : Container(color: AppColors.accentSoft, child: Icon(Icons.queue_music_rounded, size: 40, color: AppColors.accentLight));
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox(width: size, height: size, child: cover)),
        const SizedBox(height: 8),
        Text('${playlist['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w800, color: AppColors.text))),
        if (total != null) Text('$total bài', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
      ]),
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
              Text('Hồ sơ ›', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
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
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: LinearGradient(colors: AppColors.heroGradient)),
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
                    child: SizedBox(height: 50, child: Center(child: Text('Đăng nhập', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.wine))))),
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
                child: Icon(icon, size: 22, color: strong ? Colors.white : AppColors.accentFg),
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
  final VoidCallback? onOpen;
  const _PlaylistRow({required this.playlist, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final total = playlist['items']?['paginatorInfo']?['total'];
    final cover = PlaylistCover(thumb: playlist['thumbnail']?['url']?.toString(), songThumbs: PlaylistCover.thumbsOf(playlist['items']), size: 52);
    return InkWell(
      onTap: onOpen ?? () => context.push('/playlist/${playlist['id']}'),
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
