import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import '../services/image_upload.dart';
import '../services/player.dart';
import '../services/upload_types.dart';
import '../widgets/desktop_page.dart';
import '../widgets/same_recordings.dart';
import '../widgets/upload_thread.dart';
import '../widgets/ui.dart' show PillButton, EmptyBlock, OfflineBlock, NetImage, typingInField;
import '../widgets/waveform_player.dart';

/// Bài gửi — xem & sửa (desktop, canvas "Desktop · Bài gửi — xem & sửa" +
/// Dân ca + Bổ sung bản ghi variants).
/// Left (≤780): the recording (video on demand), picture, then the details
/// as a form — the fields follow the upload's type; people are chips picked
/// from the archive. Right (320): status, and for BQT the decision.
/// Editable by BQT, and by the sender while it is waiting, unsure or refused.
/// Keys: A/N/R decide (not while typing), Ctrl/⌘+S saves. Pops 'decided' or
/// 'saved' so Bàn làm việc can refresh.
class UploadDetailDesktop extends StatefulWidget {
  final String id;
  const UploadDetailDesktop({super.key, required this.id});

  @override
  State<UploadDetailDesktop> createState() => _UploadDetailDesktopState();
}

const _fields = '''
  id title type status reason result link note source content year record_year karaoke_type accompaniment_instrument
  composers artists poets recomposers accompanists users fcats melodies
  pre_composers pre_artists pre_poets pre_recomposers pre_accompanists pre_fcats pre_melodies
  created_at file_id image_id
  user { id username } processor { id username }
  file { id audio_url video_url duration bitrate }
  thumbnail { id url }
  object { __typename
    ... on Song { id title thumbnail { url } sheet { composers(first: 3) { data { title } } } file { audio_url duration bitrate } }
    ... on Folk { id title thumbnail { url } file { audio_url duration bitrate } }
    ... on Instrumental { id title thumbnail { url } file { audio_url duration bitrate } }
    ... on Poem { id title thumbnail { url } file { audio_url duration bitrate } }
    ... on Karaoke { id title thumbnail { url } file { audio_url duration bitrate } }
  }
''';

/// People columns: upload field → (label, archive query, singular for *_list).
const _people = {
  'composers': ('Sáng tác', 'composers', 'composer'),
  'poets': ('Lời thơ', 'poets', 'poet'),
  'recomposers': ('Soạn giả', 'recomposers', 'recomposer'),
  'melodies': ('Làn điệu', 'melodies', 'melody'),
  'fcats': ('Thể loại dân ca', 'fcats', 'fcat'),
  'artists': ('Trình bày', 'artists', 'artist'),
  'accompanists': ('Người đệm', 'artists', 'accompanist'),
};

/// Which people / text fields each type has.
List<String> _peopleFor(String t) => switch (t) {
      'song' => ['composers', 'poets', 'artists', 'accompanists'],
      'folk' => ['recomposers', 'melodies', 'fcats', 'artists'],
      'instrumental' => ['composers', 'artists', 'accompanists'],
      'poem' => ['poets', 'artists'],
      'sheet' => ['composers', 'poets'],
      _ => const [],
    };
bool _has(String t, String f) => switch (f) {
      'year' => const {'song', 'instrumental', 'poem', 'sheet'}.contains(t),
      'record_year' => const {'song', 'folk', 'instrumental', 'poem', 'karaoke'}.contains(t),
      'accompaniment_instrument' => const {'song', 'instrumental'}.contains(t),
      'content' => !const {'replace', 'instrumental', 'karaoke', 'beat'}.contains(t),
      'link' => t != 'replace',
      'karaoke' => t == 'karaoke',
      _ => true,
    };

String _htmlToText(dynamic html) => '${html ?? ''}'
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</p>\s*', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
String _textToHtml(String t) => t.trim().isEmpty
    ? ''
    : t.trim().replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('\n', '<br>');

class _Person {
  final String? id;
  final String title;
  const _Person(this.id, this.title);
}

class _UploadDetailDesktopState extends State<UploadDetailDesktop> {
  Map<String, dynamic>? _u;
  bool _loading = true, _failed = false, _saving = false, _busy = false;
  String? _error;
  int? _dupes;

  // Form state.
  final _text = <String, TextEditingController>{};
  final _ppl = <String, List<_Person>>{};
  String _type = '';
  String _initial = '';

  /// Đổi file: null when idle, 0–1 while sending, -1 while the server converts.
  double? _fileProgress;
  bool _showVideo = false;
  bool _lyricsOpen = false;
  VideoPlayerController? _videoCtl;
  ChewieController? _chewie;
  final _focus = FocusNode();

  AuthProvider get _auth => context.read<AuthProvider>();

