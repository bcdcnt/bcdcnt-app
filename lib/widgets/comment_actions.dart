import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import 'song_admin_actions.dart' show PeopleField;

// The "⋮" menu on a comment — same actions and permissions as the web
// (bcdcnt-web components/shared/CommentSection.jsx → CommentActions).

const _reqBlue = Color(0xFF2196F3);
const _reqGreen = Color(0xFF4CAF50);
const _aiPurple = Color(0xFF9C27B0);

/// What happened, so the list can update without a reload.
sealed class CommentChange {}

class CommentUpdated extends CommentChange {
  final Map<String, dynamic> fields;
  CommentUpdated(this.fields);
}

class CommentRemoved extends CommentChange {}

class CommentEditRequested extends CommentChange {}

/// The song / page itself changed (lyric, recording, picture…) — reload it.
class CommentPageChanged extends CommentChange {}

/// Label + colour for a request comment ("Yêu cầu bổ sung" thread).
({String label, Color color})? requestBadge(Map c) {
  final isReq = c['is_request'] == 1 || c['is_request'] == true;
  if (!isReq) return null;
  return switch (c['request_status']?.toString()) {
    'done' => (label: 'Đã xử lý', color: _reqGreen),
    'rejected' => (label: 'Không thể xử lý', color: AppColors.error),
    'need_more_info' => (label: 'Cần thêm thông tin', color: _reqBlue),
    'processing' => (label: 'Đang xử lý', color: _aiPurple),
    _ => (label: 'Yêu cầu', color: const Color(0xFFE6A23C)),
  };
}

class _A {
  final String key, label;
  final IconData icon;
  final Color? color;
  const _A(this.key, this.label, this.icon, [this.color]);
}

