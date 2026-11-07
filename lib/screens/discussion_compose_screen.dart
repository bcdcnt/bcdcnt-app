import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import '../widgets/ui.dart' show PillButton;

/// "Gửi tác phẩm" (bài gửi) — needs an attached file and goes through the
/// Bài gửi flow, so it is never offered as a forum to post a topic into.
const submissionForumId = '28';

/// Opens the "Đăng thảo luận" screen. Guests get the login dialog first.
/// On success [onPosted] runs (so the caller can refresh its list), then the
/// new topic opens — or "Thảo luận của tôi" when BQT must review it first.
Future<void> openDiscussionCompose(
  BuildContext context, {
  String? forumId,
  String? forumTitle,
  VoidCallback? onPosted,
}) async {
  final auth = context.read<AuthProvider>();
  if (!auth.isAuthenticated) {
    await askLogin(context);
    if (!context.mounted || !context.read<AuthProvider>().isAuthenticated) return;
  }
  final created = await Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(builder: (_) => DiscussionComposeScreen(forumId: forumId, forumTitle: forumTitle)),
  );
  if (created == null || !context.mounted) return;
  onPosted?.call();
  final pending = '${created['status']}' == '2';
  if (pending) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(seconds: 6),
      content: Text('Đã đăng. Chủ đề đang chờ BQT duyệt trước khi hiện cho mọi người.'),
    ));
    context.push('/thao-luan-cua-toi');
  } else {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đăng thảo luận.')));
    context.push('/thao-luan/${created['id']}');
  }
}

class DiscussionComposeScreen extends StatefulWidget {
  /// Fixed forum (posting from a forum page). Null → the user picks one.
  final String? forumId;
  final String? forumTitle;
  const DiscussionComposeScreen({super.key, this.forumId, this.forumTitle});

  @override
  State<DiscussionComposeScreen> createState() => _DiscussionComposeScreenState();
}

