import '../services/imgcdn.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:pasteboard/pasteboard.dart';
import '../constants/theme.dart';
import 'ui.dart' show PillButton, OfflineBlock, SkeletonSongRow;
import '../services/api.dart';
import '../services/push.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import 'comment_actions.dart';
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
  /// A comment action changed the page itself (lyric, recording, picture…).
  final VoidCallback? onPageChanged;
  /// Locked discussion: comments stay readable, the composer is replaced by a note.
  final bool readOnly;
  const CommentSection({super.key, required this.type, required this.id, this.highlightCommentId, this.onPageChanged, this.readOnly = false});

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  List<Map<String, dynamic>> _comments = [];
  int _total = 0;
  int _page = 1;
  bool _hasMore = false;
  bool _loadError = false;
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
  // Audio / video attachments. Quill only handles images inline;
  // audio + video upload as separate attachments and append to
  // the comment HTML as `<audio>` / `<video>` blocks at submit time
  // (same shape the web stores).
  final List<String> _attachedAudios = [];
  final List<String> _attachedVideos = [];
  bool _uploadingAudio = false;
  bool _uploadingVideo = false;
  // Same for the inline-edit composer.
  final List<String> _editAttachedAudios = [];
  final List<String> _editAttachedVideos = [];
  // Subscription on the Quill document — drives the `@` mention
  // typeahead. Re-attached when the edit-mode controller is
  // created so mentions also work mid-edit.
  StreamSubscription? _quillDocSub;
  StreamSubscription? _editQuillDocSub;
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
    // Drive @mention detection off the Quill document. Every edit
    // fires here; we re-evaluate the text around the caret and
    // surface the picker if it matches `@token`.
    _quillDocSub = _quillCtl.documentChanges.listen((_) {
      _onActiveCommentTextChanged(_quillCtl);
    });
    _fetchComments(1);
  }

  @override
  void dispose() {
    _quillDocSub?.cancel();
    _editQuillDocSub?.cancel();
    _mentionDebounce?.cancel();
    _quillCtl.dispose();
    _editQuillCtl?.dispose();
    super.dispose();
  }

  // Detect whether the caret sits inside an `@token` token. Walks backwards
  // from the cursor stopping at whitespace; if the run starts with `@`
  // (and `@` is at start-of-string OR preceded by whitespace) we've found
  // a mention. Otherwise clears mention state.
  // Tracks which controller's `@token` we're currently completing,
  // so `_insertMention` knows whether to write into the main
  // composer or the inline-edit composer.
  QuillCommentController? _mentionTarget;

  /// Walks backwards from the cursor in the active Quill editor and
  /// flips the mention picker on when it finds an `@token` run.
  void _onActiveCommentTextChanged(QuillCommentController ctl) {
    final text = ctl.plainText;
    final cursor = ctl.cursorOffset;
    if (cursor < 0 || cursor > text.length) { _clearMention(); return; }
    int i = cursor - 1;
    while (i >= 0) {
      final ch = text[i];
      if (ch == ' ' || ch == '\n' || ch == '\t') { _clearMention(); return; }
      if (ch == '@') {
        if (i == 0 || text[i - 1] == ' ' || text[i - 1] == '\n') {
          final query = text.substring(i + 1, cursor);
          setState(() {
            _mentionStart = i;
            _mentionQuery = query;
            _mentionTarget = ctl;
          });
          _scheduleMentionFetch(query);
          return;
        } else {
          _clearMention();
          return;
        }
      }
      i--;
    }
    _clearMention();
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
    final ctl = _mentionTarget;
    if (ctl == null || _mentionStart < 0) { _clearMention(); return; }
    final cursor = ctl.cursorOffset;
    final length = (cursor - _mentionStart).clamp(0, ctl.plainText.length);
    ctl.replaceTextAt(_mentionStart, length, '@$username ');
    _clearMention();
  }

  /// "Trả lời": start the composer with @name and bring it into view.
  void _replyTo(String? username) {
    if (username == null || username.isEmpty) return;
    final text = _quillCtl.plainText.trimRight();
    final mention = '@$username ';
    if (!text.contains(mention.trim())) _quillCtl.replaceTextAt(0, 0, mention);
    _quillCtl.requestFocus();
    final ctx = _composerKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), alignment: 0.2);
  }

  final _composerKey = GlobalKey();

  /// "No comments yet" in words that fit the page it sits on.
  String get _emptyText {
    switch (widget.type) {
      case 'song': case 'folk': case 'instrumental': case 'poem': case 'karaoke':
        return 'Hãy là người đầu tiên chia sẻ cảm nghĩ hay kỷ niệm với bài hát này.';
      case 'artist': case 'composer': case 'poet': case 'recomposer':
        return 'Chưa có bình luận. Hãy chia sẻ cảm nghĩ hay kỷ niệm của bạn về người này.';
      case 'ticket':
        return 'Chưa có trao đổi nào. Bạn có thể viết thêm thông tin ở đây.';
      case 'playlist':
        return 'Chưa có bình luận. Hãy là người đầu tiên chia sẻ cảm nghĩ về playlist này.';
      case 'document':
        return 'Chưa có bình luận. Hãy là người đầu tiên chia sẻ cảm nghĩ về tư liệu này.';
      case 'discussion':
        return 'Chưa có ai trả lời. Hãy là người đầu tiên góp ý kiến.';
      default:
        return 'Chưa có bình luận. Hãy là người đầu tiên chia sẻ cảm nghĩ.';
    }
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
      // Count comes from paginatorInfo.total; "did I like it" from a
      // user_id-filtered alias, so it is right even past the first rows.
      final meId = int.tryParse('${context.read<AuthProvider>().user?['id'] ?? ''}');
      final myLove = meId == null ? '' : 'myLove: loves(first: 1, where: {column: "user_id", value: $meId}) { paginatorInfo { total } }';
      final query = '''query(\$val: ID!, \$page: Int) {
        $field(id: \$val) {
          comments(first: 10, page: \$page, orderBy: [{column: "id", order: DESC}], where: {AND: [{column: "status", value: 1}]}) {
            data {
              id content created_at nickname is_request request_status processRequestUser { id username }
              user { id username avatar { url } roles { name alias display_in_comment group_type userRolePivot { custom_title } } }
              loves(first: 1) { paginatorInfo { total } }
              $myLove
            }
            paginatorInfo { currentPage lastPage total }
          }
        }
      }''';
      // Tickets are private (only the author and BQT can read them), so
      // their comments need the session; public pages stay anonymous so
      // the edge cache keeps serving them.
      final auth = context.read<AuthProvider>();
      final data = widget.type == 'ticket' && auth.isAuthenticated
          ? await auth.authedQuery(query, {'val': widget.id, 'page': page})
          : await ApiClient.query(query, {'val': widget.id, 'page': page});
      final result = data[field];
      final items = (result?['comments']?['data'] ?? []) as List;
      final pi = result?['comments']?['paginatorInfo'];
      if (!mounted) return;
    setState(() {
        if (page == 1) {
          _comments = items.map((e) => Map<String, dynamic>.from(e)).toList();
        } else {
          // A new comment posted meanwhile shifts the pages: skip rows
          // we already show so nobody sees the same comment twice.
          final seen = _comments.map((c) => c['id']?.toString()).toSet();
          _comments.addAll(items
              .map((e) => Map<String, dynamic>.from(e))
              .where((c) => seen.add(c['id']?.toString())));
        }
        _total = pi?['total'] ?? 0;
        _hasMore = (pi?['currentPage'] ?? 0) < (pi?['lastPage'] ?? 0);
        _page = page;
        _loadError = false;
      });
    } catch (_) {
      // Never retry by itself: offline that became ~5 requests a second.
      if (mounted) setState(() { _loading = false; _loadingMore = false; _loadError = true; });
      return;
    }
    if (!mounted) return;
    setState(() { _loading = false; _loadingMore = false; });
    // Deep-link target — keep paginating until we find it (or run
    // out of pages), then scroll to it + flash a highlight.
    if (page == 1 && widget.highlightCommentId != null && !_searchingHighlight) {
      _searchingHighlight = true;
      _hydrateHighlight();
      return;
    }
    // No background loading of every page: 10 at a time, more on request
    // ("Xem thêm bình luận"), per the project's page-based rule.
  }

  /// Walks pages until the highlighted comment id surfaces, then
  /// triggers the scroll-into-view + flash. Idempotent — safely no-ops
  /// when there's nothing to find or we've exhausted pagination.
  Future<void> _hydrateHighlight() async {
    final targetId = widget.highlightCommentId;
    if (targetId == null) return;
    // Bounded walk: stop on a failed page (offline would otherwise re-ask
    // the same page in a tight loop) and after ~10 pages.
    var tries = 0;
    while (mounted) {
      final found = _comments.any((c) => c['id']?.toString() == targetId);
      if (found) break;
      if (!_hasMore || _loadError || tries >= 10) { _searchingHighlight = false; return; }
      tries++;
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
      target.insertImageUrl(finalUrl);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không tải được ảnh lên. ${friendlyError(e)}'), backgroundColor: AppColors.error));
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
          SnackBar(content: const Text('Chưa có ảnh nào được sao chép để dán'), backgroundColor: AppColors.surfaceLight),
        );
        return;
      }
      await _uploadImageBytes(bytes, 'pasted-${DateTime.now().millisecondsSinceEpoch}.png', 'png');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không dán được ảnh. ${friendlyError(e)}'), backgroundColor: AppColors.error),
      );
    }
  }

  String _mimeFromExt(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'mp3': return 'audio/mpeg';
      case 'm4a': return 'audio/mp4';
      case 'wav': return 'audio/wav';
      case 'ogg': return 'audio/ogg';
      case 'flac': return 'audio/flac';
      case 'mp4': return 'video/mp4';
      case 'mov': return 'video/quicktime';
      case 'webm': return 'video/webm';
      case 'mkv': return 'video/x-matroska';
      default: return 'image/jpeg';
    }
  }

  Future<void> _pickAndUploadAudio() async {
    if (_uploadingAudio) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3','m4a','wav','ogg','flac','aac'],
      withData: true,
    );
    final file = pick?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    await _uploadMediaBytes(file.bytes!, file.name, file.extension, isAudio: true);
  }

  Future<void> _pickAndUploadVideo() async {
    if (_uploadingVideo) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4','mov','webm','mkv'],
      withData: true,
    );
    final file = pick?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    await _uploadMediaBytes(file.bytes!, file.name, file.extension, isAudio: false);
  }

  /// Upload audio or video. The API treats both as `UploadType.mp3`
  /// (server-side transcoder handles audio→mp3 / video→mp4) — same
  /// contract the web's MediaLibrary uses.
  Future<void> _uploadMediaBytes(List<int> bytes, String filename, String? ext, {required bool isAudio}) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    setState(() {
      if (isAudio) { _uploadingAudio = true; } else { _uploadingVideo = true; }
    });
    try {
      final presign = await auth.authedMutate(
        r'''mutation($filename: String!, $type: UploadType!, $context: String) { presignUpload(filename: $filename, type: $type, context: $context) { upload_url key } }''',
        {'filename': filename, 'type': 'mp3', 'context': 'comment'},
      );
      final uploadUrl = presign['presignUpload']?['upload_url'] as String?;
      final key = presign['presignUpload']?['key'] as String?;
      if (uploadUrl == null || key == null) throw Exception('Presign failed');
      final putRes = await http.put(Uri.parse(uploadUrl), body: bytes, headers: {'Content-Type': _mimeFromExt(ext)});
      if (putRes.statusCode >= 400) throw Exception('Upload failed (${putRes.statusCode})');
      // Audio/video transcoding takes longer than image processing
      // — poll with a wider window before giving up.
      String? finalUrl;
      for (int i = 0; i < 180; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final status = await ApiClient.authedQuery(
          r'''query($key: String!) { uploadStatus(key: $key) { status data } }''',
          {'key': key},
          auth.token!,
        );
        final st = status['uploadStatus']?['status'];
        if (st == 'completed') {
          final raw = status['uploadStatus']?['data'];
          final data = raw is String ? (await _tryParseJson(raw)) : raw;
          finalUrl = data?['url'] as String?;
          break;
        }
        if (st == 'failed' || st == 'error') throw Exception('Xử lý ${isAudio ? "audio" : "video"} lỗi');
      }
      if (finalUrl == null) throw Exception('Hết thời gian xử lý');
      if (!mounted) return;
      final inEdit = _editingId != null;
      setState(() {
        if (isAudio) {
          (inEdit ? _editAttachedAudios : _attachedAudios).add(finalUrl!);
        } else {
          (inEdit ? _editAttachedVideos : _attachedVideos).add(finalUrl!);
        }
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không tải được ${isAudio ? "bản ghi âm" : "video"} lên. ${friendlyError(e)}'), backgroundColor: AppColors.error));
    }
    if (mounted) setState(() {
      if (isAudio) { _uploadingAudio = false; } else { _uploadingVideo = false; }
    });
  }

  Future<dynamic> _tryParseJson(String s) async {
    try { return jsonDecode(s); } catch (_) { return null; }
  }

  /// Single "attach" entry point — paperclip icon that opens a
  /// menu with Ảnh / Dán ảnh / Audio / Video. Shows a spinner
  /// whenever any upload is in progress so the user knows
  /// background work is happening even though the toolbar is
  /// collapsed.
  Widget _attachMenuButton() {
    final busy = _uploadingImage || _uploadingAudio || _uploadingVideo;
    return PopupMenuButton<String>(
      tooltip: 'Đính kèm',
      position: PopupMenuPosition.over,
      enabled: !busy,
      onSelected: (v) {
        switch (v) {
          case 'image': _pickAndUploadImage(); break;
          case 'paste': _pasteImageFromClipboard(); break;
          case 'audio': _pickAndUploadAudio(); break;
          case 'video': _pickAndUploadVideo(); break;
        }
      },
      itemBuilder: (_) => [
        _attachItem('image', Icons.image_outlined, 'Ảnh'),
        _attachItem('paste', Icons.content_paste_go_outlined, 'Dán ảnh'),
        _attachItem('audio', Icons.audiotrack_outlined, 'Ghi âm / bài hát'),
        _attachItem('video', Icons.videocam_outlined, 'Video'),
      ],
      icon: busy
          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
          : Icon(Icons.attach_file, size: 24, color: AppColors.textSecondary),
      padding: EdgeInsets.zero,
      iconSize: 24,
      splashRadius: 24,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }

  PopupMenuItem<String> _attachItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      height: 48,
      child: Row(children: [
        Icon(icon, size: 22, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 15, color: AppColors.text)),
      ]),
    );
  }

  /// Render attached audio + video as chips below the input. Audio
  /// shows a music-note icon; video shows a film-strip icon. Each
  /// has a close button to remove before submit.
  Widget _buildMediaChipsStrip({
    required List<String> audios,
    required List<String> videos,
    required void Function(int) onRemoveAudio,
    required void Function(int) onRemoveVideo,
  }) {
    final chips = <Widget>[];
    for (var i = 0; i < audios.length; i++) {
      chips.add(_mediaChip(label: 'Ghi âm ${i + 1}', icon: Icons.audiotrack, onRemove: () => onRemoveAudio(i)));
    }
    for (var i = 0; i < videos.length; i++) {
      chips.add(_mediaChip(label: 'Video ${i + 1}', icon: Icons.videocam, onRemove: () => onRemoveVideo(i)));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 36),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  Widget _mediaChip({required String label, required IconData icon, required VoidCallback onRemove}) {
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 15, color: AppColors.text)),
        Semantics(
          button: true,
          label: 'Bỏ $label',
          excludeSemantics: true,
          child: InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: SizedBox(width: 48, height: 48, child: Icon(Icons.close, size: 20, color: AppColors.textMuted)),
          ),
        ),
      ]),
    );
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final hasMedia = _attachedAudios.isNotEmpty || _attachedVideos.isNotEmpty;
    if ((_quillCtl.isEmpty && !hasMedia) || !auth.isAuthenticated) return;
    setState(() => _submitting = true);
    // Quill emits the rich-text body (images inline, paragraphs).
    // Audio/video aren't Quill embeds — append them as raw <audio>/
    // <video> blocks at the end, matching the web's storage shape.
    final body = _quillCtl.isEmpty ? '' : _quillCtl.html;
    final audioHtml = _attachedAudios.map((u) => '<p><audio controls src="$u"></audio></p>').join();
    final videoHtml = _attachedVideos.map((u) => '<p><video controls src="$u"></video></p>').join();
    final content = '$body$audioHtml$videoHtml';
    try {
      await auth.authedMutate(
        r'''mutation($type: String!, $id: Int!, $content: String!) { addComment(type: $type, object_id: $id, content: $content) { id } }''',
        {'type': widget.type, 'id': int.parse(widget.id), 'content': content},
      );
      _quillCtl.clear();
      _attachedAudios.clear();
      _attachedVideos.clear();
      await _fetchComments(1);
      if (mounted) PushService.instance.maybeAsk(context, reason: 'Biết ngay khi có người trả lời hoặc thích bình luận của bạn.');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chưa đăng được bình luận. ${friendlyError(e)}'), backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  final Set<String> _lovingIds = {};

  /// Applies a like/unlike to one comment row locally.
  void _setLoved(String commentId, bool loved) {
    final idx = _comments.indexWhere((c) => c['id'].toString() == commentId);
    if (idx < 0) return;
    final c = _comments[idx];
    final total = ((c['loves']?['paginatorInfo']?['total'] ?? 0) as num).toInt() + (loved ? 1 : -1);
    _comments[idx] = {
      ...c,
      'loves': {'paginatorInfo': {'total': total < 0 ? 0 : total}},
      'myLove': {'paginatorInfo': {'total': loved ? 1 : 0}},
    };
  }

  Future<void> _love(String commentId, bool isLoved) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      await askLogin(context);
      return;
    }
    // One request per comment at a time: a double tap must not race.
    if (!_lovingIds.add(commentId)) return;
    setState(() => _setLoved(commentId, !isLoved));
    try {
      // Same mutation as the web (there is no loveComment/unloveComment).
      await auth.authedMutate(
        isLoved
            ? r'''mutation($id: ID!) { unlove(lovable_id: $id, lovable_type: "comment") { id } }'''
            : r'''mutation($id: ID!) { love(lovable_id: $id, lovable_type: "comment") { id } }''',
        {'id': commentId},
      );
    } catch (e) {
      if (mounted) {
        setState(() => _setLoved(commentId, isLoved));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${isLoved ? 'Chưa bỏ thích được' : 'Chưa thích được'}. ${friendlyError(e)}'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      _lovingIds.remove(commentId);
    }
  }

  Future<void> _openActions(Map<String, dynamic> c) async {
    final change = await showCommentActions(context, comment: c, type: widget.type, objectId: widget.id);
    if (!mounted || change == null) return;
    final cid = c['id'].toString();
    switch (change) {
      case CommentUpdated(:final fields):
        setState(() {
          final i = _comments.indexWhere((x) => x['id'].toString() == cid);
          if (i >= 0) _comments[i] = {..._comments[i], ...fields};
        });
      case CommentRemoved():
        setState(() {
          _comments.removeWhere((x) => x['id'].toString() == cid);
          if (_total > 0) _total--;
        });
      case CommentEditRequested():
        _startEdit(c);
      case CommentPageChanged():
        widget.onPageChanged?.call();
    }
  }

  void _startEdit(Map<String, dynamic> c) {
    final html = (c['content'] ?? '').toString();
    // Tear down any prior edit session — switching from one comment
    // straight to another shouldn't leak the old Quill document.
    _editQuillDocSub?.cancel();
    _editQuillCtl?.dispose();
    final ctl = QuillCommentController(initialHtml: html);
    _editQuillDocSub = ctl.documentChanges.listen((_) {
      _onActiveCommentTextChanged(ctl);
    });
    // Seed audio/video chips from the existing comment so the user
    // can drop or keep them; new uploads land in the same lists.
    final audios = <String>[];
    final videos = <String>[];
    for (final m in RegExp(r'<audio[^>]*src="([^"]+)"', caseSensitive: false).allMatches(html)) {
      final u = m.group(1); if (u != null) audios.add(u);
    }
    for (final m in RegExp(r'<video[^>]*src="([^"]+)"', caseSensitive: false).allMatches(html)) {
      final u = m.group(1); if (u != null) videos.add(u);
    }
    setState(() {
      _editingId = c['id']?.toString();
      _editQuillCtl = ctl;
      _editAttachedAudios..clear()..addAll(audios);
      _editAttachedVideos..clear()..addAll(videos);
    });
  }

  void _cancelEdit() {
    _editQuillDocSub?.cancel();
    _editQuillCtl?.dispose();
    setState(() {
      _editingId = null;
      _editQuillCtl = null;
      _editQuillDocSub = null;
      _editAttachedAudios.clear();
      _editAttachedVideos.clear();
    });
  }

  Future<void> _saveEdit(Map<String, dynamic> c) async {
    final ctl = _editQuillCtl;
    final hasMedia = _editAttachedAudios.isNotEmpty || _editAttachedVideos.isNotEmpty;
    if (_savingEdit || ctl == null || (ctl.isEmpty && !hasMedia)) return;
    setState(() => _savingEdit = true);
    final body = ctl.isEmpty ? '' : ctl.html;
    final audioHtml = _editAttachedAudios.map((u) => '<p><audio controls src="$u"></audio></p>').join();
    final videoHtml = _editAttachedVideos.map((u) => '<p><video controls src="$u"></video></p>').join();
    final html = '$body$audioHtml$videoHtml';
    try {
      final auth = context.read<AuthProvider>();
      final data = await auth.authedMutate(
        r'mutation($id: ID!, $content: String!) { updateComment(id: $id, content: $content) { id content } }',
        {'id': c['id'].toString(), 'content': html},
      );
      if (!mounted) return;
      final updated = data['updateComment'];
      _editQuillDocSub?.cancel();
      _editQuillCtl?.dispose();
      setState(() {
        if (updated != null) {
          final idx = _comments.indexWhere((x) => x['id'].toString() == c['id'].toString());
          if (idx >= 0) _comments[idx] = {..._comments[idx], 'content': updated['content']};
        }
        _editingId = null;
        _editQuillCtl = null;
        _editQuillDocSub = null;
        _editAttachedAudios.clear();
        _editAttachedVideos.clear();
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chưa lưu được. ${friendlyError(e)}'), backgroundColor: AppColors.error));
    }
    if (mounted) setState(() => _savingEdit = false);
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
        if (widget.readOnly)
          Text('Chủ đề đã khoá, không nhận thêm bình luận.', style: body(TextStyle(fontSize: 15, color: AppColors.textMuted)))
        else if (auth.isAuthenticated)
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
                                          backgroundImage: avatar != null ? CachedNetworkImageProvider(cdnImg((avatar).toString(), 160)) : null,
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
                // Compose card — input + media toolbar live inside a
                // single rounded panel so the surface feels like a
                // standalone "post box" (Threads/Twitter style),
                // and the send button sits in the bottom-right
                // corner of that same panel.
                Container(
                  padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Discord/Telegram-style row: avatar + input grow
                    // horizontally and the send pill rides at the
                    // bottom of the row so it always sits beside
                    // the last line of text. Bottom-aligning means
                    // the button stays put when the input is empty
                    // and follows the input as it grows multi-line.
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.surface,
                        backgroundImage: auth.user?['avatar'] != null ? CachedNetworkImageProvider(cdnImg((auth.user!['avatar']).toString(), 160)) : null,
                        child: auth.user?['avatar'] == null ? Icon(Icons.person, size: 12, color: AppColors.textMuted) : null,
                      ),
                      const SizedBox(width: 4),
                      _attachMenuButton(),
                      const SizedBox(width: 2),
                      Expanded(
                        key: _composerKey,
                        child: QuillCommentInput(
                          controller: _quillCtl,
                          hintText: 'Viết bình luận...',
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send, size: 18),
                        // Nhãn cố định "Đăng" để nút không phình khi đang gửi.
                        label: const Text('Đăng', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.55),
                          disabledForegroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          minimumSize: const Size(64, 48),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ]),
                    // Attached audio / video chips below the input.
                    if (_attachedAudios.isNotEmpty || _attachedVideos.isNotEmpty)
                      _buildMediaChipsStrip(audios: _attachedAudios, videos: _attachedVideos, onRemoveAudio: (i) => setState(() => _attachedAudios.removeAt(i)), onRemoveVideo: (i) => setState(() => _attachedVideos.removeAt(i))),
                    // Inline upload status line for audio/video,
                    // which take longer than images.
                    if ((_uploadingAudio || _uploadingVideo) && _editingId == null) Padding(
                      padding: const EdgeInsets.only(top: 4, left: 36),
                      child: Text(
                        _uploadingAudio ? 'Đang tải bản ghi âm lên...' : 'Đang tải video lên...',
                        style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: PillButton(
              label: 'Đăng nhập để bình luận',
              icon: Icons.login_rounded,
              primary: false,
              onTap: () => askLogin(context),
            ),
          ),

        const SizedBox(height: 20),

        if (_loading && _comments.isEmpty)
          Column(children: [for (var i = 0; i < 3; i++) const SkeletonSongRow()])
        else if (_loadError && _comments.isEmpty)
          OfflineBlock(onRetry: () => _fetchComments(1))
        else if (_comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(_emptyText, style: body(TextStyle(fontSize: 16, height: 1.5, color: AppColors.textSecondary))),
          )
        else ...[
          ..._comments.map((c) {
            final user = c['user'] ?? {};
            final loveCount = ((c['loves']?['paginatorInfo']?['total'] ?? 0) as num).toInt();
            final isLoved = userId != null && ((c['myLove']?['paginatorInfo']?['total'] ?? 0) as num) > 0;
            final roles = ((user['roles'] ?? []) as List).where((r) => r != null && r['display_in_comment'] == true).toList();
            final content = (c['content'] ?? '').toString();
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
                      backgroundImage: user['avatar']?['url'] != null ? CachedNetworkImageProvider(cdnImg((user['avatar']['url']).toString(), 160)) : null,
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
                            child: Text(user['username'] ?? c['nickname'] ?? 'Ẩn danh', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
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
                              child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
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
                          if (_editAttachedAudios.isNotEmpty || _editAttachedVideos.isNotEmpty)
                            _buildMediaChipsStrip(
                              audios: _editAttachedAudios,
                              videos: _editAttachedVideos,
                              onRemoveAudio: (i) => setState(() => _editAttachedAudios.removeAt(i)),
                              onRemoveVideo: (i) => setState(() => _editAttachedVideos.removeAt(i)),
                            ),
                          if ((_uploadingImage || _uploadingAudio || _uploadingVideo) && _editingId == c['id']?.toString()) Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(children: [
                              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight)),
                              const SizedBox(width: 8),
                              Text(
                                _uploadingAudio ? 'Đang tải bản ghi âm lên...' : _uploadingVideo ? 'Đang tải video lên...' : 'Đang tải ảnh lên...',
                                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 6),
                          Row(children: [
                            TextButton(
                              onPressed: _savingEdit ? null : () => _saveEdit(c),
                              style: TextButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                minimumSize: const Size(64, 48),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                              child: Text(_savingEdit ? 'Đang lưu…' : 'Lưu', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _savingEdit ? null : _cancelEdit,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                minimumSize: const Size(64, 48),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text('Huỷ', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
                            ),
                            const Spacer(),
                            _attachMenuButton(),
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
                          // 48pt targets with words: older readers miss bare
                          // 14px icons.
                          Semantics(
                            button: true,
                            excludeSemantics: true,
                            label: '${isLoved ? 'Bỏ thích' : 'Thích'} bình luận${loveCount > 0 ? ', $loveCount lượt thích' : ''}',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => _love(c['id'].toString(), isLoved),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(isLoved ? Icons.favorite : Icons.favorite_border, size: 20, color: isLoved ? AppColors.error : AppColors.textMuted),
                                    const SizedBox(width: 6),
                                    Text(loveCount > 0 ? '$loveCount' : 'Thích', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isLoved ? AppColors.error : AppColors.textSecondary)),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                          if (auth.isAuthenticated && widget.type != 'ticket')
                            InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => _replyTo(user['username']?.toString() ?? c['nickname']?.toString()),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.reply_rounded, size: 20, color: AppColors.textMuted),
                                    const SizedBox(width: 6),
                                    Text('Trả lời', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                                  ]),
                                ),
                              ),
                            ),
                          if (requestBadge(c) case final b?) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: b.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.back_hand_outlined, size: 12, color: b.color),
                                const SizedBox(width: 4),
                                Text(
                                  c['processRequestUser']?['username'] != null && c['request_status'] != null ? '${b.label} bởi ${c['processRequestUser']['username']}' : b.label,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: b.color),
                                ),
                              ]),
                            ),
                          ],
                          const Spacer(),
                          if (auth.isAuthenticated)
                            IconButton(
                              tooltip: 'Tuỳ chọn bình luận',
                              onPressed: () => _openActions(c),
                              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                              icon: Icon(Icons.more_vert_rounded, size: 22, color: AppColors.textMuted),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: PillButton(
                  label: _loadError ? 'Chưa tải được · Thử lại' : 'Xem thêm bình luận (${(_total - _comments.length).clamp(0, 1 << 30)})',
                  loading: _loadingMore,
                  primary: false,
                  onTap: _loadingMore ? null : () => _fetchComments(_page + 1),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
