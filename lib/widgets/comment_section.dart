import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import 'comment_media.dart';

class CommentSection extends StatefulWidget {
  final String type;
  final String id;
  const CommentSection({super.key, required this.type, required this.id});

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
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchComments(1);
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

    setState(() => _uploadingImage = true);
    try {
      // 1. presign
      final presign = await auth.authedMutate(
        r'''mutation($filename: String!, $type: UploadType!, $context: String) { presignUpload(filename: $filename, type: $type, context: $context) { upload_url key } }''',
        {'filename': file.name, 'type': 'img', 'context': 'comment'},
      );
      final uploadUrl = presign['presignUpload']?['upload_url'] as String?;
      final key = presign['presignUpload']?['key'] as String?;
      if (uploadUrl == null || key == null) throw Exception('Presign failed');

      // 2. PUT to R2
      final putRes = await http.put(Uri.parse(uploadUrl), body: file.bytes!, headers: {'Content-Type': _mimeFromExt(file.extension)});
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
      setState(() => _attachedImages.add(finalUrl!));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải ảnh: $e'), backgroundColor: AppColors.error));
    }
    if (mounted) setState(() => _uploadingImage = false);
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
    final text = _controller.text.trim();
    if ((text.isEmpty && _attachedImages.isEmpty) || !auth.isAuthenticated) return;
    setState(() => _submitting = true);
    // Compose: text + each image as <p><img></p>
    final imgsHtml = _attachedImages.map((u) => '<p><img src="$u" alt="" /></p>').join();
    final content = text.isNotEmpty ? '<p>$text</p>$imgsHtml' : imgsHtml;
    try {
      await auth.authedMutate(
        r'''mutation($type: String!, $id: ID!, $content: String!) { addComment(commentable_type: $type, commentable_id: $id, content: $content) { id } }''',
        {'type': widget.type, 'id': widget.id, 'content': content},
      );
      _controller.clear();
      _attachedImages.clear();
      await _fetchComments(1);
    } catch (_) {}
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

  Future<void> _editComment(Map<String, dynamic> c) async {
    final controller = TextEditingController(text: _stripHtml(c['content'] ?? ''));
    final newContent = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Sửa bình luận', style: display(const TextStyle(color: AppColors.text))),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          style: body(const TextStyle(color: AppColors.text)),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Lưu', style: TextStyle(color: AppColors.accentLight))),
        ],
      ),
    );
    if (newContent == null || newContent.isEmpty) return;
    try {
      final auth = context.read<AuthProvider>();
      final data = await auth.authedMutate(
        r'mutation($id: ID!, $content: String!) { updateComment(id: $id, content: $content) { id content } }',
        {'id': c['id'].toString(), 'content': newContent},
      );
      if (!mounted) return;
      final updated = data['updateComment'];
      if (updated != null) {
        setState(() {
          final idx = _comments.indexWhere((x) => x['id'].toString() == c['id'].toString());
          if (idx >= 0) _comments[idx] = {..._comments[idx], 'content': updated['content']};
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi sửa: $e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Xoá bình luận', style: display(const TextStyle(color: AppColors.text))),
        content: Text('Bạn có chắc muốn xoá bình luận này?', style: body(const TextStyle(color: AppColors.textSecondary))),
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

  String _stripHtml(String html) => html.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final userId = auth.user?['id'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            const Text('Bình luận', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text)),
            if (_total > 0) ...[
              const SizedBox(width: 6),
              Text('($_total)', style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.surfaceLight,
                      backgroundImage: auth.user?['avatar'] != null ? CachedNetworkImageProvider(auth.user!['avatar']) : null,
                      child: auth.user?['avatar'] == null ? const Icon(Icons.person, size: 14, color: AppColors.textMuted) : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: body(const TextStyle(color: AppColors.text, fontSize: 14)),
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: 'Viết bình luận...',
                          hintStyle: body(const TextStyle(color: AppColors.textMuted, fontSize: 14)),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    // Image attach button
                    IconButton(
                      icon: _uploadingImage
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
                          : const Icon(Icons.image_outlined, size: 20, color: AppColors.textSecondary),
                      onPressed: _uploadingImage ? null : _pickAndUploadImage,
                      tooltip: 'Đính kèm ảnh',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: _submitting ? AppColors.surfaceLight : AppColors.accent, shape: BoxShape.circle),
                      child: IconButton(
                        icon: const Icon(Icons.send, size: 16, color: Colors.white),
                        onPressed: _submitting ? null : _submit,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                if (_attachedImages.isNotEmpty) Padding(
                  padding: const EdgeInsets.only(top: 8, left: 42),
                  child: Wrap(
                    spacing: 6, runSpacing: 6,
                    children: _attachedImages.asMap().entries.map((e) {
                      final i = e.key; final url = e.value;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(imageUrl: url, width: 60, height: 60, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: -6, right: -6,
                            child: GestureDetector(
                              onTap: () => setState(() => _attachedImages.removeAt(i)),
                              child: Container(
                                width: 20, height: 20,
                                decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
                                child: const Icon(Icons.close, size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          )
        else
          Text('Đăng nhập để bình luận', style: AppText.meta),

        const SizedBox(height: 20),

        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.accent)))
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
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
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
                      child: user['avatar']?['url'] == null ? const Icon(Icons.person, size: 16, color: AppColors.textMuted) : null,
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
                            child: Text(user['username'] ?? c['nickname'] ?? 'Ẩn danh', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
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
                        CommentMedia(html: content, authorName: user['username']?.toString() ?? c['nickname']?.toString()),
                        const SizedBox(height: 4),
                        Row(children: [
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
                            const SizedBox(width: 14),
                            InkWell(
                              onTap: () => _editComment(c),
                              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                                Icon(Icons.edit_outlined, size: 13, color: AppColors.textMuted),
                                SizedBox(width: 3),
                                Text('Sửa', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            InkWell(
                              onTap: () => _confirmDelete(c),
                              child: Row(mainAxisSize: MainAxisSize.min, children: const [
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
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
            : const SizedBox(width: 1, height: 1),
      ),
    );
  }
}
