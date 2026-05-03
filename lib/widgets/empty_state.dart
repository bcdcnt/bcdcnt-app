import 'package:flutter/material.dart';
import '../constants/theme.dart';

/// Standard empty-state placeholder used across list screens. Centred
/// glyph + title + optional subtitle + optional CTA. Replaces the bare
/// "Chưa có ..." Text we used inline in many spots.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, size: 32, color: AppColors.textMuted),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: display(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: body(TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
            ),
          ],
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onCta,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(ctaLabel!, style: body(const TextStyle(fontWeight: FontWeight.w700))),
            ),
          ],
        ],
      ),
    );
  }
}
