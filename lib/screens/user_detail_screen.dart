import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/imgcdn.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/activity.dart';
import '../services/player.dart';
import '../services/share.dart';
import '../widgets/ui.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';

/// Plain text from a comment's HTML: line breaks kept, entities decoded.
String userCommentText(String? html) {
  if (html == null || html.isEmpty) return '';
  return html
      .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final code = int.tryParse(m[1]!);
        return code == null ? m[0]! : String.fromCharCode(code);
      })
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

const _objFragments = '''
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
  ... on Upload { id title }
''';

const _karaokeFields = 'id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } users(first: 5) { data { id username avatar { url } } } sheet { year composers(first: 5) { data { id slug title } } }';
const _commentFields = 'id content created_at object { $_objFragments }';
const _pointFields = 'id point reward_type reason created_at activity { action object_type object_id object { $_objFragments } }';
const _uploadFields = 'id title type composers artists poets year created_at';
const _approved = '{AND: [{column: "status", value: "approved"}]}';
const _commentWhere = '{AND: [{column: "status", value: 1}]}';

const _commentPageSize = 30, _pointPageSize = 30, _uploadPageSize = 20, _karaokePageSize = 10;

class UserDetailScreen extends StatefulWidget {
  final String id;
  const UserDetailScreen({super.key, required this.id});

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> with TickerProviderStateMixin {
  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _error = false;
  int? _rank;

  // Built from the tabs that actually have content (see [_syncTabs]).
  TabController? _tabCtl;
  List<String> _tabs = const ['overview'];

  // Bản thu
  List<Map<String, dynamic>> _karaokes = [];
  int _karaokePage = 1, _karaokeLastPage = 1;
  bool _karaokeLoadingMore = false;

  // Bài gửi
  List<Map<String, dynamic>> _uploads = [];
  int _uploadPage = 0, _uploadLastPage = 1;
  bool _uploadsLoading = false, _uploadsLoaded = false, _uploadsError = false;

  // Bình luận
  List<Map<String, dynamic>> _comments = [];
  int _commentPage = 0, _commentLastPage = 1;
  bool _commentsLoading = false, _commentsLoaded = false, _commentsError = false;

  // Cống hiến
  List<Map<String, dynamic>> _points = [];
  int _pointPage = 0, _pointLastPage = 1;
  bool _pointsLoading = false, _pointsLoaded = false, _pointsError = false;

  // Tổng quan previews
  List<Map<String, dynamic>> _previewComments = [];
  List<Map<String, dynamic>> _previewPoints = [];
  List<Map<String, dynamic>> _previewUploads = [];
  List<Map<String, dynamic>> _playlists = [];

  int _karaokeTotal = 0, _commentTotal = 0, _contribTotal = 0, _uploadTotal = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _tabCtl?.removeListener(_onTabChanged);
    _tabCtl?.dispose();
    super.dispose();
  }

