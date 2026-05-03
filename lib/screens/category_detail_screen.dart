import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';

class _CatCfg {
  final String name, slug, query, artistField, composerField, fileType;
  final Color bg;
  final IconData icon;
  const _CatCfg({
    required this.name, required this.slug, required this.query,
    required this.artistField, required this.composerField,
    required this.fileType, required this.bg, required this.icon,
  });
}

const _cats = <String, _CatCfg>{
  'tan-nhac': _CatCfg(name: 'Tân nhạc', slug: 'tan-nhac', query: 'songs', artistField: 'artists', composerField: 'composers', fileType: 'song', bg: Color(0xFF711313), icon: Icons.music_note),
  'dan-ca': _CatCfg(name: 'Dân ca', slug: 'dan-ca', query: 'folks', artistField: 'artists', composerField: 'recomposers', fileType: 'folk', bg: Color(0xFF8B6914), icon: Icons.music_note),
  'khi-nhac': _CatCfg(name: 'Khí nhạc', slug: 'khi-nhac', query: 'instrumentals', artistField: 'artists', composerField: 'composers', fileType: 'instrumental', bg: Color(0xFF7A3B3A), icon: Icons.piano),
  'tieng-tho': _CatCfg(name: 'Tiếng thơ', slug: 'tieng-tho', query: 'poems', artistField: 'artists', composerField: 'poets', fileType: 'poem', bg: Color(0xFF6B5210), icon: Icons.auto_stories_outlined),
  'thanh-vien-hat': _CatCfg(name: 'Thành viên hát', slug: 'thanh-vien-hat', query: 'karaokes', artistField: 'users', composerField: 'composers', fileType: 'karaoke', bg: Color(0xFF2D5E3A), icon: Icons.mic),
};

const _sortOptions = [
  ('views', 'Nghe nhiều', 'views'),
  ('newest', 'Mới nhất', 'id'),
  ('likes', 'Yêu thích', 'likes'),
  ('downloads', 'Tải nhiều', 'downloads'),
];

