import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import '../services/image_upload.dart';
import '../widgets/desktop_page.dart';
import '../widgets/empty_state.dart';
import '../widgets/ui.dart' show PillButton, goBack;
import '../widgets/waveform_player.dart';

/// Gửi bài (canvas "Gửi bài · 1–3", "Chọn nhạc sĩ", "Đã gửi" and
/// "Desktop · Gửi bài", chốt 17/11). Same fields and rules as web /gui-bai:
/// the type decides which people, texts and files the upload carries.
/// Phone: three steps (loại → tệp → thông tin). Desktop: one page, two
/// columns. Ends in "Đã gửi" with links to Bài gửi của tôi / gửi bài khác.
class UploadFormScreen extends StatefulWidget {
  final String? initialType;
  /// Thay thế bản thu: the song page the new recording is for.
  final String? initialLink;
  const UploadFormScreen({super.key, this.initialType, this.initialLink});

  @override
  State<UploadFormScreen> createState() => _UploadFormScreenState();
}

/// value, label, one-line description, icon.
const _types = [
  ('song', 'Tân nhạc', 'Bản thu bài hát, ca khúc', Icons.music_note_rounded),
  ('folk', 'Dân ca', 'Làn điệu dân ca các vùng miền', Icons.place_outlined),
  ('instrumental', 'Khí nhạc', 'Bản nhạc không lời', Icons.piano_outlined),
  ('poem', 'Tiếng thơ', 'Bản ngâm, đọc thơ', Icons.edit_outlined),
  ('karaoke', 'Thành viên hát', 'Bản bạn tự hát, tự đàn', Icons.mic_none_rounded),
  ('document', 'Tư liệu', 'Âm thanh, ảnh, video, bài viết', Icons.description_outlined),
  ('sheet', 'Bản nhạc', 'Ảnh chụp bản nhạc (sheet)', Icons.image_outlined),
  ('replace', 'Thay thế bản thu', 'Bản chất lượng hơn cho bài đã có', Icons.swap_horiz_rounded),
];
const _karaokeTypes = [('song', 'Tân nhạc'), ('folk', 'Dân ca'), ('instrumental', 'Khí nhạc')];
const _docTypes = [('audio', 'Âm thanh'), ('image', 'Hình ảnh'), ('video', 'Video'), ('news', 'Bài viết')];
const _workTypes = {'song', 'folk', 'instrumental', 'poem', 'karaoke'};

/// People columns: key → (archive query, singular used in `<one>_list`).
const _peopleQuery = {
  'composers': ('composers', 'composer'),
  'recomposers': ('recomposers', 'recomposer'),
  'poets': ('poets', 'poet'),
  'artists': ('artists', 'artist'),
  'accompanists': ('artists', 'accompanist'),
  'fcats': ('fcats', 'fcat'),
  'melodies': ('melodies', 'melody'),
};

class _Person {
  final String? id;
  final String title;
  final String? yob;
  const _Person(this.id, this.title, [this.yob]);
}

class _UploadFormScreenState extends State<UploadFormScreen> {
  late String _type;
  String _karaokeType = 'song';
  String _docType = 'audio';
  int _step = 0;

  final _title = TextEditingController();
  final _link = TextEditingController();
  final _lyrics = TextEditingController();
  final _year = TextEditingController();
  final _recordYear = TextEditingController();
  final _note = TextEditingController();
  final _source = TextEditingController();
  final _instrument = TextEditingController();
  final _news = TextEditingController();
  final _ppl = <String, List<_Person>>{};
  bool _showAccompanists = false;

  /// The uploaded recording (file row: id, audio_url, duration, bitrate…).
  Map<String, dynamic>? _file;
  String? _fileName;
  int? _fileSize;
  /// null idle, 0–1 sending, -1 server converting.
  double? _fileProgress;
  UploadedImage? _image;
  bool _imageBusy = false;
  final _sheet = <UploadedImage>[];
  bool _sheetBusy = false;

  bool _agree = false;
  bool _submitting = false;
  bool _done = false;
  String? _doneTitle;
  int? _dupes;
  Timer? _dupeTimer;

  AuthProvider get _auth => context.read<AuthProvider>();

  @override
  void initState() {
    super.initState();
    final allowed = _allowed(context.read<AuthProvider>());
    final want = widget.initialType;
    _type = want != null && allowed.contains(want) ? want : (allowed.firstOrNull ?? 'song');
    if (widget.initialLink != null) _link.text = widget.initialLink!;
    if (want != null && allowed.contains(want)) _step = 1;
    _title.addListener(_scheduleDupes);
  }

