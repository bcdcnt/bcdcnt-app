import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, PillButton, EmptyBlock, PagedLoader, PagedList, PageResult, pagedListBody;
import '../widgets/shimmer.dart' show SongListSkeleton;
import '../services/friendly_error.dart' show askLogin;
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';

/// Shared list screen for user-scoped song lists: Favorites (loves) and
/// Listen History (recentListens). Same shape: paginated [{ object: Song|… }].
enum UserListKind { favorites, history }

class UserSongListScreen extends StatefulWidget {
  final UserListKind kind;
  const UserSongListScreen({super.key, required this.kind});

  @override
  State<UserSongListScreen> createState() => _UserSongListScreenState();
}

// No sort tabs here: loves / recentListens rows only carry their own id
// and time (the song is a polymorphic `object`), so the API can't order
// them by listens, likes or downloads. Newest first, page by page.
class _UserSongListScreenState extends State<UserSongListScreen> with PagedLoader {
  static const _perPage = 20;
  final _scrollCtl = ScrollController();
  final _list = PagedList<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _items => _list.items;

  String get _field => widget.kind == UserListKind.favorites ? 'loves' : 'recentListens';
  String get _title => widget.kind == UserListKind.favorites ? 'Yêu thích' : 'Nghe gần đây';
  IconData get _icon => widget.kind == UserListKind.favorites ? Icons.favorite : Icons.access_time;

  AuthProvider? _authRef;
  bool _didInitialFetch = false;
  String? _fetchedFor;