class CategoryDetailScreen extends StatefulWidget {
  final String slug;
  const CategoryDetailScreen({super.key, required this.slug});

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  _CatCfg? get _cfg => _cats[widget.slug];
  List<dynamic> _items = [];
  int _total = 0;
  int _page = 1;
  int _lastPage = 1;
  String _sort = 'views';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch(1);
  }

  @override
  void didUpdateWidget(CategoryDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      setState(() { _items = []; _total = 0; _page = 1; _lastPage = 1; _sort = 'views'; _loading = true; });
      _fetch(1);
    }
  }

  Future<void> _fetch(int page, {String? sort}) async {
    final cfg = _cfg;
    if (cfg == null) { setState(() => _loading = false); return; }
    final useSort = sort ?? _sort;
    final sortCol = _sortOptions.firstWhere((o) => o.$1 == useSort, orElse: () => _sortOptions.first).$3;
    setState(() { _sort = useSort; _loading = true; });

    final artistNested = cfg.artistField == 'users'
        ? 'users(first: 5) { data { id username } }'
        : 'artists(first: 5) { data { id title slug avatar { url } } }';
    final composerNested = '${cfg.composerField}(first: 20) { data { id slug title } }';
    final q = 'query(\$page: Int) { ${cfg.query}(first: 10, page: \$page, orderBy: [{column: "$sortCol", order: DESC}]) { data { id title subtitle slug views downloads likes created_at play_type thumbnail { url } file { audio_url video_url duration } sheet { year } $artistNested $composerNested } paginatorInfo { total currentPage lastPage } } }';

    try {
      final data = await ApiClient.query(q, {'page': page});
      final raw = data[cfg.query];
      final items = ((raw?['data'] ?? []) as List).map((s) {
        final m = Map<String, dynamic>.from(s as Map);
        m['file_type'] = cfg.fileType;
        // Normalize karaoke users -> artists shape
        if (cfg.artistField == 'users' && m['users']?['data'] != null) {
          m['artists'] = {'data': ((m['users']['data']) as List).map((u) => {'id': u['id'], 'title': u['username']}).toList()};
        }
        return m;
      }).toList();
      final pi = raw?['paginatorInfo'] ?? {};
      if (!mounted) return;
      setState(() {
        _items = items;
        _total = pi['total'] ?? 0;
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return n < 0 ? '-${buf.toString()}' : buf.toString();
  }

  void _playAll() {
    if (_items.isEmpty) return;
    final player = context.read<PlayerProvider>();
    final queue = <Map<String, dynamic>>[];
    for (final s in _items) {
      final m = Map<String, dynamic>.from(s as Map);
      m['audioUrl'] = m['file']?['audio_url'];
      if (m['audioUrl'] != null) queue.add(m);
    }
    if (queue.isEmpty) return;
    player.playSong(queue.first, queue);
    player.setFetchMore(null);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    if (cfg == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
        body: Center(child: Text('Không tìm thấy thể loại', style: AppText.bodyText)),
      );
    }
    final player = context.watch<PlayerProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.bg.withValues(alpha: 0.88),
                title: Text('THỂ LOẠI', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
                centerTitle: true,
                leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Hero banner
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(colors: [cfg.bg, cfg.bg.withValues(alpha: 0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        boxShadow: [BoxShadow(color: cfg.bg.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                            child: Icon(cfg.icon, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cfg.name, style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                                const SizedBox(height: 4),
                                Text(
                                  _total > 0 ? '${_formatInt(_total)} bài' : 'Đang tải...',
                                  style: body(const TextStyle(fontSize: 13, color: Colors.white70)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Play all
                    if (_items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _playAll,
                              icon: const Icon(Icons.play_arrow, size: 20),
                              label: const Text('Phát tất cả'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Sort tabs — underline style for app-wide consistency
                    // (matches search filter, BXH period tabs, in-page
                    // section tabs).
                    Container(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                      child: SizedBox(
                        height: 38,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _sortOptions.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 16),
                          itemBuilder: (ctx, i) {
                            final opt = _sortOptions[i];
                            final active = _sort == opt.$1;
                            return InkWell(
                              onTap: active ? null : () => _fetch(1, sort: opt.$1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: active ? AppColors.accentLight : Colors.transparent, width: 2)),
                                ),
                                child: Text(opt.$2, style: body(TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? AppColors.accentLight : AppColors.textSecondary))),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // List / loader
                    if (_loading && _items.isEmpty)
                      Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
                    else if (_items.isEmpty)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('Chưa có bài', style: body(TextStyle(color: AppColors.textMuted)))))
                    else
                      ..._items.asMap().entries.map((e) {
                        final song = Map<String, dynamic>.from(e.value as Map);
                        song['file_type'] = cfg.fileType;
                        return SongRow(
                          song: song,
                          index: (_page - 1) * 10 + e.key,
                          showIndex: true,
                          metricKey: _sort == 'newest' ? 'time' : _sort,
                          onTap: () => context.push('/song/${song['id']}', extra: song),
                        );
                      }),

                    if (_lastPage > 1) Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _Pager(
                        currentPage: _page,
                        lastPage: _lastPage,
                        loading: _loading,
                        onGoto: (p) => _fetch(p),
                      ),
                    ),

                    SizedBox(height: player.currentSong != null ? 90 : 20),
                  ]),
                ),
              ),
            ],
          ),
          if (player.currentSong != null)
            const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
        ],
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  final int currentPage;
  final int lastPage;
  final bool loading;
  final void Function(int) onGoto;
  const _Pager({required this.currentPage, required this.lastPage, required this.loading, required this.onGoto});

  @override
  Widget build(BuildContext context) {
    final pages = <int>{1, lastPage};
    for (int i = -1; i <= 1; i++) {
      final p = currentPage + i;
      if (p >= 1 && p <= lastPage) pages.add(p);
    }
    final ordered = pages.toList()..sort();
    final children = <Widget>[
      _PageBtn(icon: Icons.chevron_left, enabled: currentPage > 1 && !loading, onTap: () => onGoto(currentPage - 1)),
    ];
    int prev = 0;
    for (final p in ordered) {
      if (prev != 0 && p - prev > 1) {
        children.add(Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: AppColors.textMuted))));
      }
      children.add(_PageBtn(label: '$p', enabled: p != currentPage && !loading, active: p == currentPage, onTap: () => onGoto(p)));
      prev = p;
    }
    children.add(_PageBtn(icon: Icons.chevron_right, enabled: currentPage < lastPage && !loading, onTap: () => onGoto(currentPage + 1)));
    return Center(child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: children));
  }
}

class _PageBtn extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool enabled;
  final bool active;
  final VoidCallback onTap;
  const _PageBtn({this.label, this.icon, this.enabled = true, this.active = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.accent : AppColors.surfaceLight;
    final fg = active ? Colors.white : (enabled ? AppColors.text : AppColors.textMuted);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? AppColors.accent : AppColors.border),
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, size: 16, color: fg)
                : Text(label!, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg))),
          ),
        ),
      ),
    );
  }
}