  @override
  void dispose() {
    _dupeTimer?.cancel();
    for (final c in [_title, _link, _lyrics, _year, _recordYear, _note, _source, _instrument, _news]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _allowed(AuthProvider a) => [
        for (final t in _types)
          if ((t.$1 != 'song' || a.hasPermission('upload_song')) && (t.$1 != 'folk' || a.hasPermission('upload_folk'))) t.$1,
      ];

  // ---- What the type carries (same switches as web UploadClient) ----
  bool get _isDoc => _type == 'document';
  bool get _kSong => _type == 'karaoke' && _karaokeType == 'song';
  bool get _kFolk => _type == 'karaoke' && _karaokeType == 'folk';
  bool get _showComposers => const {'song', 'instrumental', 'sheet', 'document'}.contains(_type) || _kSong;
  bool get _showArtists => const {'song', 'folk', 'instrumental', 'poem', 'document'}.contains(_type);
  bool get _canAccompany => const {'song', 'folk', 'instrumental', 'poem'}.contains(_type);
  bool get _showPoets => const {'song', 'poem', 'document'}.contains(_type);
  bool get _showRecomposers => _type == 'folk' || _kFolk || _isDoc;
  bool get _showFolkCats => _type == 'folk' || _kFolk;
  bool get _showLyrics => const {'song', 'folk', 'poem'}.contains(_type) || (_type == 'karaoke' && _karaokeType != 'instrumental');
  bool get _showYears => _type == 'song';
  bool get _isReplace => _type == 'replace';
  bool get _needsAudio => const {'song', 'folk', 'instrumental', 'poem', 'karaoke', 'replace'}.contains(_type) || (_isDoc && _docType == 'audio');
  bool get _needsVideo => _isDoc && _docType == 'video';
  bool get _needsMainImage => _isDoc && _docType == 'image';
  bool get _isSheet => _type == 'sheet';
  bool get _isNews => _isDoc && _docType == 'news';
  bool get _optionalImage => _workTypes.contains(_type) || _isNews;
  bool get _needAgreement => _workTypes.contains(_type);

  /// People pickers in the web's order, with labels.
  List<(String, String)> get _pickers {
    if (_isDoc) {
      return [('composers', 'Nhạc sĩ liên quan'), ('artists', 'Nghệ sĩ liên quan'), ('poets', 'Nhà thơ liên quan'), ('recomposers', 'Soạn giả liên quan')];
    }
    return [
      if (_showComposers) ('composers', 'Nhạc sĩ'),
      if (_showRecomposers) ('recomposers', 'Soạn giả'),
      if (_showPoets) ('poets', _type == 'song' ? 'Nhà thơ (phổ thơ)' : 'Nhà thơ'),
      if (_showArtists) ('artists', _type == 'poem' ? 'Người ngâm, đọc' : 'Nghệ sĩ trình bày'),
      if (_showFolkCats) ('fcats', 'Thể loại dân ca'),
      if (_showFolkCats) ('melodies', 'Làn điệu'),
    ];
  }

  String get _typeLabel {
    final base = _types.firstWhere((t) => t.$1 == _type).$2;
    if (_isDoc) return '$base · ${_docTypes.firstWhere((d) => d.$1 == _docType).$2}';
    return base;
  }

  void _setType(String t) {
    setState(() => _type = t);
    _checkDupes();
  }

  void _snack(String t, {bool error = false}) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t), backgroundColor: error ? AppColors.errorText : null, duration: const Duration(seconds: 3)));

  // ---- Duplicates: "Kho đã có N bài cùng tên" ----
  void _scheduleDupes() {
    _dupeTimer?.cancel();
    _dupeTimer = Timer(const Duration(milliseconds: 600), _checkDupes);
  }

  Future<void> _checkDupes() async {
    final t = _title.text.trim();
    final root = switch (_type) { 'song' => 'songs', 'folk' => 'folks', 'instrumental' => 'instrumentals', 'poem' => 'poems', 'karaoke' => 'karaokes', _ => null };
    if (t.length < 2 || root == null) {
      if (_dupes != null && mounted) setState(() => _dupes = null);
      return;
    }
    try {
      final d = await ApiClient.query('query(\$q: String) { $root(first: 1, q: \$q) { paginatorInfo { total } } }', {'q': t});
      if (mounted && _title.text.trim() == t) setState(() => _dupes = (d[root]?['paginatorInfo']?['total'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  // ---- Files ----
  Future<void> _pickMedia() async {
    final f = await pickMedia();
    if (f == null || !mounted) return;
    setState(() {
      _file = null;
      _fileName = f.name;
      _fileSize = f.size;
      _fileProgress = 0;
    });
    try {
      final row = await uploadMedia(_auth, f,
          onProgress: (p) {
            if (mounted) setState(() => _fileProgress = p);
          },
          onProcessing: () {
            if (mounted) setState(() => _fileProgress = -1);
          });
      if (!mounted) return;
      setState(() {
        _file = row;
        _fileProgress = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fileProgress = null;
        _fileName = null;
      });
      _snack(friendlyError(e, fallback: 'Chưa tải được tệp lên, vui lòng thử lại.'), error: true);
    }
  }

  Future<void> _pickImage() async {
    final files = await pickImages();
    if (files.isEmpty || !mounted) return;
    setState(() => _imageBusy = true);
    try {
      final img = await uploadImage(_auth, files.first);
      if (mounted) setState(() => _image = img);
    } catch (e) {
      if (mounted) _snack(friendlyError(e, fallback: 'Chưa tải được ảnh lên.'), error: true);
    }
    if (mounted) setState(() => _imageBusy = false);
  }

  Future<void> _pickSheet() async {
    final files = await pickImages(multiple: true);
    if (files.isEmpty || !mounted) return;
    setState(() => _sheetBusy = true);
    for (final f in files) {
      try {
        final img = await uploadImage(_auth, f);
        if (mounted) setState(() => _sheet.add(img));
      } catch (e) {
        if (mounted) _snack(friendlyError(e, fallback: 'Có ảnh chưa tải lên được.'), error: true);
      }
    }
    if (mounted) setState(() => _sheetBusy = false);
  }

  bool get _busy => _fileProgress != null || _imageBusy || _sheetBusy;

  // ---- Validation & submit ----
  String? _mediaProblem() {
    if (_busy) return 'Đợi tệp tải lên xong đã nhé.';
    if ((_needsAudio || _needsVideo) && _file == null) return _needsVideo ? 'Vui lòng chọn tệp video.' : 'Vui lòng chọn tệp âm thanh.';
    if (_needsMainImage && _image == null) return 'Vui lòng chọn ảnh tư liệu.';
    if (_isSheet && _sheet.isEmpty) return 'Vui lòng thêm ít nhất một ảnh bản nhạc.';
    return null;
  }

  String? _infoProblem() {
    if (_isReplace) {
      if (_link.text.trim().isEmpty) return 'Vui lòng dán link bài cần thay bản thu.';
      if (_note.text.trim().isEmpty) return 'Vui lòng nêu lý do vì sao bản thu mới chất lượng hơn.';
    } else if (_title.text.trim().isEmpty) {
      return 'Vui lòng nhập tên tác phẩm.';
    }
    if (_isNews && _news.text.trim().isEmpty) return 'Vui lòng nhập nội dung bài viết.';
    if (_needAgreement && !_agree) return 'Vui lòng tick đồng ý cam kết trước khi gửi.';
    return null;
  }

  String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  Map<String, dynamic> _input() {
    final i = <String, dynamic>{
      'title': _isReplace ? _link.text.trim() : _title.text.trim(),
      'type': _type,
    };
    if (_isDoc) i['document_type'] = _docType;
    if (_isReplace) i['link'] = _link.text.trim();
    if (_file != null) i['file_id'] = int.tryParse('${_file!['id']}');
    if (_image != null) i['image_id'] = int.tryParse(_image!.id);
    if (_showLyrics && _lyrics.text.trim().isNotEmpty) i['content'] = _lyrics.text.trim();
    if (_isSheet) i['content'] = _sheet.where((s) => s.url != null).map((s) => '<p><img src="${s.url}"></p>').join();
    if (_isNews) {
      i['content'] = _news.text.trim().split(RegExp(r'\n\s*\n')).map((p) => '<p>${_esc(p.trim()).replaceAll('\n', '<br>')}</p>').join();
    }
    if (_showYears && _year.text.trim().isNotEmpty) i['year'] = _year.text.trim();
    if (_showYears && _recordYear.text.trim().isNotEmpty) i['record_year'] = _recordYear.text.trim();
    if (_note.text.trim().isNotEmpty) i['note'] = _note.text.trim();
    if ((_needsAudio || _needsVideo) && _source.text.trim().isNotEmpty) i['source'] = _source.text.trim();
    if (_canAccompany && _instrument.text.trim().isNotEmpty) i['accompaniment_instrument'] = _instrument.text.trim();
    if (_type == 'karaoke') i['karaoke_type'] = _karaokeType;
    final keys = [..._pickers.map((p) => p.$1), if (_canAccompany) 'accompanists'];
    for (final k in keys) {
      final l = _ppl[k] ?? const [];
      if (l.isEmpty) continue;
      final one = _peopleQuery[k]!.$2;
      i['${one}_list'] = l.where((p) => p.id != null).map((p) => p.id).join(',');
      i[k] = l.map((p) => p.title).join(' - ');
      i['pre_$k'] = jsonEncode([for (final p in l) {if (p.id != null) 'id': p.id, 'title': p.title}]);
    }
    return i;
  }

  Future<void> _submit() async {
    final problem = _mediaProblem() ?? _infoProblem();
    if (problem != null) return _snack(problem, error: true);
    setState(() => _submitting = true);
    try {
      await _auth.authedMutate(r'mutation($input: CreateUploadInput!) { createUpload(input: $input) { id } }', {'input': _input()});
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _done = true;
        _doneTitle = _isReplace ? null : _title.text.trim();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack(friendlyError(e, fallback: 'Chưa gửi được, vui lòng thử lại.'), error: true);
    }
  }

  void _reset() {
    for (final c in [_title, _link, _lyrics, _year, _recordYear, _note, _source, _instrument, _news]) {
      c.clear();
    }
    setState(() {
      _ppl.clear();
      _file = null;
      _fileName = null;
      _image = null;
      _sheet.clear();
      _agree = false;
      _done = false;
      _dupes = null;
      _step = 0;
      _showAccompanists = false;
    });
  }

  void _next() {
    if (_step == 1) {
      final p = _mediaProblem();
      if (p != null) return _snack(p, error: true);
    }
    setState(() => _step++);
  }

  // =================================================================
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final desk = isDesk(context);
    Widget page(Widget child) => Scaffold(
          backgroundColor: AppColors.bg,
          appBar: desk
              ? null
              : AppBar(
                  title: const Text('Gửi bài'),
                  centerTitle: true,
                  leading: IconButton(
                    tooltip: 'Quay lại',
                    icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text),
                    onPressed: () => (!_done && _step > 0) ? setState(() => _step--) : goBack(context),
                  ),
                ),
          body: child,
        );
    if (!auth.isAuthenticated) {
      return page(Center(
        child: auth.loading
            ? CircularProgressIndicator(color: AppColors.accentFg)
            : EmptyState(icon: Icons.upload_outlined, title: 'Vui lòng đăng nhập', subtitle: 'Đăng nhập để gửi bài lên BCĐCNT.', ctaLabel: 'Đăng nhập', onCta: () => askLogin(context)),
      ));
    }
    if (!auth.hasPermission('upload')) {
      return page(const Center(child: EmptyState(icon: Icons.lock_outline, title: 'Chưa gửi bài được', subtitle: 'Tài khoản của bạn hiện chưa có quyền gửi bài. Liên hệ BQT nếu cần hỗ trợ.')));
    }
    if (_done) return page(_doneView(desk));
    return PopScope(
      canPop: desk || _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step--);
      },
      child: page(desk ? _desktop(auth) : _mobile(auth)),
    );
  }

  // ---------------- Shared pieces ----------------
  TextStyle get _labelStyle => body(TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary));

  Widget _label(String t, {bool req = false, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: t),
          if (req) TextSpan(text: ' *', style: TextStyle(color: AppColors.accentFg)),
          if (hint != null) TextSpan(text: ' · $hint', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textMuted)),
        ])),
      );

  Widget _field(TextEditingController c, String label, {String? hint, bool req = false, String? note, int lines = 1, TextInputType? keyboard}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DefaultTextStyle.merge(style: _labelStyle, child: _label(label, req: req, hint: note)),
          TextField(
            controller: c,
            minLines: lines,
            maxLines: lines == 1 ? 1 : lines + 4,
            keyboardType: keyboard ?? (lines > 1 ? TextInputType.multiline : TextInputType.text),
            style: body(TextStyle(fontSize: 16, height: 1.45, color: AppColors.text)),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: body(TextStyle(fontSize: 16, color: AppColors.textMuted)),
              filled: true,
              fillColor: AppColors.surfaceLight,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.accentFg, width: 1.5)),
            ),
          ),
        ],
      );

  Widget _chips<T>(List<(T, String)> items, T value, ValueChanged<T> on) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (v, l) in items)
          ChoiceChip(
            label: Text(l),
            selected: v == value,
            showCheckmark: false,
            onSelected: (_) => on(v),
            labelStyle: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: v == value ? Colors.white : AppColors.text)),
            selectedColor: AppColors.accent,
            backgroundColor: AppColors.surface,
            side: BorderSide.none,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
      ]);

  Widget? _subType() {
    if (_type == 'karaoke') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DefaultTextStyle.merge(style: _labelStyle, child: _label('Thể loại bài bạn hát')),
        _chips(_karaokeTypes, _karaokeType, (v) => setState(() => _karaokeType = v)),
      ]);
    }
    if (_isDoc) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DefaultTextStyle.merge(style: _labelStyle, child: _label('Loại tư liệu')),
        _chips(_docTypes, _docType, (v) => setState(() {
              _docType = v;
              _file = null;
              _fileName = null;
              _image = null;
            })),
      ]);
    }
    return null;
  }

  Widget _people(String key, String label) {
    final list = _ppl[key] ?? const <_Person>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DefaultTextStyle.merge(style: _labelStyle, child: _label(label)),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (var i = 0; i < list.length; i++) _personChip(list[i], () => setState(() => _ppl[key] = [...list]..removeAt(i))),
        _AddButton(
          label: list.isEmpty ? 'Thêm' : 'Thêm',
          onTap: () async {
            final picked = await _PersonSearch.open(context, title: label, query: _peopleQuery[key]!.$1, initial: list);
            if (picked != null && mounted) setState(() => _ppl[key] = picked);
          },
        ),
      ]),
    ]);
  }

  Widget _personChip(_Person p, VoidCallback onRemove) {
    final initials = p.title.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w[0]).toList();
    final ini = initials.isEmpty ? '?' : (initials.length == 1 ? initials.first : '${initials.first}${initials.last}').toUpperCase();
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 4, right: 2),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 16, backgroundColor: AppColors.accentSoft, child: Text(ini, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
        const SizedBox(width: 8),
        Text(p.title, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text))),
        if (p.id == null) ...[
          const SizedBox(width: 6),
          Text('mới', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.warningText))),
        ],
        IconButton(
          tooltip: 'Bỏ ${p.title}',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
          onPressed: onRemove,
        ),
      ]),
    );
  }

  Widget? _dupeBanner() {
    if ((_dupes ?? 0) == 0) return null;
    final c = AppColors.warningText;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.3))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: 20, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Kho đã có ${formatInt(_dupes!)} bài cùng tên. ', style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: 'Xem trước để tránh gửi trùng. '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: InkWell(
                  onTap: () => context.push('/search', extra: _title.text.trim()),
                  child: Text('Xem', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c, decoration: TextDecoration.underline, decorationColor: c))),
                ),
              ),
            ]),
            style: body(TextStyle(fontSize: 14, height: 1.45, color: AppColors.text)),
          ),
        ),
      ]),
    );
  }

  Widget _agreement() => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _agree = !_agree),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 10, 14, 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(value: _agree, activeColor: AppColors.accent, onChanged: (v) => setState(() => _agree = v ?? false)),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: DefaultTextStyle.merge(
                    style: body(TextStyle(fontSize: 14, height: 1.45, color: AppColors.text)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Tôi cam kết khi gửi bài này:', style: body(const TextStyle(fontWeight: FontWeight.w800))),
                      const SizedBox(height: 6),
                      const Text.rich(TextSpan(children: [TextSpan(text: '•  Không dùng '), TextSpan(text: 'AI', style: TextStyle(fontWeight: FontWeight.w800)), TextSpan(text: ' trong phần trình bày và sáng tác.')])),
                      const SizedBox(height: 4),
                      const Text.rich(TextSpan(children: [TextSpan(text: '•  Đồng ý chia sẻ trên BCĐCNT với mục đích '), TextSpan(text: 'phi lợi nhuận', style: TextStyle(fontWeight: FontWeight.w800)), TextSpan(text: '.')])),
                      const SizedBox(height: 4),
                      Text.rich(TextSpan(children: [
                        const TextSpan(text: '•  Tuân theo '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: InkWell(
                            onTap: () => launchUrl(Uri.parse('$siteUrl/tieu-chi'), mode: LaunchMode.externalApplication),
                            child: Text('Tiêu chí gửi tác phẩm', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentFg, decoration: TextDecoration.underline, decorationColor: AppColors.accentFg))),
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ])),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );

  // ---- Media blocks ----
  String _size(int? b) => b == null ? '' : (b >= 1024 * 1024 ? '${(b / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB' : '${(b / 1024).round()} KB');
  String _dur(dynamic s) {
    final n = (s is num ? s : num.tryParse('${s ?? ''}'))?.round();
    if (n == null || n <= 0) return '';
    return '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';
  }

  Widget _box({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: child,
      );

  Widget _mediaBlock() {
    final video = _needsVideo;
    final title = video ? 'Tệp video' : 'Tệp âm thanh';
    final hint = video ? 'MP4, MOV…' : 'MP3, M4A, WAV…';
    Widget inner;
    if (_fileProgress != null) {
      final p = _fileProgress!;
      inner = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_fileName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text))),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: p < 0 ? null : p, minHeight: 6, color: AppColors.accent, backgroundColor: AppColors.border)),
        const SizedBox(height: 8),
        Text(p < 0 ? 'Máy chủ đang xử lý tệp…' : 'Đang tải lên ${(p * 100).round()}% · bạn vẫn điền tiếp được', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
      ]);
    } else if (_file != null) {
      final url = '${_file!['audio_url'] ?? ''}';
      final meta = [_dur(_file!['duration']), _size(_fileSize), if (_file!['bitrate'] != null) '${_file!['bitrate']} kbps'].where((s) => s.isNotEmpty).join(' · ');
      inner = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(_fileName ?? 'Tệp đã tải lên', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.successText.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text('Đã tải lên', style: body(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.successText))),
          ),
        ]),
        if (meta.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(meta, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)))),
        if (url.isNotEmpty && !video) ...[
          const SizedBox(height: 10),
          WaveformPlayer(key: ValueKey(url), audioUrl: url, height: 44, buttonSize: 44, durationHint: (_file!['duration'] as num?)?.toDouble()),
        ],
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: PillButton(label: 'Đổi tệp', primary: false, height: 40, onTap: _pickMedia)),
      ]);
    } else {
      inner = _DashedButton(icon: video ? Icons.video_file_outlined : Icons.audio_file_outlined, label: video ? 'Chọn tệp video' : 'Chọn tệp âm thanh', height: 120, onTap: _pickMedia);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DefaultTextStyle.merge(style: _labelStyle, child: _label(title, req: true, hint: hint)),
      _file == null && _fileProgress == null ? inner : _box(child: inner),
    ]);
  }

  Widget _imageBlock({required bool required, String label = 'Ảnh minh hoạ'}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DefaultTextStyle.merge(style: _labelStyle, child: _label(label, req: required, hint: required ? null : 'không bắt buộc')),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (_image?.url != null)
            Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_image!.url!, width: 104, height: 104, fit: BoxFit.cover)),
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(customBorder: const CircleBorder(), onTap: () => setState(() => _image = null), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 16, color: Colors.white))),
                ),
              ),
            ]),
          SizedBox(
            width: 104,
            child: _DashedButton(icon: Icons.add_photo_alternate_outlined, label: _image == null ? 'Chọn ảnh' : 'Đổi ảnh', height: 104, busy: _imageBusy, onTap: _pickImage),
          ),
        ]),
      ]);

  Widget _sheetBlock() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DefaultTextStyle.merge(style: _labelStyle, child: _label('Ảnh bản nhạc', req: true, hint: 'chọn nhiều ảnh, theo thứ tự trang')),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < _sheet.length; i++)
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(color: Colors.white, width: 96, height: 128, child: _sheet[i].url == null ? const SizedBox() : Image.network(_sheet[i].url!, fit: BoxFit.cover, alignment: Alignment.topCenter)),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(customBorder: const CircleBorder(), onTap: () => setState(() => _sheet.removeAt(i)), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 16, color: Colors.white))),
                ),
              ),
              Positioned(left: 6, bottom: 6, child: Text('${i + 1}', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white, shadows: [Shadow(blurRadius: 3)])))),
            ]),
          SizedBox(width: 96, child: _DashedButton(icon: Icons.add_photo_alternate_outlined, label: 'Thêm ảnh', height: 128, busy: _sheetBusy, onTap: _pickSheet)),
        ]),
      ]);

  /// Everything about files for the current type (step 2 / right column).
  List<Widget> _mediaSection() => [
        if (_needsAudio || _needsVideo) _mediaBlock(),
        if (_needsAudio || _needsVideo) _field(_source, 'Nguồn bản thu', note: 'để tri ân người sưu tầm', hint: 'Đĩa than, băng cối, đài phát thanh… sưu tầm của ai', lines: 2),
        if (_needsMainImage) _imageBlock(required: true, label: 'Ảnh tư liệu'),
        if (_isSheet) _sheetBlock(),
        if (_optionalImage) _imageBlock(required: false),
      ];

  /// Names, people, texts (step 3 / left column).
  List<Widget> _infoSection() {
    final dupe = _dupeBanner();
    return [
      if (_isReplace)
        _field(_link, 'Link bài cần thay bản thu', req: true, hint: 'https://bcdcnt.net/bai-hat/…')
      else
        _field(_title, _isNews ? 'Tiêu đề bài viết' : 'Tên tác phẩm', req: true),
      ?dupe,
      for (final (k, l) in _pickers) _people(k, l),
      if (_canAccompany && !_showAccompanists && (_ppl['accompanists'] ?? const []).isEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showAccompanists = true),
            icon: Icon(Icons.add_rounded, color: AppColors.accentFg),
            label: Text('Thêm người đệm đàn, nhạc cụ', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.accentFg))),
          ),
        )
      else if (_canAccompany) ...[
        _people('accompanists', 'Người đệm đàn'),
        _field(_instrument, 'Nhạc cụ đệm', hint: 'VD: đàn bầu, piano'),
      ],
      if (_showYears)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _field(_year, 'Năm sáng tác', hint: 'VD: 1967', keyboard: TextInputType.number)),
          const SizedBox(width: 12),
          Expanded(child: _field(_recordYear, 'Năm thu', hint: 'VD: 1975', keyboard: TextInputType.number)),
        ]),
      if (_showLyrics) _field(_lyrics, _type == 'poem' ? 'Lời thơ' : 'Lời bài hát', hint: 'Dán lời (nếu có)', note: 'không bắt buộc', lines: 4),
      if (_isNews) _field(_news, 'Nội dung bài viết', req: true, hint: 'Mỗi đoạn cách nhau một dòng trống', lines: 8),
      _field(_note, _isReplace ? 'Vì sao bản thu mới chất lượng hơn?' : 'Ghi chú cho BQT', req: _isReplace, hint: _isReplace ? 'VD: bản gốc đĩa than, không rè, đủ đoạn đầu' : 'Điều BQT nên biết về bài gửi này', lines: 2),
    ];
  }

  Widget _gap(List<Widget> ws, double gap) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < ws.length; i++) ...[if (i > 0) SizedBox(height: gap), ws[i]],
      ]);

  // ---------------- Phone: 3 steps ----------------
  Widget _mobile(AuthProvider auth) {
    const labels = ['Chọn loại', 'Tệp', 'Thông tin'];
    final content = switch (_step) {
      0 => _stepType(auth),
      1 => _gap([
          ?_subType(),
          ..._mediaSection(),
          if (_mediaSection().isEmpty) Text('Loại này không cần tệp. Bấm Tiếp tục để điền thông tin.', style: body(TextStyle(fontSize: 15, color: AppColors.textMuted))),
        ], 20),
      _ => _gap([..._infoSection(), if (_needAgreement) _agreement()], 20),
    };
    final last = _step == 2;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: Container(height: 4, decoration: BoxDecoration(color: i <= _step ? AppColors.accent : AppColors.border, borderRadius: BorderRadius.circular(2)))),
            ],
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('Bước ${_step + 1}/3 · ${labels[_step]}', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)))),
            if (_step > 0) Text(_typeLabel, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentFg))),
          ]),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          key: PageStorageKey('upload-step-$_step'),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: content,
        ),
      ),
      Container(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border))),
        child: SizedBox(
          width: double.infinity,
          child: PillButton(
            label: last ? 'Gửi bài' : 'Tiếp tục',
            height: 52,
            loading: _submitting,
            onTap: _submitting ? null : (last ? _submit : _next),
          ),
        ),
      ),
    ]);
  }

  Widget _stepType(AuthProvider auth) {
    final allowed = _allowed(auth);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Bạn muốn gửi gì?', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text))),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final t in _types)
            if (allowed.contains(t.$1)) SizedBox(width: w, child: _TypeCard(type: t, selected: _type == t.$1, onTap: () => _setType(t.$1))),
        ]);
      }),
      if (_subType() case final sub?) ...[const SizedBox(height: 20), sub],
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => launchUrl(Uri.parse('$siteUrl/tieu-chi'), mode: LaunchMode.externalApplication),
          icon: Icon(Icons.info_outline_rounded, size: 18, color: AppColors.accentFg),
          label: Text('Tiêu chí gửi tác phẩm', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accentFg))),
        ),
      ),
    ]);
  }

  // ---------------- Desktop: one page ----------------
  Widget _desktop(AuthProvider auth) {
    final allowed = _allowed(auth);
    final sub = _subType();
    final media = _mediaSection();
    return SingleChildScrollView(
      padding: deskPad,
      child: DeskFrame(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const DeskHead(title: 'Gửi bài', subtitle: 'Chọn loại, điền thông tin và tải tệp lên'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in _types)
              if (allowed.contains(t.$1))
                _TypePill(type: t, selected: _type == t.$1, onTap: () => _setType(t.$1)),
          ]),
          if (sub != null) ...[const SizedBox(height: 18), sub],
          const SizedBox(height: 24),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _gap(_infoSection(), 20)),
            const SizedBox(width: 32),
            SizedBox(
              width: 380,
              child: _gap([
                if (media.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                    child: _gap(media, 18),
                  ),
                if (_needAgreement) _agreement(),
                PillButton(label: 'Gửi bài', icon: Icons.upload_rounded, height: 52, loading: _submitting, onTap: _submitting ? null : _submit),
              ], 20),
            ),
          ]),
        ]),
      ),
    );
  }

  // ---------------- Đã gửi ----------------
  Widget _doneView(bool desk) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, size: 44, color: AppColors.accentFg),
              ),
              const SizedBox(height: 14),
              Text('Đã gửi bài', style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text))),
              const SizedBox(height: 10),
              Text(
                _doneTitle == null || _doneTitle!.isEmpty ? 'Bài gửi đang chờ BQT duyệt. Bạn sẽ nhận thông báo khi có kết quả.' : '“$_doneTitle” đang chờ BQT duyệt. Bạn sẽ nhận thông báo khi có kết quả.',
                textAlign: TextAlign.center,
                style: body(TextStyle(fontSize: 16, height: 1.45, color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 22),
              SizedBox(width: double.infinity, child: PillButton(label: 'Xem bài gửi của tôi', height: 52, onTap: () => context.pushReplacement('/bai-gui-cua-toi'))),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: PillButton(label: 'Gửi bài khác', primary: false, height: 52, onTap: _reset)),
            ]),
          ),
        ),
      );
}

