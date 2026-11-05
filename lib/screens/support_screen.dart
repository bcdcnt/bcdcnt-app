import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/push.dart';
import '../services/auth.dart';
import '../widgets/auth_dialogs.dart';
import '../widgets/comment_section.dart';
import '../widgets/mini_player.dart';
import '../widgets/ui.dart';

/// Same categories as the web /ho-tro page.
const _categories = ['Lỗi kỹ thuật', 'Tài khoản', 'Bản quyền / gỡ nội dung', 'Góp ý riêng', 'Khác'];

/// Ticket status is a free string from the backend (mirrors web statusInfo).
(String, Color) _status(dynamic s) {
  final v = (s ?? '').toString().toLowerCase();
  if (v == 'closed' || v == 'processed') return ('Đã xử lý', AppColors.success);
  if (v == 'processing') return ('Đang xử lý', const Color(0xFFB7791F));
  return ('Đang chờ', AppColors.wine);
}

/// Category label; system-made reports carry a technical key.
String _cat(dynamic c) => const {'report_message': 'Báo cáo tin nhắn', 'report_comment': 'Báo cáo bình luận', 'report_user': 'Báo cáo thành viên'}[c] ?? (c ?? '').toString();

String _date(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString());
  return d == null ? '' : '${d.day}/${d.month}/${d.year}';
}

Widget _statusChip((String, Color) st) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: st.$2, borderRadius: BorderRadius.circular(20)),
      child: Text(st.$1, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white))),
    );

/// "Góp ý & hỗ trợ" (/ho-tro): private requests to BQT via the ticket API —
/// send a new one, follow the ones already sent. Only the member and BQT
/// (manage_ticket) can read a ticket.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  String _category = 'Góp ý riêng';
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _loadedFor;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _load(AuthProvider auth) async {
    setState(() => _loading = true);
    try {
      final d = await auth.authedQuery('{ me { tickets(first: 50, orderBy: [{column: "id", order: DESC}]) { data { id title category status created_at } } } }', null);
      if (!mounted) return;
      setState(() {
        _tickets = ((d['me']?['tickets']?['data'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit(AuthProvider auth) async {
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (title.isEmpty || content.isEmpty) {
      setState(() => _error = 'Vui lòng nhập tiêu đề và nội dung');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final d = await auth.authedMutate(
        r'mutation($input: CreateTicketInput!) { createTicket(input: $input) { id } }',
        {'input': {'title': title, 'content': content, 'category': _category}},
      );
      if (!mounted) return;
      _title.clear();
      _content.clear();
      _category = 'Góp ý riêng';
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi — BQT sẽ trả lời trong yêu cầu này')));
      final id = d['createTicket']?['id'];
      await _load(auth);
      if (mounted && id != null) context.push('/ho-tro/$id');
      if (mounted) PushService.instance.maybeAsk(context, reason: 'Biết ngay khi BQT trả lời yêu cầu hỗ trợ của bạn.');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.wine, width: 2)),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final uid = auth.isAuthenticated ? (auth.user?['id']?.toString()) : null;
    if (uid != null && uid != _loadedFor) {
      _loadedFor = uid;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(auth));
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const SubPageBar(title: 'Góp ý & hỗ trợ'),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
          children: [
            Text('Gửi riêng cho BQT', style: display(TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.text))),
            const SizedBox(height: 8),
            Text('Chỉ bạn và ban quản trị đọc được. Dùng để góp ý, báo lỗi, hỏi về tài khoản hay đề nghị gỡ nội dung. BQT trả lời ngay trong yêu cầu, bạn sẽ nhận thông báo.',
                style: body(TextStyle(fontSize: 15, height: 1.55, fontWeight: FontWeight.w500, color: AppColors.textSecondary))),
            const SizedBox(height: 14),
            Material(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/faq'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Icon(Icons.help_outline_rounded, color: AppColors.accentLight),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Nhiều thắc mắc đã có lời giải sẵn — xem Câu hỏi thường gặp trước khi gửi.', style: body(TextStyle(fontSize: 14, height: 1.45, fontWeight: FontWeight.w600, color: AppColors.text)))),
                    Icon(Icons.chevron_right_rounded, color: AppColors.accentLight),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 22),
            if (uid == null)
              EmptyBlock(
                icon: Icons.support_agent_rounded,
                title: 'Đăng nhập để gửi',
                message: 'Cần đăng nhập để BQT trả lời đúng cho bạn.',
                action: 'Đăng nhập',
                onAction: () => showDialog(context: context, builder: (_) => const LoginDialog()),
              )
            else ...[
              Text('Chủ đề', style: AppText.title),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final c in _categories) BrandChip(label: c, selected: c == _category, onTap: () => setState(() => _category = c))],
              ),
              const SizedBox(height: 16),
              TextField(controller: _title, textInputAction: TextInputAction.next, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)), decoration: _input('Tiêu đề ngắn gọn')),
              const SizedBox(height: 10),
              TextField(controller: _content, minLines: 5, maxLines: 12, style: body(TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w500, color: AppColors.text)), decoration: _input('Nội dung chi tiết…')),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.error))),
              ],
              const SizedBox(height: 14),
              PillButton(label: 'Gửi cho BQT', icon: Icons.send_rounded, loading: _sending, onTap: _sending ? null : () => _submit(auth)),
              SectionTitle('Yêu cầu đã gửi', action: null, padding: const EdgeInsets.fromLTRB(0, 32, 0, 6)),
              if (_loading)
                for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.only(bottom: 10), child: Skeleton(height: 64, radius: 16))
              else if (_tickets.isEmpty)
                Text('Bạn chưa gửi yêu cầu nào.', style: AppText.bodyText)
              else
                for (final t in _tickets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          await context.push('/ho-tro/${t['id']}');
                          if (mounted) _load(auth);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text((t['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.title),
                                const SizedBox(height: 3),
                                Text([_cat(t['category']), _date(t['created_at'])].where((s) => s != null && s.toString().isNotEmpty).join(' · '), style: AppText.meta),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            _statusChip(_status(t['status'])),
                          ]),
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ),
        const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}

