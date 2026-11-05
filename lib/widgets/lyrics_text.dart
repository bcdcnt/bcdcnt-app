import 'package:flutter/material.dart';
import '../constants/theme.dart';

/// Plain (non-LRC) lyrics rendered line by line. Verse markers typed into
/// the lyrics ("1, 3-", "2.", "ĐK:") become small labels ("LỜI 1 & 3",
/// "ĐIỆP KHÚC") instead of showing as raw text; blank lines become verse
/// gaps. Used by the phone player and the song page.
class LyricsText extends StatelessWidget {
  final String html;
  final double fontSize;
  final FontWeight weight;
  final Color color;
  final Color labelColor;
  /// Show only the first N lines (collapsed song page); null = all.
  final int? maxLines;

  const LyricsText({
    super.key,
    required this.html,
    this.fontSize = 17,
    this.weight = FontWeight.w600,
    required this.color,
    required this.labelColor,
    this.maxLines,
  });

  static final _labelOnly = RegExp(r'^\s*(?:(\d+(?:\s*[,&]\s*\d+)*)\s*[-–.:)]?|(đk|điệp khúc|coda|kết)\s*[-–.:)]?)\s*$', caseSensitive: false);
  static final _labelLead = RegExp(r'^\s*(\d+(?:\s*[,&]\s*\d+)*)\s*[-–.:)]\s*(.+)$');
  static final _chorusLead = RegExp(r'^\s*(đk|điệp khúc)\s*[-–.:)]\s*(.+)$', caseSensitive: false);

  static String plain(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>\s*', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  static String _label(String? nums, String? word) {
    if (word != null) {
      final w = word.toLowerCase();
      return w.startsWith('đk') || w.startsWith('điệp') ? 'Điệp khúc' : word;
    }
    final n = nums!.split(RegExp(r'\s*[,&]\s*')).where((s) => s.isNotEmpty).toList();
    return 'Lời ${n.length > 1 ? '${n.sublist(0, n.length - 1).join(', ')} & ${n.last}' : n.first}';
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var lines = 0;
    Widget label(String s) => Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 10, bottom: 6),
          child: Text(s.toUpperCase(), style: body(TextStyle(fontSize: 12, letterSpacing: 0.9, fontWeight: FontWeight.w800, color: labelColor))),
        );
    Widget line(String s) {
      lines++;
      return Text(s, style: body(TextStyle(fontSize: fontSize, height: 1.5, fontWeight: weight, color: color)));
    }

    for (final l in plain(html).split('\n')) {
      if (maxLines != null && lines >= maxLines!) break;
      final s = l.trim();
      if (s.isEmpty) {
        if (children.isNotEmpty) children.add(SizedBox(height: fontSize * 0.8));
        continue;
      }
      final m1 = _labelOnly.firstMatch(s);
      if (m1 != null) {
        children.add(label(_label(m1.group(1), m1.group(2))));
        continue;
      }
      final m2 = _labelLead.firstMatch(s);
      if (m2 != null && m2.group(1)!.length <= 6) {
        children.add(label(_label(m2.group(1), null)));
        children.add(line(m2.group(2)!));
        continue;
      }
      final m3 = _chorusLead.firstMatch(s);
      if (m3 != null) {
        children.add(label('Điệp khúc'));
        children.add(line(m3.group(2)!));
        continue;
      }
      children.add(line(s));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