  @override
  void initState() {
    super.initState();
    // Auth restores its token asynchronously from storage. If we fetched
    // once in initState we'd race it (token not ready → empty list, no
    // retry) — visible when deep-linking straight onto this screen. So we
    // wait until auth is no longer `loading` (re-triggered by its notify).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authRef = context.read<AuthProvider>();
      _authRef!.addListener(_initialFetch);
      _initialFetch();
    });
  }

  void _initialFetch() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.loading) return;            // still restoring — wait for next notify
    final uid = auth.user?['id']?.toString();
    // Re-fetch after logging in from the guest prompt (or switching account).
    if (_didInitialFetch && uid == _fetchedFor) return;
    _didInitialFetch = true;
    _fetchedFor = uid;
    setState(() => _list.reset());
    _fetch(1);
  }

  @override
  void dispose() {
    _authRef?.removeListener(_initialFetch);
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<void> _fetch(int page) async {
    final auth = context.read<AuthProvider>();
    final userId = auth.user?['id']?.toString();
    if (!auth.isAuthenticated || userId == null) {
      setState(() => _list.reset());
      return;
    }

    final q = '''query(\$id: ID!, \$first: Int!, \$page: Int) {
      user(id: \$id) {
        $_field(first: \$first, page: \$page, orderBy: [{column: "id", order: DESC}]) {
          data {
            object {
              __typename
              ... on Song { id title subtitle slug views created_at play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug avatar { url } } } }
              ... on Folk { id title subtitle slug views created_at play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug avatar { url } } } }
              ... on Instrumental { id title subtitle slug views created_at play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug avatar { url } } } }
              ... on Poem { id title subtitle slug views created_at play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug avatar { url } } } }
              ... on Karaoke { id title subtitle slug views created_at play_type thumbnail { url } file { audio_url video_url duration } users(first: 3) { data { id username avatar { url } } } }
            }
          }
          paginatorInfo { total currentPage lastPage }
        }
      }
    }''';

    await loadPage(_list, page, (page, _) async {
      final data = await auth.authedQuery(q, {'id': userId, 'first': _perPage, 'page': page});
      // Signed out / switched account while this was loading: drop it.
      if (!mounted || userId != context.read<AuthProvider>().user?['id']?.toString()) {
        throw StateError('account changed');
      }
      final raw = data['user']?[_field];
      final pi = raw?['paginatorInfo'] ?? {};
      const tnMap = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem', 'Karaoke': 'karaoke'};
      final fresh = <Map<String, dynamic>>[];
      // id + kind: tân nhạc 12 and dân ca 12 are different songs.
      final seen = <String>{};
      for (final entry in ((raw?['data'] ?? []) as List)) {
        final obj = entry is Map ? entry['object'] : null;
        if (obj == null) continue;
        final m = Map<String, dynamic>.from(obj as Map);
        m['file_type'] = tnMap[m['__typename']?.toString()] ?? 'song';
        if (!seen.add('${m['file_type']}:${m['id']}')) continue;
        if (m['users']?['data'] != null && m['artists'] == null) {
          m['artists'] = {'data': ((m['users']['data']) as List).map((u) => {'id': u['id'], 'title': u['username']}).toList()};
        }
        fresh.add(m);
      }
      return PageResult(
        items: fresh,
        page: (pi['currentPage'] as num?)?.toInt() ?? page,
        lastPage: (pi['lastPage'] as num?)?.toInt() ?? 1,
        total: (pi['total'] as num?)?.toInt() ?? fresh.length,
      );
    }, scrollToTop: _scrollCtl);
  }

  void _playAll({bool shuffle = false}) {
    if (_items.isEmpty) return;
    final queue = <Map<String, dynamic>>[];
    for (final s in _items) {
      final m = Map<String, dynamic>.from(s);
      m['audioUrl'] = m['file']?['audio_url'];
      if (m['audioUrl'] != null) queue.add(m);
    }
    if (queue.isEmpty) return;
    if (shuffle) queue.shuffle();
    final player = context.read<PlayerProvider>();
    player.playSong(queue.first, queue);
    player.setFetchMore(null);
    if (shuffle && !player.shuffle) player.toggleShuffle();
  }

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return n < 0 ? '-$buf' : buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final player = context.watch<PlayerProvider>();
    if (!auth.isAuthenticated) {
      return _scaffoldGuest();
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollCtl,
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.bg,
                title: Text(_title),
                centerTitle: true,
                leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  // Hero stats
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                          child: Icon(_icon, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_title, style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                              const SizedBox(height: 4),
                              Text(
                                _list.total > 0 ? '${_formatInt(_list.total)} bài' : (!_list.loaded && !_list.failed ? 'Đang tải...' : (_list.failed ? '' : 'Chưa có')),
                                style: body(const TextStyle(fontSize: 15, color: Colors.white70)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Action buttons
                  if (_items.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: PillButton(onTap: () => _playAll(), icon: Icons.play_arrow, label: 'Phát tất cả', primary: true),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PillButton(onTap: () => _playAll(shuffle: true), icon: Icons.shuffle, label: 'Ngẫu nhiên', primary: false),
                        ),
                      ],
                    ),
                  if (_items.isNotEmpty)
                    Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SizedBox(width: double.infinity, child: PillButton(onTap: () => saveAllForOffline(context, _items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(), title: _title), icon: Icons.download_for_offline_outlined, label: _list.lastPage > 1 ? 'Tải về máy cả trang này' : 'Tải tất cả về máy', primary: false)),
                  ),
                  const SizedBox(height: 8),

                  // List / loader / empty, then the pager
                  ...pagedListBody<Map<String, dynamic>>(
                    _list,
                    perPage: _perPage,
                    onRetry: () => _fetch(_list.page),
                    onPage: (p) => _fetch(p),
                    skeleton: SongListSkeleton(rows: 8, showIndex: widget.kind != UserListKind.history),
                    empty: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        children: [
                          Icon(_icon, size: 48, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            widget.kind == UserListKind.favorites ? 'Bạn chưa yêu thích bài nào' : 'Chưa có lịch sử nghe',
                            style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)),
                          ),
                        ],
                      ),
                    ),
                    itemBuilder: (song, i) => SongRow(
                      song: song,
                      index: i,
                      showIndex: widget.kind != UserListKind.history,
                      metricKey: widget.kind == UserListKind.history ? 'none' : 'views',
                      queue: asSongList(_items),
                    ),
                  ),

                  SizedBox(height: player.currentSong != null ? 90 : 20),
                ])),
              ),
            ],
          ),
          if (player.currentSong != null)
            const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
        ],
      ),
    );
  }

  Widget _scaffoldGuest() => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: Text(_title), centerTitle: true, leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context))),
    body: Center(child: SingleChildScrollView(child: EmptyBlock(
      icon: _icon,
      title: 'Đăng nhập để xem $_title',
      message: widget.kind == UserListKind.favorites
          ? 'Bài bạn yêu thích được lưu theo tài khoản, mở trên máy nào cũng thấy.'
          : 'Những bài bạn đã nghe được lưu theo tài khoản.',
      action: 'Đăng nhập',
      onAction: () => askLogin(context),
    ))),
  );
}
