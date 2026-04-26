import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';

class UserDetailScreen extends StatefulWidget {
  final String id;
  const UserDetailScreen({super.key, required this.id});

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _user;
  bool _loading = true;
  late TabController _tabCtl;

  List<Map<String, dynamic>> _karaokes = [];
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _activities = [];
  bool _loadingTab = false;
  int _karaokeTotal = 0, _commentTotal = 0;

  @override
  void initState() {
    super.initState();
    _tabCtl = TabController(length: 3, vsync: this);
    _tabCtl.addListener(() {
      if (!_tabCtl.indexIsChanging) _loadTab();
    });
    _fetch();
  }

  @override
  void dispose() { _tabCtl.dispose(); super.dispose(); }

  Future<void> _fetch() async {
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        user(id: $id) {
          id username fullname gender yob point views listen
          avatar { url } background { url }
          roles { name alias group_type display_in_profile userRolePivot { role custom_title } }
          uploads(first: 1, where: {AND: [{column: "status", value: "approved"}]}) { paginatorInfo { total } }
          allComments: comments(first: 1, where: {AND: [{column: "status", value: 1}]}) { paginatorInfo { total } }
          allPoints: points(first: 1) { paginatorInfo { total } }
          karaokes(first: 10, page: 1, orderBy: [{column: "views", order: DESC}]) {
            data { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } users(first: 5) { data { id username avatar { url } } } sheet { year composers(first: 5) { data { id slug title } } } }
            paginatorInfo { total }
          }
        }
      }''', {'id': widget.id});
      final u = data['user'];
      if (u == null) { if (mounted) setState(() => _loading = false); return; }
      final user = Map<String, dynamic>.from(u as Map);
      final ks = ((user['karaokes']?['data'] ?? []) as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['file_type'] = 'karaoke';
        m['artists'] = {'data': ((m['users']?['data'] ?? []) as List).map((x) => {
          'id': x['id'], 'title': x['username'], 'slug': x['username'], 'avatar': x['avatar'],
        }).toList()};
        return m;
      }).toList();
      if (!mounted) return;
      setState(() {
        _user = user;
        _karaokes = ks;
        _karaokeTotal = user['karaokes']?['paginatorInfo']?['total'] ?? 0;
        _commentTotal = user['allComments']?['paginatorInfo']?['total'] ?? 0;
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _loadTab() async {
    if (_tabCtl.index == 1 && _comments.isEmpty) { await _loadComments(); }
    if (_tabCtl.index == 2 && _activities.isEmpty) { await _loadActivities(); }
  }

  Future<void> _loadComments() async {
    setState(() => _loadingTab = true);
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        user(id: $id) {
          comments(first: 20, page: 1, orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: 1}]}) {
            data { id content created_at object { __typename ... on Song { id title slug } ... on Folk { id title slug } ... on Instrumental { id title slug } ... on Poem { id title slug } ... on Karaoke { id title slug } ... on Sheet { id title slug } ... on Discussion { id title slug } } }
          }
        }
      }''', {'id': widget.id});
      final list = ((data['user']?['comments']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() { _comments = list; _loadingTab = false; });
    } catch (_) { if (mounted) setState(() => _loadingTab = false); }
  }

  Future<void> _loadActivities() async {
    setState(() => _loadingTab = true);
    try {
      final data = await ApiClient.query(r'''query($id: Mixed) {
        activities(first: 30, where: {AND: [{column: "user_id", value: $id}]}, orderBy: [{column: "id", order: DESC}]) {
          edges { node {
            action created_at
            object { __typename
              ... on Song { id title slug }
              ... on Folk { id title slug }
              ... on Instrumental { id title slug }
              ... on Poem { id title slug }
              ... on Karaoke { id title slug }
              ... on Sheet { id title slug }
              ... on Discussion { id title slug }
              ... on Document { id title slug }
              ... on Comment { id object { __typename ... on Song { id title slug } ... on Folk { id title slug } ... on Instrumental { id title slug } ... on Poem { id title slug } ... on Karaoke { id title slug } ... on Sheet { id title slug } ... on Discussion { id title slug } } }
            }
          } }
        }
      }''', {'id': widget.id});
      final edges = (data['activities']?['edges'] ?? []) as List;
      final list = edges.map((e) => Map<String, dynamic>.from(e['node'] as Map)).toList();
      if (!mounted) return;
      setState(() { _activities = list; _loadingTab = false; });
    } catch (_) { if (mounted) setState(() => _loadingTab = false); }
  }

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 == 0) buf.write('.'); buf.write(s[i]); }
    return buf.toString();
  }

  String _stripHtml(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  static const _typeLabels = {
    'song': 'Tân nhạc', 'folk': 'Dân ca', 'instrumental': 'Khí nhạc', 'poem': 'Tiếng thơ',
    'karaoke': 'Thành viên hát', 'sheet': 'Bản nhạc', 'discussion': 'Thảo luận',
    'document': 'Tư liệu', 'artist': 'Nghệ sĩ', 'composer': 'Nhạc sĩ', 'poet': 'Nhà thơ', 'recomposer': 'Soạn giả',
  };
  static const _actionLabels = {
    'listen': 'nghe', 'view': 'xem', 'love': 'thích', 'unlove': 'bỏ thích',
    'comment': 'bình luận', 'love_comment': 'thích bình luận', 'update_lyric': 'cập nhật lời',
    'create_sheet': 'đăng bản nhạc', 'create_document': 'đăng tư liệu',
    'create_song': 'đăng tân nhạc', 'create_folk': 'đăng dân ca',
    'create_instrumental': 'đăng khí nhạc', 'create_karaoke': 'đăng karaoke',
    'create_poem': 'đăng tiếng thơ', 'create_discussion': 'mở thảo luận',
    'approve_upload': 'duyệt bài gửi', 'reject_upload': 'từ chối bài gửi',
  };

  String _objectTypeLabel(String? typename) {
    if (typename == null) return '(không có)';
    return _typeLabels[typename.toLowerCase()] ?? typename;
  }

  String? _routeForObject(Map<String, dynamic>? obj) {
    if (obj == null) return null;
    final type = (obj['__typename'] ?? '').toString().toLowerCase();
    if (['song', 'folk', 'instrumental', 'poem', 'karaoke'].contains(type)) return '/song/${obj['id']}';
    if (type == 'sheet') return '/sheet/${obj['id']}';
    if (type == 'discussion') return '/thao-luan/${obj['id']}';
    return null;
  }

  Widget _rolesRow(Map<String, dynamic> u) {
    final roles = ((u['roles'] ?? []) as List)
        .where((r) => r != null && (r['display_in_profile'] == 1 || r['display_in_profile'] == true))
        .toList();
    if (roles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 4, runSpacing: 4, children: roles.map((r) {
        final label = r['userRolePivot']?['custom_title'] ?? r['name'] ?? '';
        final alias = (r['alias'] ?? '').toString();
        final group = (r['group_type'] ?? '').toString();
        Color color = AppColors.accentLight;
        if (alias == 'admin' || alias == 'ban') color = const Color(0xFFE74C3C);
        else if (alias == 'mod') color = const Color(0xFF3498DB);
        else if (group == 'nhom') color = const Color(0xFF2ECC71);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
          child: Text(label, style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
        );
      }).toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (_loading) return const Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    if (_user == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
        body: Center(child: Text('Không tìm thấy thành viên', style: AppText.bodyText)),
      );
    }
    final u = _user!;
    final uploadsTotal = u['uploads']?['paginatorInfo']?['total'] ?? 0;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        NestedScrollView(
          headerSliverBuilder: (ctx, innerBoxScrolled) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 270,
              backgroundColor: AppColors.bg,
              leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop()),
              title: innerBoxScrolled ? Text((u['username'] ?? '').toString().toUpperCase(), style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.text))) : null,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(fit: StackFit.expand, children: [
                  if (u['background']?['url'] != null)
                    CachedNetworkImage(imageUrl: u['background']['url'], fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppColors.surface))
                  else
                    Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight], begin: Alignment.topLeft, end: Alignment.bottomRight))),
                  Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
                  Positioned(left: 16, right: 16, bottom: 12, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 3)),
                        child: ClipOval(
                          child: u['avatar']?['url'] != null
                              ? CachedNetworkImage(imageUrl: u['avatar']['url'], fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.person, color: Colors.white))
                              : Container(color: AppColors.accent, child: const Icon(Icons.person, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(u['username'] ?? '', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                        if (u['yob'] != null && (u['yob'] as String).isNotEmpty)
                          Padding(padding: const EdgeInsets.only(top: 2), child: Text('${DateTime.now().year - (int.tryParse(u['yob']) ?? DateTime.now().year)} tuổi', style: body(const TextStyle(fontSize: 12, color: Colors.white70)))),
                      ])),
                    ]),
                    const SizedBox(height: 8),
                    _rolesRow(u),
                  ])),
                ]),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(TabBar(
                controller: _tabCtl,
                indicatorColor: AppColors.accent,
                labelColor: AppColors.text,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                unselectedLabelStyle: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                tabs: const [Tab(text: 'Tổng quan'), Tab(text: 'Bình luận'), Tab(text: 'Hoạt động')],
              )),
            ),
          ],
          body: TabBarView(controller: _tabCtl, children: [
            _overviewTab(u, uploadsTotal),
            _commentsTab(),
            _activitiesTab(),
          ]),
        ),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  Widget _overviewTab(Map<String, dynamic> u, int uploadsTotal) {
    final player = context.watch<PlayerProvider>();
    final intOf = (dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
    final contribTotal = intOf(u['allPoints']?['paginatorInfo']?['total']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        // Stats grid
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.1,
          children: [
            _stat('Điểm', intOf(u['point'])),
            _stat('Cống hiến', contribTotal),
            _stat('Bình luận', _commentTotal),
            _stat('Đóng góp', uploadsTotal),
          ],
        ),
        const SizedBox(height: 22),

        if (_karaokes.isNotEmpty) ...[
          Row(children: [
            const Icon(Icons.mic, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text('Thành viên hát (${_formatInt(_karaokeTotal)})', style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
          ]),
          const SizedBox(height: 8),
          ..._karaokes.asMap().entries.map((e) => SongRow(song: e.value, index: e.key, showIndex: true, onTap: () => context.push('/song/${e.value['id']}', extra: e.value))),
        ],
        SizedBox(height: player.currentSong != null ? 90 : 20),
      ],
    );
  }

  Widget _commentsTab() {
    if (_loadingTab && _comments.isEmpty) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    if (_comments.isEmpty) return Center(child: Text('Chưa có bình luận', style: AppText.bodyText));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: _comments.length,
      itemBuilder: (ctx, i) {
        final c = _comments[i];
        final obj = c['object'] != null ? Map<String, dynamic>.from(c['object'] as Map) : null;
        final route = _routeForObject(obj);
        return InkWell(
          onTap: route != null ? () => context.push(route) : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                obj?['title']?.toString() ?? _objectTypeLabel(obj?['__typename']?.toString()),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accentLight)),
              ),
              const SizedBox(height: 4),
              Text(_stripHtml(c['content'] ?? ''), maxLines: 3, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, color: AppColors.text, height: 1.5))),
              const SizedBox(height: 6),
              Text(timeago(c['created_at']), style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
            ]),
          ),
        );
      },
    );
  }

  Widget _activitiesTab() {
    if (_loadingTab && _activities.isEmpty) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    if (_activities.isEmpty) return Center(child: Text('Chưa có hoạt động', style: AppText.bodyText));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: _activities.length,
      itemBuilder: (ctx, i) {
        final a = _activities[i];
        final obj = a['object'] != null ? Map<String, dynamic>.from(a['object'] as Map) : null;
        Map<String, dynamic>? target = obj;
        if (obj?['__typename'] == 'Comment' && obj?['object'] != null) target = Map<String, dynamic>.from(obj!['object'] as Map);
        final route = _routeForObject(target);
        final action = (a['action'] ?? '').toString();
        final actionLabel = _actionLabels[action] ?? action;
        final targetTitle = target?['title']?.toString() ?? _objectTypeLabel(target?['__typename']?.toString());
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.access_time, size: 14, color: AppColors.accentLight),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                onTap: route != null ? () => context.push(route) : null,
                child: RichText(text: TextSpan(children: [
                  TextSpan(text: actionLabel, style: body(const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4))),
                  const TextSpan(text: ' '),
                  TextSpan(text: targetTitle, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.4))),
                ])),
              ),
              const SizedBox(height: 2),
              Text(timeago(a['created_at']), style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
            ])),
          ]),
        );
      },
    );
  }

  Widget _stat(String label, int value) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_formatInt(value), maxLines: 1, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
        const SizedBox(height: 4),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
      ]),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);
  @override double get maxExtent => tabBar.preferredSize.height;
  @override double get minExtent => tabBar.preferredSize.height;
  @override Widget build(BuildContext ctx, double shrinkOffset, bool overlapsContent) {
    return Container(color: AppColors.bg, child: tabBar);
  }
  @override bool shouldRebuild(covariant SliverPersistentHeaderDelegate old) => false;
}
