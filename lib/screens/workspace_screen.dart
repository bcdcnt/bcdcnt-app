import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import '../services/player.dart';
import '../services/upload_types.dart';
import '../widgets/ui.dart';
import '../widgets/waveform_player.dart';

/// "Bàn làm việc" (desktop, members with manage_upload): what BQT has to do,
/// in one place — queues with counts | list | detail. Uploads get the
/// recording, the details sent checked against the archive, a possible-
/// duplicate warning and the decision (A duyệt, N chưa chắc, R từ chối);
/// the other queues (bản nhạc thiếu, tag, yêu cầu, bình luận, mất file)
/// point at the page to fix. J/K: next/previous everywhere.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

/// (key, label, list title). The first group is the work; "Đã xử lý" keeps
/// the decided uploads at hand.
const _todo = [
  ('pending', 'Bài gửi chờ duyệt', 'Bài gửi'),
  ('no_score', 'Thiếu bản nhạc', 'Bản nhạc'),
  ('doc_request', 'Yêu cầu tư liệu', 'Yêu cầu'),
  ('no_tag', 'Bài thiếu tag', 'Bản nhạc'),
  ('comment_pending', 'Bình luận chờ duyệt', 'Bình luận'),
  ('lost_file', 'Bài mất file', 'Bài hát'),
];
const _done = [
  ('not_sure', 'Chưa chắc chắn', 'Bài gửi'),
  ('rejected', 'Đã từ chối', 'Bài gửi'),
  ('approved', 'Đã duyệt', 'Bài gửi'),
];
const _uploadQueues = {'pending', 'not_sure', 'rejected', 'approved'};

