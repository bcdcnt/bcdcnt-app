import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import '../widgets/gallery_lightbox.dart';
import '../widgets/video_poster.dart';

enum ArchiveType { image, audio, video, news }

class _Cfg {
  final String label;
  final String docType;
  final IconData icon;
  final Color tint;
  const _Cfg({required this.label, required this.docType, required this.icon, required this.tint});
}

const _cfg = <ArchiveType, _Cfg>{
  ArchiveType.image: _Cfg(label: 'Thư viện ảnh', docType: 'image', icon: Icons.image_outlined, tint: Color(0xFF7986CB)),
  ArchiveType.audio: _Cfg(label: 'Tư liệu âm thanh', docType: 'audio', icon: Icons.audiotrack, tint: Color(0xFF81C784)),
  ArchiveType.video: _Cfg(label: 'Tư liệu video', docType: 'video', icon: Icons.video_library_outlined, tint: Color(0xFFE57373)),
  ArchiveType.news: _Cfg(label: 'Tư liệu bài viết', docType: 'news', icon: Icons.article_outlined, tint: Color(0xFFFFB74D)),
};

const _slugMap = <String, ArchiveType>{
  'hinh-anh': ArchiveType.image,
  'am-thanh': ArchiveType.audio,
  'video': ArchiveType.video,
  'bai-viet': ArchiveType.news,
};

ArchiveType? archiveTypeFromSlug(String slug) => _slugMap[slug];

class DocumentArchiveScreen extends StatefulWidget {
  final ArchiveType type;
  const DocumentArchiveScreen({super.key, required this.type});

  @override
  State<DocumentArchiveScreen> createState() => _DocumentArchiveScreenState();
}

class _DocumentArchiveScreenState extends State<DocumentArchiveScreen> {
  static const _perPage = 24;
  final _scrollCtl = ScrollController();
  List<dynamic> _items = [];
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;

  _Cfg get _cf => _cfg[widget.type]!;

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

    String fields;
    switch (widget.type) {
      case ArchiveType.image:
        fields = 'id slug title views downloads thumbnail { url } uploader { id username } comments(first: 0) { paginatorInfo { total } }';
        break;
      case ArchiveType.audio:
        fields = 'id slug title views downloads file { audio_url } uploader { id username } comments(first: 0) { paginatorInfo { total } }';
        break;
      case ArchiveType.video:
        fields = 'id slug title views downloads thumbnail { url } file { video_url } uploader { id username } comments(first: 0) { paginatorInfo { total } }';
        break;
      case ArchiveType.news:
        fields = 'id slug title thumbnail { url } content created_at uploader { id username }';
        break;
    }
    final q = '''query(\$page: Int, \$where: WhereConditions) {
      documents(first: $_perPage, page: \$page, orderBy: [{column: "id", order: DESC}], where: \$where) {
        data { $fields }
        paginatorInfo { total currentPage lastPage }
      }
    }''';
    try {
      final data = await ApiClient.query(q, {'page': page, 'where': {'AND': [{'column': 'type', 'value': _cf.docType}]}});
      final raw = data['documents'];
      final list = (raw?['data'] ?? []) as List;
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

  String _fmt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return n < 0 ? '-$buf' : buf.toString();
  }

  String _plainExcerpt(String? html, {int maxLen = 120}) {
    if (html == null || html.isEmpty) return '';
    final s = html.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length <= maxLen ? s : '${s.substring(0, maxLen)}…';
  }

  Future<List<dynamic>> _loadMoreForLightbox() async {
    if (_page >= _lastPage) return [];
    await _fetch(_page + 1);
    // Return only the freshly added tail
    final start = ((_page - 1) * _perPage).clamp(0, _items.length);
    return _items.sublist(start);
  }

