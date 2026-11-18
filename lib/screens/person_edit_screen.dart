import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart' show PlatformFile;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_quill/quill_delta.dart' show Delta;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart' show QuillDeltaToHtmlConverter;
import '../constants/theme.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import '../services/image_upload.dart';
import '../services/imgcdn.dart';
import '../widgets/desktop_page.dart';
import '../widgets/ui.dart';
import '../widgets/empty_state.dart';
import '../widgets/quill_comment_input.dart' show htmlToQuillDelta;
import 'upload_form_screen.dart' show openImageLibrary;

/// Sửa nhạc sĩ / nghệ sĩ / nhà thơ / soạn giả (BQT, quyền manage_people) —
/// canvas Desktop_NgheSi_Sua + NgheSi_Sua, chốt 18/11. Same fields as the
/// web's admin PersonForm; pops `true` once saved.
class PersonEditScreen extends StatefulWidget {
  /// composer | artist | poet | recomposer
  final String kind;
  final String id;
  const PersonEditScreen({super.key, required this.kind, required this.id});

  @override
  State<PersonEditScreen> createState() => _PersonEditScreenState();
}

const _labels = {'composer': 'nhạc sĩ', 'artist': 'nghệ sĩ', 'poet': 'nhà thơ', 'recomposer': 'soạn giả'};
const _textKeys = ['title', 'rank', 'real_name', 'dob', 'mob', 'yob', 'dod', 'mod', 'yod', 'born_address', 'current_address', 'work_address', 'phone', 'email'];

class _PersonEditScreenState extends State<PersonEditScreen> {
  late final AuthProvider _auth = context.read<AuthProvider>();
  final _c = {for (final k in _textKeys) k: TextEditingController()};
  q.QuillController? _bio;
  String _initialBio = '';
  Delta? _initialDelta;
  String _type = 'domestic';
  ({String id, String? url})? _image;
  Map? _owner;
  bool _loading = true, _failed = false, _saving = false, _imageBusy = false, _dirty = false, _dragOver = false;
  Map<String, dynamic> _orig = {};

