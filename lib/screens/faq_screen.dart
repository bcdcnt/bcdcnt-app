import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/faq_data.dart';
import '../constants/theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/ui.dart';

/// Câu hỏi thường gặp: topic chips, a filter box and expandable answers.
/// Screen names inside answers ("Yêu thích", "Góp ý & hỗ trợ"…) are links.
class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});
  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  int _group = -1; // -1 = tất cả
  String _q = '';

  static String _fold(String s) {
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final low = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in low.characters) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  List<InlineSpan> _linked(String text) {
    final spans = <InlineSpan>[];
    var rest = text;
    while (rest.isNotEmpty) {
      var at = -1;
      (String, String)? hit;
      for (final l in kFaqLinks) {
        final i = rest.indexOf(l.$1);
        if (i >= 0 && (at < 0 || i < at)) {
          at = i;
          hit = l;
        }
      }
      if (hit == null) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (at > 0) spans.add(TextSpan(text: rest.substring(0, at)));
      final route = hit.$2;
      spans.add(TextSpan(
        text: hit.$1,
        style: TextStyle(color: AppColors.accentLight, fontWeight: FontWeight.w700),
        recognizer: TapGestureRecognizer()..onTap = () => context.push(route),
      ));
      rest = rest.substring(at + hit.$1.length);
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final q = _fold(_q.trim());
    final groups = <(String, List<FaqItem>)>[];
    for (var i = 0; i < kFaq.length; i++) {
      if (_group >= 0 && i != _group) continue;
      final items = kFaq[i].items.where((it) => q.isEmpty || _fold(it.q).contains(q) || _fold(it.a).contains(q)).toList();
      if (items.isNotEmpty) groups.add((kFaq[i].cat, items));
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const SubPageBar(title: 'Câu hỏi thường gặp'),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                decoration: InputDecoration(
                  hintText: 'Tìm câu hỏi…',
                  hintStyle: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                ),
              ),
            ),
            ChipStrip(
              labels: ['Tất cả', for (final g in kFaq) g.cat],
              selected: _group + 1,
              onSelect: (i) => setState(() => _group = i - 1),
            ),
            if (groups.isEmpty)
              EmptyBlock(
                icon: Icons.help_outline_rounded,
                title: 'Không thấy câu hỏi phù hợp',
                message: 'Bạn có thể hỏi trực tiếp ban quản trị.',
                action: 'Gửi câu hỏi',
                onAction: () => context.push('/ho-tro'),
              ),
            for (final (cat, items) in groups) ...[
              SectionTitle(cat, action: null),
              for (final it in items)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                    childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    iconColor: AppColors.accentLight,
                    collapsedIconColor: AppColors.textMuted,
                    title: Text(it.q, style: body(TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.text))),
                    children: [
                      Text.rich(
                        TextSpan(children: _linked(it.a)),
                        style: body(TextStyle(fontSize: 15, height: 1.6, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  Expanded(child: Text('Chưa tìm được câu trả lời?', style: AppText.title)),
                  TextButton(
                    onPressed: () => context.push('/ho-tro'),
                    child: Text('Hỏi BQT', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
                  ),
                ]),
              ),
            ),
          ],
        ),
        const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
