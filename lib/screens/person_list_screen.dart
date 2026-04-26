import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import 'person_detail_screen.dart' show PersonType;

class PersonListScreen extends StatefulWidget {
  final PersonType type;
  const PersonListScreen({super.key, required this.type});

  @override
  State<PersonListScreen> createState() => _PersonListScreenState();
}

class _PersonListScreenState extends State<PersonListScreen> {
  static const _perPage = 30;
  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;

  String get _queryName {
    switch (widget.type) {
      case PersonType.artist: return 'artists';
      case PersonType.composer: return 'composers';
      case PersonType.poet: return 'poets';
      case PersonType.recomposer: return 'recomposers';
    }
  }

  String get _label {
    switch (widget.type) {
      case PersonType.artist: return 'Nghệ sĩ';
      case PersonType.composer: return 'Nhạc sĩ';
      case PersonType.poet: return 'Nhà thơ';
      case PersonType.recomposer: return 'Soạn giả';
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case PersonType.artist: return Icons.mic;
      case PersonType.composer: return Icons.music_note_outlined;
      case PersonType.poet: return Icons.auto_stories_outlined;
      case PersonType.recomposer: return Icons.edit_outlined;
    }
  }

  String get _routePrefix {
    switch (widget.type) {
      case PersonType.artist: return '/nghe-si/';
      case PersonType.composer: return '/nhac-si/';
      case PersonType.poet: return '/nha-tho/';
      case PersonType.recomposer: return '/soan-gia/';
    }
  }

  Color get _heroColor {
    switch (widget.type) {
      case PersonType.artist: return const Color(0xFF711313);
      case PersonType.composer: return const Color(0xFF8B6914);
      case PersonType.poet: return const Color(0xFF6B5210);
      case PersonType.recomposer: return const Color(0xFF7A3B3A);
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    _fetch(1);
  }

  @override
  void dispose() {
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _loading) return;
    if (_page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) {
      _fetch(_page + 1);
    }
  }

  Future<void> _fetch(int page) async {
    setState(() { if (page == 1) _loading = true; else _loadingMore = true; });
    final q = '''query(\$page: Int) {
      $_queryName(first: $_perPage, page: \$page, orderBy: [{column: "total_listens", order: DESC}]) {
        data { id slug title avatar { url } total_listens }
        paginatorInfo { currentPage lastPage total }
      }
    }''';
    try {
      final data = await ApiClient.query(q, {'page': page});
      final raw = data[_queryName];
      final list = ((raw?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final pi = raw?['paginatorInfo'] ?? {};
      if (!mounted) return;
      setState(() {
        if (page == 1) _items = list; else _items.addAll(list);
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
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollCtl,
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.bg.withValues(alpha: 0.88),
                title: Text(_label.toUpperCase(), style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
                centerTitle: true,
                leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(colors: [_heroColor, Color.lerp(_heroColor, Colors.black, 0.35)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: _heroColor.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
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
                              Text(_label, style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                              const SizedBox(height: 4),
                              Text(_total > 0 ? '${_formatInt(_total)} người' : (_loading ? 'Đang tải...' : 'Chưa có'), style: body(const TextStyle(fontSize: 13, color: Colors.white70))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ])),
              ),
              if (_loading && _items.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
              else if (_items.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Chưa có dữ liệu', style: body(const TextStyle(color: AppColors.textMuted)))))
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 14, mainAxisSpacing: 18, childAspectRatio: 0.72,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final p = _items[i];
                        final avatar = p['avatar']?['url'];
                        return InkWell(
                          onTap: () => context.push('$_routePrefix${p['slug']}'),
                          child: Column(
                            children: [
                              Container(
                                width: 80, height: 80,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                                ),
                                child: ClipOval(
                                  child: avatar != null
                                      ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.person, color: Colors.white70))
                                      : Center(child: Text((p['title'] ?? '?').toString().substring(0, 1).toUpperCase(), style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white70)))),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(p['title'] ?? '', maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text))),
                              if ((p['total_listens'] ?? 0) > 0) Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text('${_formatInt(p['total_listens'])} nghe', style: body(const TextStyle(fontSize: 10, color: AppColors.textMuted))),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: _items.length,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Column(children: [
                  if (_loadingMore) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
                  SizedBox(height: player.currentSong != null ? 90 : 20),
                ]),
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