  bool get _hasType => widget.kind != 'recomposer';
  String get _kindLabel => _labels[widget.kind] ?? 'người';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _bio?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _failed = false; });
    try {
      final d = await _auth.authedQuery(
        'query(\$id: ID!) { p: ${widget.kind}ByID(id: \$id) { id title content ${_textKeys.where((k) => k != 'title').join(' ')} ${_hasType ? 'type' : ''} image_id avatar { id url } owner { id username } } }',
        {'id': widget.id},
      );
      final p = d['p'];
      if (p is! Map) throw Exception('Không tìm thấy');
      _orig = Map<String, dynamic>.from(p);
      for (final k in _textKeys) {
        final v = '${p[k] ?? ''}';
        _c[k]!.text = v == '0' && k != 'title' ? '' : v;
        _c[k]!.addListener(_touch);
      }
      _initialBio = '${p['content'] ?? ''}';
      Delta delta;
      try {
        delta = _initialBio.trim().isEmpty ? (Delta()..insert('\n')) : htmlToQuillDelta(_initialBio);
      } catch (_) {
        delta = Delta()..insert('${_initialBio.replaceAll(RegExp(r'<[^>]+>'), '')}\n');
      }
      _initialDelta = q.Document.fromDelta(delta).toDelta();
      _bio = q.QuillController(document: q.Document.fromDelta(delta), selection: const TextSelection.collapsed(offset: 0));
      _bio!.document.changes.listen((_) => _touch());
      _type = '${p['type'] ?? 'domestic'}' == 'foreign' ? 'foreign' : 'domestic';
      final av = p['avatar'];
      _image = av is Map && av['id'] != null ? (id: '${av['id']}', url: av['url']?.toString()) : null;
      _owner = p['owner'] is Map ? p['owner'] as Map : null;
      if (mounted) setState(() { _loading = false; _dirty = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  void _touch() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  String _bioHtml() {
    final b = _bio;
    if (b == null) return _initialBio;
    if (b.document.toPlainText().trim().isEmpty) return '';
    var out = QuillDeltaToHtmlConverter(b.document.toDelta().toJson(), null).convert();
    out = out.replaceAll(RegExp(r'(<p><br/?></p>)+$'), '');
    return out.trim();
  }

  void _snack(String m, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.error : null));
  }

  Future<void> _save() async {
    final title = _c['title']!.text.trim();
    if (title.isEmpty) return _snack('Nhập nghệ danh $_kindLabel.', error: true);
    setState(() => _saving = true);
    final name = '${widget.kind[0].toUpperCase()}${widget.kind.substring(1)}';
    // Only what changed: an untouched empty field stays NULL in the DB.
    String old(String k) {
      final v = '${_orig[k] ?? ''}';
      return v == '0' && k != 'title' ? '' : v;
    }
    final bio = _bioHtml();
    final oldImage = (_orig['avatar'] is Map ? '${_orig['avatar']['id'] ?? ''}' : '');
    final vars = <String, dynamic>{
      'id': widget.id,
      for (final k in _textKeys)
        if (_c[k]!.text.trim() != old(k).trim()) k: _c[k]!.text.trim(),
      if (bio != _initialBio.trim() && _bio!.document.toDelta() != _initialDelta) 'content': bio,
      if (_hasType && _type != ('${_orig['type'] ?? 'domestic'}' == 'foreign' ? 'foreign' : 'domestic')) 'type': _type,
      // 0 = bỏ ảnh, như web.
      if ((_image?.id ?? '') != oldImage) 'image_id': _image?.id ?? '0',
      if (_owner != null && '${_owner!['id']}' != '${(_orig['owner'] as Map?)?['id'] ?? ''}') 'user_id': '${_owner!['id']}',
    };
    if (vars.length == 1) {
      _dirty = false;
      setState(() => _saving = false);
      context.pop();
      return;
    }
    final decl = vars.keys.where((k) => k != 'id').map((k) => '\$$k: ${k == 'image_id' || k == 'user_id' ? 'ID' : 'String'}').join(', ');
    final args = vars.keys.map((k) => '$k: \$$k').join(', ');
    try {
      await _auth.authedMutate('mutation(\$id: ID!, $decl) { update$name(input: { $args }) { id } }', vars);
      if (!mounted) return;
      _dirty = false;
      context.pop(true);
    } catch (e) {
      if (mounted) _snack(friendlyError(e, fallback: 'Chưa lưu được. Thử lại sau.'), error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _cancel() async {
    if (!_dirty) return context.pop();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bỏ các thay đổi?'),
        content: const Text('Những gì bạn vừa sửa sẽ không được lưu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Sửa tiếp')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Bỏ thay đổi', style: TextStyle(color: AppColors.errorText))),
        ],
      ),
    );
    if (ok == true && mounted) context.pop();
  }

  Future<void> _upload(PlatformFile f) async {
    setState(() => _imageBusy = true);
    try {
      final img = await uploadImage(_auth, f);
      if (mounted) setState(() { _image = img; _dirty = true; });
    } catch (e) {
      if (mounted) _snack(friendlyError(e, fallback: 'Chưa tải được ảnh lên.'), error: true);
    }
    if (mounted) setState(() => _imageBusy = false);
  }

  Future<void> _pickImage() async {
    final files = await pickImages();
    if (files.isNotEmpty && mounted) _upload(files.first);
  }

  Future<void> _fromLibrary() async {
    final img = await openImageLibrary(context);
    if (img != null && mounted) setState(() { _image = img; _dirty = true; });
  }

  Future<void> _pickOwner() async {
    final u = await showDialog<Map>(context: context, builder: (_) => _UserSearch(auth: _auth));
    if (u != null && mounted) setState(() { _owner = u; _dirty = true; });
  }

  bool get _canDrop => !kIsWeb && const {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}.contains(defaultTargetPlatform);

  // ---------------- pieces ----------------
  TextStyle get _labelStyle => body(TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary));

  InputDecoration _deco(String? hint) => InputDecoration(
        hintText: hint,
        hintStyle: body(TextStyle(fontSize: 16, color: AppColors.textMuted)),
        filled: true,
        fillColor: AppColors.surfaceLight,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.accentFg, width: 1.5)),
      );

  Widget _label(String t, {bool req = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(children: [TextSpan(text: t), if (req) TextSpan(text: ' *', style: TextStyle(color: AppColors.accentFg))]), style: _labelStyle),
      );

  Widget _f(String key, String label, {String? hint, bool req = false, TextInputType? keyboard}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(label, req: req),
          TextField(controller: _c[key], keyboardType: keyboard, style: body(TextStyle(fontSize: 16, color: AppColors.text)), decoration: _deco(hint)),
        ],
      );

  Widget _row(List<Widget> xs, {List<int>? flex}) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < xs.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(flex: flex?[i] ?? 1, child: xs[i]),
        ],
      ]);

  Widget _bioEditor({required double height}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('Tiểu sử'),
        Container(
          decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: AppColors.surface,
              child: q.QuillSimpleToolbar(
                controller: _bio!,
                config: const q.QuillSimpleToolbarConfig(
                  multiRowsDisplay: false,
                  showFontFamily: false, showFontSize: false, showSmallButton: false, showLineHeightButton: false,
                  showStrikeThrough: false, showInlineCode: false, showColorButton: false, showBackgroundColorButton: false,
                  showClearFormat: true, showAlignmentButtons: false, showLeftAlignment: false, showCenterAlignment: false,
                  showRightAlignment: false, showJustifyAlignment: false, showListCheck: false, showCodeBlock: false,
                  showIndent: false, showDirection: false, showSearchButton: false, showSubscript: false, showSuperscript: false,
                ),
              ),
            ),
            SizedBox(
              height: height,
              child: q.QuillEditor.basic(
                controller: _bio!,
                config: const q.QuillEditorConfig(padding: EdgeInsets.all(14), placeholder: 'Tiểu sử, sự nghiệp, tác phẩm tiêu biểu…'),
              ),
            ),
          ]),
        ),
      ]);

  Widget _typeChips() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('Phân loại'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (v, l) in [('domestic', '${_kindLabel[0].toUpperCase()}${_kindLabel.substring(1)} Việt Nam'), ('foreign', '${_kindLabel[0].toUpperCase()}${_kindLabel.substring(1)} nước ngoài')])
            ChoiceChip(
              label: Text(l),
              selected: _type == v,
              showCheckmark: false,
              onSelected: (_) => setState(() { _type = v; _dirty = true; }),
              labelStyle: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _type == v ? Colors.white : AppColors.text)),
              selectedColor: AppColors.accent,
              backgroundColor: AppColors.surface,
              side: BorderSide.none,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
        ]),
      ]);

  Widget _avatar(double size) {
    final url = _image?.url;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface),
      clipBehavior: Clip.antiAlias,
      child: _imageBusy
          ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentFg))
          : (url != null && url.isNotEmpty
              ? CachedNetworkImage(imageUrl: cdnImg(url, (size * 2).round()), fit: BoxFit.cover)
              : Icon(Icons.person_outline_rounded, size: size * 0.45, color: AppColors.textMuted)),
    );
  }

  Widget _imageCard({required bool desk}) {
    Widget btn(String l, VoidCallback onTap, {Color? color}) => SizedBox(
          height: 40,
          child: OutlinedButton(
            onPressed: _imageBusy ? null : onTap,
            style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: BorderSide(color: AppColors.border), foregroundColor: color ?? AppColors.text),
            child: Text(l, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color ?? AppColors.text))),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('Ảnh đại diện'),
      Row(children: [
        _avatar(desk ? 120 : 88),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            btn(_image == null ? 'Tải ảnh lên' : 'Tải ảnh khác', _pickImage),
            const SizedBox(height: 8),
            btn('Chọn từ thư viện ảnh', _fromLibrary, color: AppColors.accentFg),
            if (_image != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() { _image = null; _dirty = true; }),
                  child: Text('Bỏ ảnh', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.errorText))),
                ),
              ),
          ]),
        ),
      ]),
      if (desk && _canDrop)
        Padding(padding: const EdgeInsets.only(top: 10), child: Text('Kéo ảnh vào cửa sổ để thay nhanh', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)))),
    ]);
  }

  Widget _ownerCard() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('Tài khoản liên kết'),
        Material(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _pickOwner,
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                Icon(_owner == null ? Icons.search_rounded : Icons.person_rounded, size: 20, color: AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _owner == null ? 'Tìm thành viên…' : '${_owner!['username']}',
                    style: body(TextStyle(fontSize: 16, fontWeight: _owner == null ? FontWeight.w500 : FontWeight.w700, color: _owner == null ? AppColors.textMuted : AppColors.text)),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Thành viên chính là người này (hoặc người nhà) — trang người hiện huy hiệu tài khoản.', style: body(TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
      ]);

  List<Widget> _fields({required bool desk}) {
    const gap = SizedBox(height: 18);
    final dates = desk
        ? [
            _row([
              _f('dob', 'Ngày sinh', hint: 'DD', keyboard: TextInputType.number),
              _f('mob', 'Tháng', hint: 'MM', keyboard: TextInputType.number),
              _f('yob', 'Năm sinh', hint: 'YYYY', keyboard: TextInputType.number),
              _f('dod', 'Ngày mất', hint: 'DD', keyboard: TextInputType.number),
              _f('mod', 'Tháng', hint: 'MM', keyboard: TextInputType.number),
              _f('yod', 'Năm mất', hint: 'YYYY', keyboard: TextInputType.number),
            ], flex: [2, 2, 3, 2, 2, 3]),
          ]
        : [
            _row([_f('dob', 'Ngày sinh', hint: 'DD', keyboard: TextInputType.number), _f('mob', 'Tháng', hint: 'MM', keyboard: TextInputType.number), _f('yob', 'Năm', hint: 'YYYY', keyboard: TextInputType.number)]),
            gap,
            _row([_f('dod', 'Ngày mất', hint: 'DD', keyboard: TextInputType.number), _f('mod', 'Tháng', hint: 'MM', keyboard: TextInputType.number), _f('yod', 'Năm', hint: 'YYYY', keyboard: TextInputType.number)]),
          ];
    return [
      _f('title', 'Nghệ danh', req: true),
      gap,
      _bioEditor(height: desk ? 300 : 240),
      gap,
      _row([_f('rank', 'Danh hiệu', hint: 'VD: NSND, NSƯT'), _f('real_name', 'Tên thật')]),
      gap,
      ...dates,
      gap,
      _f('born_address', 'Quê quán'),
      gap,
      if (desk) _row([_f('current_address', 'Chỗ ở hiện tại'), _f('work_address', 'Nơi công tác')]) else ...[_f('current_address', 'Chỗ ở hiện tại'), gap, _f('work_address', 'Nơi công tác')],
      gap,
      _row([_f('phone', 'Số điện thoại', keyboard: TextInputType.phone), _f('email', 'Email', keyboard: TextInputType.emailAddress)]),
      if (_hasType) ...[gap, _typeChips()],
    ];
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: child,
      );

  Widget _desktop() {
    final name = '${_orig['title'] ?? ''}';
    Widget page = SingleChildScrollView(
      padding: deskPad,
      child: DeskFrame(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Material(
              color: AppColors.surface,
              shape: const CircleBorder(),
              child: IconButton(tooltip: 'Quay lại', onPressed: _cancel, icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.text)),
            ),
            const SizedBox(width: 14),
            Expanded(child: DeskHead(eyebrow: 'Sửa $_kindLabel', title: name.isEmpty ? 'Sửa $_kindLabel' : name)),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _fields(desk: true))),
            const SizedBox(width: 32),
            SizedBox(
              width: 380,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _card(_imageCard(desk: true)),
                const SizedBox(height: 16),
                _card(_ownerCard()),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.wine, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: _saving
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Lưu thay đổi', style: body(const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white))),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _saving ? null : _cancel,
                    style: OutlinedButton.styleFrom(side: BorderSide(color: AppColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text('Huỷ', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                  ),
                ),
              ]),
            ),
          ]),
        ]),
      ),
    );
    if (!_canDrop) return page;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragOver = true),
      onDragExited: (_) => setState(() => _dragOver = false),
      onDragDone: (d) async {
        setState(() => _dragOver = false);
        final f = d.files.where((x) => RegExp(r'\.(jpe?g|png|webp|gif)$', caseSensitive: false).hasMatch(x.name)).firstOrNull;
        if (f == null) return _snack('Chỉ nhận tệp ảnh.', error: true);
        final bytes = await f.readAsBytes();
        _upload(PlatformFile(name: f.name, size: bytes.length, bytes: bytes));
      },
      child: Stack(children: [
        page,
        if (_dragOver)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: AppColors.bg.withValues(alpha: 0.85),
                alignment: Alignment.center,
                child: Text('Thả ảnh để làm ảnh đại diện', style: body(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _mobile() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _imageCard(desk: false),
          const SizedBox(height: 18),
          ..._fields(desk: false),
          const SizedBox(height: 18),
          _ownerCard(),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final desk = isDesk(context);
    final allowed = context.watch<AuthProvider>().hasPermission('manage_people');
    Widget body0;
    if (!allowed) {
      body0 = const Center(child: EmptyState(icon: Icons.lock_outline, title: 'Không có quyền', subtitle: 'Chỉ BQT được sửa thông tin trang người.'));
    } else if (_loading) {
      body0 = Center(child: CircularProgressIndicator(color: AppColors.accentFg));
    } else if (_failed || _bio == null) {
      body0 = Center(child: OfflineBlock(onRetry: _load));
    } else {
      body0 = desk ? _desktop() : _mobile();
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: desk
            ? null
            : AppBar(
                leadingWidth: 76,
                leading: TextButton(onPressed: _cancel, child: Text('Huỷ', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)))),
                title: Text('Sửa $_kindLabel'),
                centerTitle: true,
                actions: [
                  if (allowed && !_loading && !_failed)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: PillButton(label: 'Lưu', height: 40, loading: _saving, onTap: _saving ? null : _save),
                    ),
                ],
              ),
        body: body0,
      ),
    );
  }
}

