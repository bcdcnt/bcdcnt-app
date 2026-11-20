import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import '../services/player.dart';
import '../services/upload_types.dart';
import '../widgets/ui.dart';
import '../widgets/waveform_player.dart';
import '../widgets/same_recordings.dart';
import '../widgets/replace_compare.dart';
import '../widgets/same_sheets.dart';
import '../widgets/upload_thread.dart';

/// "Bàn làm việc" (desktop, members with manage_upload): what BQT has to do,
/// in one place — queues with counts | list | detail. Uploads get the
/// recording, the details sent checked against the archive, a possible-
/// duplicate warning and the decision (A duyệt, N chưa chắc, R từ chối);
/// the other queues (bản nhạc thiếu, tag, yêu cầu, bình luận, mất file)
/// point at the page to fix. J/K: next/previous everywhere.
class WorkspaceScreen extends StatefulWidget {
  /// Queue (and sort) to open on (`/ban-lam-viec?q=no_tag&s=new`), e.g. from the home strip.
  final String? queue;
  final String? sort;
  const WorkspaceScreen({super.key, this.queue, this.sort});
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

/// (key, label, list title). The first group is the work; "Đã xử lý" keeps
/// the decided uploads at hand.
const _todo = [
  ('pending', 'Bài gửi chờ duyệt', 'Bài gửi'),
  ('doc_request', 'Xử lý yêu cầu', 'Yêu cầu'),
  ('no_year', 'Thiếu năm sáng tác', 'Bản nhạc'),
  ('no_score', 'Thiếu bản nhạc', 'Bản nhạc'),
  ('no_tag', 'Thiếu tag', 'Bản nhạc'),
  ('no_image', 'Thiếu ảnh minh hoạ', 'Bài hát'),
  ('no_lyric', 'Thiếu lời', 'Bài hát'),
  ('lost_file', 'Mất dữ liệu', 'Bài hát'),
];
const _done = [
  ('not_sure', 'Chưa chắc chắn', 'Bài gửi'),
  ('rejected', 'Đã từ chối', 'Bài gửi'),
  ('approved', 'Đã duyệt', 'Bài gửi'),
];
const _uploadQueues = {'pending', 'not_sure', 'rejected', 'approved'};

/// Server filter / list query per queue (not uploads).
/// The song's year of composition lives on its sheet.
const _noYearWhere = '{OR: [{column: "year", operator: IS_NULL}, {column: "year", value: 0}]}';
const _noScoreWhere = '{OR: [{column: "content", operator: IS_NULL}, {column: "content", value: ""}]}';
const _requestWhere = '{AND: [{column: "is_request", value: 1}, {OR: [{column: "request_status", operator: IS_NULL}, {column: "request_status", operator: IN, value: ["processing", "need_more_info"]}]}]}';
const _commentPendingWhere = '{column: "status", value: 0}';
/// Songs still without a picture / lyrics, whole catalogue (the home
/// "Nhờ bạn giúp sức" strip shows the same totals).
const _noImageWhere = '{column: "image_id", operator: IS_NULL}';
const _noLyricWhere = '{OR: [{column: "content", operator: IS_NULL}, {column: "content", value: ""}]}';
const _commentObj = '__typename ... on Song { id title } ... on Folk { id title } ... on Instrumental { id title } ... on Poem { id title } ... on Karaoke { id title } ... on Sheet { id title }'
    ' ... on Composer { id title slug } ... on Artist { id title slug } ... on Poet { id title slug } ... on Recomposer { id title slug }'
    ' ... on Document { id title } ... on Discussion { id title } ... on Playlist { id title }';
/// Pages other than recordings/sheets that carry comments → their app route.
const _personPaths = {'Composer': 'nhac-si', 'Artist': 'nghe-si', 'Poet': 'nha-tho', 'Recomposer': 'soan-gia'};
const _idPaths = {'Document': 'tu-lieu/chi-tiet', 'Discussion': 'thao-luan', 'Playlist': 'playlist'};
const _fileTypes = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem', 'Karaoke': 'karaoke'};

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  // An old link to a queue no longer listed (Bình luận chờ duyệt) lands on the uploads.
  late String _queue = [..._todo, ..._done].any((q) => q.$1 == widget.queue) ? widget.queue! : 'pending';
  final Map<String, int> _counts = {};
  List<Map<String, dynamic>> _items = [];
  int _sel = 0;
  bool _loading = true;
  bool _busy = false;
  int? _dupes;
  /// Newest first; the sheet queues also offer "Xem nhiều nhất".
  late String _sort = widget.sort ?? ((widget.queue == 'no_score' || widget.queue == 'no_tag' || widget.queue == 'no_year') ? 'views' : 'new');
  /// Upload detail: name → found in the archive (null while asking).
  final Map<String, bool> _inKho = {};
  final _focus = FocusNode();
  /// Trao đổi column: the member's choice (saved), else open from 1600px.
  bool? _threadPref;
  /// Lời gửi kèm: long lyrics start folded to [_lyricsFold] lines.
  bool _lyricsOpen = false;
  static const _lyricsFold = 8;

