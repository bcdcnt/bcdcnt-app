import 'package:flutter/material.dart';
import '../constants/theme.dart';
import 'hover_effects.dart';

class SectionHeader extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  /// Inline count badge rendered next to the title — e.g. `(8 bản)`, `(15)`.
  /// Helpful when the section has a known length to set expectations.
  final String? count;
  final String? actionText;
  /// When set, the trailing action renders as an icon-only ghost button with
  /// `actionText` (or its own tooltip) showing on hover instead of inline
  /// label. Use for short universal actions (copy, refresh, share) where an
  /// icon reads cleaner than a text link.
  final IconData? actionIcon;
  final VoidCallback? onAction;
  /// When set, the trailing action renders as the gradient "Phát" pill
  /// (same as the artist/composer banners) for a consistent play-all affordance.
  /// Unlike `actionText`, this pill is NOT mutually exclusive with the action
  /// link — both can show (pill first, then "Xem tất cả").
  final VoidCallback? onPlayAll;
  /// Icon + label for the play-all pill. Defaults to a plain "Phát" (play).
  /// Pass `Icons.shuffle` / "Ngẫu nhiên" for shuffle-style sections.
  final IconData playAllIcon;
  final String playAllLabel;
  /// When set, a small "làm mới" (refresh) icon button shows before the main
  /// action — for sections the user may want to re-fetch after sitting idle.
  final VoidCallback? onRefresh;

  const SectionHeader({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.count,
    this.actionText,
    this.actionIcon,
    this.onAction,
    this.onPlayAll,
    this.playAllIcon = Icons.play_arrow,
    this.playAllLabel = 'Phát',
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // 2026-11 brand style: no icon tile, 20/800 title, muted count, a small
    // wine "Phát" pill and a red text link. `icon` is kept for API
    // compatibility but no longer drawn.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.2)),
                      ),
                    ),
                    if (count != null) Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(count!.replaceAll(RegExp(r'[()]'), ''), style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                    ),
                  ],
                ),
                if (subtitle != null) Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: AppText.meta),
                ),
              ],
            ),
          ),
          if (onRefresh != null)
            IconButton(tooltip: 'Làm mới', onPressed: onRefresh, icon: Icon(Icons.refresh_rounded, size: 20, color: AppColors.textSecondary)),
          if (onPlayAll != null) ...[
            HoverScale(
              scale: 1.04,
              child: Material(
                color: AppColors.wine,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: onPlayAll,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(playAllIcon, size: 18, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(playAllLabel, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white))),
                    ]),
                  ),
                ),
              ),
            ),
            if ((actionText != null || actionIcon != null) && onAction != null) const SizedBox(width: 4),
          ],
          if (actionIcon != null && onAction != null)
            IconButton(tooltip: actionText ?? '', onPressed: onAction, icon: Icon(actionIcon, size: 20, color: AppColors.textSecondary))
          else if (actionText != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(actionText!, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accentLight))),
            ),
        ],
      ),
    );
  }
}