/// Tìm thành viên để liên kết (users, theo tên đăng nhập, như web).
class _UserSearch extends StatefulWidget {
  final AuthProvider auth;
  const _UserSearch({required this.auth});
  @override
  State<_UserSearch> createState() => _UserSearchState();
}

class _UserSearchState extends State<_UserSearch> {
  final _q = TextEditingController();
  Timer? _t;
  List<Map> _items = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _t?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _search(String v) {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 300), () async {
      final s = v.trim();
      if (s.isEmpty) return setState(() => _items = []);
      setState(() { _loading = true; _error = null; });
      try {
        final d = await widget.auth.authedQuery(
          r'query($q: Mixed) { users(first: 10, orderBy: [{column: "views", order: DESC}], where: {AND: [{column: "username", operator: LIKE, value: $q}]}) { data { id username avatar { url } } } }',
          {'q': '$s%'},
        );
        if (!mounted || _q.text.trim() != s) return;
        setState(() => _items = ((d['users']?['data'] as List?) ?? const []).whereType<Map>().toList());
      } catch (e) {
        if (mounted) setState(() => _error = friendlyError(e, fallback: 'Chưa tìm được.'));
      }
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: AppColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Tài khoản liên kết', style: body(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text))),
              const SizedBox(height: 12),
              TextField(
                controller: _q,
                autofocus: true,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: 'Gõ tên đăng nhập…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                ),
              ),
              const SizedBox(height: 8),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: AppColors.errorText))),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final u in _items)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.surface,
                        backgroundImage: (u['avatar']?['url'] ?? '').toString().isNotEmpty ? CachedNetworkImageProvider(cdnImg('${u['avatar']['url']}', 80)) : null,
                        child: (u['avatar']?['url'] ?? '').toString().isEmpty ? Text('${u['username']}'.characters.first.toUpperCase()) : null,
                      ),
                      title: Text('${u['username']}', style: body(TextStyle(fontWeight: FontWeight.w700, color: AppColors.text))),
                      onTap: () => Navigator.pop(context, u),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      );
}
