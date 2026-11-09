import 'package:flutter/material.dart';
import '../constants/theme.dart';
import 'activity_screen.dart';
import 'comments_screen.dart';
import 'discussion_detail_screen.dart';
import 'discussion_list_screen.dart';

/// Cộng đồng on desktop (canvas "Desktop · Cộng đồng"): Diễn đàn as a list
/// of topics beside the open topic, then Bình luận mới and Hoạt động.
class DesktopCommunityScreen extends StatefulWidget {
  const DesktopCommunityScreen({super.key});
  @override
  State<DesktopCommunityScreen> createState() => _DesktopCommunityScreenState();
}

class _DesktopCommunityScreenState extends State<DesktopCommunityScreen> {
  int _tab = 0;
  String? _topic;
  final Map<int, Widget> _built = {};

  Widget _pane(int i) => switch (i) {
        0 => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 400,
              child: DiscussionListScreen(embedded: true, onOpen: (id) => setState(() => _topic = id)),
            ),
            VerticalDivider(width: 1, color: AppColors.borderSubtle),
            Expanded(
              child: _topic == null
                  ? Center(child: Text('Chọn một chủ đề bên trái để đọc.', style: AppText.bodyText))
                  : DiscussionDetailScreen(key: ValueKey(_topic), id: _topic!),
            ),
          ]),
        1 => const CommentsFeed(showTitle: false),
        _ => const ActivityScreen(embedded: true),
      };

  @override
  Widget build(BuildContext context) {
    // The forum pane is rebuilt when a topic is opened; the others stay alive.
    _built[_tab] = _tab == 0 ? _pane(0) : (_built[_tab] ?? _pane(_tab));
    return Material(
      color: AppColors.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 20, 40, 0),
          child: Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              for (final (i, label) in const [(0, 'Diễn đàn'), (1, 'Bình luận mới'), (2, 'Hoạt động')])
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
            ]),
          ),
        ),
        Expanded(
          child: IndexedStack(index: _tab, children: [for (var i = 0; i < 3; i++) _built[i] ?? const SizedBox.shrink()]),
        ),
      ]),
    );
  }
}
