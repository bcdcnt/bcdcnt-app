import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:http/http.dart' as http;
import 'package:pasteboard/pasteboard.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import 'comment_media.dart';
import 'quill_comment_input.dart';

class CommentSection extends StatefulWidget {
  final String type;
  final String id;
  /// When set, after the initial fetch the section keeps paginating
  /// until the comment with this id appears in the list, then scrolls
  /// the surrounding Scrollable to bring it into view and briefly
  /// flashes its background. Used by deep-links from Cảm nhận hay so
  /// the user lands on the exact quote, not page 1.
  final String? highlightCommentId;
  const CommentSection({super.key, required this.type, required this.id, this.highlightCommentId});

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  List<Map<String, dynamic>> _comments = [];
  int _total = 0;
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _submitting = false;
  // Rich-text controller for the "new comment" input. HTML in/out
  // so the wire format matches what the web already stores; inline
  // images render in-place via Quill embed builder.
  final _quillCtl = QuillCommentController();
  // Inline edit state. Only one comment can be in edit mode at a
  // time — entering edit on a second comment cancels the first.
  String? _editingId;
  QuillCommentController? _editQuillCtl;
  bool _savingEdit = false;
  // GlobalKey per highlighted comment so we can ScrollPosition.ensure-
  // visible on it once it lands. Cleared when the highlight is done.
  GlobalKey? _highlightKey;
  bool _highlightAnimating = false;
  // Guards against re-entrancy while we paginate looking for the
  // highlight target.
  bool _searchingHighlight = false;

  // @mention autocomplete state — tracked when the cursor sits inside a
  // bare `@token` token. _mentionStart is the position of the `@` (so we
  // know what range to replace when a user is picked).
  int _mentionStart = -1;
  String _mentionQuery = '';
  List<Map<String, dynamic>> _mentionResults = [];
  bool _mentionLoading = false;
  Timer? _mentionDebounce;

  @override
  void initState() {
    super.initState();
    // Mention typeahead listener — wired to a TextEditingController
    // that the Quill prototype no longer uses. Keeping the no-op
    // listener so the rest of the mention plumbing compiles; we'll
    // port it onto Quill's document changes in a follow-up.
    _fetchComments(1);
  }

  @override
  void dispose() {
    // No-op: see initState note about mention listener.
    _mentionDebounce?.cancel();
    _quillCtl.dispose();
    _editQuillCtl?.dispose();
    super.dispose();
  }

  // Detect whether the caret sits inside an `@token` token. Walks backwards
  // from the cursor stopping at whitespace; if the run starts with `@`
  // (and `@` is at start-of-string OR preceded by whitespace) we've found
  // a mention. Otherwise clears mention state.
  void _onCommentTextChanged() {
    // Mention typeahead is currently disabled while the input uses
    // Quill (rich-text). To re-enable, listen on the Quill document
    // change stream and resolve cursor position to surrounding text
    // via `Document.toPlainText()`. Left as a no-op so the rest of
    // the picker UI compiles without forcing a bigger refactor here.
  }

  void _clearMention() {
    if (_mentionStart < 0 && _mentionResults.isEmpty) return;
    _mentionDebounce?.cancel();
    setState(() {
      _mentionStart = -1;
      _mentionQuery = '';
      _mentionResults = [];
      _mentionLoading = false;
    });
  }

  void _scheduleMentionFetch(String query) {
    _mentionDebounce?.cancel();
    _mentionDebounce = Timer(const Duration(milliseconds: 200), () => _fetchMentionUsers(query));
    if (mounted) setState(() {});
  }