// =====================================================================

class _TypeCard extends StatelessWidget {
  final (String, String, String, IconData) type;
  final bool selected;
  final VoidCallback onTap;
  const _TypeCard({required this.type, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? AppColors.accentSoft : AppColors.bg,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 124),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 2 : 1)),
              child: Stack(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: selected ? AppColors.bg : AppColors.accentSoft, borderRadius: BorderRadius.circular(12)),
                    child: Icon(type.$4, size: 22, color: AppColors.accentFg),
                  ),
                  const SizedBox(height: 8),
                  Text(type.$2, style: body(TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w800, color: AppColors.text))),
                  const SizedBox(height: 2),
                  Text(type.$3, style: body(TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w500, color: AppColors.textMuted))),
                ]),
                if (selected)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(width: 22, height: 22, decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, size: 16, color: Colors.white)),
                  ),
              ]),
            ),
          ),
        ),
      );
}

class _TypePill extends StatelessWidget {
  final (String, String, String, IconData) type;
  final bool selected;
  final VoidCallback onTap;
  const _TypePill({required this.type, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: type.$3,
        child: Material(
          color: selected ? AppColors.accent : AppColors.bg,
          shape: StadiumBorder(side: selected ? BorderSide.none : BorderSide(color: AppColors.border)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(type.$4, size: 20, color: selected ? Colors.white : AppColors.accentFg),
                const SizedBox(width: 8),
                Text(type.$2, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.text))),
              ]),
            ),
          ),
        ),
      );
}

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: AppColors.accentFg.withValues(alpha: 0.45))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, size: 18, color: AppColors.accentFg),
              const SizedBox(width: 6),
              Text(label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.accentFg))),
            ]),
          ),
        ),
      );
}