/// Server filter / list query per queue (not uploads).
const _noScoreWhere = '{OR: [{column: "content", operator: IS_NULL}, {column: "content", value: ""}]}';
const _requestWhere = '{AND: [{column: "is_request", value: 1}, {OR: [{column: "request_status", operator: IS_NULL}, {column: "request_status", operator: IN, value: ["processing", "need_more_info"]}]}]}';
const _commentPendingWhere = '{column: "status", value: 0}';
const _commentObj = '__typename ... on Song { id title } ... on Folk { id title } ... on Instrumental { id title } ... on Poem { id title } ... on Karaoke { id title } ... on Sheet { id title }';
const _fileTypes = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem', 'Karaoke': 'karaoke'};

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  String _queue = 'pending';
  final Map<String, int> _counts = {};
  List<Map<String, dynamic>> _items = [];
  int _sel = 0;
  bool _loading = true;
  bool _busy = false;
  int? _dupes;
  /// Newest first; the sheet queues also offer "Xem nhiều nhất".
  String _sort = 'new';
  /// Upload detail: name → found in the archive (null while asking).
  final Map<String, bool> _inKho = {};
  final _focus = FocusNode();

  bool get _isUpload => _uploadQueues.contains(_queue);
  bool get _isSheet => _queue == 'no_score' || _queue == 'no_tag';
  bool get _isComment => _queue == 'doc_request' || _queue == 'comment_pending';

  static const _fields = 'id title content note source type composers artists poets recomposers accompanists accompaniment_instrument year record_year link status reason created_at user { id username avatar { url } } file { id audio_url duration bitrate }';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCounts();
      _load();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  AuthProvider get _auth => context.read<AuthProvider>();

  Future<void> _loadCounts() async {
    int n(dynamic v) => (v?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0;
    final uploads = [for (final k in _uploadQueues) '$k: uploads(first: 1, where: {column: "status", value: "$k"}) { paginatorInfo { total } }'];
    // Two asks: an API without one of the newer filters must not cost the
    // upload counts.
    final others = {
      'no_score': 'sheets(first: 1, where: $_noScoreWhere)',
      'no_tag': 'sheets(first: 1, untagged: true)',
      'doc_request': 'comments(first: 1, where: $_requestWhere)',
      'comment_pending': 'comments(first: 1, where: $_commentPendingWhere)',
      'lost_file': 'songs(first: 1, where: {column: "empty_file", value: 1})',
    };
    Future<void> ask(Iterable<String> keys, String q) async {
      try {
        final d = await _auth.authedQuery('query { $q }');
        if (mounted) setState(() { for (final k in keys) { _counts[k] = n(d[k]); } });
      } catch (_) {}
    }
    await Future.wait([
      ask(_uploadQueues, uploads.join(' ')),
      for (final e in others.entries) ask([e.key], '${e.key}: ${e.value} { paginatorInfo { total } }'),
    ]);
  }

  Future<void> _load() async {
    final queue = _queue;
    setState(() { _loading = true; _items = []; _sel = 0; _dupes = null; });
    final order = _sort == 'views' ? '{column: "views", order: DESC}' : '{column: "id", order: ${_sort == 'old' ? 'ASC' : 'DESC'}}';
    const people = '{ data { title } }';
    final (root, q) = switch (queue) {
      'no_score' => ('sheets', 'sheets(first: 40, where: $_noScoreWhere, orderBy: [$order]) { data { id title views year composers(first: 3) $people songs(first: 1) { paginatorInfo { total } } } }'),
      'no_tag' => ('sheets', 'sheets(first: 40, untagged: true, orderBy: [$order]) { data { id title views year composers(first: 3) $people songs(first: 1) { paginatorInfo { total } } } }'),
      'lost_file' => ('songs', 'songs(first: 40, where: {column: "empty_file", value: 1}, orderBy: [$order]) { data { id title views record_year thumbnail { url } artists(first: 3) $people sheet { year composers(first: 3) $people } } }'),
      'doc_request' => ('comments', 'comments(first: 40, where: $_requestWhere, orderBy: [$order]) { data { id content created_at request_status user { id username } object { $_commentObj } } }'),
      'comment_pending' => ('comments', 'comments(first: 40, where: $_commentPendingWhere, orderBy: [$order]) { data { id content created_at user { id username } object { $_commentObj } } }'),
      _ => ('uploads', 'uploads(first: 40, page: 1, where: {column: "status", value: "$queue"}, orderBy: [$order]) { data { $_fields } }'),
    };
    try {
      final d = await _auth.authedQuery('query { $q }');
      if (!mounted || queue != _queue) return;
      setState(() {
        _items = ((d[root]?['data'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
      _checkDupes();
    } catch (e) {
      if (mounted && queue == _queue) setState(() => _loading = false);
    }
  }

  void _openQueue(String k) {
    setState(() { _queue = k; _sort = (k == 'no_score' || k == 'no_tag') ? 'views' : 'new'; });
    _load();
    _focus.requestFocus();
  }

  /// Names sent with an upload, each looked up in the archive (exact title).
  Future<void> _checkKho(Map<String, dynamic> u) async {
    const kinds = {'composers': 'composers', 'poets': 'poets', 'recomposers': 'recomposers', 'artists': 'artists'};
    final ask = <String, (String, String)>{};
    var i = 0;
    for (final e in kinds.entries) {
      for (final name in '${u[e.key] ?? ''}'.split(RegExp(r'[,;]')).map((x) => x.trim()).where((x) => x.isNotEmpty)) {
        final key = '${e.key}|$name';
        if (_inKho.containsKey(key)) continue;
        ask['p${i++}'] = (key, '${e.value}(first: 1, where: {column: "title", value: ${jsonEncode(name)}}) { paginatorInfo { total } }');
      }
    }
    if (ask.isEmpty) return;
    try {
      final d = await ApiClient.query('query { ${[for (final e in ask.entries) '${e.key}: ${e.value.$2}'].join(' ')} }');
      if (!mounted) return;
      setState(() {
        for (final e in ask.entries) {
          _inKho[e.value.$1] = ((d[e.key]?['paginatorInfo']?['total'] as num?) ?? 0) > 0;
        }
      });
    } catch (_) {}
  }

  Map<String, dynamic>? get _cur => _items.isEmpty ? null : _items[_sel.clamp(0, _items.length - 1)];

  /// Songs already in the archive under the same title.
  Future<void> _checkDupes() async {
    final u = _cur;
    setState(() => _dupes = null);
    if (!_isUpload) return;
    if (u != null) _checkKho(u);
    final t = '${u?['title'] ?? ''}'.trim();
    if (t.isEmpty) return;
    try {
      final d = await ApiClient.query('query(\$q: String) { songs(first: 1, q: \$q) { paginatorInfo { total } } }', {'q': t});
      if (mounted && _cur?['id'] == u?['id']) setState(() => _dupes = (d['songs']?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  void _select(int i) {
    if (i < 0 || i >= _items.length) return;
    setState(() => _sel = i);
    _checkDupes();
  }

  Future<void> _decide(String action) async {
    final u = _cur;
    if (u == null || _busy) return;
    String? reason;
    if (action == 'reject') {
      reason = await _askReason();
      if (reason == null) return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await _auth.authedMutate(
        r'mutation($id: ID!, $action: String!, $reason: String) { processUpload(id: $id, action: $action, reason: $reason) { id status } }',
        {'id': '${u['id']}', 'action': action, 'reason': ?reason},
      );
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text('${const {'approve': 'Đã duyệt', 'reject': 'Đã từ chối', 'not_sure': 'Đã chuyển sang Chưa chắc chắn'}[action]} “${u['title'] ?? ''}”'), duration: const Duration(seconds: 2)));
      setState(() {
        _items.removeAt(_sel);
        if (_sel >= _items.length) _sel = _items.length - 1;
        if (_sel < 0) _sel = 0;
      });
      _checkDupes();
      _loadCounts();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lý do không duyệt'),
        content: SizedBox(
          width: 420,
          child: TextField(controller: c, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: 'Ví dụ: trùng bản thu đã có, chất lượng kém…')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              final t = c.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('Từ chối'),
          ),
        ],
      ),
    );
  }

  void _listen(Map<String, dynamic> u) {
    final url = u['file']?['audio_url'];
    if (url == null) return;
    final song = <String, dynamic>{
      'id': 'upload-${u['id']}', 'title': u['title'], 'file_type': 'upload',
      'file': {'audio_url': url, 'duration': u['file']?['duration']},
      'artists': {'data': [if ('${u['artists'] ?? ''}'.isNotEmpty) {'title': u['artists']}]},
    };
    context.read<PlayerProvider>().playSong(song, [song], 'manual', 'Bàn làm việc');
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.keyJ) { _select(_sel + 1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.keyK) { _select(_sel - 1); return KeyEventResult.handled; }
    if (!_isUpload || _queue == 'approved') return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.keyA) { _decide('approve'); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.keyN) { _decide('not_sure'); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.keyR) { _decide('reject'); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.hasPermission('manage_upload')) {
      return Material(color: AppColors.bg, child: const EmptyBlock(icon: Icons.lock_outline_rounded, title: 'Chỉ dành cho Ban quản trị', message: 'Bàn làm việc dùng để duyệt bài gửi.'));
    }
    return Material(
      color: AppColors.bg,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Queues with counts.
          Container(
            width: 240,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            decoration: BoxDecoration(border: Border(right: BorderSide(color: AppColors.borderSubtle))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.fromLTRB(12, 0, 0, 12), child: Text('Việc cần làm', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)))),
              for (final (k, label, _) in _todo) _queueRow(k, label),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 22, 0, 8),
                child: Text('ĐÃ XỬ LÝ', style: body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted))),
              ),
              for (final (k, label, _) in _done) _queueRow(k, label),
            ]),
          ),
          // The list.
          Container(
            width: 320,
            decoration: BoxDecoration(border: Border(right: BorderSide(color: AppColors.borderSubtle))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _listHead(),
              Expanded(child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                : _items.isEmpty
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Không còn việc nào ở đây.', style: AppText.bodyText)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final u = _items[i];
                          final on = i == _sel;
                          return Material(
                            color: on ? AppColors.surface : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                _select(i);
                                _focus.requestFocus();
                              },
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                                decoration: BoxDecoration(border: Border(left: BorderSide(color: on ? AppColors.wine : Colors.transparent, width: 3))),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(_itemTitle(u), maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text))),
                                  const SizedBox(height: 2),
                                  Text(_itemMeta(u), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                                ]),
                              ),
                            ),
                          );
                        },
                      )),
            ]),
          ),
          Expanded(child: _cur == null ? const SizedBox.shrink() : (_isUpload ? _detail(_cur!) : _otherDetail(_cur!))),
        ]),
      ),
    );
  }

  Widget _queueRow(String k, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: k == _queue ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openQueue(k),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: body(TextStyle(fontSize: 15, fontWeight: k == _queue ? FontWeight.w800 : FontWeight.w700, color: k == _queue ? AppColors.accentFg : AppColors.text)))),
                if (_counts[k] != null)
                  Container(
                    constraints: const BoxConstraints(minWidth: 28),
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: k == _queue ? AppColors.wine : AppColors.surface, borderRadius: BorderRadius.circular(12)),
                    child: Text(formatInt(_counts[k]), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: k == _queue ? Colors.white : AppColors.textSecondary))),
                  ),
                const SizedBox(width: 10),
              ]),
            ),
          ),
        ),
      );

  /// "Bài gửi · 13" and the sort over the list.
  Widget _listHead() {
    final title = [..._todo, ..._done].firstWhere((q) => q.$1 == _queue).$3;
    final sorts = [if (_isSheet || _queue == 'lost_file') ('views', 'Xem nhiều nhất'), ('new', 'Mới nhất'), ('old', 'Cũ nhất')];
    final label = sorts.firstWhere((x) => x.$1 == _sort, orElse: () => sorts.first).$2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 22, 12, 8),
      child: Row(children: [
        Expanded(child: Text('$title · ${formatInt(_counts[_queue] ?? _items.length)}', style: body(TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)))),
        PopupMenuButton<String>(
          tooltip: 'Sắp xếp',
          onSelected: (v) {
            setState(() => _sort = v);
            _load();
          },
          itemBuilder: (_) => [for (final (k, t) in sorts) CheckedPopupMenuItem(value: k, checked: k == _sort, child: Text(t))],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textSecondary))),
              Icon(Icons.arrow_drop_down_rounded, size: 20, color: AppColors.textSecondary),
            ]),
          ),
        ),
      ]),
    );
  }

  static String _names(dynamic v) => (((v is Map ? v['data'] : v) as List?) ?? const []).whereType<Map>().map((e) => '${e['title'] ?? ''}').where((t) => t.isNotEmpty).join(', ');
  static String _plain(dynamic html) => '${html ?? ''}'.replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), ' ').replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  String _itemTitle(Map<String, dynamic> u) {
    if (_isComment) return _plain(u['content']).isEmpty ? '(bình luận trống)' : _plain(u['content']);
    return '${u['title'] ?? '(chưa có tên)'}';
  }

  String _itemMeta(Map<String, dynamic> u) {
    if (_isSheet) {
      return [_names(u['composers']), '${formatInt((u['views'] as num?)?.toInt() ?? 0)} lượt xem'].where((x) => x.isNotEmpty).join(' · ');
    }
    if (_queue == 'lost_file') {
      return [_names(u['artists']), '${formatInt((u['views'] as num?)?.toInt() ?? 0)} lượt nghe'].where((x) => x.isNotEmpty).join(' · ');
    }
    if (_isComment) {
      return [u['user']?['username'] ?? '', if (u['object']?['title'] != null) 'trong ${u['object']['title']}', timeago(u['created_at']?.toString())].where((x) => '$x'.isNotEmpty).join(' · ');
    }
    return '${u['user']?['username'] ?? ''} · ${timeago(u['created_at']?.toString())}';
  }

  /// Detail for the queues that are fixed on the item's own page.
  Widget _otherDetail(Map<String, dynamic> u) {
    Widget row(String k, String v) => v.trim().isEmpty
        ? const SizedBox.shrink()
        : Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 130, child: Text(k, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted)))),
              Expanded(child: SelectableText(v, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)))),
            ]),
          );
    final (eyebrow, title, hint) = switch (_queue) {
      'no_score' => ('BẢN NHẠC · CHƯA CÓ BẢN NHẠC', '${u['title'] ?? ''}', 'Thêm ảnh hoặc tệp bản nhạc ở trang bản nhạc.'),
      'no_tag' => ('BẢN NHẠC · CHƯA GẮN TAG', '${u['title'] ?? ''}', 'Gắn chủ đề (tag) ở trang bản nhạc để bài hiện trong các trang chủ đề.'),
      'lost_file' => ('BÀI HÁT · MẤT FILE', '${u['title'] ?? ''}', 'Đường dẫn file không còn mở được. Tải lại file ở trang bài hát.'),
      'doc_request' => ('YÊU CẦU · ${'${u['user']?['username'] ?? ''}'.toUpperCase()} · ${timeago(u['created_at']?.toString()).toUpperCase()}', 'Trong ${u['object']?['title'] ?? 'bài'}', 'Xử lý yêu cầu ở phần bình luận của bài.'),
      _ => ('BÌNH LUẬN · ${'${u['user']?['username'] ?? ''}'.toUpperCase()} · ${timeago(u['created_at']?.toString()).toUpperCase()}', 'Trong ${u['object']?['title'] ?? 'bài'}', 'Duyệt hoặc ẩn bình luận ở trang của bài.'),
    };
    final obj = u['object'] is Map ? u['object'] as Map : null;
    void open() {
      if (_isSheet) { context.push('/sheet/${u['id']}'); return; }
      if (_queue == 'lost_file') { context.push('/song/${u['id']}'); return; }
      final tn = '${obj?['__typename'] ?? ''}';
      if (_fileTypes.containsKey(tn)) {
        context.push('/song/${obj!['id']}?binh-luan=1', extra: {...Map<String, dynamic>.from(obj), 'file_type': _fileTypes[tn], 'highlightCommentId': '${u['id']}'});
      } else if (tn == 'Sheet') {
        context.push('/sheet/${obj!['id']}');
      }
    }
    final songs = (u['songs']?['paginatorInfo']?['total'] as num?)?.toInt();
    return ListView(padding: const EdgeInsets.fromLTRB(36, 24, 36, 40), children: [
      Text(eyebrow, style: AppText.eyebrow),
      const SizedBox(height: 6),
      Text(title, style: display(TextStyle(fontSize: 30, height: 1.15, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: AppColors.text))),
      const SizedBox(height: 16),
      if (_isComment)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: SelectableText(_plain(u['content']), style: body(TextStyle(fontSize: 16, height: 1.55, color: AppColors.text))),
        ),
      if (_isSheet) ...[
        row('Sáng tác', _names(u['composers'])),
        row('Năm sáng tác', '${u['year'] ?? ''}' == '0' ? '' : '${u['year'] ?? ''}'),
        row('Lượt xem', formatInt((u['views'] as num?)?.toInt() ?? 0)),
        if (songs != null) row('Bản thu', songs > 0 ? '$songs bản thu trong kho' : 'chưa có bản thu'),
      ],
      if (_queue == 'lost_file') ...[
        row('Sáng tác', _names(u['sheet']?['composers'])),
        row('Trình bày', _names(u['artists'])),
        row('Năm thu', '${u['record_year'] ?? ''}'),
        row('Lượt nghe', formatInt((u['views'] as num?)?.toInt() ?? 0)),
      ],
      if (_queue == 'doc_request' && '${u['request_status'] ?? ''}'.isNotEmpty)
        row('Trạng thái', const {'processing': 'Đang xử lý', 'need_more_info': 'Cần thêm thông tin'}['${u['request_status']}'] ?? '${u['request_status']}'),
      const SizedBox(height: 14),
      Text(hint, style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary))),
      const SizedBox(height: 18),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        PillButton(label: _isSheet ? 'Mở bản nhạc' : (_queue == 'lost_file' ? 'Mở bài hát' : 'Mở bình luận trong bài'), icon: Icons.open_in_new_rounded, onTap: open),
        const SizedBox(width: 12),
        _kbd('J', 'tiếp theo'),
        _kbd('K', 'trước đó'),
      ]),
    ]);
  }

  Widget _khoTag(String t, Color c) => Text(t, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)));

  Widget _kbd(String k, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          constraints: const BoxConstraints(minWidth: 24),
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
          child: Text(k, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.text))),
        ),
        const SizedBox(width: 6),
        Text(t, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
      ]);

  Widget _detail(Map<String, dynamic> u) {
    /// [kho]: the upload column whose names are checked against the archive
    /// ("composers", "artists"…); the row then says whether each is known.
    Widget field(String k, String? v, {String? kho, Widget? status}) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return const SizedBox.shrink();
      Widget? right = status;
      if (kho != null) {
        final names = t.split(RegExp(r'[,;]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
        final known = [for (final n in names) _inKho['$kho|$n']];
        if (known.every((x) => x != null)) {
          final missing = [for (var i = 0; i < names.length; i++) if (known[i] == false) names[i]];
          right = missing.isEmpty
              ? _khoTag('✓ đã khớp kho', AppColors.successText)
              : _khoTag(missing.length == names.length ? 'chưa có trong kho · tạo mới?' : 'chưa có: ${missing.join(', ')}', AppColors.warningText);
        }
      }
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted)))),
          Expanded(child: SelectableText(t, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)))),
          if (right != null) ...[const SizedBox(width: 12), right],
        ]),
      );
    }

    final file = u['file'] is Map ? u['file'] as Map : const {};
    final dur = (file['duration'] as num?)?.toDouble();
    final lyrics = '${u['content'] ?? ''}'.replaceAll(RegExp(r'<br\s*/?>'), '\n').replaceAll(RegExp(r'<[^>]+>'), '').trim();
    final decided = _queue == 'approved';
    return ListView(padding: const EdgeInsets.fromLTRB(36, 24, 36, 40), children: [
      Text('BÀI GỬI · ${'${u['user']?['username'] ?? ''}'.toUpperCase()} · ${timeago(u['created_at']?.toString()).toUpperCase()}', style: AppText.eyebrow),
      const SizedBox(height: 6),
      Text('${u['title'] ?? '(chưa có tên)'}', style: display(TextStyle(fontSize: 30, height: 1.15, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: AppColors.text))),
      const SizedBox(height: 16),
      if (file['audio_url'] != null) ...[
        // The recording right here, as on the upload page; keyed so a new
        // upload starts from its own waveform.
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: WaveformPlayer(key: ValueKey('wf-${u['id']}'), audioUrl: '${file['audio_url']}', seed: int.tryParse('${u['id']}') ?? 0),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Row(children: [
            Text([if (dur != null && dur > 0) formatTime(dur), if (file['bitrate'] != null) '${file['bitrate']} kbps'].join(' · '), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textSecondary))),
            const Spacer(),
            TextButton.icon(onPressed: () => _listen(u), icon: const Icon(Icons.queue_music_rounded, size: 18), label: const Text('Nghe trên thanh phát')),
          ]),
        ),
      ],
      if ((_dupes ?? 0) > 0) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: AppColors.warningText.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.warningText),
            const SizedBox(width: 10),
            Expanded(child: Text('Có thể trùng: kho đã có $_dupes bài tên “${u['title']}”', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.warningText)))),
            TextButton(onPressed: () => context.push('/search', extra: '${u['title']}'), child: const Text('So sánh')),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      field('Tên bài', u['title']?.toString(), status: _dupes == null ? null : (_dupes! > 0 ? _khoTag('✓ đã có trong kho', AppColors.successText) : _khoTag('bài mới', AppColors.textMuted))),
      field('Loại', uploadTypeLabel(u['type'])),
      field('Sáng tác', u['composers']?.toString(), kho: 'composers'),
      field('Lời thơ', u['poets']?.toString(), kho: 'poets'),
      field('Soạn giả', u['recomposers']?.toString(), kho: 'recomposers'),
      field('Trình bày', u['artists']?.toString(), kho: 'artists'),
      field('Đệm', [u['accompaniment_instrument'], u['accompanists']].where((x) => '${x ?? ''}'.trim().isNotEmpty).join(' · ')),
      field('Năm sáng tác', u['year']?.toString()),
      field('Năm thu', u['record_year']?.toString()),
      field('Nguồn', u['source']?.toString()),
      field('Đường dẫn', u['link']?.toString()),
      field('Ghi chú', u['note']?.toString()),
      field('Lý do', u['reason']?.toString()),
      if (lyrics.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('LỜI GỬI KÈM', style: AppText.eyebrow),
        const SizedBox(height: 6),
        SelectableText(lyrics, style: body(TextStyle(fontSize: 16, height: 1.6, color: AppColors.text))),
      ],
      const SizedBox(height: 24),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (!decided) ...[
          PillButton(label: 'Duyệt (A)', icon: Icons.check_rounded, loading: _busy, onTap: () => _decide('approve')),
          PillButton(label: 'Chưa chắc (N)', icon: Icons.help_outline_rounded, primary: false, onTap: _busy ? null : () => _decide('not_sure')),
          PillButton(label: 'Từ chối (R)', icon: Icons.close_rounded, primary: false, onTap: _busy ? null : () => _decide('reject')),
        ],
        PillButton(label: 'Sửa thông tin', icon: Icons.edit_outlined, primary: false, onTap: () => context.push('/bai-gui/${u['id']}')),
        const SizedBox(width: 12),
        _kbd('J', 'bài sau'),
        _kbd('K', 'bài trước'),
      ]),
    ]);
  }
}
