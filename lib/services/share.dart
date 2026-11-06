import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../constants/theme.dart';

/// Opens the phone's share sheet (Zalo, Facebook, Messenger, SMS…) with a
/// ready-written message; members mostly pass songs on through Zalo groups,
/// so a bare copied link was the weakest way to spread the site. Falls back
/// to copying when the platform has no share sheet.
Future<void> shareText(BuildContext context, {required String text, String? subject}) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject, sharePositionOrigin: origin));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép để dán vào Zalo, Facebook…')));
    }
  }
}

String _names(dynamic list) {
  final raw = list is Map ? list['data'] : list;
  if (raw is! List) return '';
  return raw.whereType<Map>().map((e) => (e['title'] ?? e['username'] ?? '').toString()).where((s) => s.isNotEmpty).take(3).join(', ');
}

/// "🎵 Bài ca cho em — Phan Nhân (1981)\nTrình bày: Tô Thanh Phương\n<link>"
String songShareText(Map song) {
  final title = (song['title'] ?? '').toString();
  final composers = _names(song['sheet']?['composers'] ?? song['composers']);
  final year = (song['sheet']?['year'] ?? song['year'])?.toString();
  final artists = _names(song['artists']);
  final url = '$siteUrl/bai-hat/${song['slug']}-${song['id']}';
  final head = StringBuffer('🎵 $title');
  if (composers.isNotEmpty) head.write(' — $composers');
  if (year != null && year.isNotEmpty && year != '0') head.write(' ($year)');
  return [
    head.toString(),
    if (artists.isNotEmpty) 'Trình bày: $artists',
    'Nghe trên Bài ca đi cùng năm tháng: $url',
  ].join('\n');
}