/// [type] / [objectId]: what the comment section belongs to (song, folk,
/// discussion…).
Future<CommentChange?> showCommentActions(BuildContext context, {required Map<String, dynamic> comment, required String type, required String objectId}) async {
  final auth = context.read<AuthProvider>();
  if (!auth.isAuthenticated) return null;
  final id = '${comment['id']}';
  final isOwn = '${comment['user']?['id']}' == '${auth.user?['id']}';
  final isReq = comment['is_request'] == 1 || comment['is_request'] == true;
  bool can(String p) => auth.hasPermission(p);
  final content = (comment['content'] ?? '').toString();
  // Content-based actions only show when the comment has that content.
  final hasImg = RegExp(r'<img', caseSensitive: false).hasMatch(content);
  final hasMedia = RegExp(r'<audio|<video|<oembed|<source', caseSensitive: false).hasMatch(content);

  // Each item follows the API's own check (CommentPolicy / @can in
  // schema.graphql), so nothing shows that the server would refuse.
  final moderator = can('manage_comment');
  final requestStaff = moderator || can('manage_thumbnail') || can('manage_sheet');
  final actions = <_A>[
    if ((isOwn || requestStaff) && !isReq) const _A('markRequest', 'Đánh dấu là yêu cầu', Icons.back_hand_outlined),
    if ((isOwn || moderator) && isReq) const _A('unmarkRequest', 'Bỏ đánh dấu yêu cầu', Icons.back_hand_outlined),
    if (requestStaff) ...[
      const _A('statusDone', 'Đã xử lý xong yêu cầu', Icons.back_hand_outlined, _reqGreen),
      _A('statusRejected', 'Không thể xử lý yêu cầu', Icons.back_hand_outlined, AppColors.error),
      const _A('statusNeedInfo', 'Cần thêm thông tin', Icons.back_hand_outlined, _reqBlue),
    ],
    if (can('process_ai_request') && isReq) const _A('processAI', 'Xử lý bằng AI', Icons.auto_awesome_rounded, _aiPurple),
    if (isOwn || moderator) const _A('edit', 'Sửa bình luận', Icons.edit_outlined),
    if (can('manage_sheet') && hasImg) const _A('createSheet', 'Dùng làm sheet nhạc', Icons.description_outlined),
    if (can('update_lyric') && const ['song', 'folk', 'poem'].contains(type)) const _A('applyLyric', 'Dùng làm lời bài hát', Icons.subtitles_outlined),
    if (can('manage_song') && hasMedia) const _A('replaceFile', 'Dùng làm bản thu', Icons.music_note_outlined),
    if (can('manage_thumbnail') && hasImg) const _A('replaceImage', 'Dùng làm minh hoạ', Icons.image_outlined),
    if (can('manage_document') && RegExp(r'<img|<oembed', caseSensitive: false).hasMatch(content)) const _A('tagDocument', 'Đặt làm tư liệu ảnh', Icons.photo_library_outlined),
    if (moderator) const _A('move', 'Chuyển bình luận', Icons.open_in_new_rounded),
    if (isOwn || moderator) _A('delete', 'Xoá bình luận', Icons.delete_outline_rounded, AppColors.error),
    if (moderator) _A('hide', 'Ẩn bình luận', Icons.visibility_off_outlined, AppColors.error),
    // Everyone can copy the text, so ⋮ is never an empty menu.
    const _A('copy', 'Sao chép nội dung', Icons.copy_rounded),
  ];

  final picked = await showModalBottomSheet<_A>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 8), children: [
          for (final a in actions)
            ListTile(
              leading: Icon(a.icon, color: a.color ?? AppColors.textSecondary),
              title: Text(a.label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: a.color ?? AppColors.text))),
              onTap: () => Navigator.pop(ctx, a),
            ),
        ]),
      ),
    ),
  );
  if (picked == null || !context.mounted) return null;

  void toast(String m, {bool error = false}) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.error : null));
  }

  Future<T?> guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      toast('Lỗi: ${e.toString().replaceFirst('Exception: ', '')}', error: true);
      return null;
    }
  }

  final me = {'id': auth.user?['id'], 'username': auth.user?['username']};
  switch (picked.key) {
    case 'markRequest':
      return await guard<CommentChange?>(() async {
        await auth.authedMutate(r'mutation($id: ID!) { markAsCommentRequest(id: $id) { id } }', {'id': id});
        return CommentUpdated({'is_request': 1, 'request_status': null});
      });
    case 'unmarkRequest':
      return await guard<CommentChange?>(() async {
        await auth.authedMutate(r'mutation($id: ID!) { unmarkCommentRequest(id: $id) { id } }', {'id': id});
        return CommentUpdated({'is_request': 0, 'request_status': null});
      });
    case 'statusDone':
    case 'statusRejected':
    case 'statusNeedInfo':
      final status = picked.key == 'statusDone' ? 'done' : picked.key == 'statusRejected' ? 'rejected' : 'need_more_info';
      return await guard<CommentChange?>(() async {
        if (!isReq) await auth.authedMutate(r'mutation($id: ID!) { markAsCommentRequest(id: $id) { id } }', {'id': id});
        await auth.authedMutate(r'mutation($id: ID!, $s: String!) { changeCommentRequestStatus(id: $id, status: $s) { id } }', {'id': id, 's': status});
        return CommentUpdated({'is_request': 1, 'request_status': status, 'processRequestUser': me});
      });
    case 'processAI':
      return await guard<CommentChange?>(() async {
        final d = await auth.authedMutate(r'mutation($id: ID!) { processCommentRequestByAI(id: $id) { id request_status processRequestUser { id username } } }', {'id': id});
        toast('Đã gửi xử lý bằng AI, chờ kết quả…');
        final u = d['processCommentRequestByAI'];
        return u == null ? null : CommentUpdated({'request_status': u['request_status'], 'processRequestUser': u['processRequestUser']});
      });
    case 'edit':
      return CommentEditRequested();
    case 'createSheet':
      if (!await _confirm(context, 'Dùng làm sheet nhạc', 'Tạo bản nhạc từ ảnh trong bình luận này?')) return null;
      return await guard<CommentChange?>(() async {
        await auth.authedMutate(r'mutation($c: ID!) { createSheetFromComment(comment_id: $c) { id } }', {'c': id});
        toast('Đã tạo sheet nhạc');
        return CommentPageChanged();
      });
    case 'replaceFile':
      if (!await _confirm(context, 'Dùng làm bản thu', 'Thay bản thu của bài bằng file trong bình luận này?')) return null;
      return await guard<CommentChange?>(() async {
        await auth.authedMutate(r'mutation($c: ID!) { replaceFileFromComment(comment_id: $c) { id } }', {'c': id});
        toast('Đã thay bản thu');
        return CommentPageChanged();
      });
    case 'replaceImage':
      final n = RegExp(r'<img', caseSensitive: false).allMatches(content).length;
      final index = await _pickImageIndex(context, n);
      if (index == null) return null;
      return await guard<CommentChange?>(() async {
        await auth.authedMutate(r'mutation($c: ID!, $i: Int) { replaceImageFromComment(comment_id: $c, index: $i) { id } }', {'c': id, 'i': index});
        toast('Đã thay ảnh minh hoạ');
        return CommentPageChanged();
      });
    case 'applyLyric':
      final saved = await _applyLyric(context, auth, comment: comment, type: type, objectId: objectId);
      return saved ? CommentPageChanged() : null;
    case 'tagDocument':
      await _tagDocument(context, auth, comment);
      return null;
    case 'move':
      final link = await _askText(context, 'Chuyển bình luận', 'Dán link trang đích (bài hát, chủ đề…)', hint: 'https://bcdcnt.net/bai-hat/…');
      if (link == null || link.isEmpty) return null;
      return await guard<CommentChange?>(() async {
        await auth.authedMutate(r'mutation($ids: [ID]!, $link: String!) { moveComments(comment_ids: $ids, link: $link) }', {'ids': [id], 'link': link});
        toast('Đã chuyển bình luận');
        return CommentRemoved();
      });
    case 'delete':
      if (!await _confirm(context, 'Xoá bình luận', 'Bạn có chắc muốn xoá bình luận này?', danger: true)) return null;
      return await guard<CommentChange?>(() async {
        await auth.authedMutate(r'mutation($id: ID!) { deleteComment(id: $id) { id } }', {'id': id});
        toast('Đã xoá bình luận');
        return CommentRemoved();
      });
    case 'hide':
      if (!await _confirm(context, 'Ẩn bình luận', 'Ẩn bình luận này khỏi trang chủ?', danger: true)) return null;
      return await guard<CommentChange?>(() async {
        await auth.authedMutate(r'mutation($id: ID!) { hideComment(id: $id) { id } }', {'id': id});
        toast('Đã ẩn bình luận');
        return CommentRemoved();
      });
    case 'copy':
      final plain = content
          .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
      await Clipboard.setData(ClipboardData(text: plain));
      toast('Đã sao chép bình luận');
      return null;
  }
  return null;
}