class _DiscussionComposeScreenState extends State<DiscussionComposeScreen> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  String? _forumId;
  String? _forumTitle;
  String? _error;
  bool _sending = false;

  /// Parent forums with their child forums (only children take topics).
  List<({String title, List<({String id, String title})> children})> _groups = [];
  bool _forumsLoading = false, _forumsFailed = false;

  bool get _fixedForum => widget.forumId != null;

  @override
  void initState() {
    super.initState();
    _forumId = widget.forumId;
    _forumTitle = widget.forumTitle;
    if (!_fixedForum) _loadForums();
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _loadForums() async {
    setState(() { _forumsLoading = true; _forumsFailed = false; });
    try {
      final data = await ApiClient.query(r'''query {
        forums(first: 100, where: {AND: [{column: "parent_id", value: null}]}, orderBy: [{column: "position", order: ASC}]) {
          data { id title children(first: 100, orderBy: [{column: "position", order: ASC}]) { data { id title } } }
        }
      }''');
      final groups = <({String title, List<({String id, String title})> children})>[];
      for (final p in (data['forums']?['data'] ?? []) as List) {
        final kids = <({String id, String title})>[
          for (final c in (p['children']?['data'] ?? []) as List)
            if ('${c['id']}' != submissionForumId) (id: '${c['id']}', title: '${c['title'] ?? ''}'),
        ];
        if (kids.isNotEmpty) groups.add((title: '${p['title'] ?? ''}', children: kids));
      }
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _forumsLoading = false;
        // Like the web: a new topic goes to "Thảo luận" unless one is picked.
        if (_forumId == null) {
          final general = groups.expand((g) => g.children).where((c) => c.title.trim() == 'Thảo luận').firstOrNull;
          if (general != null) { _forumId = general.id; _forumTitle = general.title; }
        }
      });
    } catch (_) {
      if (mounted) setState(() { _forumsLoading = false; _forumsFailed = true; });
    }
  }

  /// Plain text → the simple HTML the site's editor stores: one <p> per
  /// paragraph, single line breaks kept as <br>.
  static String _toHtml(String text) {
    String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    final paras = text.trim().split(RegExp(r'\n\s*\n')).map((p) => p.trim()).where((p) => p.isNotEmpty);
    return paras.map((p) => '<p>${esc(p).replaceAll('\n', '<br>')}</p>').join();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final content = _content.text.trim();
    String? err;
    if (_forumId == null) {
      err = 'Vui lòng chọn chuyên mục để đăng.';
    } else if (title.isEmpty) {
      err = 'Vui lòng nhập tiêu đề.';
    } else if (title.length < 5) {
      err = 'Tiêu đề hơi ngắn, bạn viết rõ hơn một chút nhé.';
    } else if (title.length > 200) {
      err = 'Tiêu đề dài quá, vui lòng viết gọn lại.';
    } else if (content.isEmpty) {
      err = 'Vui lòng viết nội dung bạn muốn chia sẻ.';
    }
    if (err != null) { setState(() => _error = err); return; }

    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) { await askLogin(context); return; }
    FocusScope.of(context).unfocus();
    setState(() { _sending = true; _error = null; });
    try {
      final d = await auth.authedMutate(
        r'mutation($title: String!, $content: String, $forum_id: ID!) { createDiscussion(input: { title: $title, content: $content, forum_id: $forum_id }) { id slug status } }',
        {'title': title, 'content': _toHtml(content), 'forum_id': _forumId},
      );
      final created = d['createDiscussion'];
      if (!mounted) return;
      if (created is! Map || created['id'] == null) {
        setState(() { _sending = false; _error = 'Chưa đăng được, vui lòng thử lại.'; });
        return;
      }
      Navigator.of(context).pop(Map<String, dynamic>.from(created));
    } catch (e) {
      if (!mounted) return;
      final low = e.toString().toLowerCase();
      final denied = low.contains('không có quyền') || low.contains('unauthorized') || low.contains('forbidden');
      setState(() {
        _sending = false;
        _error = denied
            ? 'Tài khoản của bạn hiện chưa được đăng thảo luận. Nếu cần, hãy liên hệ BQT qua mục Hỗ trợ.'
            : friendlyError(e, fallback: 'Chưa đăng được, vui lòng thử lại.');
      });
    }
  }

  Future<void> _pickForum() async {
    if (_groups.isEmpty) {
      if (!_forumsLoading) _loadForums();
      return;
    }
    final picked = await showModalBottomSheet<({String id, String title})>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        child: SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Chọn chuyên mục', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
            ),
            for (final g in _groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                child: Text(g.title.toUpperCase(), style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.textMuted))),
              ),
              for (final c in g.children)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(ctx).pop(c),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(children: [
                        Icon(c.id == _forumId ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 24, color: c.id == _forumId ? AppColors.accentLight : AppColors.textMuted),
                        const SizedBox(width: 12),
                        Expanded(child: Text(c.title, style: body(TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)))),
                      ]),
                    ),
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
    if (picked != null && mounted) setState(() { _forumId = picked.id; _forumTitle = picked.title; _error = null; });
  }

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.wine, width: 2)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 18),
        child: Text(text, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
      );

  bool get _hasDraft => _title.text.trim().isNotEmpty || _content.text.trim().isNotEmpty;

  /// Leaving with text typed: ask first so a slip of the finger doesn't
  /// throw away a long post.
  Future<bool> _confirmLeave() async {
    if (!_hasDraft || _sending) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Bỏ bài đang viết?', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
        content: Text('Nội dung bạn vừa viết sẽ không được lưu.', style: body(TextStyle(fontSize: 16, color: AppColors.textSecondary))),
        actions: [
          TextButton(style: TextButton.styleFrom(minimumSize: const Size(64, 48)), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Viết tiếp', style: TextStyle(fontSize: 16))),
          TextButton(style: TextButton.styleFrom(minimumSize: const Size(64, 48)), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Bỏ bài', style: TextStyle(fontSize: 16))),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          centerTitle: true,
          title: const Text('Đăng thảo luận'),
          leading: IconButton(
            tooltip: 'Quay lại',
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text),
            onPressed: () async { if (await _confirmLeave() && context.mounted) Navigator.of(context).pop(); },
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              _label('Chuyên mục'),
              if (_fixedForum)
                Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                  alignment: Alignment.centerLeft,
                  child: Row(children: [
                    Icon(Icons.forum_outlined, size: 22, color: AppColors.accentLight),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_forumTitle ?? 'Chuyên mục này', style: body(TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)))),
                  ]),
                )
              else
                Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _pickForum,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(children: [
                        Icon(Icons.forum_outlined, size: 22, color: AppColors.accentLight),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _forumsLoading
                              ? Text('Đang tải chuyên mục…', style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)))
                              : _forumsFailed && _groups.isEmpty
                                  ? Text('Chưa tải được chuyên mục. Chạm để thử lại.', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.errorText)))
                                  : Text(_forumTitle ?? 'Chạm để chọn chuyên mục', style: body(TextStyle(fontSize: 17, fontWeight: _forumTitle != null ? FontWeight.w700 : FontWeight.w500, color: _forumTitle != null ? AppColors.text : AppColors.textMuted))),
                        ),
                        Icon(Icons.expand_more_rounded, size: 26, color: AppColors.textSecondary),
                      ]),
                    ),
                  ),
                ),
              _label('Tiêu đề'),
              TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 200,
                onChanged: (_) { if (_error != null) setState(() => _error = null); },
                style: body(TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.text)),
                decoration: _input('Ví dụ: Tìm bài hát về mẹ thập niên 80'),
              ),
              _label('Nội dung'),
              TextField(
                controller: _content,
                minLines: 7,
                maxLines: 16,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                onChanged: (_) { if (_error != null) setState(() => _error = null); },
                style: body(TextStyle(fontSize: 17, height: 1.5, fontWeight: FontWeight.w500, color: AppColors.text)),
                decoration: _input('Bạn muốn chia sẻ hoặc hỏi điều gì?'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.errorText))),
                ),
              ],
              const SizedBox(height: 20),
              PillButton(label: 'Đăng', icon: Icons.send_rounded, height: 52, loading: _sending, onTap: _sending ? null : _submit),
              const SizedBox(height: 12),
              Text(
                'Bài có từ ngữ không phù hợp sẽ chờ BQT duyệt trước khi hiện.',
                textAlign: TextAlign.center,
                style: body(TextStyle(fontSize: 14, color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
