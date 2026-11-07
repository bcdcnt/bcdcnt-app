import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';

/// "Góp tay cho kho nhạc": invitation to fill gaps in the archive. Sits on
/// top of Cộng đồng › Hoạt động, next to what others just contributed.
class ContributeCard extends StatelessWidget {
  const ContributeCard({super.key});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.push('/gop-tay'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            child: Row(children: [
              Icon(Icons.volunteer_activism_outlined, color: AppColors.accentLight, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Góp tay cho kho nhạc', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
                  const SizedBox(height: 2),
                  Text('Nhiều bài còn thiếu tác giả, năm sáng tác. Bạn có nhớ?', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary))),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ]),
          ),
        ),
      );
}