class _DashedButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final double height;
  final bool busy;
  final VoidCallback onTap;
  const _DashedButton({required this.icon, required this.label, required this.height, required this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy ? null : onTap,
          child: Container(
            height: height,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.accentFg.withValues(alpha: 0.4), width: 1.2)),
            child: Center(
              child: busy
                  ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.accentFg))
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: 26, color: AppColors.accentFg),
                      const SizedBox(height: 6),
                      Text(label, textAlign: TextAlign.center, style: body(TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.accentFg))),
                    ]),
            ),
          ),
        ),
      );
}

/// "Chọn nhạc sĩ / nghệ sĩ…": search the archive, tick several, or add a
/// name that isn't there yet (BQT creates it when approving). A bottom
/// sheet on phones, a dialog on desktop. Returns the new list, or null.
class _PersonSearch extends StatefulWidget {
  final String title;
  final String query;
  final List<_Person> initial;
  const _PersonSearch({required this.title, required this.query, required this.initial});

  static Future<List<_Person>?> open(BuildContext context, {required String title, required String query, required List<_Person> initial}) {
    final sheet = _PersonSearch(title: title, query: query, initial: initial);
    if (isDesk(context)) {
      return showDialog<List<_Person>>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: AppColors.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640), child: sheet),
        ),
      );
    }
    return showModalBottomSheet<List<_Person>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SizedBox(height: MediaQuery.sizeOf(ctx).height * 0.82, child: sheet),
      ),
    );
  }

  @override
  State<_PersonSearch> createState() => _PersonSearchState();
}

