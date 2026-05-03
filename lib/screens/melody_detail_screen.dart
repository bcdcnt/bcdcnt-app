import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';

class MelodyDetailScreen extends StatefulWidget {
  final String slug;
  const MelodyDetailScreen({super.key, required this.slug});

  @override
  State<MelodyDetailScreen> createState() => _MelodyDetailScreenState();
}

class _MelodyDetailScreenState extends State<MelodyDetailScreen> {
  final _scrollCtl = ScrollController();
  Map<String, dynamic>? _melody;
  List<Map<String, dynamic>> _songs = [];
  int _page = 1, _lastPage = 1, _total = 0;
  bool _loading = true, _loadingMore = false;
  String _sort = 'views';

  @override
  void initState() { super.initState(); _scrollCtl.addListener(_onScroll); _fetch(1); }
  @override
  void dispose() { _scrollCtl.removeListener(_onScroll); _scrollCtl.dispose(); super.dispose(); }
  void _onScroll() {
    if (_loadingMore || _loading || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(_page + 1);
  }

  Future<void> _fetch(int page) async {
    setState(() { if (page == 1) _loading = true; else _loadingMore = true; });
    try {
      final q = '''query(\$slug: Mixed, \$page: Int) {
        melodies(first: 1, where: { column: "slug", value: \$slug }) {
          data {
            id title slug
            folks(first: 20, page: \$page, orderBy: [{column: "$_sort", order: DESC}]) {
              data {
                id title subtitle slug views play_type thumbnail { url } file { audio_url video_url duration }
                artists(first: 5) { data { id title slug } }
                recomposers(first: 5) { data { id slug title } }
              }
              paginatorInfo { currentPage lastPage total }
            }
          }
        }
      }''';
      final data = await ApiClient.query(q, {'slug': widget.slug, 'page': page});
      final melody = ((data['melodies']?['data'] ?? []) as List).isNotEmpty
          ? Map<String, dynamic>.from(data['melodies']['data'][0] as Map) : null;
      if (!mounted) return;
      if (melody == null) { setState(() => _loading = false); return; }
      final folks = ((melody['folks']?['data'] ?? []) as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['file_type'] = 'folk';
        return m;
      }).toList();
      final pi = melody['folks']?['paginatorInfo'] ?? {};
      setState(() {
        _melody = melody;
        if (page == 1) _songs = folks; else _songs.addAll(folks);
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _total = pi['total'] ?? 0;
        _loading = false; _loadingMore = false;
      });
    } catch (_) { if (mounted) setState(() { _loading = false; _loadingMore = false; }); }
  }

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 == 0) buf.write('.'); buf.write(s[i]); }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(controller: _scrollCtl, slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text('LÀN ĐIỆU', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          if (_loading && _songs.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else if (_melody == null)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Không tìm thấy làn điệu', style: AppText.bodyText)))
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              sliver: SliverList(delegate: SliverChildListDelegate([
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(colors: [Color(0xFF8B6914), Color(0xFFC9A96E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: const Color(0xFF8B6914).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.music_note_outlined, color: Colors.white, size: 28)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_melody!['title'] ?? '', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                      const SizedBox(height: 4),
                      Text(_total > 0 ? '${_formatInt(_total)} bài' : 'Đang tải...', style: body(const TextStyle(fontSize: 13, color: Colors.white70))),
                    ])),
                  ]),
                ),
                const SizedBox(height: 14),
                // Sort tabs
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 2,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (ctx, i) {
                      final s = i == 0 ? ('views', 'Nghe nhiều') : ('id', 'Mới cập nhật');
                      final active = _sort == s.$1;
                      return InkWell(
                        onTap: active ? null : () { setState(() => _sort = s.$1); _fetch(1); },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: active ? AppColors.accent : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: active ? AppColors.accent : AppColors.border),
                          ),
                          child: Text(s.$2, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : AppColors.textSecondary))),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ])),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final s = _songs[i];
                  return SongRow(song: s, index: i, showIndex: true, onTap: () => context.push('/song/${s['id']}', extra: s));
                },
                childCount: _songs.length,
              )),
            ),
          ],
          SliverToBoxAdapter(child: Column(children: [
            if (_loadingMore) Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
            SizedBox(height: player.currentSong != null ? 90 : 20),
          ])),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
