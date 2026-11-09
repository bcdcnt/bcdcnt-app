import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import '../services/player.dart';
import '../widgets/ui.dart';

/// "Bàn làm việc" (desktop, members with manage_upload): the uploads
/// waiting for BQT in one place — queues with counts | list | detail with
/// the recording, the details sent, a possible-duplicate warning and the
/// decision. Keys: A duyệt, N chưa chắc, R từ chối, J/K bài sau/trước.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

const _queues = [
  ('pending', 'Bài gửi chờ duyệt'),
  ('not_sure', 'Chưa chắc chắn'),
  ('rejected', 'Đã từ chối'),
  ('approved', 'Đã duyệt'),
];

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  String _queue = 'pending';
  final Map<String, int> _counts = {};
  List<Map<String, dynamic>> _items = [];
  int _sel = 0;
  bool _loading = true;
  bool _busy = false;
  int? _dupes;
  final _focus = FocusNode();

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
    final parts = [for (final (k, _) in _queues) '$k: uploads(first: 1, where: {column: "status", value: "$k"}) { paginatorInfo { total } }'];
    try {
      final d = await _auth.authedQuery('query { ${parts.join(' ')} }');
      if (!mounted) return;
      setState(() {
        for (final (k, _) in _queues) {
          _counts[k] = (d[k]?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0;
        }
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _loading = true; _items = []; _sel = 0; _dupes = null; });
    try {
      final d = await _auth.authedQuery('query(\$s: Mixed) { uploads(first: 40, page: 1, where: {column: "status", value: \$s}, orderBy: [{column: "id", order: DESC}]) { data { $_fields } } }', {'s': _queue});
      if (!mounted) return;
      setState(() {
        _items = ((d['uploads']?['data'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
      _checkDupes();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? get _cur => _items.isEmpty ? null : _items[_sel.clamp(0, _items.length - 1)];

  /// Songs already in the archive under the same title.
  Future<void> _checkDupes() async {
    final u = _cur;
    setState(() => _dupes = null);
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
    if (e is! KeyDownEvent || _queue == 'approved') return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.keyJ) { _select(_sel + 1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.keyK) { _select(_sel - 1); return KeyEventResult.handled; }
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
              for (final (k, label) in _queues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: k == _queue ? AppColors.accentSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() => _queue = k);
                        _load();
                        _focus.requestFocus();
                      },
                      child: SizedBox(
                        height: 48,
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
                ),
            ]),
          ),
          // The list.
          Container(
            width: 320,
            decoration: BoxDecoration(border: Border(right: BorderSide(color: AppColors.borderSubtle))),
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                : _items.isEmpty
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Không còn bài nào ở đây.', style: AppText.bodyText)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
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
                                  Text('${u['title'] ?? '(chưa có tên)'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text))),
                                  const SizedBox(height: 2),
                                  Text('${u['user']?['username'] ?? ''} · ${timeago(u['created_at']?.toString())}', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Expanded(child: _cur == null ? const SizedBox.shrink() : _detail(_cur!)),
        ]),
      ),
    );
  }

  Widget _detail(Map<String, dynamic> u) {
    Widget field(String k, String? v) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted)))),
          Expanded(child: SelectableText(t, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)))),
        ]),
      );
    }

    final file = u['file'] is Map ? u['file'] as Map : const {};
    final dur = (file['duration'] as num?)?.toDouble();
    final lyrics = '${u['content'] ?? ''}'.replaceAll(RegExp(r'<br\s*/?>'), '\n').replaceAll(RegExp(r'<[^>]+>'), '').trim();
    Widget kbd(String k, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
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
    final decided = _queue == 'approved';
    return ListView(padding: const EdgeInsets.fromLTRB(36, 24, 36, 40), children: [
      Text('BÀI GỬI · ${'${u['user']?['username'] ?? ''}'.toUpperCase()} · ${timeago(u['created_at']?.toString()).toUpperCase()}', style: AppText.eyebrow),
      const SizedBox(height: 6),
      Text('${u['title'] ?? '(chưa có tên)'}', style: display(TextStyle(fontSize: 30, height: 1.15, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: AppColors.text))),
      const SizedBox(height: 16),
      if (file['audio_url'] != null)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: AppColors.wine, fixedSize: const Size(52, 52)),
              onPressed: () => _listen(u),
              icon: const Icon(Icons.play_arrow_rounded, size: 30, color: Colors.white),
              tooltip: 'Nghe bản gửi',
            ),
            const SizedBox(width: 14),
            Expanded(child: Text('Nghe bản gửi trên thanh phát', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)))),
            Text([if (dur != null && dur > 0) formatTime(dur), if (file['bitrate'] != null) '${file['bitrate']} kbps'].join(' · '), style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textSecondary))),
          ]),
        ),
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
      field('Loại', '${u['type'] ?? ''}'),
      field('Sáng tác', u['composers']?.toString()),
      field('Lời thơ', u['poets']?.toString()),
      field('Soạn giả', u['recomposers']?.toString()),
      field('Trình bày', u['artists']?.toString()),
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
        kbd('J', 'bài sau'),
        kbd('K', 'bài trước'),
      ]),
    ]);
  }
}