  Future<void> _fetchMentionUsers(String prefix) async {
    if (prefix.isEmpty) {
      // Show recent / suggested users would be nice — for now just clear
      // results so the picker doesn't flood with random members.
      if (mounted) setState(() { _mentionResults = []; _mentionLoading = false; });
      return;
    }
    if (mounted) setState(() => _mentionLoading = true);
    try {
      // Inline LIKE pattern (mirrors person_list_screen) — passing the
      // value through a GraphQL variable wasn't matching anything in
      // testing. Escape `"` to keep the query safe for usernames that
      // contain quotes (rare but possible).
      final safe = prefix.replaceAll('"', '\\"');
      final q = 'query { users(first: 5, where: {column: "username", operator: LIKE, value: "$safe%"}, orderBy: [{column: "views", order: DESC}]) { data { id username avatar { url } views } } }';
      final data = await ApiClient.query(q, {});
      final list = ((data['users']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() { _mentionResults = list; _mentionLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _mentionResults = []; _mentionLoading = false; });
    }
  }

  void _insertMention(String username) {
    // No-op: see `_onCommentTextChanged` — mention insertion will be
    // re-implemented against the Quill document in a follow-up.
    _clearMention();
  }

  String get _entityField {
    // Person types use {type}ByID(id:); others use {type}(id:)
    const personTypes = {'artist', 'composer', 'poet', 'recomposer'};
    return personTypes.contains(widget.type) ? '${widget.type}ByID' : widget.type;
  }

  Future<void> _fetchComments(int page) async {
    if (page == 1) setState(() => _loading = true); else setState(() => _loadingMore = true);
    try {
      final field = _entityField;
      final query = '''query(\$val: ID!, \$page: Int) {
        $field(id: \$val) {
          comments(first: 10, page: \$page, orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: 1}]}) {
            data {
              id content created_at nickname
              user { id username avatar { url } roles { name alias display_in_comment group_type userRolePivot { custom_title } } }
              loves(first: 50) { data { user_id } paginatorInfo { total } }
            }
            paginatorInfo { currentPage lastPage total }
          }
        }
      }''';
      final data = await ApiClient.query(query, {'val': widget.id, 'page': page});
      final result = data[field];
      final items = (result?['comments']?['data'] ?? []) as List;
      final pi = result?['comments']?['paginatorInfo'];
      if (!mounted) return;
    setState(() {
        if (page == 1) {
          _comments = items.map((e) => Map<String, dynamic>.from(e)).toList();
        } else {
          _comments.addAll(items.map((e) => Map<String, dynamic>.from(e)));
        }
        _total = pi?['total'] ?? 0;
        _hasMore = (pi?['currentPage'] ?? 0) < (pi?['lastPage'] ?? 0);
        _page = page;
      });
    } catch (_) {}
    if (!mounted) return;
    setState(() { _loading = false; _loadingMore = false; });
    // Deep-link target — keep paginating until we find it (or run
    // out of pages), then scroll to it + flash a highlight.
    if (page == 1 && widget.highlightCommentId != null && !_searchingHighlight) {
      _searchingHighlight = true;
      _hydrateHighlight();
      return;
    }
    // Auto-load remaining pages so the user doesn't have to scroll
    // all the way down to trigger infinite-scroll. Caps at 50 pages
    // (~500 comments) so a runaway thread can't burn through requests.
    if (_hasMore && _page < 50 && widget.highlightCommentId == null) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && _hasMore && !_loadingMore) _fetchComments(_page + 1);
      });
    }
  }

  /// Walks pages until the highlighted comment id surfaces, then
  /// triggers the scroll-into-view + flash. Idempotent — safely no-ops
  /// when there's nothing to find or we've exhausted pagination.
  Future<void> _hydrateHighlight() async {
    final targetId = widget.highlightCommentId;
    if (targetId == null) return;
    while (mounted) {
      final found = _comments.any((c) => c['id']?.toString() == targetId);
      if (found) break;
      if (!_hasMore) return;
      await _fetchComments(_page + 1);
    }
    if (!mounted) return;
    // Build phase needs to run before the GlobalKey can resolve, so
    // schedule the scroll for the next frame.
    setState(() {
      _highlightKey = GlobalKey();
      _highlightAnimating = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = _highlightKey?.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          alignment: 0.18,
        );
      }
      // Hold the highlight for a moment, then fade it out.
      await Future.delayed(const Duration(milliseconds: 1800));
      if (!mounted) return;
      setState(() => _highlightAnimating = false);
    });
  }

  // Pending image attachments (final URLs after upload)
  final List<String> _attachedImages = [];
  bool _uploadingImage = false;

  Future<void> _pickAndUploadImage() async {
    if (_uploadingImage || _submitting) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    final pick = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = pick?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    await _uploadImageBytes(file.bytes!, file.name, file.extension);
  }

  /// Shared upload path used by both the picker and clipboard paste.
  /// Surfaces errors through the same SnackBar the picker uses so
  /// the user gets identical feedback regardless of how the bytes
  /// landed in the input.
  Future<void> _uploadImageBytes(List<int> bytes, String filename, String? ext) async {
    if (_uploadingImage || _submitting) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;

    setState(() => _uploadingImage = true);
    try {
      // 1. presign
      final presign = await auth.authedMutate(
        r'''mutation($filename: String!, $type: UploadType!, $context: String) { presignUpload(filename: $filename, type: $type, context: $context) { upload_url key } }''',
        {'filename': filename, 'type': 'img', 'context': 'comment'},
      );
      final uploadUrl = presign['presignUpload']?['upload_url'] as String?;
      final key = presign['presignUpload']?['key'] as String?;
      if (uploadUrl == null || key == null) throw Exception('Presign failed');

      // 2. PUT to R2
      final putRes = await http.put(Uri.parse(uploadUrl), body: bytes, headers: {'Content-Type': _mimeFromExt(ext)});
      if (putRes.statusCode >= 400) throw Exception('Upload failed (${putRes.statusCode})');

      // 3. Poll status until processed
      String? finalUrl;
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final status = await ApiClient.authedQuery(r'''query($key: String!) { uploadStatus(key: $key) { status data } }''', {'key': key}, auth.token!);
        final st = status['uploadStatus']?['status'];
        if (st == 'completed') {
          final raw = status['uploadStatus']?['data'];
          final data = raw is String ? (await _tryParseJson(raw)) : raw;
          finalUrl = data?['url'] as String?;
          break;
        }
        if (st == 'failed' || st == 'error') throw Exception('Xử lý ảnh lỗi');
      }
      if (finalUrl == null) throw Exception('Hết thời gian xử lý');

      if (!mounted) return;
      // Insert at the active Quill editor's cursor. Edit mode →
      // that comment's edit editor; otherwise → the main input.
      final target = _editQuillCtl ?? _quillCtl;
      target.insertImageUrl(finalUrl!);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải ảnh: $e'), backgroundColor: AppColors.error));
    }
    if (mounted) setState(() => _uploadingImage = false);
  }

  /// Explicit-button entry point. Same flow as the keyboard
  /// shortcut but surfaces a SnackBar when the clipboard has no
  /// image so the user gets feedback instead of silence.
  Future<void> _pasteImageFromClipboard() async {
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null || bytes.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Clipboard không có ảnh'), backgroundColor: AppColors.surfaceLight),
        );
        return;
      }
      await _uploadImageBytes(bytes, 'pasted-${DateTime.now().millisecondsSinceEpoch}.png', 'png');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi dán ảnh: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  /// Handle Cmd/Ctrl+V on the comment input. The default TextField
  /// paste flow on desktop runs through Shortcuts/Actions — so a
  /// Focus.onKeyEvent listener never sees the keystroke. Binding the
  /// shortcut via `CallbackShortcuts` consumes the event entirely;
  /// we therefore re-implement the text-paste path manually here,
  /// alongside the image upload.
  Future<void> _handlePasteIntent() async {
    // 1. Check clipboard for an image first. macOS screenshots,
    //    in-browser image copies, etc. surface here.
    try {
      final bytes = await Pasteboard.image;
      if (bytes != null && bytes.isNotEmpty && mounted) {
        unawaited(_uploadImageBytes(bytes, 'pasted-${DateTime.now().millisecondsSinceEpoch}.png', 'png'));
      }
    } catch (_) {}
    // Quill handles text paste through its own clipboard manager;
    // no manual insert needed here.
  }

  String _mimeFromExt(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      default: return 'image/jpeg';
    }
  }

  Future<dynamic> _tryParseJson(String s) async {
    try { return jsonDecode(s); } catch (_) { return null; }
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    if (_quillCtl.isEmpty || !auth.isAuthenticated) return;
    setState(() => _submitting = true);
    // Quill already produces the canonical HTML format the web
    // writes (`<p>...</p>`, `<br>`, `<img src>`), so no extra
    // paragraph splitting needed.
    final content = _quillCtl.html;
    try {
      await auth.authedMutate(
        r'''mutation($type: String!, $id: Int!, $content: String!) { addComment(type: $type, object_id: $id, content: $content) { id } }''',
        {'type': widget.type, 'id': int.parse(widget.id), 'content': content},
      );
      _quillCtl.clear();
      await _fetchComments(1);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _love(String commentId, bool isLoved) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    try {
      await auth.authedMutate(
        isLoved
            ? r'''mutation($id: ID!) { unloveComment(comment_id: $id) { id } }'''
            : r'''mutation($id: ID!) { loveComment(comment_id: $id) { id } }''',
        {'id': commentId},
      );
      if (!mounted) return;
    setState(() {
        final idx = _comments.indexWhere((c) => c['id'].toString() == commentId);
        if (idx >= 0) {
          final c = _comments[idx];
          final loves = List<Map<String, dynamic>>.from((c['loves']?['data'] ?? []) as List);
          final userId = auth.user?['id'];
          if (isLoved) {
            loves.removeWhere((l) => l['user_id'].toString() == userId.toString());
          } else {
            loves.add({'user_id': userId});
          }
          final total = (c['loves']?['paginatorInfo']?['total'] ?? 0) + (isLoved ? -1 : 1);
          _comments[idx] = {
            ...c,
            'loves': {'data': loves, 'paginatorInfo': {'total': total < 0 ? 0 : total}},
          };
        }
      });
    } catch (_) {}
  }

  void _startEdit(Map<String, dynamic> c) {
    final html = (c['content'] ?? '').toString();
    // Tear down any prior edit session — switching from one comment
    // straight to another shouldn't leak the old Quill document.
    _editQuillCtl?.dispose();
    setState(() {
      _editingId = c['id']?.toString();
      _editQuillCtl = QuillCommentController(initialHtml: html);
    });
  }

  void _cancelEdit() {
    _editQuillCtl?.dispose();
    setState(() {
      _editingId = null;
      _editQuillCtl = null;
    });
  }

  Future<void> _saveEdit(Map<String, dynamic> c) async {
    final ctl = _editQuillCtl;
    if (_savingEdit || ctl == null || ctl.isEmpty) return;
    setState(() => _savingEdit = true);
    final html = ctl.html;
    try {
      final auth = context.read<AuthProvider>();
      final data = await auth.authedMutate(
        r'mutation($id: ID!, $content: String!) { updateComment(id: $id, content: $content) { id content } }',
        {'id': c['id'].toString(), 'content': html},
      );
      if (!mounted) return;
      final updated = data['updateComment'];
      _editQuillCtl?.dispose();
      setState(() {
        if (updated != null) {
          final idx = _comments.indexWhere((x) => x['id'].toString() == c['id'].toString());
          if (idx >= 0) _comments[idx] = {..._comments[idx], 'content': updated['content']};
        }
        _editingId = null;
        _editQuillCtl = null;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi sửa: $e'), backgroundColor: AppColors.error));
    }
    if (mounted) setState(() => _savingEdit = false);
  }

  Future<void> _confirmDelete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Xoá bình luận', style: display(TextStyle(color: AppColors.text))),
        content: Text('Bạn có chắc muốn xoá bình luận này?', style: body(TextStyle(color: AppColors.textSecondary))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xoá', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final auth = context.read<AuthProvider>();
      await auth.authedMutate(
        r'mutation($id: ID!) { deleteComment(id: $id) { id } }',
        {'id': c['id'].toString()},
      );
      if (!mounted) return;
      setState(() {
        _comments.removeWhere((x) => x['id'].toString() == c['id'].toString());
        if (_total > 0) _total--;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xoá: $e'), backgroundColor: AppColors.error));
    }
  }

  /// HTML → plain text that round-trips with `_submit` / `_saveEdit`:
  /// each `<p>` becomes its own paragraph, `<br>` becomes a single
  /// newline. So a comment saved as `<p>a<br>b</p><p>c</p>` reloads
  /// as "a\nb\n\nc" — exactly what the user originally typed.
  String _htmlToPlainText(String html) {
    var s = html;
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</p>\s*<p[^>]*>', caseSensitive: false), '\n\n');
    s = s.replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    return s.trim();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final userId = auth.user?['id'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Text('Bình luận', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text)),
            if (_total > 0) ...[
              const SizedBox(width: 6),
              Text('($_total)', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Input
        if (auth.isAuthenticated)
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderSubtle)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // @mention picker — appears above the input when the
                // cursor sits inside an `@token`. Tap to insert.
                if (_mentionStart >= 0 && (_mentionResults.isNotEmpty || _mentionLoading || _mentionQuery.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: _mentionLoading && _mentionResults.isEmpty
                          ? Padding(padding: const EdgeInsets.all(10), child: Row(children: [
                              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight)),
                              const SizedBox(width: 8),
                              Text('Đang tìm @${_mentionQuery}...', style: body(TextStyle(fontSize: 12, color: AppColors.textMuted))),
                            ]))
                          : _mentionResults.isEmpty
                              ? Padding(padding: const EdgeInsets.all(10), child: Text('Không có thành viên @${_mentionQuery}', style: body(TextStyle(fontSize: 12, color: AppColors.textMuted))))
                              : Column(mainAxisSize: MainAxisSize.min, children: _mentionResults.map((u) {
                                  final username = u['username']?.toString() ?? '';
                                  final avatar = u['avatar']?['url']?.toString();
                                  return InkWell(
                                    onTap: () => _insertMention(username),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      child: Row(children: [
                                        CircleAvatar(
                                          radius: 12,
                                          backgroundColor: AppColors.surface,
                                          backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
                                          child: avatar == null ? Icon(Icons.person, size: 12, color: AppColors.textMuted) : null,
                                        ),
                                        const SizedBox(width: 8),
                                        Text('@$username', style: body(TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w600))),
                                      ]),
                                    ),
                                  );
                                }).toList()),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.surfaceLight,
                        backgroundImage: auth.user?['avatar'] != null ? CachedNetworkImageProvider(auth.user!['avatar']) : null,
                        child: auth.user?['avatar'] == null ? Icon(Icons.person, size: 14, color: AppColors.textMuted) : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: QuillCommentInput(
                        controller: _quillCtl,
                        hintText: 'Viết bình luận...',
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 42),
                  child: Row(children: [
                    IconButton(
                      icon: _uploadingImage
                          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
                          : Icon(Icons.image_outlined, size: 18, color: AppColors.textSecondary),
                      onPressed: _uploadingImage ? null : _pickAndUploadImage,
                      tooltip: 'Đính kèm ảnh',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    IconButton(
                      icon: Icon(Icons.content_paste_go_outlined, size: 16, color: AppColors.textSecondary),
                      onPressed: _uploadingImage ? null : _pasteImageFromClipboard,
                      tooltip: 'Dán ảnh từ clipboard',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    if (_uploadingImage && _editingId == null) ...[
                      const SizedBox(width: 4),
                      Text('Đang tải ảnh...', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                    const Spacer(),
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: _submitting ? AppColors.surfaceLight : AppColors.accent, shape: BoxShape.circle),
                      child: IconButton(
                        icon: const Icon(Icons.send, size: 16, color: Colors.white),
                        onPressed: _submitting ? null : _submit,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          )
        else
          Text('Đăng nhập để bình luận', style: AppText.meta),

        const SizedBox(height: 20),

        if (_loading)
          Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.accent)))
        else if (_comments.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Chưa có bình luận nào', style: AppText.bodyText)))
        else ...[
          ..._comments.map((c) {
            final user = c['user'] ?? {};
            final loves = (c['loves']?['data'] ?? []) as List;
            final loveCount = c['loves']?['paginatorInfo']?['total'] ?? 0;
            final isLoved = userId != null && loves.any((l) => l['user_id'].toString() == userId.toString());
            final roles = ((user['roles'] ?? []) as List).where((r) => r != null && r['display_in_comment'] == true).toList();
            final content = (c['content'] ?? '').toString();
            final isOwn = userId != null && user['id']?.toString() == userId.toString();
            final isHighlight = widget.highlightCommentId != null && c['id']?.toString() == widget.highlightCommentId;
            return AnimatedContainer(
              key: isHighlight ? _highlightKey : null,
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(bottom: 16),
              padding: isHighlight ? const EdgeInsets.fromLTRB(10, 10, 10, 10) : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: isHighlight && _highlightAnimating
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : Colors.transparent,
                border: isHighlight && _highlightAnimating
                    ? Border.all(color: AppColors.accentLight.withValues(alpha: 0.6), width: 1)
                    : Border.all(color: Colors.transparent, width: 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: user['id'] != null ? () => context.push('/user/${user['id']}') : null,
                    borderRadius: BorderRadius.circular(20),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.surfaceLight,
                      backgroundImage: user['avatar']?['url'] != null ? CachedNetworkImageProvider(user['avatar']['url']) : null,
                      child: user['avatar']?['url'] == null ? Icon(Icons.person, size: 16, color: AppColors.textMuted) : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          InkWell(
                            onTap: user['id'] != null ? () => context.push('/user/${user['id']}') : null,
                            child: Text(user['username'] ?? c['nickname'] ?? 'Ẩn danh', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
                          ),
                          ...roles.map((r) {
                            final label = r['userRolePivot']?['custom_title'] ?? r['name'] ?? r['alias'] ?? '';
                            final alias = (r['alias'] ?? '').toString();
                            final group = (r['group_type'] ?? '').toString();
                            Color color = AppColors.accentLight;
                            if (alias == 'admin' || alias == 'ban') color = const Color(0xFFE74C3C);
                            else if (alias == 'mod') color = const Color(0xFF3498DB);
                            else if (group == 'nhom') color = const Color(0xFF2ECC71);
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                              child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                            );
                          }),
                          Text(timeago(c['created_at']), style: AppText.caption),
                        ]),
                        const SizedBox(height: 4),
                        if (_editingId == c['id']?.toString()) ...[
                          // Inline edit mode — replaces the comment
                          // body with a text field + save/cancel
                          // affordances. Mirrors the "Add comment"
                          // input style so it feels at home.
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: _editQuillCtl == null
                                ? const SizedBox.shrink()
                                : QuillCommentInput(
                                    controller: _editQuillCtl!,
                                    hintText: 'Sửa bình luận...',
                                    autofocus: true,
                                  ),
                          ),
                          if (_uploadingImage && _editingId == c['id']?.toString()) Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(children: [
                              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight)),
                              const SizedBox(width: 8),
                              Text('Đang tải ảnh lên...', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ]),
                          ),
                          const SizedBox(height: 6),
                          Row(children: [
                            TextButton(
                              onPressed: _savingEdit ? null : () => _saveEdit(c),
                              style: TextButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                minimumSize: const Size(0, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(_savingEdit ? 'Đang lưu…' : 'Lưu', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _savingEdit ? null : _cancelEdit,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: const Size(0, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text('Huỷ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            ),
                            const Spacer(),
                            // Paste image into THIS edit input — the
                            // upload routes into `_editAttachedImages`
                            // because `_editingId` is set.
                            IconButton(
                              icon: Icon(Icons.content_paste_go_outlined, size: 16, color: AppColors.textSecondary),
                              onPressed: _uploadingImage ? null : _pasteImageFromClipboard,
                              tooltip: 'Dán ảnh từ clipboard',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                            IconButton(
                              icon: Icon(Icons.image_outlined, size: 16, color: AppColors.textSecondary),
                              onPressed: _uploadingImage ? null : _pickAndUploadImage,
                              tooltip: 'Đính kèm ảnh',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                          ]),
                        ] else
                          CommentMedia(html: content, authorName: user['username']?.toString() ?? c['nickname']?.toString()),
                        const SizedBox(height: 4),
                        // Hide the like/edit/delete action row while
                        // this very comment is being edited — the
                        // inline form above already exposes Lưu/Huỷ,
                        // and the like target wouldn't be the
                        // current text anyway.
                        if (_editingId != c['id']?.toString()) Row(children: [
                          InkWell(
                            onTap: () => _love(c['id'].toString(), isLoved),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(isLoved ? Icons.favorite : Icons.favorite_border, size: 14, color: isLoved ? AppColors.error : AppColors.textMuted),
                                if (loveCount > 0) ...[
                                  const SizedBox(width: 4),
                                  Text('$loveCount', style: TextStyle(fontSize: 11, color: isLoved ? AppColors.error : AppColors.textMuted)),
                                ],
                              ],
                            ),
                          ),
                          if (isOwn) ...[
                            SizedBox(width: 14),
                            InkWell(
                              onTap: () => _startEdit(c),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.edit_outlined, size: 13, color: AppColors.textMuted),
                                SizedBox(width: 3),
                                Text('Sửa', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              ]),
                            ),
                            SizedBox(width: 10),
                            InkWell(
                              onTap: () => _confirmDelete(c),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.delete_outline, size: 13, color: AppColors.textMuted),
                                SizedBox(width: 3),
                                Text('Xoá', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              ]),
                            ),
                          ],
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (_hasMore)
            _LoadMoreSentinel(
              loading: _loadingMore,
              onReach: () {
                if (!_loadingMore && _hasMore) _fetchComments(_page + 1);
              },
            ),
        ],
      ],
    );
  }
}

/// Sentinel that triggers `onReach` when it scrolls into the viewport of
/// the nearest enclosing Scrollable. Used at the tail of a paginated list
/// to enable infinite scroll without an explicit "Load more" button.
class _LoadMoreSentinel extends StatefulWidget {
  final bool loading;
  final VoidCallback onReach;
  const _LoadMoreSentinel({required this.loading, required this.onReach});

  @override
  State<_LoadMoreSentinel> createState() => _LoadMoreSentinelState();
}

class _LoadMoreSentinelState extends State<_LoadMoreSentinel> {
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollable = Scrollable.maybeOf(context);
    final newPos = scrollable?.position;
    if (newPos != _position) {
      _position?.removeListener(_check);
      _position = newPos;
      _position?.addListener(_check);
      // Initial check in case the sentinel is already visible without
      // scrolling (short list).
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!mounted || widget.loading) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || _position == null) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final reveal = viewport.getOffsetToReveal(box, 0.0).offset;
    // Trigger when sentinel's position is within ~300px of the current
    // viewport so we prefetch before the user hits the bottom.
    if (reveal - _position!.pixels < 300) {
      widget.onReach();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: widget.loading
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
            : const SizedBox(width: 1, height: 1),
      ),
    );
  }
}
