import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
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

  // Karaokes — kept in state with pagination so the dedicated tab can lazy
  // append. Initial fetch primes the first page (also used for Tổng quan
  // preview).
  List<Map<String, dynamic>> _karaokes = [];
  int _karaokePage = 1, _karaokeLastPage = 1;
  bool _karaokeLoadingMore = false;

  // Comments tab — loaded on tab open.
  List<Map<String, dynamic>> _comments = [];
  bool _commentsLoading = false;

  // Points tab — loaded on tab open.
  List<Map<String, dynamic>> _points = [];
  bool _pointsLoading = false;

  // Tổng quan previews (small samples shown in the overview tab so the user
  // sees what's behind each tab without switching).
  List<Map<String, dynamic>> _previewComments = [];
  List<Map<String, dynamic>> _previewPoints = [];

  int _karaokeTotal = 0, _commentTotal = 0;

  @override
  void initState() {
    super.initState();
    _tabCtl = TabController(length: 4, vsync: this);
    _tabCtl.addListener(_onTabChanged);
    _fetch();
  }

  @override
  void dispose() {
    _tabCtl.removeListener(_onTabChanged);
    _tabCtl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabCtl.indexIsChanging) return;
    if (_tabCtl.index == 2 && _comments.isEmpty && !_commentsLoading) _loadComments();
    if (_tabCtl.index == 3 && _points.isEmpty && !_pointsLoading) _loadPoints();
  }

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
            paginatorInfo { total currentPage lastPage }
          }
          recentComments: comments(first: 3, page: 1, orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: 1}]}) {
            data { id content created_at object { __typename ... on Song { id title slug } ... on Folk { id title slug } ... on Instrumental { id title slug } ... on Poem { id title slug } ... on Karaoke { id title slug } ... on Sheet { id title slug } ... on Discussion { id title slug } } }
          }
          recentPoints: points(first: 3, page: 1, orderBy: [{column: "id", order: DESC}]) {
            data {
              id point reward_type reason created_at
              activity {
                action object_type
                object {
                  __typename
                  ... on Song { id title slug }
                  ... on Folk { id title slug }
                  ... on Instrumental { id title slug }
                  ... on Poem { id title slug }
                  ... on Karaoke { id title slug }
                  ... on Document { id title slug }
                  ... on Sheet { id title slug }
                  ... on Discussion { id title slug }
                }
              }
            }
          }
        }
      }''', {'id': widget.id});
      final u = data['user'];
      if (u == null) { if (mounted) setState(() => _loading = false); return; }
      final user = Map<String, dynamic>.from(u as Map);
      final ks = _normalizeKaraokes((user['karaokes']?['data'] ?? []) as List);
      final pi = user['karaokes']?['paginatorInfo'];
      if (!mounted) return;
      setState(() {
        _user = user;
        _karaokes = ks;
        _karaokeTotal = pi?['total'] ?? 0;
        _karaokePage = pi?['currentPage'] ?? 1;
        _karaokeLastPage = pi?['lastPage'] ?? 1;
        _commentTotal = user['allComments']?['paginatorInfo']?['total'] ?? 0;
        _previewComments = ((user['recentComments']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _previewPoints = ((user['recentPoints']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      // ignore: avoid_print
      print('[user_detail] fetch failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _normalizeKaraokes(List raw) => raw.map((e) {
    final m = Map<String, dynamic>.from(e as Map);
    m['file_type'] = 'karaoke';
    m['artists'] = {'data': ((m['users']?['data'] ?? []) as List).map((x) => {
      'id': x['id'], 'title': x['username'], 'slug': x['username'], 'avatar': x['avatar'],
    }).toList()};
    return m;
  }).toList();

  Future<void> _loadMoreKaraokes() async {
    if (_karaokeLoadingMore || _karaokePage >= _karaokeLastPage) return;
    setState(() => _karaokeLoadingMore = true);
    try {
      final next = _karaokePage + 1;
      final data = await ApiClient.query(r'''query($id: ID!, $page: Int) {
        user(id: $id) {
          karaokes(first: 10, page: $page, orderBy: [{column: "views", order: DESC}]) {
            data { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } users(first: 5) { data { id username avatar { url } } } sheet { year composers(first: 5) { data { id slug title } } } }
            paginatorInfo { total currentPage lastPage }
          }
        }
      }''', {'id': widget.id, 'page': next});
      final raw = (data['user']?['karaokes']?['data'] ?? []) as List;
      final pi = data['user']?['karaokes']?['paginatorInfo'];
      if (!mounted) return;
      setState(() {
        _karaokes = [..._karaokes, ..._normalizeKaraokes(raw)];
        _karaokePage = pi?['currentPage'] ?? next;
        _karaokeLastPage = pi?['lastPage'] ?? _karaokeLastPage;
        _karaokeLoadingMore = false;
      });
    } catch (e) {
      // ignore: avoid_print
      print('[user_detail] karaokes page fetch failed: $e');
      if (mounted) setState(() => _karaokeLoadingMore = false);
    }
  }

  Future<void> _loadComments() async {
    setState(() => _commentsLoading = true);
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        user(id: $id) {
          comments(first: 30, page: 1, orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: 1}]}) {
            data { id content created_at object { __typename ... on Song { id title slug } ... on Folk { id title slug } ... on Instrumental { id title slug } ... on Poem { id title slug } ... on Karaoke { id title slug } ... on Sheet { id title slug } ... on Discussion { id title slug } } }
          }
        }
      }''', {'id': widget.id});
      final list = ((data['user']?['comments']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() { _comments = list; _commentsLoading = false; });
    } catch (e) {
      // ignore: avoid_print
      print('[user_detail] comments fetch failed: $e');
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  Future<void> _loadPoints() async {
    setState(() => _pointsLoading = true);
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        user(id: $id) {
          points(first: 30, page: 1, orderBy: [{column: "id", order: DESC}]) {
            data {
              id point reward_type reason created_at
              activity {
                action object_type object_id
                object {
                  __typename
                  ... on Song { id title slug }
                  ... on Folk { id title slug }
                  ... on Instrumental { id title slug }
                  ... on Poem { id title slug }
                  ... on Karaoke { id title slug }
                  ... on Document { id title slug }
                  ... on Sheet { id title slug }
                  ... on Discussion { id title slug }
                  ... on Playlist { id title slug }
                  ... on Upload { id }
                }
              }
            }
          }
        }
      }''', {'id': widget.id});
      final list = ((data['user']?['points']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() { _points = list; _pointsLoading = false; });
    } catch (e) {
      // ignore: avoid_print
      print('[user_detail] points fetch failed: $e');
      if (mounted) setState(() => _pointsLoading = false);
    }
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

  Future<void> _share() async {
    if (_user == null) return;
    final url = '$siteUrl/user/${widget.id}';
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Đã sao chép link: $url'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (_) {}
  }

  void _showAvatarZoom() {
    final url = _user?['avatar']?['url'];
    if (url == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Stack(children: [
            Center(
              child: InteractiveViewer(
                minScale: 1, maxScale: 4,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.white70)),
                  errorWidget: (_, _, _) => const Padding(padding: EdgeInsets.all(40), child: Icon(Icons.broken_image, color: Colors.white38, size: 48)),
                ),
              ),
            ),
            Positioned(top: 0, right: 0, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx))),
          ]),
        ),
      ),
    );
  }

  Widget _rolesRow(Map<String, dynamic> u) {
    final roles = ((u['roles'] ?? []) as List)
        .where((r) => r != null && (r['display_in_profile'] == 1 || r['display_in_profile'] == true))
        .toList();
    if (roles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 4, runSpacing: 4, children: roles.map((r) {
        // userRolePivot.custom_title can be null OR "" — `??` only catches
        // null, so treat empty/whitespace as "no custom title" too.
        final ct = r['userRolePivot']?['custom_title']?.toString().trim() ?? '';
        final label = ct.isNotEmpty ? ct : (r['name']?.toString() ?? '');
        final alias = (r['alias'] ?? '').toString();
        final group = (r['group_type'] ?? '').toString();
        Color color = AppColors.accentLight;
        if (alias == 'admin' || alias == 'ban') {
          color = const Color(0xFFE74C3C);
        } else if (alias == 'mod') {
          color = const Color(0xFF3498DB);
        } else if (group == 'nhom') {
          color = const Color(0xFF2ECC71);
        }
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
    final auth = context.watch<AuthProvider>();
    final isOwnProfile = auth.user?['id']?.toString() == widget.id;
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
              actions: [
                IconButton(
                  tooltip: isOwnProfile ? 'Sao chép link hồ sơ' : 'Sao chép link',
                  icon: const Icon(Icons.ios_share, color: Colors.white),
                  onPressed: _share,
                ),
              ],
              title: innerBoxScrolled ? Text((u['username'] ?? '').toString().toUpperCase(), style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.text))) : null,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(fit: StackFit.expand, children: [
                  if (u['background']?['url'] != null)
                    CachedNetworkImage(imageUrl: u['background']['url'], fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: AppColors.surface))
                  else
                    Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight], begin: Alignment.topLeft, end: Alignment.bottomRight))),
                  Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
                  Positioned(left: 16, right: 16, bottom: 12, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      InkWell(
                        onTap: u['avatar']?['url'] != null ? _showAvatarZoom : null,
                        borderRadius: BorderRadius.circular(40),
                        child: Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 3)),
                          child: ClipOval(
                            child: u['avatar']?['url'] != null
                                ? CachedNetworkImage(imageUrl: u['avatar']['url'], fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.person, color: Colors.white))
                                : Container(color: AppColors.accent, child: const Icon(Icons.person, color: Colors.white)),
                          ),
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
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: AppColors.accent,
                labelColor: AppColors.text,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                unselectedLabelStyle: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                tabs: [
                  const Tab(text: 'Tổng quan'),
                  Tab(text: 'Bản thu${_karaokeTotal > 0 ? ' (${_formatInt(_karaokeTotal)})' : ''}'),
                  Tab(text: 'Bình luận${_commentTotal > 0 ? ' (${_formatInt(_commentTotal)})' : ''}'),
                  const Tab(text: 'Cống hiến'),
                ],
              )),
            ),
          ],
          body: TabBarView(controller: _tabCtl, children: [
            _overviewTab(u, uploadsTotal),
            _karaokesTab(),
            _commentsTab(),
            _pointsTab(),
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
        // Stats grid — each cell jumps to the corresponding tab/page
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.1,
          children: [
            _statTile('Điểm', intOf(u['point']), null),
            _statTile('Cống hiến', contribTotal, () => _tabCtl.animateTo(3)),
            _statTile('Bình luận', _commentTotal, () => _tabCtl.animateTo(2)),
            _statTile('Đóng góp', uploadsTotal, null),
          ],
        ),
        const SizedBox(height: 22),

        // Recent karaokes preview (top 3 from initial fetch)
        if (_karaokes.isNotEmpty) ...[
          _previewHeader(Icons.mic, 'Bản thu', () => _tabCtl.animateTo(1)),
          const SizedBox(height: 4),
          ..._karaokes.take(3).toList().asMap().entries.map((e) => SongRow(song: e.value, index: e.key, showIndex: true, onTap: () => context.push('/song/${e.value['id']}', extra: e.value))),
          const SizedBox(height: 22),
        ],

        // Recent comments preview
        if (_previewComments.isNotEmpty) ...[
          _previewHeader(Icons.chat_bubble_outline, 'Bình luận', () => _tabCtl.animateTo(2)),
          const SizedBox(height: 8),
          ..._previewComments.map(_commentCard),
          const SizedBox(height: 22),
        ],

        // Recent points preview
        if (_previewPoints.isNotEmpty) ...[
          _previewHeader(Icons.workspace_premium_outlined, 'Cống hiến', () => _tabCtl.animateTo(3)),
          const SizedBox(height: 4),
          ..._previewPoints.map(_pointRow),
        ],

        SizedBox(height: player.currentSong != null ? 90 : 20),
      ],
    );
  }

  Widget _karaokesTab() {
    if (_karaokes.isEmpty) return Center(child: Text('Chưa có bản thu', style: AppText.bodyText));
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        if (!_karaokeLoadingMore && _karaokePage < _karaokeLastPage && n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
          _loadMoreKaraokes();
        }
        return false;
      },
      child: ListView.builder(
        key: const PageStorageKey('user-karaokes'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        itemCount: _karaokes.length + 1,
        itemBuilder: (ctx, i) {
          if (i == _karaokes.length) {
            if (_karaokeLoadingMore) {
              return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(color: AppColors.accent)));
            }
            if (_karaokePage >= _karaokeLastPage) {
              return Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('Đã hết', style: body(const TextStyle(fontSize: 12, color: AppColors.textMuted)))));
            }
            return const SizedBox(height: 16);
          }
          final s = _karaokes[i];
          return SongRow(song: s, index: i, showIndex: true, onTap: () => context.push('/song/${s['id']}', extra: s));
        },
      ),
    );
  }

  Widget _commentsTab() {
    if (_commentsLoading && _comments.isEmpty) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    if (_comments.isEmpty) return Center(child: Text('Chưa có bình luận', style: AppText.bodyText));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: _comments.length,
      itemBuilder: (ctx, i) => _commentCard(_comments[i]),
    );
  }

  Widget _pointsTab() {
    if (_pointsLoading && _points.isEmpty) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    if (_points.isEmpty) return Center(child: Text('Chưa có cống hiến', style: AppText.bodyText));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: _points.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.borderSubtle),
      itemBuilder: (ctx, i) => _pointRow(_points[i]),
    );
  }

  Widget _commentCard(Map<String, dynamic> c) {
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
  }

  Widget _pointRow(Map<String, dynamic> pt) {
    final point = (pt['point'] is num) ? (pt['point'] as num).toInt() : int.tryParse('${pt['point']}') ?? 0;
    final activity = pt['activity'] is Map ? Map<String, dynamic>.from(pt['activity'] as Map) : <String, dynamic>{};
    final target = activity['object'] is Map ? Map<String, dynamic>.from(activity['object'] as Map) : null;
    final route = _routeForObject(target);
    final reason = (pt['reason']?.toString().isNotEmpty == true) ? pt['reason'] : (pt['reward_type'] ?? '');
    return InkWell(
      onTap: route != null ? () => context.push(route) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (point >= 0 ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C)).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${point > 0 ? '+' : ''}$point',
              style: display(TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800,
                color: point >= 0 ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C),
              )),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(reason.toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, color: AppColors.text))),
            if (target?['title'] != null) ...[
              const SizedBox(height: 2),
              Text(target!['title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, color: AppColors.accentLight))),
            ],
            const SizedBox(height: 2),
            Text(timeago(pt['created_at']), style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
          ])),
        ]),
      ),
    );
  }

  Widget _previewHeader(IconData icon, String title, VoidCallback onSeeAll) {
    return Row(children: [
      Icon(icon, size: 14, color: AppColors.textSecondary),
      const SizedBox(width: 6),
      Text(title, style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
      const Spacer(),
      InkWell(
        onTap: onSeeAll,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Xem tất cả', style: body(const TextStyle(fontSize: 12, color: AppColors.accentLight, fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.accentLight),
          ]),
        ),
      ),
    ]);
  }

  Widget _statTile(String label, int value, VoidCallback? onTap) {
    final tile = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_formatInt(value), maxLines: 1, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
        const SizedBox(height: 4),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
      ]),
    );
    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: tile,
      ),
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