class _PersonSearchState extends State<_PersonSearch> {
  late final List<_Person> _picked = [...widget.initial];
  final _q = TextEditingController();
  List<_Person> _hits = const [];
  bool _loading = false;
  Timer? _debounce;

  bool get _hasYob => const {'composers', 'artists', 'poets', 'recomposers'}.contains(widget.query);

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: q.isEmpty ? 0 : 250), () async {
      setState(() => _loading = true);
      final order = _hasYob ? '{column: "views", order: DESC}' : '{column: "title", order: ASC}';
      final where = q.trim().isEmpty ? '' : ', where: {column: "title", operator: LIKE, value: \$q}';
      final fields = _hasYob ? 'id title yob' : 'id title';
      try {
        final d = await ApiClient.query('query(\$q: Mixed) { ${widget.query}(first: 20$where, orderBy: [$order]) { data { $fields } } }', {'q': '%${q.trim()}%'});
        if (!mounted || _q.text != q) return;
        setState(() {
          _hits = [
            for (final m in ((d[widget.query]?['data'] ?? []) as List).whereType<Map>())
              _Person('${m['id']}', '${m['title']}', (m['yob'] == null || '${m['yob']}' == '0') ? null : '${m['yob']}'),
          ];
          _loading = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  bool _isPicked(_Person p) => _picked.any((x) => p.id != null ? x.id == p.id : x.title.toLowerCase() == p.title.toLowerCase());

  void _toggle(_Person p) => setState(() {
        if (_isPicked(p)) {
          _picked.removeWhere((x) => p.id != null ? x.id == p.id : x.title.toLowerCase() == p.title.toLowerCase());
        } else {
          _picked.add(p);
        }
      });

  @override
  Widget build(BuildContext context) {
    final typed = _q.text.trim();
    final exact = _hits.any((h) => h.title.toLowerCase() == typed.toLowerCase());
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!isDesk(context))
          Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(3)))),
        SizedBox(
          height: 56,
          child: Row(children: [
            Expanded(child: Text('Chọn ${widget.title.toLowerCase()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text)))),
            PillButton(label: 'Xong', height: 40, onTap: () => Navigator.pop(context, _picked)),
          ]),
        ),
        TextField(
          controller: _q,
          autofocus: true,
          onChanged: (v) {
            setState(() {});
            _search(v);
          },
          style: body(TextStyle(fontSize: 17, color: AppColors.text)),
          decoration: InputDecoration(
            hintText: 'Tìm tên…',
            prefixIcon: Icon(Icons.search_rounded, color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        if (_picked.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in _picked)
              InputChip(
                label: Text(p.title),
                labelStyle: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                backgroundColor: AppColors.surface,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                deleteButtonTooltipMessage: 'Bỏ ${p.title}',
                onDeleted: () => _toggle(p),
              ),
          ]),
        ],
        const SizedBox(height: 6),
        Expanded(
          child: ListView(children: [
            if (_loading && _hits.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: AppColors.accentFg))),
            for (final h in _hits)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _toggle(h),
                leading: CircleAvatar(radius: 22, backgroundColor: AppColors.accentSoft, child: Icon(Icons.person_outline_rounded, color: AppColors.accentFg)),
                title: Text(h.title, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
                subtitle: h.yob == null ? null : Text('Sinh ${h.yob}', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
                trailing: Icon(_isPicked(h) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: _isPicked(h) ? AppColors.accentFg : AppColors.textMuted),
              ),
            if (typed.length >= 2 && !exact)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  _toggle(_Person(null, typed));
                  _q.clear();
                  _search('');
                },
                leading: CircleAvatar(radius: 22, backgroundColor: AppColors.surface, child: Icon(Icons.add_rounded, color: AppColors.textSecondary)),
                title: Text('Thêm “$typed”', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
                subtitle: Text('Chưa có trong kho, BQT sẽ tạo khi duyệt', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
              ),
            if (!_loading && _hits.isEmpty && typed.length < 2)
              Padding(padding: const EdgeInsets.all(24), child: Text('Gõ tên để tìm', textAlign: TextAlign.center, style: body(TextStyle(fontSize: 15, color: AppColors.textMuted)))),
          ]),
        ),
      ]),
    );
  }
}