  @override
  void initState() {
    super.initState();
    // Shortcuts listen app-wide while this page is on top, so they keep
    // working when the keyboard focus fell out of the page (a closed panel).
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    for (final c in _text.values) {
      c.dispose();
    }
    _chewie?.dispose();
    _videoCtl?.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _failed = false; _error = null; });
    try {
      final d = await _auth.authedQuery('query(\$w: WhereConditions) { me { uploads(first: 1, where: \$w) { data { $_fields } } } }', {'w': {'column': 'id', 'value': widget.id}});
      final list = (d['me']?['uploads']?['data'] ?? []) as List;
      Map<String, dynamic>? u = list.isEmpty ? null : Map<String, dynamic>.from(list.first as Map);
      if (u == null && _auth.hasPermission('manage_upload')) {
        final d2 = await _auth.authedQuery('query(\$id: ID!) { upload(id: \$id) { $_fields } }', {'id': widget.id});
        if (d2['upload'] is Map) u = Map<String, dynamic>.from(d2['upload'] as Map);
      }
      if (!mounted) return;
      if (u == null) {
        setState(() { _loading = false; _error = 'Bài gửi này chỉ người gửi và BQT xem được, hoặc đã bị xoá.'; });
        return;
      }
      _fill(u);
      setState(() { _u = u; _loading = false; });
      _checkDupes();
      _resolvePeople();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  void _fill(Map<String, dynamic> u) {
    _type = '${u['type'] ?? ''}';
    String v(String k) => k == 'content' ? _htmlToText(u[k]) : '${u[k] ?? ''}'.trim();
    for (final k in ['title', 'source', 'link', 'note', 'content', 'year', 'record_year', 'accompaniment_instrument', 'karaoke_type', 'users']) {
      (_text[k] ??= TextEditingController()).text = v(k);
    }
    for (final k in _people.keys) {
      _ppl[k] = _parsePeople(u['pre_$k'], u[k]);
    }
    _initial = _snapshot();
  }

  /// pre_* holds [{id, title}] when the sender picked from the archive;
  /// otherwise only the text ("A - B" or "A, B").
  List<_Person> _parsePeople(dynamic pre, dynamic text) {
    try {
      final l = jsonDecode('${pre ?? ''}');
      if (l is List && l.isNotEmpty) {
        return [for (final e in l.whereType<Map>()) if ('${e['title'] ?? ''}'.trim().isNotEmpty) _Person(e['id'] == null ? null : '${e['id']}', '${e['title']}'.trim())];
      }
    } catch (_) {}
    return [for (final t in '${text ?? ''}'.split(RegExp(r'\s-\s|[,;]')).map((x) => x.trim()).where((x) => x.isNotEmpty)) _Person(null, t)];
  }

  /// Names typed without an id: look the exact title up so they show (and
  /// save) as archive entries when they are one.
  Future<void> _resolvePeople() async {
    final ask = <String, (String, int)>{};
    var n = 0;
    _ppl.forEach((k, list) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id == null) ask['p${n++}'] = (k, i);
      }
    });
    if (ask.isEmpty) return;
    final q = [for (final e in ask.entries) '${e.key}: ${_people[e.value.$1]!.$2}(first: 1, where: {column: "title", value: ${jsonEncode(_ppl[e.value.$1]![e.value.$2].title)}}) { data { id title } }'].join(' ');
    try {
      final d = await ApiClient.query('query { $q }');
      if (!mounted) return;
      final before = _snapshot();
      setState(() {
        for (final e in ask.entries) {
          final hit = ((d[e.key]?['data'] ?? []) as List).whereType<Map>().firstOrNull;
          final (k, i) = e.value;
          if (hit != null && i < _ppl[k]!.length) _ppl[k]![i] = _Person('${hit['id']}', _ppl[k]![i].title);
        }
      });
      // Only ids filled in: not an edit.
      if (_initial == before) _initial = _snapshot();
    } catch (_) {}
  }

  String _snapshot() => jsonEncode({
        'type': _type,
        for (final e in _text.entries) e.key: e.value.text,
        for (final e in _ppl.entries) e.key: [for (final p in e.value) '${p.id}|${p.title}'],
      });
  bool get _dirty => _u != null && _snapshot() != _initial;

  bool get _canEdit {
    final u = _u;
    if (u == null) return false;
    // Approved: the song is in the archive now; edits here would not reach it.
    if ('${u['status']}' == 'approved') return false;
    if (_auth.hasPermission('manage_upload')) return true;
    final mine = '${u['user']?['id']}' == '${_auth.user?['id']}';
    return mine && const {'pending', 'not_sure', 'rejected'}.contains('${u['status']}');
  }

  bool get _canDecide => _auth.hasPermission('manage_upload') && '${_u?['status']}' != 'approved';

  Future<void> _checkDupes() async {
    final t = _text['title']!.text.trim();
    final root = switch (_type) { 'song' => 'songs', 'folk' => 'folks', 'instrumental' => 'instrumentals', 'poem' => 'poems', 'karaoke' => 'karaokes', _ => null };
    if (t.isEmpty || root == null) { setState(() => _dupes = null); return; }
    try {
      final d = await ApiClient.query('query(\$q: String) { $root(first: 1, q: \$q) { paginatorInfo { total } } }', {'q': t});
      if (mounted && _text['title']!.text.trim() == t) setState(() => _dupes = (d[root]?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  Map<String, dynamic> _input() {
    final i = <String, dynamic>{'id': widget.id, 'type': _type};
    for (final k in ['title', 'source', 'link', 'note', 'year', 'record_year', 'accompaniment_instrument', 'karaoke_type', 'users']) {
      i[k] = _text[k]!.text.trim();
    }
    i['content'] = _textToHtml(_text['content']!.text);
    for (final k in _peopleFor(_type)) {
      final l = _ppl[k] ?? const [];
      final one = _people[k]!.$3;
      i[k] = l.map((p) => p.title).join(' - ');
      i['${one}_list'] = l.where((p) => p.id != null).map((p) => p.id).join(',');
      i['pre_$k'] = jsonEncode([for (final p in l) {if (p.id != null) 'id': p.id, 'title': p.title}]);
    }
    return i;
  }

  Future<bool> _save({bool quiet = false}) async {
    if (!_dirty || _saving) return true;
    if (_text['title']!.text.trim().isEmpty && _type != 'replace') {
      _snack('Tên bài không được để trống.', error: true);
      return false;
    }
    setState(() => _saving = true);
    try {
      await _auth.authedMutate(r'mutation($input: UpdateUploadInput!) { updateUpload(input: $input) { id } }', {'input': _input()});
      if (!mounted) return false;
      _initial = _snapshot();
      setState(() => _saving = false);
      if (!quiet) _snack('Đã lưu thay đổi');
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(friendlyError(e, fallback: 'Chưa lưu được, vui lòng thử lại.'), error: true);
      }
      return false;
    }
  }

  void _snack(String t, {bool error = false}) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t), backgroundColor: error ? AppColors.error : null, duration: const Duration(seconds: 2)));

  Future<void> _decide(String action) async {
    if (!_canDecide || _busy) return;
    String? reason;
    if (action == 'reject') {
      reason = await _askReason();
      if (reason == null) return;
    }
    // Pending edits go with the decision.
    if (_dirty && !await _save(quiet: true)) return;
    setState(() => _busy = true);
    try {
      await _auth.authedMutate(r'mutation($id: ID!, $action: String!, $reason: String) { processUpload(id: $id, action: $action, reason: $reason) { id status } }',
          {'id': widget.id, 'action': action, 'reason': ?reason});
      if (!mounted) return;
      _snack('${const {'approve': 'Đã duyệt', 'reject': 'Đã từ chối', 'not_sure': 'Đã chuyển sang Chưa chắc chắn'}[action]} “${_text['title']!.text}”');
      if (context.canPop()) {
        context.pop('decided');
      } else {
        _fetch();
      }
    } catch (e) {
      _snack(friendlyError(e), error: true);
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
        content: SizedBox(width: 420, child: TextField(controller: c, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: 'Ví dụ: trùng bản thu đã có, chất lượng kém…'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(onPressed: () { if (c.text.trim().isNotEmpty) Navigator.pop(ctx, c.text.trim()); }, child: const Text('Từ chối')),
        ],
      ),
    );
  }

  Future<void> _changeImage() async {
    final files = await pickImages();
    if (files.isEmpty || !mounted) return;
    _snack('Đang tải ảnh lên…');
    try {
      final img = await uploadImage(_auth, files.first, context: 'image');
      await _auth.authedMutate(r'mutation($input: UpdateUploadInput!) { updateUpload(input: $input) { id } }', {'input': {'id': widget.id, 'image_id': int.tryParse(img.id)}});
      if (!mounted) return;
      setState(() => _u!['thumbnail'] = {'id': img.id, 'url': img.url});
      _snack('Đã đổi ảnh');
    } catch (e) {
      _snack(friendlyError(e), error: true);
    }
  }

  Future<void> _changeFile() async {
    final f = await pickMedia();
    if (f == null || !mounted) return;
    setState(() => _fileProgress = 0);
    try {
      final file = await uploadMedia(_auth, f,
          onProgress: (p) { if (mounted) setState(() => _fileProgress = p); },
          onProcessing: () { if (mounted) setState(() => _fileProgress = -1); });
      final fileId = int.tryParse('${file['id']}');
      await _auth.authedMutate(r'mutation($input: UpdateUploadInput!) { updateUpload(input: $input) { id } }', {'input': {'id': widget.id, 'file_id': fileId}});
      if (!mounted) return;
      // Fresh file row (bitrate, duration) without touching unsaved edits.
      Map<String, dynamic> row = file;
      try {
        final d = await _auth.authedQuery(r'query($id: ID!) { upload(id: $id) { file { id audio_url video_url duration bitrate } } }', {'id': widget.id});
        if (d['upload']?['file'] is Map) row = Map<String, dynamic>.from(d['upload']['file'] as Map);
      } catch (_) {}
      if (!mounted) return;
      _chewie?.dispose();
      _videoCtl?.dispose();
      setState(() {
        _u!['file'] = row;
        _u!['file_id'] = fileId;
        _fileProgress = null;
        _showVideo = false;
        _chewie = null;
        _videoCtl = null;
      });
      _snack('Đã đổi file');
    } catch (e) {
      if (mounted) {
        setState(() => _fileProgress = null);
        _snack(friendlyError(e, fallback: 'Chưa đổi được file, vui lòng thử lại.'), error: true);
      }
    }
  }

  void _listen(String url, dynamic duration) {
    final song = <String, dynamic>{
      'id': 'upload-${widget.id}', 'title': _text['title']!.text, 'file_type': 'upload',
      'file': {'audio_url': url, 'duration': duration},
    };
    context.read<PlayerProvider>().playSong(song, [song], 'manual', 'Bài gửi');
  }

  Future<void> _toggleVideo(String url) async {
    if (_showVideo) { setState(() => _showVideo = false); _chewie?.pause(); return; }
    setState(() => _showVideo = true);
    if (_chewie != null) return;
    try { context.read<PlayerProvider>().pause(); } catch (_) {}
    final ctl = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await ctl.initialize();
      if (!mounted) { ctl.dispose(); return; }
      setState(() { _videoCtl = ctl; _chewie = ChewieController(videoPlayerController: ctl, autoPlay: true); });
    } catch (_) {
      ctl.dispose();
      if (mounted) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  bool _onHardwareKey(KeyEvent e) {
    // Only for the page on top: not under a dialog or another page.
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    return _onKey(_focus, e) == KeyEventResult.handled;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final hw = HardwareKeyboard.instance;
    if (k == LogicalKeyboardKey.keyS && (hw.isControlPressed || hw.isMetaPressed)) {
      if (_canEdit) _save();
      return KeyEventResult.handled;
    }
    // Typing in a field: letters are letters.
    final typing = typingInField();
    if (typing || !_canDecide || hw.isControlPressed || hw.isMetaPressed || hw.isAltPressed) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.keyA) { _decide('approve'); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.keyN) { _decide('not_sure'); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.keyR) { _decide('reject'); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  Future<bool> _confirmLeave() async {
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bỏ thay đổi chưa lưu?'),
        content: const Text('Các ô bạn vừa sửa chưa được lưu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: const Text('Ở lại')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Bỏ thay đổi')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Lưu rồi đi')),
        ],
      ),
    );
    if (r == 'save') return _save();
    return r == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthProvider>();
    if (_loading) return Material(color: AppColors.bg, child: const Center(child: CircularProgressIndicator()));
    if (_u == null) {
      return Material(
        color: AppColors.bg,
        child: Center(child: _failed ? OfflineBlock(onRetry: _fetch) : EmptyBlock(icon: Icons.description_outlined, title: 'Không xem được bài gửi', message: _error ?? '')),
      );
    }
    final player = context.watch<PlayerProvider>();
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) {
          _initial = _snapshot();
          if (context.mounted) context.pop(_dirty ? null : 'saved');
        }
      },
      child: Material(
        color: AppColors.bg,
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: DeskFrame(
            maxWidth: 1320,
            child: ListView(
              padding: deskPad.copyWith(bottom: player.currentSong != null ? 120 : 48),
              children: [
                _header(),
                const SizedBox(height: 18),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Align(alignment: Alignment.topLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 780), child: _left()))),
                  const SizedBox(width: 32),
                  SizedBox(width: 320, child: _right()),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final u = _u!;
    final own = '${u['title'] ?? ''}'.trim();
    final title = _type == 'replace' && (own.isEmpty || own.startsWith('http')) ? 'Thay thế bản thu chất lượng' : (own.isEmpty ? '(Không tên)' : own);
    final eyebrow = AppText.eyebrow;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('BÀI GỬI · ', style: eyebrow),
        InkWell(
          onTap: u['user']?['id'] == null ? null : () => context.push('/user/${u['user']['id']}'),
          child: Text('${u['user']?['username'] ?? ''}'.toUpperCase(), style: eyebrow.copyWith(decoration: TextDecoration.underline)),
        ),
        Text(' · ${timeago(u['created_at']?.toString()).toUpperCase()}', style: eyebrow),
      ]),
      const SizedBox(height: 4),
      Text(title, style: display(TextStyle(fontSize: 34, height: 1.15, letterSpacing: -0.6, fontWeight: FontWeight.w800, color: AppColors.text))),
    ]);
  }

  Widget _wave(Map file, {double button = 52, double height = 56}) => Container(
        padding: EdgeInsets.fromLTRB(16, button > 44 ? 14 : 10, 20, button > 44 ? 14 : 10),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(button > 44 ? 20 : 16)),
        child: WaveformPlayer(
          key: ValueKey('wf-${file['audio_url']}'),
          audioUrl: '${file['audio_url']}',
          seed: '${file['audio_url']}'.hashCode,
          height: height,
          buttonSize: button,
          durationHint: (file['duration'] as num?)?.toDouble(),
          trailing: file['bitrate'] != null ? '${file['bitrate']} kbps' : null,
        ),
      );

  Widget _left() {
    final u = _u!;
    final file = u['file'] is Map ? u['file'] as Map : const {};
    final edit = _canEdit;
    final link = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accentLight);
    final media = <Widget>[];
    if (_type == 'replace') {
      final obj = u['object'] is Map ? u['object'] as Map : null;
      if (obj != null) media.add(_targetCard(obj));
      if (file['audio_url'] != null) media..add(_label('FILE GỬI KÈM'))..add(_wave(file));
      if (edit) {
        media.add(Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _fileProgress != null ? null : _changeFile, child: Text(file['audio_url'] == null ? 'Thêm file' : 'Đổi file', style: link))));
        if (_fileProgress != null) {
          media.add(Row(children: [
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: _fileProgress! < 0 ? null : _fileProgress, minHeight: 6, color: AppColors.wine, backgroundColor: AppColors.surfaceLight))),
            const SizedBox(width: 12),
            Text(_fileProgress! < 0 ? 'Đang xử lý file…' : 'Đang tải lên ${(_fileProgress! * 100).round()}%', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
          ]));
        }
      }
      final cur = obj?['file'] is Map ? obj!['file'] as Map : null;
      if (cur?['audio_url'] != null) media..add(_label('FILE ĐANG CÓ TRÊN BÀI'))..add(_wave(cur!, button: 40, height: 36));
    } else {
      final thumb = u['thumbnail']?['url']?.toString();
      media.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (file['audio_url'] != null) _wave(file),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 14, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if ('${file['video_url'] ?? ''}'.isNotEmpty)
                  ActionChip(
                    avatar: Icon(_showVideo ? Icons.close_rounded : Icons.play_arrow_rounded, size: 18),
                    label: Text(_showVideo ? 'Ẩn video' : 'Xem video'),
                    onPressed: () => _toggleVideo('${file['video_url']}'),
                  ),
                if (edit) TextButton(onPressed: _fileProgress != null ? null : _changeFile, child: Text(file['audio_url'] == null ? 'Thêm file' : 'Đổi file', style: link)),
                if (file['audio_url'] != null) TextButton.icon(onPressed: () => _listen('${file['audio_url']}', file['duration']), icon: const Icon(Icons.queue_music_rounded, size: 18), label: Text('Nghe trên thanh phát', style: link)),
              ]),
            ),
            if (_fileProgress != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Row(children: [
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: _fileProgress! < 0 ? null : _fileProgress, minHeight: 6, color: AppColors.wine, backgroundColor: AppColors.surfaceLight))),
                  const SizedBox(width: 12),
                  Text(_fileProgress! < 0 ? 'Đang xử lý file…' : 'Đang tải lên ${(_fileProgress! * 100).round()}%', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                ]),
              ),
            if (_showVideo)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _chewie == null
                          ? AspectRatio(aspectRatio: 16 / 9, child: Container(color: AppColors.surfaceLight, alignment: Alignment.center, child: const CircularProgressIndicator(strokeWidth: 2)))
                          : AspectRatio(aspectRatio: _videoCtl!.value.aspectRatio == 0 ? 16 / 9 : _videoCtl!.value.aspectRatio, child: Chewie(controller: _chewie!)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        if (thumb != null || edit) ...[
          const SizedBox(width: 16),
          Column(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: thumb != null
                  ? NetImage(url: thumb, width: 132, height: 132)
                  : Container(width: 132, height: 132, color: AppColors.surface, child: Icon(Icons.image_outlined, color: AppColors.textMuted, size: 36)),
            ),
            if (edit) TextButton(onPressed: _changeImage, child: Text(thumb == null ? 'Thêm ảnh' : 'Đổi ảnh', style: link)),
          ]),
        ],
      ]));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...media,
      const SizedBox(height: 22),
      Text('Thông tin bài gửi', style: body(TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text))),
      const SizedBox(height: 12),
      ..._form(edit),
      if (edit)
        Padding(
          padding: const EdgeInsets.only(left: 142, top: 8),
          child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            // Dimmed until something changed.
            Opacity(opacity: _dirty ? 1 : 0.45, child: PillButton(label: 'Lưu thay đổi', icon: Icons.check_rounded, loading: _saving, onTap: _dirty ? () => _save() : null)),
            Opacity(opacity: _dirty ? 1 : 0.45, child: PillButton(label: 'Huỷ', primary: false, onTap: _dirty ? () => setState(() => _fill(_u!)) : null)),
            Text('Ctrl+S để lưu', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
          ]),
        ),
      SameRecordings(upload: {..._u!, 'type': _type, 'title': _text['title']!.text, 'composers': (_ppl['composers'] ?? const []).map((p) => p.title).join(', '), 'artists': (_ppl['artists'] ?? const []).map((p) => p.title).join(', ')}),
    ]);
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(t, style: body(TextStyle(fontSize: 13, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted))));

  Widget _targetCard(Map obj) {
    final tn = '${obj['__typename'] ?? 'Song'}';
    final composers = (((obj['sheet']?['composers']?['data']) as List?) ?? const []).whereType<Map>().map((c) => '${c['title']}').join(', ');
    final br = obj['file']?['bitrate'];
    return Material(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/song/${obj['id']}', extra: {...Map<String, dynamic>.from(obj), 'file_type': tn.toLowerCase()}),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: obj['thumbnail']?['url'] != null ? NetImage(url: '${obj['thumbnail']['url']}', width: 56, height: 56) : Container(width: 56, height: 56, color: AppColors.surface, child: Icon(Icons.music_note_rounded, color: AppColors.textMuted)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('BỔ SUNG CHO BÀI', style: AppText.eyebrow),
                Text('${obj['title'] ?? ''}', style: body(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text))),
                Text([if (composers.isNotEmpty) 'Nhạc sĩ $composers', if (br != null) 'bản hiện tại: $br kbps'].join(' · '), style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary))),
              ]),
            ),
            Text('Mở bài ›', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
          ]),
        ),
      ),
    );
  }

  List<Widget> _form(bool edit) {
    Widget row(String label, Widget field, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Padding(padding: const EdgeInsets.only(top: 12), child: Text(label, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted))))),
            const SizedBox(width: 12),
            Expanded(child: field),
            if (trailing != null) ...[const SizedBox(width: 12), Padding(padding: const EdgeInsets.only(top: 12), child: trailing)],
          ]),
        );
    Widget text(String k, {String? hint, int lines = 1, double? width, TextInputType? keyboard}) {
      final c = _text[k]!;
      if (!edit) {
        // Long lyrics fold to 8 lines, as in Bàn làm việc.
        final lines = c.text.split('\n');
        final long = k == 'content' && lines.length > 10;
        return Padding(
          padding: const EdgeInsets.only(top: 11),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(c.text.isEmpty ? '—' : (long && !_lyricsOpen ? lines.take(8).join('\n') : c.text), style: body(TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w600, color: AppColors.text))),
            if (long)
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => setState(() => _lyricsOpen = !_lyricsOpen),
                icon: Icon(_lyricsOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
                label: Text(_lyricsOpen ? 'Thu gọn' : 'Xem thêm (${lines.length - 8} dòng)'),
              ),
          ]),
        );
      }
      final f = TextField(
        controller: c,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 30,
        keyboardType: keyboard,
        onChanged: (_) => setState(() {}),
        style: body(TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w600, color: AppColors.text)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border, width: 1.5)),
        ),
      );
      return width == null ? f : Align(alignment: Alignment.centerLeft, child: SizedBox(width: width, child: f));
    }

    final t = _type;
    final out = <Widget>[];
    // Read-only: rows with nothing in them are left out.
    bool blank(String k) => !edit && _text[k]!.text.trim().isEmpty;
    if (t == 'replace') {
      out
        ..addAll([if (!blank('note')) row('Ghi chú', text('note', hint: 'Ghi chú cho BQT', lines: 2))])
        ..addAll([if (!blank('source')) row('Nguồn', text('source', hint: 'Ví dụ: Đài TNVN'))]);
      return out;
    }
    out.add(row('Tên bài', text('title'), trailing: _dupesTag()));
    out.add(row(
      'Loại',
      edit
          ? Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  initialValue: kUploadTypeLabels.containsKey(t) ? t : null,
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border, width: 1.5)),
                  ),
                  items: [for (final e in kUploadTypeLabels.entries) if (e.key != 'replace') DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _type = v);
                    _checkDupes();
                  },
                ),
              ),
            )
          : Padding(padding: const EdgeInsets.only(top: 11), child: Text(uploadTypeLabel(t), style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)))),
    ));
    for (final k in _peopleFor(t)) {
      if (!edit && (_ppl[k] ?? const []).isEmpty) continue;
      final label = (t == 'poem' && k == 'artists') ? 'Người đọc' : _people[k]!.$1;
      out.add(row(label, _PeopleField(
        key: ValueKey('ppl-$k'),
        people: _ppl[k] ?? const [],
        search: _people[k]!.$2,
        editable: edit,
        onChanged: (l) => setState(() => _ppl[k] = l),
      )));
      if (k == 'accompanists' && !blank('accompaniment_instrument')) out.add(row('Nhạc cụ đệm', text('accompaniment_instrument', hint: 'Ví dụ: đàn bầu, piano')));
    }
    if (_has(t, 'karaoke')) {
      if (!blank('users')) out.add(row('Thành viên hát', text('users', hint: 'Tên thành viên, cách nhau bằng dấu phẩy')));
      if (!blank('karaoke_type')) out.add(row('Kiểu bản thu', text('karaoke_type')));
    }
    final years = <Widget>[];
    final showYear = _has(t, 'year') && !blank('year');
    if (showYear) years.add(text('year', width: 120, keyboard: TextInputType.number));
    if (_has(t, 'record_year') && !blank('record_year')) {
      if (years.isNotEmpty) {
        years..add(const SizedBox(width: 16))..add(Padding(padding: const EdgeInsets.only(top: 12), child: Text('Năm thu', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted)))))..add(const SizedBox(width: 12));
      }
      years.add(text('record_year', width: 120, keyboard: TextInputType.number));
    }
    if (years.isNotEmpty) out.add(row(showYear ? 'Năm sáng tác' : 'Năm thu', Row(crossAxisAlignment: CrossAxisAlignment.start, children: years)));
    if (!blank('source')) out.add(row('Nguồn', text('source', hint: 'Ví dụ: Đài TNVN, băng cá nhân')));
    if (_has(t, 'link') && !blank('link')) out.add(row('Link', text('link', hint: 'https://…')));
    if (!blank('note')) out.add(row('Ghi chú', text('note', hint: 'Ghi chú cho BQT', lines: 2)));
    if (_has(t, 'content') && !blank('content')) out.add(row(t.startsWith('document') || t == 'discussion' ? 'Nội dung' : 'Lời', text('content', lines: 5)));
    return out;
  }

  Widget? _dupesTag() {
    if (_dupes == null) return null;
    if (_dupes == 0) return Text('bài mới', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textMuted)));
    return InkWell(
      onTap: () => context.push('/search', extra: _text['title']!.text),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '${formatInt(_dupes)} bài cùng tên · ', style: TextStyle(color: AppColors.warningText)),
        TextSpan(text: 'So sánh ›', style: TextStyle(color: AppColors.accentLight)),
      ]), style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
    );
  }

  Widget _right() {
    final u = _u!;
    final st = '${u['status'] ?? 'pending'}';
    final who = u['processor']?['username'];
    final (Color bg, Color fg, IconData icon, String label) = switch (st) {
      'approved' => (AppColors.successText.withValues(alpha: 0.12), AppColors.successText, Icons.check_circle_outline, 'Đã duyệt'),
      'rejected' => (AppColors.errorText.withValues(alpha: 0.1), AppColors.errorText, Icons.cancel_outlined, 'Bị từ chối'),
      'not_sure' => (AppColors.warningText.withValues(alpha: 0.12), AppColors.warningText, Icons.help_outline, 'Chưa chắc chắn'),
      _ => (AppColors.warningText.withValues(alpha: 0.12), AppColors.warningText, Icons.access_time, 'Chờ duyệt'),
    };
    final small = body(TextStyle(fontSize: 13, height: 1.45, color: AppColors.textSecondary));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: fg),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg))),
              Text([uploadTypeLabel(_type), if (who != null) 'BQT: $who', 'gửi ${timeago(u['created_at']?.toString())}'].join(' · '), style: small),
            ])),
          ]),
          if (st == 'rejected' && '${u['reason'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text.rich(TextSpan(children: [const TextSpan(text: 'Phản hồi: ', style: TextStyle(fontWeight: FontWeight.w800)), TextSpan(text: '${u['reason']}')]), style: body(TextStyle(fontSize: 14, height: 1.45, color: AppColors.text))),
          ],
          if (st == 'approved' && '${u['result'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                final r = uploadResultRoute('${u['result']}');
                if (r != null) {
                  context.push(r.path, extra: r.extra);
                } else {
                  launchUrl(Uri.parse('${u['result']}'), mode: LaunchMode.externalApplication);
                }
              },
              child: Text('Xem kết quả ›', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg))),
            ),
          ],
          const SizedBox(height: 8),
          Text(_canEdit ? (st == 'rejected' ? 'Sửa lại các ô rồi lưu để BQT xem lại.' : 'Bạn sửa được các ô bên trái.') : 'Các ô chỉ để xem.', style: small),
        ]),
      ),
      if (_canDecide) ...[
        const SizedBox(height: 16),
        Text('BQT', style: body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted))),
        const SizedBox(height: 4),
        for (final (a, l, i, p) in [('approve', 'Duyệt (A)', Icons.check_rounded, true), ('not_sure', 'Chưa chắc (N)', Icons.help_outline_rounded, false), ('reject', 'Từ chối (R)', Icons.close_rounded, false)])
          if (!(a == 'not_sure' && st == 'not_sure'))
            Padding(padding: const EdgeInsets.only(top: 8), child: PillButton(label: l, icon: i, primary: p, loading: p && _busy, onTap: _busy ? null : () => _decide(a))),
        if (_dirty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Thay đổi chưa lưu sẽ được lưu trước khi duyệt.', style: small)),
      ],
      const SizedBox(height: 22),
      UploadThread(uploadId: widget.id, senderId: '${u['user']?['id'] ?? ''}'),
    ]);
  }
}

