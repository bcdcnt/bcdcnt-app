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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentSoft, Color(0x00711313)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 18, color: AppColors.accentLight),
            ),
            const SizedBox(width: 10),
          ],
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
                        style: display(TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                          letterSpacing: -0.2,
                          height: 1.15,
                        )),
                      ),
                    ),
                    if (count != null) Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        count!,
                        style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: body(TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ),
                ),
              ],
            ),
          ),
          if (onRefresh != null)
            Tooltip(
              message: 'Làm mới',
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onRefresh,
                  customBorder: const CircleBorder(),
                  hoverColor: AppColors.surfaceHover,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
          if (onPlayAll != null) ...[
            // Opaque gradient hides the InkWell hover, so lift the pill with a
            // scale + shadow on hover instead.
            HoverScale(
              scale: 1.06,
              child: InkWell(
                onTap: onPlayAll,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(playAllIcon, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(playAllLabel, style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white))),
                  ]),
                ),
              ),
            ),
            // Pill and the "Xem tất cả" link/icon can coexist — small gap.
            if ((actionText != null || actionIcon != null) && onAction != null) const SizedBox(width: 8),
          ],
          if (actionIcon != null && onAction != null)
            Tooltip(
              message: actionText ?? '',
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onAction,
                  customBorder: const CircleBorder(),
                  hoverColor: AppColors.surfaceHover,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(actionIcon, size: 16, color: AppColors.textSecondary),
                  ),
                ),
              ),
            )
          else if (actionText != null && onAction != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    Text(actionText!, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
                    Icon(Icons.chevron_right, size: 14, color: AppColors.accentLight),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
