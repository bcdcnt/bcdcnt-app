import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../widgets/contribute_card.dart';
import '../widgets/gap_scroll.dart';
import '../widgets/ui.dart';
import 'activity_screen.dart';
import 'comments_screen.dart';
import 'discussion_compose_screen.dart';
import 'discussion_detail_screen.dart';

/// Cộng đồng on desktop (canvas "Desktop · Cộng đồng"); opens on Bình luận
/// mới, where most new posts land. Diễn đàn as a list
/// of topics (by category) beside the open topic; Bình luận mới and Hoạt
/// động in a readable column with members, the call to contribute and the
/// liveliest topics beside them.
class DesktopCommunityScreen extends StatefulWidget {
  const DesktopCommunityScreen({super.key});
  @override
  State<DesktopCommunityScreen> createState() => _DesktopCommunityScreenState();
}

class _DesktopCommunityScreenState extends State<DesktopCommunityScreen> {
  int _tab = 1; // Bình luận mới; pane indices stay 0 forum, 1 comments, 2 activity
  String? _topic;
  final _forumKey = GlobalKey<_ForumListState>();
  final Map<int, Widget> _built = {};

  void _openTopic(String id) => setState(() { _tab = 0; _topic = id; });

  Widget _withSide(Widget feed) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: GapScroll(maxWidth: 760, child: feed)),
        const SizedBox(width: 40),
        SizedBox(width: 340, child: _CommunitySide(onOpenTopic: _openTopic)),
      ]);

  Widget _pane(int i) => switch (i) {
        0 => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 440, child: _ForumList(key: _forumKey, selected: _topic, onOpen: (id) => setState(() => _topic = id))),
            VerticalDivider(width: 1, color: AppColors.borderSubtle),
            Expanded(
              child: _topic == null
                  ? Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.4))
                  : DiscussionDetailScreen(
                      key: ValueKey(_topic), id: _topic!, embedded: true,
                      onChanged: () => _forumKey.currentState?.reload(),
                      onDeleted: () { setState(() => _topic = null); _forumKey.currentState?.reload(); },
                    ),
            ),
          ]),
        1 => _withSide(const CommentsFeed(showTitle: false, desktop: true)),
        _ => _withSide(const ActivityScreen(embedded: true, desktop: true)),
      };

  @override
  Widget build(BuildContext context) {
    // The forum pane follows the open topic; the others stay alive.
    _built[_tab] = _tab == 0 ? _pane(0) : (_built[_tab] ?? _pane(_tab));
    if (_tab != 0 && _built[0] != null) _built[0] = _pane(0);
    return Material(
      color: AppColors.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 20, 40, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              for (final (i, label) in const [(1, 'Bình luận mới'), (0, 'Diễn đàn'), (2, 'Hoạt động')])
                Padding(
                  padding: const EdgeInsets.only(right: 28),
                  child: InkWell(
                    onTap: () => setState(() => _tab = i),
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i == _tab ? AppColors.wine : Colors.transparent, width: 3))),
                      child: Text(label, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: i == _tab ? AppColors.text : AppColors.textMuted))),
                    ),
                  ),
                ),
              const Spacer(),
              if (_tab == 0)
                PillButton(
                  label: 'Đăng thảo luận',
                  icon: Icons.edit_note_rounded,
                  height: 40,
                  onTap: () => openDiscussionCompose(context, onPosted: () => _forumKey.currentState?.reload()),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(child: IndexedStack(index: _tab, children: [for (var i = 0; i < 3; i++) _built[i] ?? const SizedBox.shrink()])),
        ]),
      ),
    );
  }
}

/// BQT's internal forums ("Ban truyền thông"…) and the bin stay out.
bool _hiddenForum(String? title) {
  final t = (title ?? '').trim();
  return t.startsWith('Ban ') || t == 'Sọt rác';
}

String _since() {
  final y = DateTime.now().subtract(const Duration(days: 365));
  return '${y.year}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
}

const _topicFields = 'id title comment_count views is_sticky created_at last_comment_at forum { id title } author_name author { id username avatar { url } } lastCommentBy { id username avatar { url } }';

/// Diễn đàn list: categories, Mới hoạt động | Sôi nổi, pinned topics in a
/// short block on top, then the topics. Opens the first one by itself.
class _ForumList extends StatefulWidget {
  final String? selected;
  final ValueChanged<String> onOpen;
  const _ForumList({super.key, required this.selected, required this.onOpen});
  @override
  State<_ForumList> createState() => _ForumListState();
}

class _ForumListState extends State<_ForumList> {
  List<Map<String, dynamic>> _cats = [];
  String? _cat;
  int _sort = 0;
  List<Map<String, dynamic>>? _topics;
  List<Map<String, dynamic>> _pinned = [];
  int _limit = 20;
  bool _more = false;

