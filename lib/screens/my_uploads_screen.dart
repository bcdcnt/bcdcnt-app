import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';
import '../widgets/empty_state.dart';

class MyUploadsScreen extends StatefulWidget {
  const MyUploadsScreen({super.key});

  @override
  State<MyUploadsScreen> createState() => _MyUploadsScreenState();
}

class _MyUploadsScreenState extends State<MyUploadsScreen> {
  static const _perPage = 20;
  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch(1));
  }

  @override
  void dispose() {
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _loading || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(_page + 1);
  }

  Future<void> _fetch(int page) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) { setState(() => _loading = false); return; }
    final userId = auth.user?['id']?.toString();
    if (userId == null) { setState(() => _loading = false); return; }
    setState(() { if (page == 1) _loading = true; else _loadingMore = true; });
    try {
      final data = await auth.authedQuery(r'''query($id: ID!, $first: Int!, $page: Int) {
        user(id: $id) {
          uploads(first: $first, page: $page, orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: "approved"}]}) {
            data {
              id
              object {
                __typename id title slug
                ... on Song { views thumbnail { url } play_type file { audio_url video_url duration } artists(first: 3) { data { id title slug avatar { url } } } }
                ... on Folk { views thumbnail { url } play_type file { audio_url video_url duration } artists(first: 3) { data { id title slug avatar { url } } } }
                ... on Instrumental { views thumbnail { url } play_type file { audio_url video_url duration } artists(first: 3) { data { id title slug avatar { url } } } }
                ... on Poem { views thumbnail { url } play_type file { audio_url video_url duration } artists(first: 3) { data { id title slug avatar { url } } } }
                ... on Karaoke { views thumbnail { url } play_type file { audio_url video_url duration } users(first: 3) { data { id username avatar { url } } } }
              }
            }
            paginatorInfo { total currentPage lastPage }
          }
        }
      }''', {'id': userId, 'first': _perPage, 'page': page});
      final raw = data['user']?['uploads'];
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
      if (!mounted) return;
      setState(() {
        if (page == 1) _items = fresh; else _items.addAll(fresh);
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _total = pi['total'] ?? _total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadingMore = false; });
    }
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
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
        body: Center(child: Text('Vui lòng đăng nhập', style: AppText.bodyText)),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(
          controller: _scrollCtl,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.bg.withValues(alpha: 0.88),
              title: Text('BÀI TÔI GỬI', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
              centerTitle: true,
              leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList(delegate: SliverChildListDelegate([
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(colors: [Color(0xFFF57C00), Color(0xFFFFB74D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: const Color(0xFFF57C00).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.upload_outlined, color: Colors.white, size: 28)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Bài tôi gửi', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                      const SizedBox(height: 4),
                      Text(_total > 0 ? '${_formatInt(_total)} bài đã duyệt' : (_loading ? 'Đang tải...' : 'Chưa có'), style: body(const TextStyle(fontSize: 13, color: Colors.white70))),
                    ])),
                  ]),
                ),
                const SizedBox(height: 16),
              ])),
            ),
            if (_loading && _items.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
            else if (_items.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: EmptyState(
                icon: Icons.upload_outlined,
                title: 'Chưa có bài gửi',
                subtitle: 'Bài bạn gửi đóng góp cho thư viện sẽ xuất hiện tại đây.',
              ))
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final song = _items[i];
                    return SongRow(song: song, index: i, showIndex: true, onTap: () => context.push('/song/${song['id']}', extra: song));
                  },
                  childCount: _items.length,
                )),
              ),
            SliverToBoxAdapter(child: Column(children: [
              if (_loadingMore) Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
              SizedBox(height: player.currentSong != null ? 90 : 20),
            ])),
          ],
        ),
        if (player.currentSong != null)
          const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
