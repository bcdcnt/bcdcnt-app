import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock, NetImage, Pager, PillButton, SkeletonSongRow;
import '../services/upload_types.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import '../widgets/empty_state.dart';
import '../widgets/desktop_page.dart';

/// Bài gửi: every upload the member sent — approved, waiting or rejected —
/// so a pending or refused submission never just "disappears".
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
  bool _error = false;
  /// Desktop: a status tab ('' = all) and numbered pages instead of the
  /// phone's endless scroll.
  String _status = '';
  bool _paged = false;
  Map<String, int> _counts = const {};

  static const _statusTabs = [('', 'Tất cả'), ('pending', 'Chờ duyệt'), ('approved', 'Đã duyệt'), ('rejected', 'Bị từ chối')];

  Future<void> _fetchCounts() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.user?['id']?.toString();
    if (userId == null) return;
    final parts = [for (final (k, _) in _statusTabs.skip(1)) '$k: uploads(first: 1, where: {column: "status", value: "$k"}) { paginatorInfo { total } }'].join(' ');
    try {
      final d = await auth.authedQuery('query(\$id: ID!) { user(id: \$id) { all: uploads(first: 1) { paginatorInfo { total } } $parts } }', {'id': userId});
      final u = d['user'];
      if (!mounted || u == null) return;
      setState(() => _counts = {
            for (final k in ['all', 'pending', 'approved', 'rejected']) k: (u[k]?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0,
          });
    } catch (_) {}
  }

  void _setStatus(String s) {
    if (s == _status) return;
    setState(() { _status = s; _items = []; });
    _fetch(1);
  }

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
    _fetchCounts();
  }

  @override
  void dispose() {
    _authRef?.removeListener(_initialFetch);
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_paged || _loadingMore || _loading || _error || _page >= _lastPage) return;
    if (_scrollCtl.position.pixels > _scrollCtl.position.maxScrollExtent - 600) _fetch(_page + 1);
  }

  Future<void> _fetch(int page) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) { setState(() => _loading = false); return; }
    final userId = auth.user?['id']?.toString();
    if (userId == null) { setState(() => _loading = false); return; }
    setState(() {
      _error = false;
      if (page == 1 || _paged) { _loading = true; } else { _loadingMore = true; }
    });
    try {
      final data = await auth.authedQuery(r'''query($id: ID!, $first: Int!, $page: Int, $where: WhereConditions) {
        user(id: $id) {
          uploads(first: $first, page: $page, where: $where, orderBy: [{column: "id", order: DESC}]) {
            data {
              id title type status reason created_at
              thumbnail { url }
              object { __typename ... on Song { title thumbnail { url } } ... on Folk { title thumbnail { url } } ... on Instrumental { title thumbnail { url } } ... on Poem { title thumbnail { url } } ... on Karaoke { title thumbnail { url } } }
            }
            paginatorInfo { total currentPage lastPage }
          }
        }
      }''', {'id': userId, 'first': _perPage, 'page': page, 'where': _status.isEmpty ? null : {'column': 'status', 'value': _status}});
      final raw = data['user']?['uploads'];
      final list = ((raw?['data'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final pi = raw?['paginatorInfo'] ?? {};
      final seen = {if (page > 1 && !_paged) ..._items.map((s) => s['id'].toString())};
      final fresh = [for (final u in list) if (seen.add(u['id'].toString())) u];
      if (!mounted) return;
      setState(() {
        if (page == 1 || _paged) { _items = fresh; } else { _items.addAll(fresh); }
        _page = pi['currentPage'] ?? page;
        _lastPage = pi['lastPage'] ?? 1;
        _total = pi['total'] ?? _total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _loadingMore = false; _error = page == 1 || _items.isEmpty; });
      if (page > 1) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
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
        appBar: AppBar(title: const Text('Bài gửi'), leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context))),
        body: Center(
          child: auth.loading
              ? CircularProgressIndicator(color: AppColors.accentFg)
              : EmptyState(icon: Icons.upload_outlined, title: 'Vui lòng đăng nhập', subtitle: 'Đăng nhập để xem bài bạn đã gửi.', ctaLabel: 'Đăng nhập', onCta: () => askLogin(context)),
        ),
      );
    }
    final desk = isDesk(context);
    _paged = desk;
    final count = _total > 0 ? '${_formatInt(_total)} bài đã gửi' : (_loading ? 'Đang tải...' : 'Chưa có');
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        RefreshIndicator(
          color: AppColors.accentFg,
          onRefresh: () => _fetch(1),
          child: DeskFrame(maxWidth: desk ? 1320 : double.infinity, child: CustomScrollView(
            controller: _scrollCtl,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (!desk)
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.bg,
                title: const Text('Bài gửi'),
                centerTitle: true,
                leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
                actions: [
                  Padding(padding: const EdgeInsets.only(right: 12), child: PillButton(label: 'Gửi bài', icon: Icons.add_rounded, height: 40, onTap: () => context.push('/gui-bai'))),
                ],
              ),
              SliverPadding(
                padding: desk ? EdgeInsets.fromLTRB(deskPad.left, deskPad.top, deskPad.right, 0) : const EdgeInsets.fromLTRB(20, 8, 20, 16),
                sliver: SliverToBoxAdapter(
                  child: desk
                      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          DeskHead(title: 'Bài gửi của tôi', subtitle: count, actions: [
                            PillButton(label: 'Gửi bài', icon: Icons.add_rounded, height: 44, onTap: () => context.push('/gui-bai')),
                          ]),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final (k, label) in _statusTabs)
                              _StatusTab(label: label, count: _counts[k.isEmpty ? 'all' : k], on: _status == k, onTap: () => _setStatus(k)),
                          ]),
                          const SizedBox(height: 10),
                        ])
                      : Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    child: Row(children: [
                      Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.upload_outlined, color: Colors.white, size: 28)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Bài gửi của tôi', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                        const SizedBox(height: 4),
                        Text(count, style: body(const TextStyle(fontSize: 15, color: Colors.white))),
                      ])),
                    ]),
                  ),
                ),
              ),
              if (_loading && desk)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: deskPad.left - 12),
                  sliver: SliverList(delegate: SliverChildBuilderDelegate((_, __) => const SkeletonSongRow(), childCount: 10)),
                )
              else if (_loading && _items.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accentFg)))
              else if (_error)
                SliverFillRemaining(hasScrollBody: false, child: Center(child: OfflineBlock(onRetry: () => _fetch(1))))
              else if (_items.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: EmptyState(
                  icon: Icons.upload_outlined,
                  title: 'Chưa có bài gửi',
                  subtitle: 'Bài bạn gửi đóng góp cho thư viện sẽ xuất hiện tại đây.',
                ))
              else if (desk) ...[
                SliverPadding(padding: EdgeInsets.symmetric(horizontal: deskPad.left), sliver: const SliverToBoxAdapter(child: _UploadTableHead())),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: deskPad.left),
                  sliver: SliverList(delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _UploadRow(upload: _items[i], desk: true),
                    childCount: _items.length,
                  )),
                ),
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Pager(page: _page, lastPage: _lastPage, loading: _loading, onPage: (p) {
                    _fetch(p);
                    if (_scrollCtl.hasClients) _scrollCtl.jumpTo(0);
                  }),
                )),
              ] else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverList(delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _UploadRow(upload: _items[i]),
                    childCount: _items.length,
                  )),
                ),
              SliverToBoxAdapter(child: Column(children: [
                if (_loadingMore) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.accentFg, strokeWidth: 2))),
                SizedBox(height: player.currentSong != null ? 90 : 20),
              ])),
            ],
          )),
        ),
        if (player.currentSong != null)
          const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}

