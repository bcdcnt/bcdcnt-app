import 'package:flutter/material.dart';
import '../constants/theme.dart';
import 'ui.dart' show PillButton;

/// Desktop list pages (canvas "Desktop · danh sách"): no phone title bar
/// (the shell's top bar has Back), a page title with its count and actions
/// on one row instead of the colour banner, content capped in width.
bool isDesk(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

/// Side padding of a desktop page.
const deskPad = EdgeInsets.fromLTRB(40, 28, 40, 48);

/// Keeps a desktop page at a readable width, against the left edge.
class DeskFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const DeskFrame({super.key, required this.child, this.maxWidth = 1320});
  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.topLeft, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}

/// Title · count on the left, actions on the right.
class DeskHead extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? eyebrow;
  final List<Widget> actions;
  const DeskHead({super.key, required this.title, this.subtitle, this.eyebrow, this.actions = const []});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (eyebrow != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(eyebrow!.toUpperCase(), style: AppText.eyebrow)),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 34, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: AppColors.text))),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMuted)))),
            ]),
          ),
          for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 10) else const SizedBox(width: 16), actions[i]],
        ]),
      );
}

/// "Phát tất cả" / "Ngẫu nhiên" as normal-size buttons for [DeskHead].
List<Widget> deskPlayButtons({VoidCallback? play, VoidCallback? shuffle, String playLabel = 'Phát tất cả'}) => [
      if (play != null) PillButton(label: playLabel, icon: Icons.play_arrow_rounded, height: 48, onTap: play),
      if (shuffle != null) PillButton(label: 'Ngẫu nhiên', icon: Icons.shuffle_rounded, height: 48, primary: false, onTap: shuffle),
    ];