  @override
  void initState() {
    super.initState();
    ApiClient.query(r'''query {
      forums(first: 100, where: {AND: [{column: "parent_id", value: null}]}, orderBy: [{column: "position", order: ASC}]) {
        data { children(first: 100, orderBy: [{column: "position", order: ASC}]) { data { id title discussions(first: 1, where: {column: "status", value: 1}) { paginatorInfo { total } } } } }
      }
    }''').then((d) {
      final cats = [
        for (final p in ((d['forums']?['data'] ?? []) as List).whereType<Map>())
          for (final c in ((p['children']?['data'] ?? []) as List).whereType<Map>())
            if (!_hiddenForum(c['title']?.toString())) Map<String, dynamic>.from(c),
      ];
      if (mounted) setState(() => _cats = cats);
    }).catchError((_) {});
    reload();
  }

  void reload() {
    _limit = 20;
    _load();
  }

  Future<void> _load() async {
    final cat = _cat, sort = _sort;
    List<Map<String, Object?>> where({bool pinned = false}) => [
          {'column': 'status', 'value': 1},
          if (cat != null) {'column': 'forum_id', 'value': cat},
          if (pinned) {'column': 'is_sticky', 'value': 1},
          if (!pinned && sort == 1) {'column': 'last_comment_at', 'operator': 'GTE', 'value': _since()},
        ];
    List<Map<String, dynamic>> list(dynamic data) => ((data ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).where((t) => !_hiddenForum(t['forum']?['title']?.toString())).toList();
    setState(() => _more = _topics != null);
    try {
      final d = await ApiClient.query('''query(\$w: WhereConditions, \$p: WhereConditions, \$n: Int) {
        topics: discussions(first: \$n, orderBy: [{column: "${sort == 1 ? 'comment_count' : 'last_comment_at'}", order: DESC}], where: \$w) { data { $_topicFields } }
        pinned: discussions(first: 4, orderBy: [{column: "last_comment_at", order: DESC}], where: \$p) { data { $_topicFields } }
      }''', {'w': {'AND': where()}, 'p': {'AND': where(pinned: true)}, 'n': _limit});
      if (!mounted || cat != _cat || sort != _sort) return;
      final pinned = list(d['pinned']?['data']);
      final ids = {for (final p in pinned) '${p['id']}'};
      final topics = list(d['topics']?['data']).where((t) => !ids.contains('${t['id']}')).toList();
      setState(() { _pinned = pinned; _topics = topics; _more = false; });
      // Never an empty reading pane: the newest topic opens by itself.
      if (widget.selected == null && topics.isNotEmpty) widget.onOpen('${topics.first['id']}');
    } catch (_) {
      if (mounted) setState(() { _topics ??= []; _more = false; });
    }
  }

  /// One row: the category menu (busy ones first, each with its topic
  /// count) on the left, Mới hoạt động | Sôi nổi on the right.
  Widget _catMenu(List<Map<String, dynamic>> main, List<Map<String, dynamic>> rest) {
    final current = _cats.where((c) => '${c['id']}' == _cat).firstOrNull;
    PopupMenuItem<String> item(String id, String title, int? n) {
      final on = (_cat ?? '') == id;
      return PopupMenuItem(
        value: id,
        height: 40,
        child: Row(children: [
          SizedBox(width: 26, child: on ? Icon(Icons.check_rounded, size: 18, color: AppColors.accentFg) : null),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)))),
          if (n != null) Padding(padding: const EdgeInsets.only(left: 12), child: Text(formatInt(n), style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)))),
        ]),
      );
    }
    int? count(Map<String, dynamic> c) => (c['discussions']?['paginatorInfo']?['total'] as num?)?.toInt();
    return PopupMenuButton<String>(
      tooltip: 'Chọn chuyên mục',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 340),
      onSelected: (id) { setState(() => _cat = id.isEmpty ? null : id); reload(); },
      itemBuilder: (_) => [
        item('', 'Tất cả chuyên mục', null),
        for (final c in main) item('${c['id']}', '${c['title']}', count(c)),
        if (rest.isNotEmpty) const PopupMenuDivider(),
        for (final c in rest) item('${c['id']}', '${c['title']}', count(c)),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.only(left: 14, right: 8),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.text, width: 1.5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(current != null ? '${current['title']}' : 'Tất cả chuyên mục', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)))),
          const SizedBox(width: 4),
          Icon(Icons.expand_more_rounded, size: 20, color: AppColors.text),
        ]),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
        child: Text(t, style: body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted))),
      );

  /// The forum has ~27 categories; the busy ones head the menu.
  static const _mainCats = ['Thảo luận', 'Yêu cầu nhạc', 'Chia sẻ nhạc', 'Giọng ca vàng', 'Gửi tác phẩm'];

  @override
  Widget build(BuildContext context) {
    final muted = body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted));
    final main = [for (final n in _mainCats) ..._cats.where((c) => c['title'] == n).take(1)];
    final rest = _cats.where((c) => !main.contains(c)).toList();
    return ListView(
      padding: const EdgeInsets.only(right: 18, bottom: 40),
      children: [
        Row(children: [
          Flexible(child: Align(alignment: Alignment.centerLeft, child: _catMenu(main, rest))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final (i, t) in const [(0, 'Mới hoạt động'), (1, 'Sôi nổi')])
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () { if (_sort != i) { setState(() => _sort = i); reload(); } },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _sort == i ? AppColors.bg : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                    child: Text(t, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _sort == i ? AppColors.text : AppColors.textSecondary))),
                  ),
                ),
            ]),
          ),
        ]),
        if (_pinned.isNotEmpty) ...[
          _label('ĐƯỢC GHIM'),
          for (final p in _pinned)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => widget.onOpen('${p['id']}'),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: widget.selected == '${p['id']}' ? AppColors.accentSoft : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Icon(Icons.push_pin_rounded, size: 16, color: AppColors.accentFg),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${p['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)))),
                  const SizedBox(width: 8),
                  Text('${p['comment_count'] ?? 0} trả lời', style: muted),
                ]),
              ),
            ),
        ],
        _label(_sort == 1 ? 'SÔI NỔI 12 THÁNG QUA' : 'MỚI HOẠT ĐỘNG'),
        if (_topics == null)
          for (var i = 0; i < 6; i++) const SkeletonSongRow()
        else if (_topics!.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text('Chưa có chủ đề nào', style: AppText.bodyText))
        else ...[
          for (final t in _topics!) _topicRow(t, muted),
          const SizedBox(height: 10),
          PillButton(
            label: 'Xem thêm chủ đề',
            primary: false,
            height: 44,
            loading: _more,
            onTap: _more ? null : () { _limit += 20; _load(); },
          ),
        ],
      ],
    );
  }

  Widget _topicRow(Map<String, dynamic> d, TextStyle muted) {
    final who = d['lastCommentBy'] ?? d['author'];
    final whoName = d['lastCommentBy']?['username']?.toString() ?? topicAuthorName(d);
    final on = widget.selected == '${d['id']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: on ? AppColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onOpen('${d['id']}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              UserAvatar(url: who?['avatar']?['url']?.toString(), name: whoName, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${d['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w800, color: AppColors.text))),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${d['forum']?['title'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.accentFg)),
                      TextSpan(text: ' · ${timeago((d['last_comment_at'] ?? d['created_at'])?.toString())} · ${d['comment_count'] ?? 0} trả lời · ${formatViews((d['views'] as num?)?.toInt())} xem'),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Side column of Bình luận mới / Hoạt động: top members by points, the
/// call to contribute, and the liveliest topics of the year.
class _CommunitySide extends StatefulWidget {
  final ValueChanged<String> onOpenTopic;
  const _CommunitySide({required this.onOpenTopic});
  @override
  State<_CommunitySide> createState() => _CommunitySideState();
}

class _CommunitySideState extends State<_CommunitySide> {
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _hot = [];

  @override
  void initState() {
    super.initState();
    ApiClient.query('query { topMember(field: "point", first: 5) { data { id username point avatar { url } } } }').then((d) {
      if (mounted) setState(() => _members = ((d['topMember']?['data'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
    }).catchError((_) {});
    ApiClient.query('''query(\$w: WhereConditions) {
      discussions(first: 6, orderBy: [{column: "comment_count", order: DESC}], where: \$w) { data { id title comment_count forum { title } } }
    }''', {'w': {'AND': [{'column': 'status', 'value': 1}, {'column': 'last_comment_at', 'operator': 'GTE', 'value': _since()}]}}).then((d) {
      final l = ((d['discussions']?['data'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).where((t) => !_hiddenForum(t['forum']?['title']?.toString())).take(3).toList();
      if (mounted) setState(() => _hot = l);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    const medals = {1: Color(0xFFC9A227), 2: Color(0xFF9AA0A6), 3: Color(0xFFB0703C)};
    final muted = body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted));
    String points(num? p) => (p ?? 0).toInt().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Thành viên tiêu biểu', style: display(TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text)))),
          TextButton(onPressed: () => context.push('/bang-xep-hang/cong-hien'), child: Text('Xem tất cả', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accentFg)))),
        ]),
        Text('Điểm đóng góp cho kho nhạc', style: muted),
        const SizedBox(height: 4),
        for (var i = 0; i < _members.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => context.push('/user/${_members[i]['id']}'),
            child: SizedBox(
              height: 56,
              child: Row(children: [
                SizedBox(width: 22, child: Text('${i + 1}', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: medals[i + 1] ?? AppColors.textMuted)))),
                UserAvatar(url: _members[i]['avatar']?['url']?.toString(), name: '${_members[i]['username'] ?? ''}', size: 40),
                const SizedBox(width: 12),
                Expanded(child: Text('${_members[i]['username'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)))),
                Text('${points(_members[i]['point'] as num?)} điểm', style: muted),
              ]),
            ),
          ),
        const SizedBox(height: 20),
        const ContributeCard(),
        if (_hot.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(children: [
            const Icon(Icons.local_fire_department_rounded, size: 20, color: Color(0xFFC2410C)),
            const SizedBox(width: 8),
            Text('Đang sôi nổi', style: display(TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text))),
          ]),
          const SizedBox(height: 4),
          for (final t in _hot)
            InkWell(
              onTap: () => widget.onOpenTopic('${t['id']}'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${t['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w800, color: AppColors.text))),
                  const SizedBox(height: 3),
                  Text('${t['comment_count'] ?? 0} trả lời · ${t['forum']?['title'] ?? ''}', style: muted),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}
