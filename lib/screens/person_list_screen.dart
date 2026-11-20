import 'dart:async';
import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock, Pager, Skeleton, PagedLoader, PagedList, PageResult;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import '../widgets/hover_effects.dart';
import '../widgets/desktop_page.dart';
import 'person_detail_screen.dart' show PersonType;

class PersonListScreen extends StatefulWidget {
  final PersonType type;
  const PersonListScreen({super.key, required this.type});

  @override
  State<PersonListScreen> createState() => _PersonListScreenState();
}

class _PersonListScreenState extends State<PersonListScreen> with PagedLoader {
  static const _perPage = 30;
  final _scrollCtl = ScrollController();
  final _list = PagedList<Map<String, dynamic>>();
  // Name search, sent to the API as `title LIKE %…%` (the collation is
  // accent-insensitive, so "tuan" also finds "Tuấn"). Debounced.
  final _searchCtl = TextEditingController();
  String _search = '';
  Timer? _debounce;
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
    _fetch(1);
  }

  @override
  void didUpdateWidget(PersonListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
      _debounce?.cancel();
      _searchCtl.clear();
      setState(() { _letter = null; _search = ''; _list.reset(); });
      _fetch(1);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<void> _fetch(int page) => loadPage(_list, page, (page, _) async {
        final and = <Map<String, dynamic>>[
          if (_letter != null) {'column': 'title', 'operator': 'LIKE', 'value': '${_letter!}%'},
          if (_search.isNotEmpty) {'column': 'title', 'operator': 'LIKE', 'value': '%${_search.replaceAll('%', '').replaceAll('_', ' ')}%'},
        ];
        final q = '''query(\$page: Int, \$where: WhereConditions) {
          $_queryName(first: $_perPage, page: \$page, where: \$where, orderBy: [{column: "total_listens", order: DESC}]) {
            data { id slug title avatar { url } total_listens }
            paginatorInfo { currentPage lastPage total }
          }
        }''';
        final data = await ApiClient.query(q, {'page': page, 'where': and.isEmpty ? null : {'AND': and}});
        return PageResult.fromPaginator(data[_queryName], page);
      }, scrollToTop: _scrollCtl);

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      final q = v.trim();
      if (!mounted || q == _search) return;
      setState(() => _search = q);
      _fetch(1);
    });
  }

  static String _initial(dynamic title) {
    final t = (title ?? '').toString().trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }

  void _setLetter(String? l) {
    if (_letter == l) return;
    setState(() => _letter = l);
    _fetch(1);
  }

  Widget _buildSearch() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: _searchCtl,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (v) {
          _debounce?.cancel();
          final q = v.trim();
          if (q == _search) return;
          setState(() => _search = q);
          _fetch(1);
        },
        style: body(TextStyle(fontSize: 17, color: AppColors.text)),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          hintText: 'Tìm ${_label.toLowerCase()} theo tên',
          hintStyle: body(TextStyle(fontSize: 17, color: AppColors.textMuted)),
          prefixIcon: Icon(Icons.search, size: 22, color: AppColors.textMuted),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchCtl,
            builder: (_, v, _) => v.text.isEmpty ? const SizedBox.shrink() : IconButton(
              tooltip: 'Xoá',
              iconSize: 22,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(Icons.close, color: AppColors.textMuted),
              onPressed: () {
                _debounce?.cancel();
                _searchCtl.clear();
                if (_search.isEmpty) return;
                setState(() => _search = '');
                _fetch(1);
              },
            ),
          ),
        ),
      ),
    );
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
    final desk = isDesk(context);
    // Grid and pager line up with the desktop page title.
    final side = desk ? deskPad.left : 20.0;
    final count = _list.total > 0 ? '${_formatInt(_list.total)} ${_label.toLowerCase()}' : (!_list.loaded && !_list.failed ? 'Đang tải...' : (_list.failed ? '' : 'Chưa có'));
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          DeskFrame(maxWidth: desk ? 1320 : double.infinity, child: CustomScrollView(
            controller: _scrollCtl,
            slivers: [
              if (!desk)
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.bg,
                title: Text(_label),
                centerTitle: true,
                leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
              ),
              SliverPadding(
                padding: desk ? EdgeInsets.fromLTRB(deskPad.left, deskPad.top, deskPad.right, 24) : const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  if (desk)
                    DeskHead(title: _label, subtitle: count)
                  else ...[
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
                              Text(count, style: body(const TextStyle(fontSize: 15, color: Colors.white70))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ],
                  _buildSearch(),
                  const SizedBox(height: 12),
                  // Filter row: A-Z index. Resets to "all" when tapped twice.
                  _buildFilters(),
                  const SizedBox(height: 12),
                ])),
              ),
              if (_list.loading || (!_list.loaded && !_list.failed))
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, crossAxisSpacing: 14, mainAxisSpacing: 18, mainAxisExtent: tileExtent),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Skeleton(width: 80, height: 80, radius: 40),
                        SizedBox(height: 10),
                        Skeleton(width: 90, height: 14, radius: 6),
                      ]),
                      childCount: 12,
                    ),
                  ),
                )
              else if (_list.failed && _list.items.isEmpty)
                SliverToBoxAdapter(child: OfflineBlock(onRetry: () => _fetch(_list.page)))
              else if (_list.items.isEmpty)
                SliverToBoxAdapter(child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40, horizontal: side),
                  child: Center(child: Text(_search.isNotEmpty ? 'Không tìm thấy "$_search"' : 'Chưa có dữ liệu', textAlign: TextAlign.center, style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)))),
                ))
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: side),
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
                        final p = _list.items[i];
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
                                  gradient: LinearGradient(colors: AppColors.heroGradient),
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
                      childCount: _list.items.length,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Column(children: [
                  if (!_list.loading && _list.items.isNotEmpty && _list.lastPage > 1)
                    Padding(
                      padding: EdgeInsets.fromLTRB(side, 20, side, 0),
                      child: Pager(page: _list.page, lastPage: _list.lastPage, onPage: _fetch),
                    ),
                  SizedBox(height: player.currentSong != null ? 90 : 20),
                ]),
              ),
            ],
          )),
          if (player.currentSong != null)
            const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
        ],
      ),
    );
  }
}
