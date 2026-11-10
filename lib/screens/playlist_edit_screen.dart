import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import '../services/image_upload.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/song_row.dart' show SongCover, songByline;
import '../widgets/ui.dart' show goBack, OfflineBlock;

/// "Sửa playlist" — `/playlist/:id/sua`, and "Tạo playlist" for BQT —
/// `/playlist-moi`. Nothing is sent until Lưu: name, giới thiệu, ảnh bìa,
/// công khai, songs taken out and the new order go in one updatePlaylist.
/// BQT (manage_playlist) also get a foldable box: tóm tắt, playlist sự
/// kiện, ghim, playlist hệ thống. Pops with 'saved' or 'deleted'.
class PlaylistEditScreen extends StatefulWidget {
  /// null: a new playlist (BQT only; members name one in a dialog).
  final String? id;
  const PlaylistEditScreen({super.key, this.id});

  @override
  State<PlaylistEditScreen> createState() => _PlaylistEditScreenState();
}

const _itemObject = '''object {
  __typename
  ... on Song { id title thumbnail { url } artists(first: 3) { data { id title } } }
  ... on Folk { id title thumbnail { url } artists(first: 3) { data { id title } } }
  ... on Instrumental { id title thumbnail { url } artists(first: 3) { data { id title } } }
  ... on Poem { id title thumbnail { url } artists(first: 3) { data { id title } } }
  ... on Karaoke { id title thumbnail { url } users(first: 3) { data { id username } } }
}''';

/// Asks before a playlist is deleted, then deletes it. True when it's gone.
Future<bool> confirmDeletePlaylist(BuildContext context, {required String id, required String title, int? songs}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Xoá playlist?', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text))),
      content: Text(
        'Playlist “$title”${songs != null ? ' ($songs bài)' : ''} sẽ bị xoá và không lấy lại được. Các bài hát vẫn còn trên trang.',
        style: body(TextStyle(fontSize: 16, height: 1.5, color: AppColors.textSecondary)),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Huỷ', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48), backgroundColor: const Color(0xFFA32020), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Xoá', style: body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await context.read<AuthProvider>().authedMutate(r'mutation($id: ID!) { deletePlaylist(id: $id) { id } }', {'id': id});
    messenger?.showSnackBar(SnackBar(content: Text('Đã xoá playlist “$title”')));
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error));
    return false;
  }
}

/// Giới thiệu written on the web may carry pictures, links, bold…: the app
/// only edits plain paragraphs, so anything else stays as it is.
bool _isRich(String html) => RegExp(r'<(?!/?(p|br)\b)[a-z/]', caseSensitive: false).hasMatch(html);

