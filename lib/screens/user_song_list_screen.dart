import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, PillButton, EmptyBlock, OfflineBlock;
import '../services/friendly_error.dart';
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

class _UserSongListScreenState extends State<UserSongListScreen> {
  static const _perPage = 20;
  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;

  String get _field => widget.kind == UserListKind.favorites ? 'loves' : 'recentListens';
  String get _title => widget.kind == UserListKind.favorites ? 'Yêu thích' : 'Nghe gần đây';
  IconData get _icon => widget.kind == UserListKind.favorites ? Icons.favorite : Icons.access_time;

  AuthProvider? _authRef;
  bool _didInitialFetch = false;
  String? _fetchedFor;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
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
    if (_items.isNotEmpty) setState(() { _items = []; _total = 0; _page = 1; _lastPage = 1; });
    _fetch(1);
  }

  @override
  void dispose() {
    _authRef?.removeListener(_initialFetch);
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _loading) return;
    if (_page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 400) {
      _fetch(_page + 1);
    }
  }

  Future<void> _fetch(int page) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      setState(() => _loading = false);
      return;
    }
    final userId = auth.user?['id']?.toString();
    if (userId == null) { setState(() => _loading = false); return; }

    setState(() {
      _failed = false;
      if (page == 1) { _loading = true; } else { _loadingMore = true; }
    });

    final q = '''query(\$id: ID!, \$first: Int!, \$page: Int) {
      user(id: \$id) {
        $_field(first: \$first, page: \$page, orderBy: [{column: "id", order: DESC}]) {
          data {
            object {
              __typename
              ... on Song { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug avatar { url } } } }
              ... on Folk { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug avatar { url } } } }
              ... on Instrumental { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug avatar { url } } } }
              ... on Poem { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug avatar { url } } } }
              ... on Karaoke { id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration } users(first: 3) { data { id username avatar { url } } } }
            }
          }
          paginatorInfo { total currentPage lastPage }
        }
      }
    }''';

    try {
      final data = await auth.authedQuery(q, {'id': userId, 'first': _perPage, 'page': page});
      final raw = data['user']?[_field];
      final list = ((raw?['data'] ?? []) as List);
      final pi = raw?['paginatorInfo'] ?? {};
      const tnMap = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem', 'Karaoke': 'karaoke'};

      final fresh = <Map<String, dynamic>>[];
      final seen = {if (page > 1) ..._items.map((s) => s['id'].toString())};
      for (final entry in list) {
        final obj = entry['object'];
        if (obj == null) continue;
        final m = Map<String, dynamic>.from(obj as Map);
        final id = m['id'].toString();
        if (seen.contains(id)) continue;
        seen.add(id);
        if (m['users']?['data'] != null && m['artists'] == null) {
          m['artists'] = {'data': ((m['users']['data']) as List).map((u) => {'id': u['id'], 'title': u['username']}).toList()};
        }
        m['file_type'] = tnMap[m['__typename']?.toString()] ?? 'song';
        fresh.add(m);
      }

      if (!mounted || userId != context.read<AuthProvider>().user?['id']?.toString()) return;
      setState(() {
        if (page == 1) _items = fresh; else _items.addAll(fresh);
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _total = pi['total'] ?? _total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _loadingMore = false; _failed = page == 1; });
      if (page > 1) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'Chưa tải thêm được, vui lòng thử lại.'))));
    }
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
                                _total > 0 ? '${_formatInt(_total)} bài' : (_loading ? 'Đang tải...' : 'Chưa có'),
                                style: body(const TextStyle(fontSize: 13, color: Colors.white70)),
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
                    child: SizedBox(width: double.infinity, child: PillButton(onTap: () => saveAllForOffline(context, _items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(), title: _title), icon: Icons.download_for_offline_outlined, label: 'Tải tất cả về máy', primary: false)),
                  ),
                  const SizedBox(height: 8),

                  // List / loader / empty
                  if (_loading && _items.isEmpty)
                    Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
                  else if (_failed && _items.isEmpty)
                    OfflineBlock(onRetry: () => _fetch(1))
                  else if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        children: [
                          Icon(_icon, size: 48, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            widget.kind == UserListKind.favorites ? 'Bạn chưa yêu thích bài nào' : 'Chưa có lịch sử nghe',
                            style: body(TextStyle(fontSize: 15, color: AppColors.textMuted)),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._items.asMap().entries.map((e) {
                      final song = Map<String, dynamic>.from(e.value);
                      return SongRow(
                        song: song,
                        index: e.key,
                        showIndex: widget.kind != UserListKind.history,
                        queue: asSongList(_items),
                      );
                    }),

                  if (_loadingMore) Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),

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
