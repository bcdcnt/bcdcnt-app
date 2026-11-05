import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../widgets/ui.dart';
import 'activity_screen.dart';
import 'comments_screen.dart';
import 'discussion_list_screen.dart';

/// Cộng đồng tab: listener comments, the forum and member activity under
/// one header. Each pane is built on first visit and kept alive.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  int _pane = 0;
  final Map<int, Widget> _built = {};

  Widget _build(int i) => switch (i) {
        0 => const CommentsFeed(),
        1 => const DiscussionListScreen(embedded: true),
        _ => const ActivityScreen(embedded: true),
      };

  @override
  Widget build(BuildContext context) {
    _built.putIfAbsent(_pane, () => _build(_pane));
    return ColoredBox(
      color: AppColors.bg,
      child: Column(
        children: [
          PageTitle('Cộng đồng', actions: [
            RoundIcon(icon: Icons.notifications_none_rounded, tooltip: 'Thông báo', onTap: () => context.push('/thong-bao')),
          ]),
          const SizedBox(height: 16),
          Segmented(labels: const ['Cảm nhận', 'Thảo luận', 'Hoạt động'], selected: _pane, onSelect: (i) => setState(() => _pane = i)),
          Expanded(
            child: IndexedStack(
              index: _pane,
              sizing: StackFit.expand,
              children: [for (var i = 0; i < 3; i++) _built[i] ?? const SizedBox.shrink()],
            ),
          ),
        ],
      ),
    );
  }
}