/// One support request: what was sent, its status, and the conversation
/// with BQT (comments on the ticket).
class TicketDetailScreen extends StatefulWidget {
  final String id;
  const TicketDetailScreen({super.key, required this.id});
  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  Map<String, dynamic>? _t;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    try {
      final d = await auth.authedQuery(r'query($id: ID!) { ticket(id: $id) { id title content category status created_at author { username } } }', {'id': widget.id});
      if (!mounted) return;
      setState(() {
        _t = d['ticket'] is Map ? Map<String, dynamic>.from(d['ticket']) : null;
        _loading = false;
        if (_t == null) _error = 'Không tìm thấy yêu cầu';
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Bạn không xem được yêu cầu này'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const SubPageBar(title: 'Yêu cầu hỗ trợ'),
      body: Stack(children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (t == null)
          ListView(children: [EmptyBlock(icon: Icons.lock_outline_rounded, title: _error ?? 'Không tìm thấy yêu cầu')])
        else
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
            children: [
              Row(children: [
                _statusChip(_status(t['status'])),
                const SizedBox(width: 10),
                Expanded(child: Text([_cat(t['category']), _date(t['created_at'])].where((s) => s != null && s.toString().isNotEmpty).join(' · '), style: AppText.meta)),
              ]),
              const SizedBox(height: 12),
              Text((t['title'] ?? '').toString(), style: display(TextStyle(fontSize: 24, height: 1.2, fontWeight: FontWeight.w800, color: AppColors.text))),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
                child: SelectableText((t['content'] ?? '').toString(), style: body(TextStyle(fontSize: 15, height: 1.6, fontWeight: FontWeight.w500, color: AppColors.text))),
              ),
              const SizedBox(height: 8),
              Text('Trao đổi với BQT bên dưới — chỉ bạn và BQT nhìn thấy.', style: AppText.meta),
              const SizedBox(height: 20),
              CommentSection(type: 'ticket', id: widget.id),
            ],
          ),
        const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