Future<bool> _confirm(BuildContext context, String title, String message, {bool danger = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Đồng ý', style: TextStyle(color: danger ? AppColors.error : AppColors.accent, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ) ==
    true;

Future<String?> _askText(BuildContext context, String title, String label, {String? hint}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: label, hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Chuyển')),
      ],
    ),
  );
}

/// Which picture of the comment to use (1-based, like the web).
Future<int?> _pickImageIndex(BuildContext context, int count) async {
  if (count <= 1) return await _confirm(context, 'Dùng làm minh hoạ', 'Dùng ảnh trong bình luận này làm ảnh minh hoạ?') ? 1 : null;
  return showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Dùng ảnh thứ mấy?'),
      children: [for (var i = 1; i <= count; i++) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, i), child: Text('Ảnh $i'))],
    ),
  );
}

String _htmlToText(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</p>\s*<p[^>]*>', caseSensitive: false), '\n\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

String _textToHtml(String text) => text
    .trim()
    .split(RegExp(r'\n\s*\n'))
    .map((p) => '<p>${p.trim().split('\n').map((l) => l.trim()).join('<br>')}</p>')
    .join();

/// "Dùng làm lời bài hát": the comment's text in an editor (drop the
/// intro, keep the lyric), saved with updateLyric credited to the
/// commenter — what the web does through its inline lyric editor.
Future<bool> _applyLyric(BuildContext context, AuthProvider auth, {required Map comment, required String type, required String objectId}) async {
  final c = TextEditingController(text: _htmlToText('${comment['content'] ?? ''}'));
  final who = comment['user']?['username'] ?? comment['nickname'];
  var busy = false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Dùng làm lời bài hát', style: display(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text))),
              const SizedBox(height: 4),
              Text('Bỏ lời dẫn, chỉ giữ lời bài rồi lưu.${who != null ? ' Ghi công cho $who.' : ''}', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                child: TextField(
                  controller: c,
                  maxLines: null,
                  minLines: 8,
                  style: body(TextStyle(fontSize: 15, height: 1.5, color: AppColors.text)),
                  decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: AppColors.surface),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (c.text.trim().isEmpty) return;
                        setState(() => busy = true);
                        try {
                          await auth.authedMutate(r'mutation($id: ID!, $t: String!, $c: String!, $by: ID) { updateLyric(id: $id, type: $t, content: $c, performed_by: $by) { id } }', {
                            'id': objectId,
                            't': type,
                            'c': _textToHtml(c.text),
                            'by': comment['user']?['id']?.toString(),
                          });
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setState(() => busy = false);
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error));
                        }
                      },
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(vertical: 13), shape: const StadiumBorder()),
                child: Text(busy ? 'Đang lưu…' : 'Lưu lời bài hát', style: body(const TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
  if (ok == true && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật lời bài hát')));
  return ok == true;
}

/// "Đặt làm tư liệu ảnh": the comment's pictures/videos become archive
/// documents of the chosen composers / singers / poets / recomposers.
Future<void> _tagDocument(BuildContext context, AuthProvider auth, Map comment) async {
  final title = TextEditingController(text: _htmlToText('${comment['content'] ?? ''}').replaceAll('\n', ' ').trim());
  if (title.text.length > 150) title.text = title.text.substring(0, 150);
  final people = <String, List<Map<String, dynamic>>>{'composers': [], 'artists': [], 'poets': [], 'recomposers': []};
  const labels = {'composers': 'Nhạc sĩ', 'artists': 'Nghệ sĩ', 'poets': 'Nhà thơ', 'recomposers': 'Soạn giả'};
  var busy = false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Đặt làm tư liệu ảnh', style: display(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text))),
                const SizedBox(height: 4),
                Text('Gán ảnh/video trong bình luận này làm tư liệu cho người được chọn (hiện ở tab Hình ảnh).', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
                const SizedBox(height: 12),
                TextField(controller: title, maxLength: 255, decoration: const InputDecoration(labelText: 'Tiêu đề tư liệu')),
                for (final k in people.keys) ...[
                  const SizedBox(height: 12),
                  Text(labels[k]!, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                  const SizedBox(height: 6),
                  PeopleField(items: people[k]!, search: k, allowCreate: false, onChanged: (v) => setState(() => people[k] = v)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy || title.text.trim().isEmpty || people.values.every((l) => l.isEmpty)
                      ? null
                      : () async {
                          setState(() => busy = true);
                          try {
                            List<String> ids(String k) => people[k]!.map((p) => '${p['id']}').toList();
                            await auth.authedMutate(
                                r'mutation($c: ID!, $t: String, $a: [ID!], $co: [ID!], $p: [ID!], $r: [ID!]) { createDocumentFromComment(comment_id: $c, title: $t, artist_ids: $a, composer_ids: $co, poet_ids: $p, recomposer_ids: $r) { id } }',
                                {'c': '${comment['id']}', 't': title.text.trim(), 'a': ids('artists'), 'co': ids('composers'), 'p': ids('poets'), 'r': ids('recomposers')});
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setState(() => busy = false);
                            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error));
                          }
                        },
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(vertical: 13), shape: const StadiumBorder()),
                  child: Text(busy ? 'Đang xử lý…' : 'Đặt làm tư liệu', style: body(const TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
  if (ok == true && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đặt làm tư liệu')));
}