String _htmlToText(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</p>\s*<p[^>]*>', caseSensitive: false), '\n\n')
    .replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&')
    .trim();

String _textToHtml(String text) {
  final esc = text.trim().replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  if (esc.isEmpty) return '';
  return esc.split(RegExp(r'\n\s*\n')).map((p) => '<p>${p.trim().replaceAll('\n', '<br>')}</p>').join();
}

/// "MM-DD" ↔ "DD/MM", "YYYY-MM-DD" ↔ "DD/MM/YYYY" (how BQT read dates).
String _md(String? v) => v == null || v.length < 5 ? '' : '${v.substring(3, 5)}/${v.substring(0, 2)}';
String _ymd(String? v) => v == null || v.length < 10 ? '' : '${v.substring(8, 10)}/${v.substring(5, 7)}/${v.substring(0, 4)}';

class _PlaylistEditScreenState extends State<PlaylistEditScreen> {
  static const _bqtOpenKey = 'playlist_edit_bqt_open';

  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  Map<String, dynamic> _orig = {};

  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _excerpt = TextEditingController();
  bool _descRich = false;
  bool _public = true;
  String? _imageId;
  String? _imageUrl;
  bool _uploading = false;
  List<String> _songThumbs = [];

  /// {itemId, song} in the order they will be saved.
  List<Map<String, dynamic>> _items = [];
  final Set<String> _removed = {};
  int _itemTotal = 0;

  // BQT
  bool _bqtOpen = false;
  bool _event = false;
  String? _eventDate; // YYYY-MM-DD
  String? _eventStart; // MM-DD
  String? _eventEnd; // MM-DD
  bool _useCover = false;
  bool _sticky = false;
  bool _system = false;

  bool get _isNew => widget.id == null;
  bool get _isBqt => context.read<AuthProvider>().hasPermission('manage_playlist');

  @override
  void initState() {
    super.initState();
    if (_isNew) {
      _loading = false;
      _public = true;
      _bqtOpen = true;
    } else {
      // Opened straight from a link: wait for the saved login first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _auth = context.read<AuthProvider>()..addListener(_fetchOnce);
        _fetchOnce();
      });
    }
  }

  AuthProvider? _auth;
  bool _fetched = false;

  void _fetchOnce() {
    if (_fetched || !mounted || _auth!.loading) return;
    _fetched = true;
    _fetch();
  }

  @override
  void dispose() {
    _auth?.removeListener(_fetchOnce);
    _title.dispose();
    _desc.dispose();
    _excerpt.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _failed = false; });
    try {
      final auth = context.read<AuthProvider>();
      final data = await auth.authedQuery('''query(\$id: ID!) {
        playlist(id: \$id) {
          id title description excerpt is_public is_sticky is_system event_start event_end event_date event_use_cover
          image_id thumbnail { url } user { id }
          items(first: 500, orderBy: [{column: "position", order: ASC}]) {
            data { id $_itemObject }
            paginatorInfo { total }
          }
        }
      }''', {'id': widget.id});
      final pl = data['playlist'];
      if (pl == null) throw Exception('Không tìm thấy playlist');
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final items = <Map<String, dynamic>>[];
      for (final e in ((pl['items']?['data'] ?? []) as List)) {
        final obj = e['object'];
        if (obj == null) continue;
        final song = Map<String, dynamic>.from(obj as Map);
        if (song['users']?['data'] != null) {
          song['artists'] = {'data': [for (final u in song['users']['data'] as List) {'id': u['id'], 'title': u['username']}]};
        }
        items.add({'itemId': e['id'].toString(), 'song': song});
      }
      final desc = (pl['description'] ?? '').toString();
      setState(() {
        _orig = Map<String, dynamic>.from(pl);
        _title.text = (pl['title'] ?? '').toString();
        _descRich = _isRich(desc);
        _desc.text = _descRich ? desc.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim() : _htmlToText(desc);
        _excerpt.text = (pl['excerpt'] ?? '').toString();
        _public = pl['is_public']?.toString() == '1';
        final img = int.tryParse('${pl['image_id'] ?? 0}') ?? 0;
        _imageId = img > 0 ? '$img' : null;
        final String? thumb = pl['thumbnail']?['url']?.toString();
        _imageUrl = img > 0 ? thumb : null;
        _items = items;
        _origOrder = [for (final i in items) i['itemId'] as String];
        _itemTotal = pl['items']?['paginatorInfo']?['total'] ?? items.length;
        _songThumbs = [for (final i in items.take(4)) if (i['song']['thumbnail']?['url'] != null) i['song']['thumbnail']['url'].toString()];
        _eventStart = pl['event_start'];
        _eventEnd = pl['event_end'];
        _eventDate = pl['event_date'];
        _event = _eventStart != null || _eventDate != null;
        _useCover = pl['event_use_cover'] == 'Y';
        _sticky = pl['is_sticky'] == 'Y';
        _system = pl['is_system']?.toString() == '1';
        _bqtOpen = _event || (prefs.getBool(_bqtOpenKey) ?? false);
        _loading = false;
      });
    } catch (e) {
      debugPrint('playlist edit: $e');
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  bool get _dirty {
    if (_isNew) return _title.text.trim().isNotEmpty;
    final o = _orig;
    final img = int.tryParse('${o['image_id'] ?? 0}') ?? 0;
    return _title.text.trim() != (o['title'] ?? '') ||
        (!_descRich && _textToHtml(_desc.text) != _textToHtml(_htmlToText((o['description'] ?? '').toString()))) ||
        _public != (o['is_public']?.toString() == '1') ||
        (_imageId ?? '0') != '$img' ||
        _removed.isNotEmpty ||
        _orderChanged ||
        _excerpt.text.trim() != (o['excerpt'] ?? '').toString().trim() ||
        (_event ? _eventStart : null) != o['event_start'] ||
        (_event ? _eventEnd : null) != o['event_end'] ||
        (_event ? _eventDate : null) != o['event_date'] ||
        _useCover != (o['event_use_cover'] == 'Y') ||
        _sticky != (o['is_sticky'] == 'Y') ||
        _system != (o['is_system']?.toString() == '1');
  }

  List<String> _origOrder = [];
  bool get _orderChanged {
    final now = [for (final i in _items) i['itemId'] as String];
    final before = _origOrder.where((id) => !_removed.contains(id)).toList();
    return now.join(',') != before.join(',');
  }

  Future<void> _cancel() async {
    if (!_dirty) {
      goBack(context);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bỏ thay đổi?', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text))),
        content: Text('Những gì bạn vừa sửa sẽ không được lưu.', style: body(TextStyle(fontSize: 16, height: 1.5, color: AppColors.textSecondary))),
        actions: [
          TextButton(style: TextButton.styleFrom(minimumSize: const Size(48, 48)), onPressed: () => Navigator.pop(ctx, false), child: Text('Sửa tiếp', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)))),
          TextButton(style: TextButton.styleFrom(minimumSize: const Size(48, 48)), onPressed: () => Navigator.pop(ctx, true), child: Text('Bỏ thay đổi', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.errorText)))),
        ],
      ),
    );
    if (leave == true && mounted) goBack(context);
  }

  Future<void> _pickCover() async {
    final files = await pickImages();
    if (files.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    try {
      final img = await uploadImage(context.read<AuthProvider>(), files.first, context: 'playlist');
      if (!mounted) return;
      setState(() { _imageId = img.id; _imageUrl = img.url; _uploading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error));
    }
  }

  Future<void> _pickDate({required bool full, required String? current, required ValueChanged<String> onPicked}) async {
    final now = DateTime.now();
    DateTime initial = now;
    if (current != null && full && current.length >= 10) initial = DateTime.tryParse(current) ?? now;
    if (current != null && !full && current.length >= 5) initial = DateTime(now.year, int.parse(current.substring(0, 2)), int.parse(current.substring(3, 5)));
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1800),
      lastDate: DateTime(now.year + 5),
      helpText: full ? 'Ngày sự kiện' : 'Chọn ngày (năm nào cũng được)',
    );
    if (d == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    onPicked(full ? '${d.year}-${two(d.month)}-${two(d.day)}' : '${two(d.month)}-${two(d.day)}');
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (title.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Hãy đặt tên cho playlist')));
      return;
    }
    if (_event && (_eventStart == null || _eventEnd == null)) {
      messenger.showSnackBar(const SnackBar(content: Text('Playlist sự kiện cần ngày bắt đầu và kết thúc hiện ở trang chủ')));
      return;
    }
    final auth = context.read<AuthProvider>();
    final bqt = _isBqt;
    setState(() => _saving = true);
    final input = <String, dynamic>{
      'title': title,
      if (!_descRich) 'description': _textToHtml(_desc.text),
      'is_public': _public ? '1' : '0',
      'image_id': int.tryParse(_imageId ?? '0') ?? 0,
      if (bqt) ...{
        'excerpt': _excerpt.text.trim(),
        'event_start': _event ? _eventStart : null,
        'event_end': _event ? _eventEnd : null,
        'event_date': _event ? _eventDate : null,
        'event_use_cover': _useCover ? 'Y' : 'N',
      },
    };
    try {
      String id;
      if (_isNew) {
        final r = await auth.authedMutate(r'mutation($input: CreatePlaylistInput!) { createPlaylist(input: $input) { id } }', {'input': input});
        id = r['createPlaylist']['id'].toString();
      } else {
        id = widget.id!;
        input['id'] = id;
        if (_removed.isNotEmpty || _orderChanged) {
          input['items'] = {
            if (_removed.isNotEmpty) 'delete': _removed.toList(),
            if (_orderChanged) 'update': [for (var i = 0; i < _items.length; i++) {'id': _items[i]['itemId'], 'position': i + 1}],
          };
        }
        await auth.authedMutate(r'mutation($input: UpdatePlaylistInput!) { updatePlaylist(input: $input) { id } }', {'input': input});
      }
      if (bqt && _sticky != (_orig['is_sticky'] == 'Y')) {
        await auth.authedMutate(r'mutation($id: ID!, $v: String!) { stickyPlaylist(id: $id, is_sticky: $v) { id } }', {'id': id, 'v': _sticky ? 'Y' : 'N'});
      }
      if (bqt && _system != (_orig['is_system']?.toString() == '1')) {
        await auth.authedMutate(r'mutation($id: ID!, $v: String!) { systemPlaylist(id: $id, is_system: $v) { id } }', {'id': id, 'v': _system ? '1' : '0'});
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(_isNew ? 'Đã tạo playlist “$title”' : 'Đã lưu playlist')));
      if (_isNew) {
        context.pushReplacement('/playlist/$id');
      } else {
        context.pop('saved');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error));
    }
  }

  Future<void> _delete() async {
    final gone = await confirmDeletePlaylist(context, id: widget.id!, title: _title.text.trim(), songs: _itemTotal);
    if (gone && mounted) context.pop('deleted');
  }

  @override
  Widget build(BuildContext context) {
    final bqt = context.watch<AuthProvider>().hasPermission('manage_playlist');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _cancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          leadingWidth: 76,
          leading: TextButton(
            onPressed: _saving ? null : _cancel,
            child: Text('Huỷ', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
          ),
          title: Text(_isNew ? 'Tạo playlist' : 'Sửa playlist'),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.wine, minimumSize: const Size(64, 40), shape: const StadiumBorder()),
                onPressed: _saving || _loading || _failed || _uploading ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isNew ? 'Tạo' : 'Lưu', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white))),
              ),
            ),
          ],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: AppColors.accentFg))
            : _failed
                ? Center(child: OfflineBlock(onRetry: _fetch))
                : _form(bqt),
      ),
    );
  }

  Widget _label(String text, [String? note]) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text),
          if (note != null) TextSpan(text: ' $note', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        ]), style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
      );

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.wine, width: 2)),
      );

  Widget _switch(String title, String? sub, bool value, ValueChanged<bool> onChanged) => MergeSemantics(
        child: InkWell(
          onTap: () => setState(() => onChanged(!value)),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
                  if (sub != null) ...[
                    const SizedBox(height: 3),
                    Text(sub, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4, color: AppColors.textMuted))),
                  ],
                ]),
              ),
              const SizedBox(width: 12),
              Switch(value: value, activeTrackColor: AppColors.wine, onChanged: (v) => setState(() => onChanged(v))),
            ]),
          ),
        ),
      );

  Widget _dateBox(String label, String shown, String hint, VoidCallback onTap, {VoidCallback? onClear}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Text(label, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)))),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.only(left: 16, right: 6),
                child: Row(children: [
                  Expanded(child: Text(shown.isEmpty ? hint : shown, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: shown.isEmpty ? AppColors.textMuted : AppColors.text)))),
                  if (onClear != null && shown.isNotEmpty)
                    IconButton(tooltip: 'Xoá $label', onPressed: onClear, icon: Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted))
                  else
                    Padding(padding: const EdgeInsets.all(10), child: Icon(Icons.calendar_today_rounded, size: 20, color: AppColors.textMuted)),
                ]),
              ),
            ),
          ),
        ]),
      );

  Widget _form(bool bqt) {
    final cover = Row(children: [
      Stack(alignment: Alignment.center, children: [
        PlaylistCover(thumb: _imageUrl, songThumbs: _songThumbs, size: 88, radius: 14, ownFirst: true),
        if (_uploading) const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
      ]),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.surface, foregroundColor: AppColors.text, minimumSize: const Size(48, 44), shape: const StadiumBorder()),
            onPressed: _uploading ? null : _pickCover,
            child: Text(_imageId == null ? 'Chọn ảnh' : 'Đổi ảnh', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          ),
          if (_imageId != null)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
              onPressed: _uploading ? null : () => setState(() { _imageId = null; _imageUrl = null; }),
              child: Text('Bỏ ảnh, lấy từ các bài', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.errorText))),
            ),
        ]),
      ),
    ]);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: [
        _label('Tên playlist'),
        TextField(
          controller: _title,
          autofocus: _isNew,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 255,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          onChanged: (_) => setState(() {}),
          style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
          decoration: _field('Ví dụ: Nhạc cho bố mẹ'),
        ),
        _label('Giới thiệu', '(không bắt buộc)'),
        if (_descRich)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_desc.text, maxLines: 4, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, height: 1.5, color: AppColors.textSecondary))),
              const SizedBox(height: 8),
              Text('Có định dạng (ảnh, đường dẫn…) — sửa trên web', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
            ]),
          )
        else
          TextField(
            controller: _desc,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            style: body(TextStyle(fontSize: 16, height: 1.5, color: AppColors.text)),
            decoration: _field('Vài dòng về playlist này…'),
          ),
        _label('Ảnh bìa'),
        cover,
        const SizedBox(height: 10),
        _switch('Công khai', 'Hiện trên trang cá nhân của bạn và các danh sách playlist. Tắt thì ẩn khỏi danh sách, ai có link vẫn mở được.', _public, (v) => _public = v),
        if (bqt) ...[const SizedBox(height: 24), _bqtBox()],
        if (!_isNew) ...[
          const SizedBox(height: 26),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${_itemTotal - _removed.length} bài', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
            const Spacer(),
            if (_items.length > 1) Text('Giữ ≡ rồi kéo để đổi thứ tự', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
          ]),
          const SizedBox(height: 6),
          if (_items.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Playlist chưa có bài', style: body(TextStyle(fontSize: 16, color: AppColors.textMuted))))
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _items.length,
              onReorder: (from, to) => setState(() {
                if (to > from) to--;
                _items.insert(to, _items.removeAt(from));
              }),
              itemBuilder: (ctx, i) => _itemRow(i),
            ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: AppColors.errorText,
              side: BorderSide(color: AppColors.errorText, width: 2),
              shape: const StadiumBorder(),
            ),
            onPressed: _saving ? null : _delete,
            icon: const Icon(Icons.delete_rounded),
            label: Text('Xoá playlist', style: body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          ),
        ],
      ],
    );
  }

  Widget _itemRow(int i) {
    final item = _items[i];
    final song = item['song'] as Map<String, dynamic>;
    final title = (song['title'] ?? '').toString();
    final by = songByline(song);
    return Container(
      key: ValueKey(item['itemId']),
      color: AppColors.bg,
      constraints: const BoxConstraints(minHeight: 64),
      child: Column(children: [
        Row(children: [
          IconButton(
            tooltip: 'Bỏ $title khỏi playlist',
            onPressed: () => setState(() {
              _removed.add(item['itemId'] as String);
              _items.removeAt(i);
            }),
            icon: Icon(Icons.remove_circle_rounded, color: AppColors.errorText, size: 26),
          ),
          SongCover(song: song, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
              if (by.isNotEmpty) Text(by, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            ]),
          ),
          ReorderableDragStartListener(
            index: i,
            child: Semantics(
              label: 'Giữ và kéo để đổi thứ tự $title',
              child: SizedBox(width: 48, height: 48, child: Icon(Icons.drag_handle_rounded, color: AppColors.textMuted)),
            ),
          ),
        ]),
        Divider(height: 1, color: AppColors.border),
      ]),
    );
  }

  Widget _bqtBox() {
    final ev = _event;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          expanded: _bqtOpen,
          child: InkWell(
            onTap: () async {
              setState(() => _bqtOpen = !_bqtOpen);
              (await SharedPreferences.getInstance()).setBool(_bqtOpenKey, _bqtOpen);
            },
            child: SizedBox(
              height: 52,
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.wine, borderRadius: BorderRadius.circular(6)),
                  child: Text('BQT', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: Colors.white))),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('Dành cho Ban quản trị', style: display(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text)))),
                Icon(_bqtOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 28, color: AppColors.textSecondary),
              ]),
            ),
          ),
        ),
        if (_bqtOpen) ...[
          _label('Tóm tắt', '(hiện ngoài trang chủ)'),
          TextField(
            controller: _excerpt,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            style: body(TextStyle(fontSize: 16, height: 1.5, color: AppColors.text)),
            decoration: _field('Một hai câu, không định dạng…'),
          ),
          const SizedBox(height: 8),
          _switch('Playlist sự kiện', 'Hiện ở trang chủ vào dịp kỷ niệm hằng năm.', ev, (v) => _event = v),
          if (ev) ...[
            const SizedBox(height: 14),
            Row(children: [
              _dateBox('Ngày sự kiện', _ymd(_eventDate), 'Không bắt buộc', () => _pickDate(full: true, current: _eventDate, onPicked: (v) => setState(() => _eventDate = v)), onClear: () => setState(() => _eventDate = null)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              _dateBox('Hiện từ ngày', _md(_eventStart), 'DD/MM', () => _pickDate(full: false, current: _eventStart, onPicked: (v) => setState(() => _eventStart = v))),
              const SizedBox(width: 12),
              _dateBox('Đến ngày', _md(_eventEnd), 'DD/MM', () => _pickDate(full: false, current: _eventEnd, onPicked: (v) => setState(() => _eventEnd = v))),
            ]),
            if (_eventStart != null && _eventEnd != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(_eventStart == _eventEnd ? 'Hằng năm, trang chủ dùng playlist này vào ngày ${_md(_eventStart)}.' : 'Hằng năm, trang chủ dùng playlist này trong các ngày từ ${_md(_eventStart)} đến ${_md(_eventEnd)}.', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.45, color: AppColors.textMuted))),
              ),
            const SizedBox(height: 6),
            _switch('Dùng ảnh bìa cho thẻ sự kiện', 'Tắt thì thẻ dùng ảnh bài đầu tiên.', _useCover, (v) => _useCover = v),
          ],
          _switch('Ghim lên đầu', null, _sticky, (v) => _sticky = v),
          _switch('Playlist hệ thống', 'Hiện ở mục “Playlist khác” và “Playlist sự kiện khác”.', _system, (v) => _system = v),
        ],
      ]),
    );
  }
}