IconData _typeIcon(String type) => switch (type) {
      'sheet' => Icons.library_music_outlined,
      'karaoke' => Icons.mic_none_rounded,
      'replace' => Icons.upload_rounded,
      'document_news' => Icons.article_outlined,
      'document_image' => Icons.image_outlined,
      'document_video' => Icons.videocam_outlined,
      'document_audio' => Icons.graphic_eq_rounded,
      'discussion' => Icons.forum_outlined,
      _ => Icons.music_note_rounded,
    };

class _StatusTab extends StatelessWidget {
  final String label;
  final int? count;
  final bool on;
  final VoidCallback onTap;
  const _StatusTab({required this.label, required this.on, required this.onTap, this.count});

  @override
  Widget build(BuildContext context) {
    final fg = on ? Colors.white : AppColors.textSecondary;
    return Material(
      color: on ? AppColors.wine : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: fg))),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text('$count', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: fg.withValues(alpha: 0.75)))),
            ],
          ]),
        ),
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  final Map<String, dynamic> upload;
  /// Desktop table row: thumbnail · title · TRẠNG THÁI · NGÀY GỬI · ›.
  final bool desk;
  const _UploadRow({required this.upload, this.desk = false});

  static String _date(String? s) {
    final d = DateTime.tryParse(s ?? '');
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final status = (upload['status'] ?? 'pending').toString();
    final (String label, Color color, IconData icon) = switch (status) {
      'approved' => ('Đã duyệt', AppColors.successText, Icons.check_circle_outline),
      'rejected' => ('Bị từ chối', AppColors.errorText, Icons.cancel_outlined),
      _ => ('Chờ duyệt', AppColors.warningText, Icons.access_time),
    };
    final obj = upload['object'] is Map ? upload['object'] as Map : null;
    final type = (upload['type'] ?? '').toString();
    final own = (upload['title'] ?? '').toString().trim();
    // Many "bổ sung bản ghi" carry no title, or the song's link as one.
    final title = own.isNotEmpty && !own.startsWith('http')
        ? own
        : ((obj?['title'] ?? '').toString().trim().isNotEmpty ? obj!['title'].toString() : '${uploadTypeLabel(type).isEmpty ? 'Bài gửi' : uploadTypeLabel(type)} #${upload['id']}');
    final thumb = (upload['thumbnail']?['url'] ?? obj?['thumbnail']?['url'])?.toString();
    final reason = (upload['reason'] ?? '').toString().trim();
    final date = _date(upload['created_at']?.toString());
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(label, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color))),
      ]),
    );
    final why = status == 'rejected' && reason.isNotEmpty ? 'Lý do: $reason' : null;

    if (desk) {
      return Semantics(
        button: true,
        label: '$title, $label',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => context.push('/bai-gui/${upload['id']}'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: thumb != null
                    ? NetImage(url: thumb, width: 44, height: 44)
                    : Container(width: 44, height: 44, color: AppColors.surfaceLight, child: Icon(_typeIcon(type), size: 20, color: AppColors.textMuted)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title),
                    if (why != null) Text(why, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary))),
                  ]),
                ),
              ),
              SizedBox(width: _kTypeW, child: Text(uploadTypeLabel(type), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
              SizedBox(width: _kStatusW, child: Align(alignment: Alignment.centerLeft, child: chip)),
              SizedBox(width: _kDateW, child: Text(date, style: AppText.caption)),
              SizedBox(width: _kChevW, child: Icon(Icons.chevron_right_rounded, color: AppColors.textMuted)),
            ]),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: '$title, $label',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/bai-gui/${upload['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: thumb != null
                  ? NetImage(url: thumb, width: 52, height: 52)
                  : Container(width: 52, height: 52, color: AppColors.surfaceLight, child: Icon(Icons.music_note_rounded, color: AppColors.textMuted)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.title),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  chip,
                  if (date.isNotEmpty) Text(date, style: AppText.caption),
                ]),
                if (why != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(why, maxLines: 3, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary))),
                  ),
              ]),
            ),
            Padding(padding: const EdgeInsets.only(top: 14), child: Icon(Icons.chevron_right_rounded, color: AppColors.textMuted)),
          ]),
        ),
      ),
    );
  }
}

// Desktop table column widths, shared by the head and the rows.
const _kTypeW = 160.0;
const _kStatusW = 150.0;
const _kDateW = 120.0;
const _kChevW = 32.0;

class _UploadTableHead extends StatelessWidget {
  const _UploadTableHead();

  @override
  Widget build(BuildContext context) {
    final st = body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted));
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        const SizedBox(width: 58),
        Expanded(child: Text('BÀI GỬI', style: st)),
        SizedBox(width: _kTypeW, child: Text('LOẠI', style: st)),
        SizedBox(width: _kStatusW, child: Text('TRẠNG THÁI', style: st)),
        SizedBox(width: _kDateW, child: Text('NGÀY GỬI', style: st)),
        const SizedBox(width: _kChevW),
      ]),
    );
  }
}
