import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock, PillButton;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import '../widgets/hover_effects.dart';
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
  bool _failed = false;
  bool _moreFailed = false;
  int _reqId = 0;
  // Filter: starting letter (uppercase Vietnamese). Null means "all".
  // Selecting it resets pagination.
  String? _letter;
  // Base Vietnamese alphabet only — the backend uses MySQL LIKE with a
  // utf8_general_ci collation, so 'O%' already matches Ô/Ơ etc. Showing the
  // diacritic vowels gave duplicate results with the base letter (E vs Ê,
  // O vs Ô/Ơ, U vs Ư, A vs Ă/Â). Đ stays — distinct phoneme + sort key.
  static const _alphabet = [
    'A','B','C','D','Đ','E','G','H','I','K','L','M','N',
    'O','P','Q','R','S','T','U','V','X','Y',
  ];

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
    if (_loadingMore || _loading || _moreFailed) return;
    if (_page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) {
      _fetch(_page + 1);
    }
  }

  Future<void> _fetch(int page) async {
    final req = ++_reqId;
    setState(() {
      if (page == 1) { _loading = true; _failed = false; } else { _loadingMore = true; }
      _moreFailed = false;
    });
    // Build a where clause with an optional letter (title LIKE 'X%').
    final wheres = <String>[];
    if (_letter != null) {
      wheres.add('{column: "title", operator: LIKE, value: "${_letter!}%"}');
    }
    final whereStr = wheres.isEmpty ? '' : ', where: {AND: [${wheres.join(',')}]}';
    final q = '''query(\$page: Int) {
      $_queryName(first: $_perPage, page: \$page$whereStr, orderBy: [{column: "total_listens", order: DESC}]) {
        data { id slug title avatar { url } total_listens }
        paginatorInfo { currentPage lastPage total }
      }
    }''';
    try {
      final data = await ApiClient.query(q, {'page': page});
      final raw = data[_queryName];
      final list = ((raw?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final pi = raw?['paginatorInfo'] ?? {};
      if (req != _reqId || !mounted) return;
      setState(() {
        if (page == 1) {
          _items = list;
        } else {
          final seen = _items.map((e) => e['id']?.toString()).toSet();
          _items.addAll(list.where((e) => !seen.contains(e['id']?.toString())));
        }
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _total = pi['total'] ?? _total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (req != _reqId || !mounted) return;
      setState(() {
        if (page == 1) { _failed = true; } else { _moreFailed = true; }
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  static String _initial(dynamic title) {
    final t = (title ?? '').toString().trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }

  void _setLetter(String? l) {
    if (_letter == l) return;
    setState(() {
      _letter = l;
      _items = []; _page = 1; _lastPage = 1; _total = 0; _loadingMore = false;
    });
    _fetch(1);
  }

  Widget _buildFilters() {
    // A-Z index — underline tab style (matches search/category/BXH/tag
    // sort tabs across the app for visual consistency).
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _letterBtn(label: 'Tất cả', active: _letter == null, onTap: () => _setLetter(null)),
            for (final c in _alphabet)
              _letterBtn(label: c, active: _letter == c, onTap: () => _setLetter(c)),
          ],
        ),
      ),
    );
  }

  Widget _letterBtn({required String label, required bool active, required VoidCallback onTap}) {
    return Semantics(
      button: true,
      selected: active,
      label: label == 'Tất cả' ? 'Tất cả' : 'Chữ $label',
      excludeSemantics: true,
      child: InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active ? AppColors.accentLight : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          style: body(TextStyle(
            fontSize: 16,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppColors.accentLight : AppColors.textSecondary,
            letterSpacing: 0.3,
          )),
        ),
      ),
      ),
    );
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
    // Tile height grows with the user's text size so names never overflow:
    // avatar 80 + gaps + 2-line name (14pt) + listen count (13pt) + slack.
    final ts = MediaQuery.textScalerOf(context);
    final tileExtent = 80 + 8 + 2 + ts.scale(14) * 1.35 * 2 + ts.scale(13) * 1.4 + 16;
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
                title: Text(_label),
                centerTitle: true,
                leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(colors: [_heroColor, Color.lerp(_heroColor, Colors.black, 0.35)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: _heroColor.withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))],
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
                              Text(_total > 0 ? '${_formatInt(_total)} ${_label.toLowerCase()}' : (_loading ? 'Đang tải...' : (_failed ? '' : 'Chưa có')), style: body(const TextStyle(fontSize: 15, color: Colors.white70))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Filter row: A-Z index. Resets to "all" when tapped twice.
                  _buildFilters(),
                  const SizedBox(height: 12),
                ])),
              ),
              if (_loading && _items.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
              else if (_failed && _items.isEmpty)
                SliverToBoxAdapter(child: OfflineBlock(onRetry: () => _fetch(1)))
              else if (_items.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Chưa có dữ liệu', style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)))))
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    // Responsive cols: more on desktop so each tile doesn't
                    // stretch with huge horizontal gaps between rows.
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 18,
                      // mainAxisExtent (not childAspectRatio, which caused
                      // 1-2px overflow) computed from the text scale above.
                      mainAxisExtent: tileExtent,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final p = _items[i];
                        final avatar = p['avatar']?['url'];
                        // Circle avatars for everyone — composer/poet/recomposer
                        // square treatment was reverted per user feedback. Section
                        // header icon already differentiates the lists; making
                        // avatar shapes vary just looked inconsistent.
                        // Hover bg fills the (near-square) cell with a gentle
                        // 16px radius. Earlier the InkWell used radius 40 on a
                        // 166×152 cell, which warped into a lopsided pill
                        // ("méo"); a moderate radius reads as a clean tile card.
                        final radius = BorderRadius.circular(16);
                        return HoverHighlight(
                          borderRadius: radius,
                          child: InkWell(
                          onTap: () => context.push('$_routePrefix${p['slug']}'),
                          borderRadius: radius,
                          hoverColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 80, height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)]),
                                ),
                                child: ClipOval(
                                  child: avatar != null
                                      ? CachedNetworkImage(imageUrl: cdnImg((avatar).toString(), 160), fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.person, color: Colors.white70))
                                      : Center(child: Text(_initial(p['title']), style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white70)))),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(p['title'] ?? '', maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w600, color: AppColors.text))),
                              if ((p['total_listens'] ?? 0) > 0) Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text('${_formatInt(p['total_listens'])} nghe', maxLines: 1, style: body(TextStyle(fontSize: 13, height: 1.3, color: AppColors.textSecondary))),
                              ),
                            ],
                          ),
                        ),
                        );
                      },
                      childCount: _items.length,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Column(children: [
                  if (_loadingMore) Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
                  if (_moreFailed) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Center(child: PillButton(label: 'Thử lại', icon: Icons.refresh, primary: false, onTap: () => _fetch(_page + 1)))),
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
