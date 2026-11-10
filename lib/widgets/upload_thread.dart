import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import 'ui.dart' show NetImage;

/// "Trao đổi với người gửi": comments on the upload. Only the sender and BQT
/// can read them (they come through upload(id), which checks viewUpload, and
/// the public comment lists leave uploads out); the sender is notified.
class UploadThread extends StatefulWidget {
  final String uploadId;
  final String senderId;
  const UploadThread({super.key, required this.uploadId, required this.senderId});

  @override
  State<UploadThread> createState() => _UploadThreadState();
}

class _UploadThreadState extends State<UploadThread> {
  static const _minLength = 20; // API Comment::CONTENT_MIN_LENGTH
  static const _quick = [
    ('Nguồn bản thu?', 'Bạn cho BQT hỏi bản thu này lấy từ nguồn nào (đài, băng, đĩa…) ạ?'),
    ('Ai trình bày?', 'Bạn có biết chắc ai trình bày bản thu này không ạ?'),
    ('Năm thu?', 'Bạn có biết bản thu này được thu năm nào không ạ?'),
    ('File chất lượng cao hơn?', 'Bạn có file chất lượng cao hơn (bitrate cao hơn) của bản thu này không ạ?'),
  ];
  final _ctl = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true, _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<AuthProvider>().authedQuery(r'''query($id: ID!) { upload(id: $id) {
        comments(first: 100, orderBy: [{column: "id", order: ASC}], where: {column: "status", operator: NEQ, value: 2}) {
          data { id content created_at user { id username avatar { url } } }
        } } }''', {'id': widget.uploadId});
      if (!mounted) return;
      setState(() {
        _items = ((d['upload']?['comments']?['data'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final t = _ctl.text.trim();
    if (t.length < _minLength) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Viết ít nhất $_minLength ký tự để người gửi hiểu rõ câu hỏi.')));
      return;
    }
    setState(() => _sending = true);
    try {
      await context.read<AuthProvider>().authedMutate(r'mutation($type: String!, $id: Int!, $content: String!) { addComment(type: $type, object_id: $id, content: $content) { id } }',
          {'type': 'upload', 'id': int.parse(widget.uploadId), 'content': t});
      _ctl.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'Chưa gửi được, vui lòng thử lại.')), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = body(TextStyle(fontSize: 12, color: AppColors.textMuted));
    final isBqt = context.read<AuthProvider>().hasPermission('manage_upload');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(isBqt ? 'Trao đổi với người gửi' : 'Trao đổi với BQT', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
          const SizedBox(width: 8),
          if (_items.isNotEmpty) Text('${_items.length}', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
        ]),
        Text(isBqt ? 'Chỉ người gửi và BQT thấy · người gửi nhận thông báo' : 'Chỉ bạn và BQT thấy', style: muted),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
        else if (_items.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(isBqt ? 'Chưa có trao đổi. Cần hỏi thêm gì thì nhắn ở đây.' : 'Chưa có trao đổi.', style: body(TextStyle(fontSize: 13, color: AppColors.textSecondary))))
        else
          for (final c in _items) _bubble(c),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.border, width: 1.5)),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctl,
                minLines: 1,
                maxLines: 5,
                style: body(TextStyle(fontSize: 14, color: AppColors.text)),
                decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: isBqt ? 'Hỏi người gửi…' : 'Trả lời BQT…', hintStyle: body(TextStyle(fontSize: 14, color: AppColors.textMuted))),
              ),
            ),
            FilledButton(
              onPressed: _sending ? null : _send,
              style: FilledButton.styleFrom(backgroundColor: AppColors.wine, minimumSize: const Size(56, 34), padding: const EdgeInsets.symmetric(horizontal: 14)),
              child: _sending ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Gửi'),
            ),
          ]),
        ),
        if (isBqt) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (label, text) in _quick)
              ActionChip(
                label: Text(label, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _ctl.text = text),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _bubble(Map<String, dynamic> c) {
    final user = c['user'] is Map ? c['user'] as Map : const {};
    final sender = '${user['id']}' == widget.senderId;
    final name = '${user['username'] ?? ''}';
    final text = '${c['content'] ?? ''}'.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n').replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipOval(
          child: SizedBox(
            width: 28, height: 28,
            child: user['avatar']?['url'] != null
                ? NetImage(url: '${user['avatar']['url']}', width: 28, height: 28)
                : Container(color: sender ? AppColors.surfaceLight : AppColors.wine, alignment: Alignment.center, child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white))),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(12), bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                Text(name, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.text))),
                if (!sender)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(6)),
                    child: Text('BQT', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
                  ),
                Text('${sender ? 'người gửi · ' : ''}${timeago(c['created_at']?.toString())}', style: body(TextStyle(fontSize: 12, color: AppColors.textMuted))),
              ]),
              const SizedBox(height: 2),
              SelectableText(text, style: body(TextStyle(fontSize: 14, height: 1.45, color: AppColors.text))),
            ]),
          ),
        ),
      ]),
    );
  }
}