/// People as chips with an inline search: picked from the archive shows
/// "✓ đã khớp kho"; a typed name (Enter) shows "chưa có trong kho · tạo mới".
class _PeopleField extends StatefulWidget {
  final List<_Person> people;
  final String search;
  final bool editable;
  final ValueChanged<List<_Person>> onChanged;
  const _PeopleField({super.key, required this.people, required this.search, required this.editable, required this.onChanged});

  @override
  State<_PeopleField> createState() => _PeopleFieldState();
}

class _PeopleFieldState extends State<_PeopleField> {
  final _ctl = TextEditingController();
  List<Map<String, dynamic>> _hits = const [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _query(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) { setState(() => _hits = const []); return; }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final d = await ApiClient.query('query(\$q: Mixed) { ${widget.search}(first: 6, where: {column: "title", operator: LIKE, value: \$q}) { data { id title } } }', {'q': '%${q.trim()}%'});
        if (mounted && _ctl.text == q) setState(() => _hits = ((d[widget.search]?['data'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
      } catch (_) {}
    });
  }

  void _add(_Person p) {
    if (widget.people.any((x) => x.title.toLowerCase() == p.title.toLowerCase())) return;
    widget.onChanged([...widget.people, p]);
    _ctl.clear();
    setState(() => _hits = const []);
  }

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (var i = 0; i < widget.people.length; i++)
        Container(
          height: 32,
          padding: EdgeInsets.only(left: 12, right: widget.editable ? 4 : 12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.people[i].title, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
            const SizedBox(width: 8),
            widget.people[i].id != null
                ? Text('✓ đã khớp kho', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.successText)))
                : Text('chưa có trong kho${widget.editable ? ' · tạo mới' : ''}', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.warningText))),
            if (widget.editable)
              IconButton(
                tooltip: 'Bỏ ${widget.people[i].title}',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                onPressed: () => widget.onChanged([...widget.people]..removeAt(i)),
              ),
          ]),
        ),
    ];
    if (!widget.editable) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: chips.isEmpty ? Text('—', style: body(TextStyle(fontSize: 15, color: AppColors.text))) : Wrap(spacing: 8, runSpacing: 6, children: chips),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border, width: 1.5)),
        child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ...chips,
          SizedBox(
            width: 200,
            child: TextField(
              controller: _ctl,
              onChanged: _query,
              onSubmitted: (v) {
                final t = v.trim();
                if (t.isEmpty) return;
                final exact = _hits.where((h) => '${h['title']}'.toLowerCase() == t.toLowerCase()).firstOrNull;
                _add(exact != null ? _Person('${exact['id']}', '${exact['title']}') : _Person(null, t));
              },
              style: body(TextStyle(fontSize: 14, color: AppColors.text)),
              decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), hintText: 'Thêm…', hintStyle: body(TextStyle(fontSize: 14, color: AppColors.textMuted))),
            ),
          ),
        ]),
      ),
      if (_hits.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            for (final h in _hits)
              ListTile(
                dense: true,
                title: Text('${h['title']}', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
                trailing: Text('trong kho', style: body(TextStyle(fontSize: 12, color: AppColors.successText))),
                onTap: () => _add(_Person('${h['id']}', '${h['title']}')),
              ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.add_rounded, size: 18),
              title: Text('Thêm “${_ctl.text.trim()}” (chưa có trong kho)', style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary))),
              onTap: () => _add(_Person(null, _ctl.text.trim())),
            ),
          ]),
        ),
    ]);
  }
}

