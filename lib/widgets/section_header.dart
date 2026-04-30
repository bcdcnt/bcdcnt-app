import 'package:flutter/material.dart';
import '../constants/theme.dart';

class SectionHeader extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  /// Inline count badge rendered next to the title — e.g. `(8 bản)`, `(15)`.
  /// Helpful when the section has a known length to set expectations.
  final String? count;
  final String? actionText;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.count,
    this.actionText,
    this.onAction,
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
                gradient: const LinearGradient(
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
                        style: display(const TextStyle(
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
                        style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ),
                ),
              ],
            ),
          ),
          if (actionText != null && onAction != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    Text(actionText!, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
                    const Icon(Icons.chevron_right, size: 14, color: AppColors.accentLight),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
