import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock;
import '../services/friendly_error.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import '../widgets/empty_state.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';

class MyPlaylistsScreen extends StatefulWidget {
  const MyPlaylistsScreen({super.key});

  @override
  State<MyPlaylistsScreen> createState() => _MyPlaylistsScreenState();
}

class _MyPlaylistsScreenState extends State<MyPlaylistsScreen> {
  static const _perPage = 20;
  final _scrollCtl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _error = false;
  bool _creating = false;

  AuthProvider? _authRef;
  bool _didInitialFetch = false;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    // Wait for auth to finish restoring its token before the first fetch —
    // otherwise a deep-link straight here races the async load and shows an
    // empty list with no retry.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authRef = context.read<AuthProvider>();
      _authRef!.addListener(_initialFetch);
      _initialFetch();
    });
  }

  void _initialFetch() {
    if (_didInitialFetch || !mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.loading) return;
    _didInitialFetch = true;
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
    if (_loadingMore || _loading || _error) return;
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
    setState(() {
      _error = false;
      if (page == 1) { _loading = true; } else { _loadingMore = true; }
    });

    const q = r'''query($first: Int!, $page: Int) {
      myPlaylists(first: $first, page: $page, orderBy: [{column: "id", order: DESC}]) {
        data {
          id title slug
          thumbnail { url }
          items(first: 1) { paginatorInfo { total } }
        }
        paginatorInfo { currentPage lastPage total }
      }
    }''';

    try {
      final data = await auth.authedQuery(q, {'first': _perPage, 'page': page});
      final raw = data['myPlaylists'];
      final list = ((raw?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final pi = raw?['paginatorInfo'] ?? {};
      if (!mounted) return;
      setState(() {
        if (page == 1) { _items = list; } else { _items.addAll(list); }
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _total = pi['total'] ?? _total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _loadingMore = false; _error = page == 1 || _items.isEmpty; });
        if (page > 1) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
        }
      }
    }
  }

  /// "+ Tạo playlist": ask for a name, create it, then open it.
  Future<void> _create() async {
    if (_creating) return;
    final ctl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tạo playlist mới', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          style: body(TextStyle(fontSize: 17, color: AppColors.text)),
          decoration: InputDecoration(
            labelText: 'Tên playlist',
            labelStyle: body(TextStyle(fontSize: 16, color: AppColors.textSecondary)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.pop(ctx),
            child: Text('Huỷ', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: Text('Tạo', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
          ),
        ],
      ),
    );
    // Not disposed here: the dialog's exit animation may still read it.
    if (title == null || title.isEmpty || !mounted) return;
    setState(() => _creating = true);
    try {
      final data = await context.read<AuthProvider>().authedMutate(
        r'''mutation($title: String!) { createPlaylist(input: {title: $title}) { id } }''',
        {'title': title},
      );
      final id = data['createPlaylist']?['id']?.toString();
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã tạo playlist "$title"')));
      _fetch(1);
      if (id != null) context.push('/playlist/$id');
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
        appBar: AppBar(title: const Text('Playlist của tôi'), leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context))),
        body: Center(
          child: auth.loading
              ? CircularProgressIndicator(color: AppColors.accentFg)
              : EmptyState(icon: Icons.queue_music, title: 'Vui lòng đăng nhập', subtitle: 'Đăng nhập để tạo và nghe playlist của bạn.', ctaLabel: 'Đăng nhập', onCta: () => askLogin(context)),
        ),
      );
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
                title: Text('Playlist của tôi'),
                centerTitle: true,
                leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
                actions: [
                  IconButton(
                    tooltip: 'Tạo playlist',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: _creating ? null : _create,
                    icon: _creating
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentFg))
                        : Icon(Icons.add_rounded, size: 28, color: AppColors.text),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  // Hero stats
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: const Color(0xFF388E3C).withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.queue_music, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Playlist của tôi', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                              const SizedBox(height: 4),
                              Text(
                                _total > 0 ? '${_formatInt(_total)} playlist' : (_loading ? 'Đang tải...' : 'Chưa có playlist'),
                                style: body(const TextStyle(fontSize: 15, color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_loading && _items.isEmpty)
                    Padding(padding: const EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: AppColors.accentFg)))
                  else if (_error)
                    OfflineBlock(onRetry: () => _fetch(1))
                  else if (_items.isEmpty)
                    EmptyState(
                      icon: Icons.queue_music,
                      title: 'Chưa có playlist',
                      subtitle: 'Tạo playlist mới, hoặc bấm ⋮ ở một bài hát rồi chọn "Thêm vào playlist".',
                      ctaLabel: '+ Tạo playlist',
                      onCta: _creating ? null : _create,
                    )
                  else
                    ..._items.map((pl) {
                      final thumb = pl['thumbnail']?['url'];
                      final total = pl['items']?['paginatorInfo']?['total'] ?? 0;
                      return InkWell(
                        onTap: () => context.push('/playlist/${pl['id']}'),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: thumb != null
                                    ? CachedNetworkImage(imageUrl: cdnImg((thumb).toString(), 140), width: 56, height: 56, fit: BoxFit.cover)
                                    : Container(width: 56, height: 56, color: AppColors.surface, child: Icon(Icons.queue_music, color: AppColors.textMuted)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(pl['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
                                    const SizedBox(height: 4),
                                    Text('$total bài', style: body(TextStyle(fontSize: 14, color: AppColors.textMuted))),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
                            ],
                          ),
                        ),
                      );
                    }),

                  if (_loadingMore) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accentFg, strokeWidth: 2))),

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
}