  void _syncTabs() {
    final next = [
      'overview',
      if (_karaokeTotal > 0) 'karaoke',
      if (_uploadTotal > 0) 'upload',
      if (_commentTotal > 0) 'comment',
      if (_contribTotal > 0) 'point',
    ];
    if (_tabCtl != null && listEquals(next, _tabs)) return;
    final old = _tabCtl;
    final prevKey = old != null ? _tabs[old.index] : 'overview';
    final idx = next.indexOf(prevKey);
    _tabs = next;
    _tabCtl = TabController(length: next.length, vsync: this, initialIndex: idx < 0 ? 0 : idx)..addListener(_onTabChanged);
    if (old != null) {
      old.removeListener(_onTabChanged);
      // The old TabBar still holds it until the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  void _goTab(String key) {
    final i = _tabs.indexOf(key);
    if (i >= 0) _tabCtl?.animateTo(i);
  }

  void _onTabChanged() {
    final ctl = _tabCtl;
    if (ctl == null || ctl.indexIsChanging) return;
    switch (_tabs[ctl.index]) {
      case 'comment':
        if (!_commentsLoaded && !_commentsLoading) _loadComments();
      case 'point':
        if (!_pointsLoaded && !_pointsLoading) _loadPoints();
      case 'upload':
        if (!_uploadsLoaded && !_uploadsLoading) _loadUploads();
    }
  }

  static int _int(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
  static List<Map<String, dynamic>> _maps(dynamic list) =>
      ((list ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  Future<void> _fetch() async {
    try {
      final rankFuture = ApiClient.query('query { topMember(field: "point", first: 100) { data { id } } }')
          .then<int?>((d) {
        final ids = ((d['topMember']?['data'] ?? []) as List).map((e) => e?['id']?.toString()).toList();
        final i = ids.indexOf(widget.id);
        return i < 0 ? null : i + 1;
      }).catchError((_) => null);
      final data = await ApiClient.query('''query(\$id: ID!) {
        user(id: \$id) {
          id username point created_at
          avatar { url } background { url }
          roles { name alias group_type display_in_profile userRolePivot { role custom_title } }
          uploads(first: 3, page: 1, orderBy: [{column: "id", order: DESC}], where: $_approved) { data { $_uploadFields } paginatorInfo { total } }
          playlists(first: 10, page: 1, orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "is_public", value: 1}]}) { data { id title thumbnail { url } } paginatorInfo { total } }
          allComments: comments(first: 1, where: $_commentWhere) { paginatorInfo { total } }
          allPoints: points(first: 1) { paginatorInfo { total } }
          karaokes(first: $_karaokePageSize, page: 1, orderBy: [{column: "views", order: DESC}]) {
            data { $_karaokeFields }
            paginatorInfo { total currentPage lastPage }
          }
          recentComments: comments(first: 3, page: 1, orderBy: [{column: "id", order: DESC}], where: $_commentWhere) { data { $_commentFields } }
          recentPoints: points(first: 3, page: 1, orderBy: [{column: "id", order: DESC}]) { data { $_pointFields } }
        }
      }''', {'id': widget.id});
      final u = data['user'];
      if (u == null) {
        if (mounted) setState(() { _user = null; _loading = false; _error = false; });
        return;
      }
      final user = Map<String, dynamic>.from(u as Map);
      final pi = user['karaokes']?['paginatorInfo'];
      final rank = await rankFuture;
      if (!mounted) return;
      setState(() {
        _user = user;
        _rank = rank;
        _karaokes = _normalizeKaraokes((user['karaokes']?['data'] ?? []) as List);
        _karaokeTotal = _int(pi?['total']);
        _karaokePage = pi?['currentPage'] ?? 1;
        _karaokeLastPage = pi?['lastPage'] ?? 1;
        _uploadTotal = _int(user['uploads']?['paginatorInfo']?['total']);
        _commentTotal = _int(user['allComments']?['paginatorInfo']?['total']);
        _contribTotal = _int(user['allPoints']?['paginatorInfo']?['total']);
        _previewUploads = _maps(user['uploads']?['data']);
        _playlists = _maps(user['playlists']?['data']);
        _previewComments = _maps(user['recentComments']?['data']);
        _previewPoints = _maps(user['recentPoints']?['data']);
        _loading = false;
        _error = false;
        _syncTabs();
      });
      logActivity(context.read<AuthProvider>(), 'view', 'user', user['id']);
    } catch (e) {
      debugPrint('[user_detail] fetch failed: $e');
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  void _retry() {
    setState(() { _loading = true; _error = false; });
    _fetch();
  }

  List<Map<String, dynamic>> _normalizeKaraokes(List raw) => raw.map((e) {
    final m = Map<String, dynamic>.from(e as Map);
    m['file_type'] = 'karaoke';
    m['artists'] = {'data': ((m['users']?['data'] ?? []) as List).map((x) => {
      'id': x['id'], 'title': x['username'], 'slug': x['username'], 'avatar': x['avatar'],
    }).toList()};
    return m;
  }).toList();

  /// Row copy of a karaoke whose byline is "Nhạc sĩ · năm" (plus any
  /// duet partners) instead of repeating this member's own name.
  Map<String, dynamic> _karaokeRowSong(Map<String, dynamic> k) {
    final composers = ((k['sheet']?['composers']?['data'] ?? []) as List)
        .map((c) => c?['title']?.toString() ?? '')
        .where((s) => s.isNotEmpty && s != 'Đang cập nhật')
        .join(', ');
    final year = k['sheet']?['year']?.toString() ?? '';
    final partners = ((k['users']?['data'] ?? []) as List)
        .where((x) => x?['id']?.toString() != widget.id)
        .map((x) => x?['username']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .join(', ');
    final line = [composers, if (year.isNotEmpty && year != '0') year, if (partners.isNotEmpty) 'cùng $partners']
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return {
      ...k,
      'artists': {'data': line.isEmpty ? [] : [{'title': line}]},
    };
  }

  Widget _karaokeRow(int i) {
    final k = _karaokes[i];
    return SongRow(
      song: _karaokeRowSong(k),
      index: i,
      showIndex: true,
      queue: asSongList(_karaokes),
      onTap: () => playOrOpen(context, k, asSongList(_karaokes)),
    );
  }

  void _loadFailedSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa tải được, vui lòng thử lại')));
  }

  Future<void> _loadMoreKaraokes() async {
    if (_karaokeLoadingMore || _karaokePage >= _karaokeLastPage) return;
    setState(() => _karaokeLoadingMore = true);
    try {
      final next = _karaokePage + 1;
      final data = await ApiClient.query('''query(\$id: ID!, \$page: Int) {
        user(id: \$id) {
          karaokes(first: $_karaokePageSize, page: \$page, orderBy: [{column: "views", order: DESC}]) {
            data { $_karaokeFields }
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
      debugPrint('[user_detail] karaokes page fetch failed: $e');
      if (mounted) setState(() => _karaokeLoadingMore = false);
      _loadFailedSnack();
    }
  }

  Future<void> _loadUploads() async {
    if (_uploadsLoading) return;
    final next = _uploadPage + 1;
    setState(() { _uploadsLoading = true; _uploadsError = false; });
    try {
      final data = await ApiClient.query('''query(\$id: ID!, \$page: Int) {
        user(id: \$id) {
          uploads(first: $_uploadPageSize, page: \$page, orderBy: [{column: "id", order: DESC}], where: $_approved) {
            data { $_uploadFields }
            paginatorInfo { total currentPage lastPage }
          }
        }
      }''', {'id': widget.id, 'page': next});
      final p = data['user']?['uploads'];
      if (!mounted) return;
      setState(() {
        _uploads = next == 1 ? _maps(p?['data']) : [..._uploads, ..._maps(p?['data'])];
        _uploadPage = p?['paginatorInfo']?['currentPage'] ?? next;
        _uploadLastPage = p?['paginatorInfo']?['lastPage'] ?? _uploadPage;
        _uploadsLoading = false;
        _uploadsLoaded = true;
      });
    } catch (e) {
      debugPrint('[user_detail] uploads fetch failed: $e');
      if (!mounted) return;
      setState(() { _uploadsLoading = false; if (next == 1) _uploadsError = true; });
      if (next > 1) _loadFailedSnack();
    }
  }

  Future<void> _loadComments() async {
    if (_commentsLoading) return;
    final next = _commentPage + 1;
    setState(() { _commentsLoading = true; _commentsError = false; });
    try {
      final data = await ApiClient.query('''query(\$id: ID!, \$page: Int) {
        user(id: \$id) {
          comments(first: $_commentPageSize, page: \$page, orderBy: [{column: "id", order: DESC}], where: $_commentWhere) {
            data { $_commentFields }
            paginatorInfo { total currentPage lastPage }
          }
        }
      }''', {'id': widget.id, 'page': next});
      final p = data['user']?['comments'];
      if (!mounted) return;
      setState(() {
        _comments = next == 1 ? _maps(p?['data']) : [..._comments, ..._maps(p?['data'])];
        _commentPage = p?['paginatorInfo']?['currentPage'] ?? next;
        _commentLastPage = p?['paginatorInfo']?['lastPage'] ?? _commentPage;
        _commentsLoading = false;
        _commentsLoaded = true;
      });
    } catch (e) {
      debugPrint('[user_detail] comments fetch failed: $e');
      if (!mounted) return;
      setState(() { _commentsLoading = false; if (next == 1) _commentsError = true; });
      if (next > 1) _loadFailedSnack();
    }
  }

  Future<void> _loadPoints() async {
    if (_pointsLoading) return;
    final next = _pointPage + 1;
    setState(() { _pointsLoading = true; _pointsError = false; });
    try {
      final data = await ApiClient.query('''query(\$id: ID!, \$page: Int) {
        user(id: \$id) {
          points(first: $_pointPageSize, page: \$page, orderBy: [{column: "id", order: DESC}]) {
            data { $_pointFields }
            paginatorInfo { total currentPage lastPage }
          }
        }
      }''', {'id': widget.id, 'page': next});
      final p = data['user']?['points'];
      if (!mounted) return;
      setState(() {
        _points = next == 1 ? _maps(p?['data']) : [..._points, ..._maps(p?['data'])];
        _pointPage = p?['paginatorInfo']?['currentPage'] ?? next;
        _pointLastPage = p?['paginatorInfo']?['lastPage'] ?? _pointPage;
        _pointsLoading = false;
        _pointsLoaded = true;
      });
    } catch (e) {
      debugPrint('[user_detail] points fetch failed: $e');
      if (!mounted) return;
      setState(() { _pointsLoading = false; if (next == 1) _pointsError = true; });
      if (next > 1) _loadFailedSnack();
    }
  }

  static const _typeLabels = {
    'song': 'Tân nhạc', 'folk': 'Dân ca', 'instrumental': 'Khí nhạc', 'poem': 'Tiếng thơ',
    'karaoke': 'Thành viên hát', 'sheet': 'Bản nhạc', 'discussion': 'Thảo luận',
    'document': 'Tư liệu', 'artist': 'Nghệ sĩ', 'composer': 'Nhạc sĩ', 'poet': 'Nhà thơ', 'recomposer': 'Soạn giả',
    'playlist': 'Playlist', 'upload': 'Bài gửi',
  };
  String _objectTypeLabel(String? typename) {
    if (typename == null) return '(không có)';
    return _typeLabels[typename.toLowerCase()] ?? typename;
  }

  static const _uploadTypeLabels = {
    'song': 'Tân nhạc', 'folk': 'Dân ca', 'instrumental': 'Khí nhạc', 'karaoke': 'Karaoke',
    'poem': 'Tiếng thơ', 'beat': 'Nhạc nền', 'replace': 'Bổ sung bản ghi', 'sheet': 'Bản nhạc',
    'document_audio': 'Tư liệu âm thanh', 'document_image': 'Tư liệu hình ảnh',
    'document_video': 'Tư liệu video', 'document_news': 'Bài viết',
  };

  String? _routeForObject(Map<String, dynamic>? obj) {
    if (obj == null || obj['id'] == null) return null;
    final type = (obj['__typename'] ?? '').toString().toLowerCase();
    final id = obj['id'];
    if (['song', 'folk', 'instrumental', 'poem', 'karaoke'].contains(type)) return '/song/$id';
    return switch (type) {
      'sheet' => '/sheet/$id',
      'discussion' => '/thao-luan/$id',
      'document' => '/tu-lieu/chi-tiet/$id',
      'playlist' => '/playlist/$id',
      'upload' => '/bai-gui/$id',
      _ => null,
    };
  }

  Future<void> _share(BuildContext ctx) async {
    final u = _user;
    if (u == null) return;
    final url = '$siteUrl/user/${widget.id}';
    final name = (u['username'] ?? '').toString();
    await shareText(ctx, text: 'Trang thành viên $name trên Bài ca đi cùng năm tháng: $url', subject: 'Trang thành viên $name');
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
                  imageUrl: url  /* full size: zoomable viewer */,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.white70)),
                  errorWidget: (_, _, _) => const Padding(padding: EdgeInsets.all(40), child: Icon(Icons.broken_image, color: Colors.white38, size: 48)),
                ),
              ),
            ),
            Positioned(top: 0, right: 0, child: IconButton(tooltip: 'Đóng', icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx))),
          ]),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: Colors.white), const SizedBox(width: 4)],
          Text(label, style: body(const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white))),
        ]),
      );

  Widget _badgesRow(Map<String, dynamic> u) {
    final roles = ((u['roles'] ?? []) as List)
        .where((r) => r != null && (r['display_in_profile'] == 1 || r['display_in_profile'] == true))
        .toList();
    if (roles.isEmpty && _rank == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        if (_rank != null) _badge('Hạng #$_rank cống hiến', const Color(0xFFB8860B), icon: Icons.emoji_events_rounded),
        ...roles.map((r) {
          // userRolePivot.custom_title can be null OR "" — treat empty as none.
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
          return _badge(label, color);
        }),
      ]),
    );
  }

  String? _memberSince(Map<String, dynamic> u) {
    final d = DateTime.tryParse((u['created_at'] ?? '').toString());
    if (d == null) return null;
    final years = DateTime.now().year - d.year;
    return years >= 1 ? 'Thành viên từ ${d.year} · $years năm gắn bó' : 'Thành viên từ ${d.year}';
  }

  ButtonStyle get _circleBtn => IconButton.styleFrom(backgroundColor: Colors.black38, foregroundColor: Colors.white, fixedSize: const Size(48, 48));

  Widget _plainBack() => IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_rounded, color: AppColors.text), onPressed: () => goBack(context));

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (_loading) return _loadingScaffold();
    if (_error) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(backgroundColor: AppColors.bg, leading: _plainBack()),
        body: Center(child: SingleChildScrollView(child: OfflineBlock(onRetry: _retry))),
      );
    }
    if (_user == null || _tabCtl == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(backgroundColor: AppColors.bg, leading: _plainBack()),
        body: const Center(child: EmptyBlock(icon: Icons.person_off_outlined, title: 'Không tìm thấy thành viên', message: 'Tài khoản này không tồn tại hoặc đã bị xoá.')),
      );
    }
    final u = _user!;
    final name = (u['username'] ?? '').toString();
    final since = _memberSince(u);
    final avatarUrl = u['avatar']?['url']?.toString();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        NestedScrollView(
          headerSliverBuilder: (ctx, innerBoxScrolled) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 220,
              backgroundColor: AppColors.bg,
              surfaceTintColor: Colors.transparent,
              leadingWidth: 64,
              leading: Center(child: IconButton(tooltip: 'Quay lại', style: _circleBtn, icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => goBack(context))),
              actions: [
                Builder(builder: (bctx) => IconButton(
                  tooltip: 'Chia sẻ',
                  style: _circleBtn,
                  icon: const Icon(Icons.ios_share, color: Colors.white),
                  onPressed: () => _share(bctx),
                )),
                const SizedBox(width: 8),
              ],
              flexibleSpace: LayoutBuilder(builder: (lctx, c) {
                final top = MediaQuery.paddingOf(lctx).top;
                final collapsed = c.maxHeight <= top + kToolbarHeight + 24;
                return Stack(fit: StackFit.expand, children: [
                  FlexibleSpaceBar(
                    background: Stack(fit: StackFit.expand, children: [
                      if (u['background']?['url'] != null)
                        CachedNetworkImage(imageUrl: cdnImg((u['background']['url']).toString(), 960), fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: AppColors.surface))
                      else
                        Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)], begin: Alignment.topLeft, end: Alignment.bottomRight))),
                      Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
                      Positioned(left: 16, right: 16, bottom: 12, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          InkWell(
                            onTap: avatarUrl != null ? _showAvatarZoom : null,
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 72, height: 72,
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 3)),
                              child: UserAvatar(url: avatarUrl, name: name, size: 66),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                            if (since != null)
                              Padding(padding: const EdgeInsets.only(top: 3), child: Text(since, maxLines: 2, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)))),
                          ])),
                        ]),
                        _badgesRow(u),
                      ])),
                    ]),
                  ),
                  Positioned(
                    left: 72, right: 72, top: top, height: kToolbarHeight,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: collapsed ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
                        ),
                      ),
                    ),
                  ),
                ]);
              }),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(TabBar(
                controller: _tabCtl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: AppColors.border,
                indicatorColor: AppColors.accent,
                labelColor: AppColors.text,
                unselectedLabelColor: AppColors.textMuted,
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                labelStyle: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                unselectedLabelStyle: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                tabs: _tabs.map((k) => Tab(height: 48, text: _tabLabel(k))).toList(),
              )),
            ),
          ],
          body: TabBarView(controller: _tabCtl, children: _tabs.map((k) => switch (k) {
            'karaoke' => _karaokesTab(),
            'upload' => _uploadsTab(),
            'comment' => _commentsTab(),
            'point' => _pointsTab(),
            _ => _overviewTab(u),
          }).toList()),
        ),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  String _tabLabel(String k) => switch (k) {
        'karaoke' => 'Bản thu (${formatInt(_karaokeTotal)})',
        'upload' => 'Bài gửi (${formatInt(_uploadTotal)})',
        'comment' => 'Bình luận (${formatInt(_commentTotal)})',
        'point' => 'Cống hiến (${formatInt(_contribTotal)})',
        _ => 'Tổng quan',
      };

  Widget _loadingScaffold() => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(backgroundColor: AppColors.bg, leading: _plainBack()),
        body: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Row(children: [
                Skeleton(width: 72, height: 72, radius: 36),
                SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FractionallySizedBox(widthFactor: 0.6, child: Skeleton(height: 20)),
                  SizedBox(height: 10),
                  FractionallySizedBox(widthFactor: 0.8, child: Skeleton(height: 13)),
                ])),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(children: [
                for (int i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  const Expanded(child: Skeleton(height: 72, radius: 12)),
                ],
              ]),
            ),
            for (int i = 0; i < 5; i++) const SkeletonSongRow(),
          ],
        ),
      );

  Widget _skeletonList() => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 12),
        children: [for (int i = 0; i < 6; i++) const SkeletonSongRow()],
      );

  Widget _offlineTab(VoidCallback onRetry) => ListView(children: [OfflineBlock(onRetry: onRetry)]);

  /// "30 / 1.631" counter plus a full-width 48pt "Xem thêm" button.
  Widget _moreFooter({required int shown, required int total, required bool hasMore, required bool loading, required String label, required VoidCallback onMore}) {
    final remaining = total - shown;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(children: [
        Text('${formatInt(shown)} / ${formatInt(total)}', style: AppText.meta),
        if (hasMore) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: PillButton(
              primary: false,
              height: 48,
              loading: loading,
              label: remaining > 0 ? 'Xem thêm $label (còn ${formatInt(remaining)})' : 'Xem thêm $label',
              onTap: loading ? null : onMore,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _overviewTab(Map<String, dynamic> u) {
    final player = context.watch<PlayerProvider>();
    final auth = context.watch<AuthProvider>();
    final isOwnProfile = auth.user?['id']?.toString() == widget.id;
    final point = _int(u['point']);
    final hasActivity = point > 0 || _karaokeTotal > 0 || _uploadTotal > 0 || _commentTotal > 0 || _contribTotal > 0 || _playlists.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        if (isOwnProfile) ...[
          SizedBox(
            width: double.infinity,
            child: PillButton(primary: false, height: 48, icon: Icons.edit_outlined, label: 'Sửa hồ sơ', onTap: () => context.push('/cai-dat')),
          ),
          const SizedBox(height: 16),
        ],
        if (!hasActivity)
          const EmptyBlock(
            icon: Icons.waving_hand_outlined,
            title: 'Thành viên mới — chưa có hoạt động',
            message: 'Khi thành viên nghe, hát, gửi bài hay bình luận, hoạt động sẽ hiện ở đây.',
          )
        else ...[
          // Stats — every tile jumps to its tab.
          Row(children: [
            Expanded(child: _statTile('Điểm', point, () => _goTab('point'))),
            const SizedBox(width: 8),
            Expanded(child: _statTile('Bài gửi', _uploadTotal, () => _goTab('upload'))),
            const SizedBox(width: 8),
            Expanded(child: _statTile('Bản thu', _karaokeTotal, () => _goTab('karaoke'))),
            const SizedBox(width: 8),
            Expanded(child: _statTile('Bình luận', _commentTotal, () => _goTab('comment'))),
          ]),
          const SizedBox(height: 22),
        ],

        if (_karaokes.isNotEmpty) ...[
          _previewHeader(Icons.mic, 'Bản thu', () => _goTab('karaoke')),
          for (int i = 0; i < _karaokes.length && i < 3; i++) _karaokeRow(i),
          const SizedBox(height: 22),
        ],

        if (_previewUploads.isNotEmpty) ...[
          _previewHeader(Icons.upload_file_outlined, 'Bài gửi', () => _goTab('upload')),
          ..._previewUploads.map(_uploadRow),
          const SizedBox(height: 22),
        ],

        if (_playlists.isNotEmpty) ...[
          _previewHeader(Icons.queue_music_rounded, 'Playlist', null),
          const SizedBox(height: 6),
          BleedRow(
            height: 130 + 10 + MediaQuery.textScalerOf(context).scale(44),
            builder: (pad) => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: pad,
              itemCount: _playlists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final p = _playlists[i];
                final title = (p['title'] ?? '').toString();
                return RailCard(
                  width: 130,
                  title: title,
                  cover: NetImage(url: p['thumbnail']?['url']?.toString(), width: 130, height: 130, fallback: GeneratedCover(title: title, size: 130, radius: 0)),
                  onTap: () => context.push('/playlist/${p['id']}'),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
        ],

        if (_previewComments.isNotEmpty) ...[
          _previewHeader(Icons.chat_bubble_outline, 'Bình luận', () => _goTab('comment')),
          const SizedBox(height: 4),
          ..._previewComments.map(_commentCard),
          const SizedBox(height: 22),
        ],

        if (_previewPoints.isNotEmpty) ...[
          _previewHeader(Icons.workspace_premium_outlined, 'Cống hiến', () => _goTab('point')),
          ..._previewPoints.map(_pointRow),
        ],

        SizedBox(height: player.currentSong != null ? 90 : 20),
      ],
    );
  }

  Widget _karaokesTab() {
    return ListView.builder(
      key: const PageStorageKey('user-karaokes'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      itemCount: _karaokes.length + 1,
      itemBuilder: (ctx, i) {
        if (i == _karaokes.length) {
          return _moreFooter(
            shown: _karaokes.length,
            total: _karaokeTotal,
            hasMore: _karaokePage < _karaokeLastPage,
            loading: _karaokeLoadingMore,
            label: 'bản thu',
            onMore: _loadMoreKaraokes,
          );
        }
        return _karaokeRow(i);
      },
    );
  }

  Widget _uploadsTab() {
    if (!_uploadsLoaded) {
      if (_uploadsError) return _offlineTab(_loadUploads);
      return _skeletonList();
    }
    if (_uploads.isEmpty) return ListView(children: const [EmptyBlock(icon: Icons.upload_file_outlined, title: 'Chưa có bài gửi')]);
    return ListView.builder(
      key: const PageStorageKey('user-uploads'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: _uploads.length + 1,
      itemBuilder: (ctx, i) => i == _uploads.length
          ? _moreFooter(shown: _uploads.length, total: _uploadTotal, hasMore: _uploadPage < _uploadLastPage, loading: _uploadsLoading, label: 'bài gửi', onMore: _loadUploads)
          : _uploadRow(_uploads[i]),
    );
  }

  Widget _commentsTab() {
    if (!_commentsLoaded) {
      if (_commentsError) return _offlineTab(_loadComments);
      return _skeletonList();
    }
    if (_comments.isEmpty) return ListView(children: const [EmptyBlock(icon: Icons.chat_bubble_outline, title: 'Chưa có bình luận')]);
    return ListView.builder(
      key: const PageStorageKey('user-comments'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: _comments.length + 1,
      itemBuilder: (ctx, i) => i == _comments.length
          ? _moreFooter(shown: _comments.length, total: _commentTotal, hasMore: _commentPage < _commentLastPage, loading: _commentsLoading, label: 'bình luận', onMore: _loadComments)
          : _commentCard(_comments[i]),
    );
  }

  Widget _pointsTab() {
    if (!_pointsLoaded) {
      if (_pointsError) return _offlineTab(_loadPoints);
      return _skeletonList();
    }
    if (_points.isEmpty) return ListView(children: const [EmptyBlock(icon: Icons.workspace_premium_outlined, title: 'Chưa có cống hiến')]);
    return ListView.separated(
      key: const PageStorageKey('user-points'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: _points.length + 1,
      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.borderSubtle),
      itemBuilder: (ctx, i) => i == _points.length
          ? _moreFooter(shown: _points.length, total: _contribTotal, hasMore: _pointPage < _pointLastPage, loading: _pointsLoading, label: 'cống hiến', onMore: _loadPoints)
          : _pointRow(_points[i]),
    );
  }

  Widget _uploadRow(Map<String, dynamic> up) {
    final type = (up['type'] ?? '').toString();
    final people = [up['composers'], up['poets'], up['artists']]
        .map((v) => (v ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .join(' · ');
    final sub = [_uploadTypeLabels[type] ?? type, people, timeago(up['created_at']?.toString())].where((s) => s.isNotEmpty).join(' · ');
    final title = (up['title'] ?? '').toString();
    return InkWell(
      onTap: () => context.push('/bai-gui/${up['id']}'),
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
              child: Icon(type.startsWith('document') ? Icons.article_outlined : (type == 'sheet' ? Icons.library_music_outlined : Icons.music_note_rounded), size: 22, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title.isEmpty ? '(Không tên)' : title, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text))),
              if (sub.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.meta)),
            ])),
            Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }

  Widget _commentCard(Map<String, dynamic> c) {
    final obj = c['object'] is Map ? Map<String, dynamic>.from(c['object'] as Map) : null;
    final route = _routeForObject(obj);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: route != null ? () => context.push(route) : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                obj?['title']?.toString() ?? _objectTypeLabel(obj?['__typename']?.toString()),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accentLight)),
              ),
              const SizedBox(height: 4),
              Text(userCommentText(c['content']?.toString()), maxLines: 4, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, color: AppColors.text, height: 1.5))),
              const SizedBox(height: 6),
              Text(timeago(c['created_at']), style: AppText.meta),
            ]),
          ),
        ),
      ),
    );
  }

  static String _capitalize(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t.characters.first.toUpperCase() + t.characters.skip(1).toString();
  }

  Widget _pointRow(Map<String, dynamic> pt) {
    final point = _int(pt['point']);
    final activity = pt['activity'] is Map ? Map<String, dynamic>.from(pt['activity'] as Map) : <String, dynamic>{};
    final target = activity['object'] is Map ? Map<String, dynamic>.from(activity['object'] as Map) : null;
    final route = _routeForObject(target);
    final rawReason = (pt['reason']?.toString().isNotEmpty == true) ? pt['reason'].toString() : (pt['reward_type'] ?? '').toString();
    final reason = _capitalize(rawReason);
    final targetTitle = target?['title']?.toString().trim() ?? '';
    final showTarget = targetTitle.isNotEmpty && !reason.toLowerCase().contains(targetTitle.toLowerCase());
    final good = point >= 0;
    final tone = good ? const Color(0xFF2E9E5B) : const Color(0xFFD64535);
    return InkWell(
      onTap: route != null ? () => context.push(route) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              constraints: const BoxConstraints(minWidth: 52),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tone.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
              child: Text('${point > 0 ? '+' : ''}$point', style: display(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tone))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.35, color: AppColors.text))),
              if (showTarget) ...[
                const SizedBox(height: 2),
                Text(targetTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
              ],
              const SizedBox(height: 2),
              Text(timeago(pt['created_at']), style: AppText.meta),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _previewHeader(IconData icon, String title, VoidCallback? onSeeAll) {
    return SizedBox(
      height: 48,
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text)))),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.only(left: 10, right: 4), foregroundColor: AppColors.accentLight),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Xem tất cả', style: body(TextStyle(fontSize: 14, color: AppColors.accentLight, fontWeight: FontWeight.w700))),
              Icon(Icons.chevron_right, size: 20, color: AppColors.accentLight),
            ]),
          ),
      ]),
    );
  }

  Widget _statTile(String label, int value, VoidCallback onTap) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(formatInt(value), maxLines: 1, style: display(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text))),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1, style: body(TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            ),
          ]),
        ),
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
  // Labels and the controller change once counts arrive.
  @override bool shouldRebuild(covariant _TabBarDelegate old) => old.tabBar != tabBar;
}