  void _openLightbox(int index) {
    Widget? lb;
    switch (widget.type) {
      case ArchiveType.image:
        lb = ImageLightbox(docs: _items, initialIndex: index, onLoadMore: _loadMoreForLightbox);
        break;
      case ArchiveType.audio:
        lb = AudioLightbox(docs: _items, initialIndex: index, onLoadMore: _loadMoreForLightbox);
        break;
      case ArchiveType.video:
        lb = VideoLightbox(docs: _items, initialIndex: index, onLoadMore: _loadMoreForLightbox);
        break;
      case ArchiveType.news:
        final d = _items[index];
        context.push('/tu-lieu/chi-tiet/${d['id']}');
        return;
    }
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => lb!));
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
                title: Text('TƯ LIỆU', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
                centerTitle: true,
                leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  // Hero
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(colors: [_cf.tint, Color.lerp(_cf.tint, Colors.black, 0.35)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: _cf.tint.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                          child: Icon(_cf.icon, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_cf.label, style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                              const SizedBox(height: 4),
                              Text(
                                _total > 0 ? '${_fmt(_total)} mục' : (_loading ? 'Đang tải...' : 'Chưa có'),
                                style: body(const TextStyle(fontSize: 13, color: Colors.white70)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_loading && _items.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
                  else if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        children: [
                          Icon(_cf.icon, size: 48, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          Text('Chưa có tư liệu nào', style: body(const TextStyle(color: AppColors.textMuted))),
                        ],
                      ),
                    )
                  else
                    _content(),

                  if (_loadingMore) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),

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

  Widget _content() {
    switch (widget.type) {
      case ArchiveType.image: return _imageGrid();
      case ArchiveType.audio: return _audioList();
      case ArchiveType.video: return _videoGrid();
      case ArchiveType.news: return _articleList();
    }
  }

  Widget _imageGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      // Responsive: more columns on wider windows so each tile shrinks
      // instead of leaving wide gaps between rows.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220, crossAxisSpacing: 6, mainAxisSpacing: 6,
      ),
      itemBuilder: (ctx, i) {
        final d = _items[i];
        final thumb = d['thumbnail']?['url'];
        return InkWell(
          onTap: () => _openLightbox(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: thumb != null
                ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppColors.surfaceLight))
                : Container(color: AppColors.surfaceLight, child: const Icon(Icons.image, color: AppColors.textMuted)),
          ),
        );
      },
    );
  }

  Widget _audioList() {
    return Column(
      children: _items.asMap().entries.map((e) {
        final i = e.key; final d = e.value;
        return InkWell(
          onTap: () => _openLightbox(i),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text))),
                      if (d['uploader']?['username'] != null) Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(d['uploader']['username'], style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.graphic_eq, size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _videoGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      // Responsive: video tiles around 280px wide max so we get 2 cols on
      // mobile but 4-5 cols on a desktop window without huge whitespace.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320, crossAxisSpacing: 10, mainAxisSpacing: 14, childAspectRatio: 1.05,
      ),
      itemBuilder: (ctx, i) {
        final d = _items[i];
        final thumb = d['thumbnail']?['url'];
        final videoUrl = d['file']?['video_url'];
        return InkWell(
          onTap: () => _openLightbox(i),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: thumb != null
                            ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppColors.surfaceLight))
                            : (videoUrl != null
                                ? VideoPoster(videoUrl: videoUrl)
                                : Container(color: AppColors.surfaceLight, child: const Icon(Icons.movie, color: AppColors.textMuted))),
                      ),
                      Center(
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 24),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(d['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.35))),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _articleList() {
    return Column(
      children: _items.asMap().entries.map((e) {
        final i = e.key; final d = e.value;
        final excerpt = _plainExcerpt(d['content']);
        final thumb = d['thumbnail']?['url'];
        return InkWell(
          onTap: () => _openLightbox(i),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: thumb != null
                      ? CachedNetworkImage(imageUrl: thumb, width: 72, height: 72, fit: BoxFit.cover)
                      : Container(width: 72, height: 72, color: AppColors.surface, child: const Icon(Icons.article, color: AppColors.textMuted)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
                      if (excerpt.isNotEmpty) Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4))),
                      ),
                      if (d['uploader']?['username'] != null) Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(d['uploader']['username'], style: body(const TextStyle(fontSize: 10, color: AppColors.textMuted))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