  bool get _isUpload => _uploadQueues.contains(_queue);
  bool get _isSheet => _queue == 'no_score' || _queue == 'no_tag' || _queue == 'no_year';
  bool get _isSong => _queue == 'lost_file' || _queue == 'no_image' || _queue == 'no_lyric';
  bool get _isComment => _queue == 'doc_request' || _queue == 'comment_pending';

  static const _fields = 'id title content note source type composers artists poets recomposers accompanists accompaniment_instrument year record_year link status reason created_at user { id username avatar { url } } thumbnail { url } file { id audio_url duration bitrate is_hq } talk: comments(first: 1, orderBy: [{column: "id", order: DESC}], where: {column: "status", operator: NEQ, value: 2}) { paginatorInfo { total } data { user { id } } } object { __typename ... on Song { id title slug artists(first: 3) { data { title } } file { id audio_url duration bitrate is_hq user { username } } sheet { composers(first: 3) { data { title } } } } }';


  @override
  void initState() {
    super.initState();
    // Shortcuts listen app-wide while this page is on top, so they keep
    // working when the keyboard focus fell out of the page (a closed panel).
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCounts();
      _load();
    });
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool('workspace_thread_open');
      if (v != null && mounted) setState(() => _threadPref = v);
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
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
      'no_year': 'sheets(first: 1, where: $_noYearWhere)',
      'no_score': 'sheets(first: 1, where: $_noScoreWhere)',
      'no_tag': 'sheets(first: 1, untagged: true)',
      'doc_request': 'comments(first: 1, where: $_requestWhere)',
      'lost_file': 'songs(first: 1, where: {column: "empty_file", value: 1})',
      'no_image': 'songs(first: 1, where: $_noImageWhere)',
      'no_lyric': 'songs(first: 1, where: $_noLyricWhere)',
    };
    Future<void> ask(Iterable<String> keys, String q) async {
      try {
        final d = await _auth.authedQuery('query { $q }', null, true);
        if (mounted) setState(() { for (final k in keys) { _counts[k] = n(d[k]); } });
        if (keys.contains('pending')) pendingUploads.value = _counts['pending'];
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
      'no_year' => ('sheets', 'sheets(first: 40, where: $_noYearWhere, orderBy: [$order]) { data { id title views year composers(first: 3) $people songs(first: 1) { paginatorInfo { total } } } }'),
      'no_score' => ('sheets', 'sheets(first: 40, where: $_noScoreWhere, orderBy: [$order]) { data { id title views year composers(first: 3) $people songs(first: 1) { paginatorInfo { total } } } }'),
      'no_tag' => ('sheets', 'sheets(first: 40, untagged: true, orderBy: [$order]) { data { id title views year composers(first: 3) $people songs(first: 1) { paginatorInfo { total } } } }'),
      'lost_file' => ('songs', 'songs(first: 40, where: {column: "empty_file", value: 1}, orderBy: [$order]) { data { id title views record_year thumbnail { url } artists(first: 3) $people sheet { year composers(first: 3) $people } } }'),
      'no_image' => ('songs', 'songs(first: 40, where: $_noImageWhere, orderBy: [$order]) { data { id title views record_year thumbnail { url } artists(first: 3) $people sheet { year composers(first: 3) $people } } }'),
      'no_lyric' => ('songs', 'songs(first: 40, where: $_noLyricWhere, orderBy: [$order]) { data { id title views record_year thumbnail { url } artists(first: 3) $people sheet { year composers(first: 3) $people } } }'),
      'doc_request' => ('comments', 'comments(first: 40, where: $_requestWhere, orderBy: [$order]) { data { id content created_at request_status user { id username } object { $_commentObj } } }'),
      'comment_pending' => ('comments', 'comments(first: 40, where: $_commentPendingWhere, orderBy: [$order]) { data { id content created_at user { id username } object { $_commentObj } } }'),
      _ => ('uploads', 'uploads(first: 40, page: 1, where: {column: "status", value: "$queue"}, orderBy: [$order]) { data { $_fields } }'),
    };
    try {
      final d = await _auth.authedQuery('query { $q }', null, true);
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
    setState(() { _queue = k; _sort = (k == 'no_score' || k == 'no_tag' || k == 'no_year') ? 'views' : 'new'; });
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
    if (u != null) {
      _checkKho(u);
    }
    final t = '${u?['title'] ?? ''}'.trim();
    if (t.isEmpty) return;
    try {
      final d = await ApiClient.query('query(\$q: String) { songs(first: 1, q: \$q) { paginatorInfo { total } } }', {'q': t});
      if (mounted && _cur?['id'] == u?['id']) setState(() => _dupes = (d['songs']?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  void _select(int i) {
    if (i < 0 || i >= _items.length) return;
    setState(() { _sel = i; _lyricsOpen = false; });
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

  bool _onHardwareKey(KeyEvent e) {
    // Only for the page on top: not under a dialog or another page.
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    return _onKey(_focus, e) == KeyEventResult.handled;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    // Typing in a field (the thread with the sender): letters are letters.
    if (typingInField()) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    if (hw.isControlPressed || hw.isMetaPressed || hw.isAltPressed) return KeyEventResult.ignored;
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
        child: LayoutBuilder(builder: (context, box) {
          _boxW = box.maxWidth;
          final threadOn = _threadOn;
          // Not enough room for four columns: the queues shrink to icons;
          // still too narrow for the detail (≥ 460) → Trao đổi slides over it.
          final rail = threadOn && box.maxWidth < 240 + 320 + 340 + 620;
          final overlay = threadOn && box.maxWidth - 72 - 320 - 340 < 460;
          final row = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (rail) _rail() else _queueColumn(),
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
                                  if (!_isComment && u['type'] == 'replace')
                                    ReplaceTitle(upload: u, maxLines: 2, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)))
                                  else
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
          if (threadOn && !overlay) _threadColumn(_cur!),
        ]);
          if (!overlay) return row;
          return Stack(children: [
            Positioned.fill(child: row),
            Positioned(top: 0, bottom: 0, right: 0, child: Material(elevation: 12, color: AppColors.bg, child: _threadColumn(_cur!))),
          ]);
        }),
      ),
    );
  }

  /// Width the workspace actually has (the app's side panel may take some).
  double _boxW = 0;
  /// Open by default only when four full columns fit.
  bool get _threadOn => _isUpload && _cur != null && (_threadPref ?? _boxW >= 240 + 320 + 340 + 620);

  void _toggleThread() {
    final next = !_threadOn;
    setState(() => _threadPref = next);
    SharedPreferences.getInstance().then((p) => p.setBool('workspace_thread_open', next));
  }

  Widget _queueColumn() => Container(
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
          );

  static const _railIcons = {
    'pending': Icons.inbox_rounded, 'no_year': Icons.event_busy_outlined, 'no_score': Icons.library_music_outlined, 'doc_request': Icons.description_outlined,
    'no_tag': Icons.sell_outlined, 'comment_pending': Icons.chat_bubble_outline_rounded, 'lost_file': Icons.music_off_outlined, 'no_image': Icons.hide_image_outlined, 'no_lyric': Icons.subtitles_off_outlined,
    'not_sure': Icons.help_outline_rounded, 'rejected': Icons.close_rounded, 'approved': Icons.check_rounded,
  };

  /// The queues as a 72px strip of icons with counts (Trao đổi open on a
  /// narrow window); » closes Trao đổi and brings the full column back.
  Widget _rail() {
    String short(int? n) => n == null ? '' : (n >= 1000 ? '${n ~/ 1000}N' : '$n');
    Widget item(String k, String label) {
      final on = k == _queue;
      return Tooltip(
        message: '$label · ${formatInt(_counts[k] ?? 0)}',
        child: Material(
          color: on ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openQueue(k),
            child: SizedBox(
              height: 52,
              child: Stack(alignment: Alignment.center, children: [
                Icon(_railIcons[k], color: on ? AppColors.accentFg : AppColors.textSecondary),
                if (_counts[k] != null)
                  Positioned(
                    top: 4, right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: on ? AppColors.wine : (_doneColors(k)?.$1 ?? AppColors.surfaceLight), borderRadius: BorderRadius.circular(9)),
                      child: Text(short(_counts[k]), style: body(TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: on ? Colors.white : (_doneColors(k)?.$2 ?? AppColors.textSecondary)))),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
    }
    return Container(
      width: 72,
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 16),
      decoration: BoxDecoration(border: Border(right: BorderSide(color: AppColors.borderSubtle))),
      child: ListView(children: [
        IconButton(tooltip: 'Đóng Trao đổi, hiện đủ Việc cần làm', onPressed: _toggleThread, icon: Icon(Icons.keyboard_double_arrow_right_rounded, color: AppColors.textMuted)),
        for (final (k, label, _) in _todo) item(k, label),
        Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6), child: Divider(height: 1, color: AppColors.border)),
        for (final (k, label, _) in _done) item(k, label),
      ]),
    );
  }

  /// Trao đổi with the sender of the upload on screen, as a right column.
  Widget _threadColumn(Map<String, dynamic> u) => Container(
        width: 340,
        decoration: BoxDecoration(border: Border(left: BorderSide(color: AppColors.borderSubtle))),
        child: Stack(children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 36, bottom: 8),
                child: Text('${u['title'] ?? ''} · ${u['user']?['username'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, color: AppColors.textMuted))),
              ),
              UploadThread(
                key: ValueKey('thread-${u['id']}'),
                uploadId: '${u['id']}',
                senderId: '${u['user']?['id'] ?? ''}',
                onSent: () => setState(() {
                  final n = (u['talk']?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0;
                  u['talk'] = {'paginatorInfo': {'total': n + 1}, 'data': [{'user': {'id': context.read<AuthProvider>().user?['id']}}]};
                }),
              ),
            ],
          ),
          Positioned(top: 10, right: 10, child: IconButton(tooltip: 'Đóng Trao đổi', onPressed: _toggleThread, icon: const Icon(Icons.close_rounded))),
        ]),
      );

  /// "💬 Trao đổi 2 ●" — the dot when the sender wrote last.
  Widget _threadChip(Map<String, dynamic> u) {
    final n = (u['talk']?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0;
    final last = ((u['talk']?['data'] ?? []) as List).whereType<Map>().firstOrNull;
    final senderLast = last != null && '${last['user']?['id']}' == '${u['user']?['id']}';
    final on = _threadOn;
    return Material(
      color: on ? AppColors.wine : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: AppColors.accentFg, width: 1.5)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _toggleThread,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 16, color: on ? Colors.white : AppColors.accentFg),
            const SizedBox(width: 6),
            Text(n > 0 ? 'Trao đổi $n' : 'Trao đổi', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: on ? Colors.white : AppColors.accentFg))),
            if (senderLast) ...[
              const SizedBox(width: 6),
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFFC62828), shape: BoxShape.circle)),
            ],
            const SizedBox(width: 4),
            Icon(on ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 18, color: on ? Colors.white : AppColors.accentFg),
          ]),
        ),
      ),
    );
  }

  /// Decided queues keep their own colour, so they read apart at a glance.
  static (Color, Color)? _doneColors(String k) => switch (k) {
        'not_sure' => (AppColors.isLight ? const Color(0xFFFFF4DE) : const Color(0xFF3A2E14), AppColors.warningText),
        'rejected' => (AppColors.isLight ? const Color(0xFFFDE8E8) : const Color(0xFF3A1818), AppColors.errorText),
        'approved' => (AppColors.isLight ? const Color(0xFFE5F3EA) : const Color(0xFF15301F), AppColors.successText),
        _ => null,
      };

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
                    decoration: BoxDecoration(color: k == _queue ? AppColors.wine : (_doneColors(k)?.$1 ?? AppColors.surface), borderRadius: BorderRadius.circular(12)),
                    child: Text(formatInt(_counts[k]), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: k == _queue ? Colors.white : (_doneColors(k)?.$2 ?? AppColors.textSecondary)))),
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
    final sorts = [if (_isSheet || _isSong) ('views', 'Xem nhiều nhất'), ('new', 'Mới nhất'), ('old', 'Cũ nhất')];
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
    if (_isSong) {
      return [_names(u['artists']), '${formatInt((u['views'] as num?)?.toInt() ?? 0)} lượt nghe'].where((x) => x.isNotEmpty).join(' · ');
    }
    if (_isComment) {
      return [u['user']?['username'] ?? '', if (u['object']?['title'] != null) 'trong ${u['object']['title']}', timeago(u['created_at']?.toString())].where((x) => '$x'.isNotEmpty).join(' · ');
    }
    // Uploads with a sender ↔ BQT thread say so.
    final talk = (u['talk']?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0;
    return [u['user']?['username'] ?? '', timeago(u['created_at']?.toString()), if (talk > 0) '$talk trao đổi'].join(' · ');
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
      'no_year' => ('BẢN NHẠC · CHƯA CÓ NĂM SÁNG TÁC', '${u['title'] ?? ''}', 'Điền năm sáng tác ở trang bản nhạc (Sửa thông tin).'),
      'no_score' => ('BẢN NHẠC · CHƯA CÓ BẢN NHẠC', '${u['title'] ?? ''}', 'Thêm ảnh hoặc tệp bản nhạc ở trang bản nhạc.'),
      'no_tag' => ('BẢN NHẠC · CHƯA GẮN TAG', '${u['title'] ?? ''}', 'Gắn chủ đề (tag) ở trang bản nhạc để bài hiện trong các trang chủ đề.'),
      'lost_file' => ('BÀI HÁT · MẤT FILE', '${u['title'] ?? ''}', 'Đường dẫn file không còn mở được. Tải lại file ở trang bài hát.'),
      'no_image' => ('BÀI HÁT · CHƯA CÓ ẢNH MINH HOẠ', '${u['title'] ?? ''}', 'Thêm ảnh ở trang bài hát: ⋯ › Công cụ CTV › Ảnh minh hoạ.'),
      'no_lyric' => ('BÀI HÁT · CHƯA CÓ LỜI', '${u['title'] ?? ''}', 'Thêm lời ở trang bài hát (mục Lời bài hát).'),
      'doc_request' => ('YÊU CẦU · ${'${u['user']?['username'] ?? ''}'.toUpperCase()} · ${timeago(u['created_at']?.toString()).toUpperCase()}', 'Trong ${u['object']?['title'] ?? 'bài'}', 'Xử lý yêu cầu ở phần bình luận của bài.'),
      _ => ('BÌNH LUẬN · ${'${u['user']?['username'] ?? ''}'.toUpperCase()} · ${timeago(u['created_at']?.toString()).toUpperCase()}', 'Trong ${u['object']?['title'] ?? 'bài'}', 'Duyệt hoặc ẩn bình luận ở trang của bài.'),
    };
    final obj = u['object'] is Map ? u['object'] as Map : null;
    void open() {
      if (_isSheet) { context.push('/sheet/${u['id']}'); return; }
      if (_isSong) { context.push('/song/${u['id']}'); return; }
      final tn = '${obj?['__typename'] ?? ''}';
      if (_fileTypes.containsKey(tn)) {
        context.push('/song/${obj!['id']}?binh-luan=1', extra: {...Map<String, dynamic>.from(obj), 'file_type': _fileTypes[tn], 'highlightCommentId': '${u['id']}'});
      } else if (tn == 'Sheet') {
        context.push('/sheet/${obj!['id']}');
      } else if (_personPaths.containsKey(tn) && '${obj!['slug'] ?? ''}'.isNotEmpty) {
        context.push('/${_personPaths[tn]}/${obj['slug']}');
      } else if (_idPaths.containsKey(tn)) {
        context.push('/${_idPaths[tn]}/${obj!['id']}');
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('App chưa mở được trang của bình luận này. Xử lý trên web.')));
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
      if (_isSong) ...[
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
        PillButton(label: _isSheet ? 'Mở bản nhạc' : (_isSong ? 'Mở bài hát' : 'Mở bình luận trong bài'), icon: Icons.open_in_new_rounded, onTap: open),
        const SizedBox(width: 12),
        Row(mainAxisSize: MainAxisSize.min, children: [_kbd('J', 'tiếp theo'), const SizedBox(width: 12), _kbd('K', 'trước đó')]),
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
    Widget field(String k, String? v, {String? kho, Widget? status, Widget? value}) {
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
          Expanded(child: value ?? SelectableText(t, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)))),
          if (right != null) ...[const SizedBox(width: 12), right],
        ]),
      );
    }

    final file = u['file'] is Map ? u['file'] as Map : const {};
    final dur = (file['duration'] as num?)?.toDouble();
    final lyrics = u['type'] == 'sheet' ? '' : '${u['content'] ?? ''}'.replaceAll(RegExp(r'<br\s*/?>'), '\n').replaceAll(RegExp(r'<[^>]+>'), '').trim();
    final decided = _queue == 'approved';
    // Sheet scans (and other attached images) live as <img> in the content
    // HTML, plus the optional thumbnail — show them, not just the text.
    final images = <String>[
      if ('${u['thumbnail']?['url'] ?? ''}'.isNotEmpty) '${u['thumbnail']['url']}',
      ...RegExp(r'<img[^>]+src="([^"]+)"', caseSensitive: false).allMatches('${u['content'] ?? ''}').map((m) => m.group(1)!),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(36, 24, 36, 40), children: [
      Row(children: [
        Expanded(child: Text('BÀI GỬI · ${'${u['user']?['username'] ?? ''}'.toUpperCase()} · ${timeago(u['created_at']?.toString()).toUpperCase()}', style: AppText.eyebrow)),
        _threadChip(u),
      ]),
      const SizedBox(height: 6),
      if (u['type'] == 'replace')
        ReplaceTitle(upload: u, style: display(TextStyle(fontSize: 30, height: 1.15, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: AppColors.text)))
      else
        Text('${u['title'] ?? '(chưa có tên)'}', style: display(TextStyle(fontSize: 30, height: 1.15, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: AppColors.text))),
      const SizedBox(height: 16),
      // Thay thế bản thu chất lượng: the recording sent beside the one on the
      // site now, with both technical sheets.
      if (u['type'] == 'replace')
        ReplaceCompare(key: ValueKey('rc-${u['id']}'), upload: u)
      else if (file['audio_url'] != null) ...[
        // The recording right here, as on the upload page; keyed so a new
        // upload starts from its own waveform.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 20, 14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
          child: WaveformPlayer(
            key: ValueKey('wf-${u['id']}'),
            audioUrl: '${file['audio_url']}',
            seed: int.tryParse('${u['id']}') ?? 0,
            durationHint: dur,
            trailing: file['bitrate'] != null ? '${file['bitrate']} kbps' : null,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(onPressed: () => _listen(u), icon: const Icon(Icons.queue_music_rounded, size: 18), label: const Text('Nghe trên thanh phát')),
        ),
      ],
      const SizedBox(height: 10),
      // Same-title songs (any composer): the count and the way to compare,
      // for every upload type.
      // Thay thế: the original song's name, no same-title check (it is
      // that song).
      if (u['type'] == 'replace')
        field('Tên bài', '${u['title'] ?? ''}', value: ReplaceTitle(upload: u, prefix: false, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text))))
      else
        field('Tên bài', u['title']?.toString(), status: _dupes == null
            ? null
            : (_dupes! > 0
                ? InkWell(
                    onTap: () => context.push('/search', extra: '${u['title']}'),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${formatInt(_dupes)} bài cùng tên · ', style: TextStyle(color: AppColors.warningText)),
                      TextSpan(text: 'So sánh ›', style: TextStyle(color: AppColors.accentLight)),
                    ]), style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                  )
                : _khoTag('bài mới', AppColors.textMuted))),
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
      SameRecordings(key: ValueKey('same-${u['id']}'), upload: u),
      // Bản nhạc: the scans sent vs the composer's sheet in the archive
      // (bản gốc + phiên bản), as on web /admin/gui-bai.
      if (u['type'] == 'sheet')
        SameSheets(key: ValueKey('sheets-${u['id']}'), upload: u)
      else if (images.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('ẢNH GỬI KÈM · ${images.length}', style: AppText.eyebrow),
        const SizedBox(height: 8),
        ImageStrip(urls: images),
      ],
      if (lyrics.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('LỜI GỬI KÈM', style: AppText.eyebrow),
        const SizedBox(height: 6),
        Builder(builder: (context) {
          final lines = lyrics.split('\n');
          final long = lines.length > _lyricsFold + 2;
          final shown = long && !_lyricsOpen ? lines.take(_lyricsFold).join('\n') : lyrics;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(shown, style: body(TextStyle(fontSize: 16, height: 1.6, color: AppColors.text))),
            if (long)
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => setState(() => _lyricsOpen = !_lyricsOpen),
                icon: Icon(_lyricsOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
                label: Text(_lyricsOpen ? 'Thu gọn' : 'Xem thêm (${lines.length - _lyricsFold} dòng)'),
              ),
          ]);
        }),
      ],
      const SizedBox(height: 20),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (!decided) ...[
          PillButton(label: 'Duyệt (A)', icon: Icons.check_rounded, loading: _busy, onTap: () => _decide('approve')),
          PillButton(label: 'Chưa chắc (N)', icon: Icons.help_outline_rounded, primary: false, onTap: _busy ? null : () => _decide('not_sure')),
          PillButton(label: 'Từ chối (R)', icon: Icons.close_rounded, primary: false, onTap: _busy ? null : () => _decide('reject')),
        ],
        PillButton(label: 'Sửa thông tin', icon: Icons.edit_outlined, primary: false, onTap: () async {
          final r = await context.push<String>('/bai-gui/${u['id']}');
          if (!mounted) return;
          // Decided or edited on the upload page: refresh this queue.
          if (r != null) { _load(); _loadCounts(); }
        }),
        const SizedBox(width: 12),
        // J and K wrap together, never split over two lines.
        Row(mainAxisSize: MainAxisSize.min, children: [_kbd('J', 'bài sau'), const SizedBox(width: 12), _kbd('K', 'bài trước')]),
      ]),
    ]);
  }
}
