import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import 'song_row.dart';
import 'ui.dart';

/// "Thông tin bài hát" (⋯ on the song page): the side facts kept off the
/// page itself. A row with no data is left out.
Future<void> showSongInfoSheet(BuildContext context, Map<String, dynamic> song) {
  String? str(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty || s == '0' ? null : s;
  }

  int? num_(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  final file = song['file'] is Map ? song['file'] as Map : const {};
  final views = num_(song['views']);
  final downloads = num_(song['downloads']);
  final duration = num_(file['duration']);
  final bitrate = num_(file['bitrate']);
  final hq = file['is_hq'] == 1 || file['is_hq'] == true;
  final created = DateTime.tryParse('${song['created_at'] ?? ''}');
  final contributor = song['uploader'] is Map ? song['uploader'] as Map : null;
  final recorder = file['user'] is Map ? file['user'] as Map : null;

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    builder: (ctx) {
      Widget row(String label, Widget value) => Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
            child: Row(children: [
              SizedBox(width: 120, child: Text(label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textMuted)))),
              const SizedBox(width: 12),
              Expanded(child: value),
            ]),
          );
      Widget text(String s) => Text(s, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)));
      Widget user(Map u) => Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: u['id'] == null
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      context.push('/user/${u['id']}');
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  UserAvatar(url: u['avatar']?['url']?.toString(), name: '${u['username'] ?? ''}', size: 26),
                  const SizedBox(width: 8),
                  Flexible(child: Text('${u['username'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.accentFg)))),
                ]),
              ),
            ),
          );
      final byline = songByline(song, withComposer: true);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 10, bottom: 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                SongCover(song: song, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${song['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text))),
                    if (byline.isNotEmpty) Text(byline, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
              child: Text('THÔNG TIN BÀI HÁT', style: AppText.eyebrow.copyWith(color: AppColors.textMuted)),
            ),
            if (views != null && views > 0) row('Lượt nghe', text(formatInt(views))),
            if (downloads != null && downloads > 0) row('Lượt tải', text(formatInt(downloads))),
            if (str(file['source']) != null) row('Nguồn', text(str(file['source'])!)),
            if (str(song['sheet']?['year']) != null) row('Năm sáng tác', text(str(song['sheet']['year'])!)),
            if (str(song['record_year']) != null) row('Năm thu', text(str(song['record_year'])!)),
            if (contributor != null && str(contributor['username']) != null) row('Đóng góp bởi', user(contributor)),
            // The recording now playing: who put it up, its length and quality.
            if (recorder != null && str(recorder['username']) != null) row('Bản thu của', user(recorder)),
            if (duration != null && duration > 0) row('Thời lượng', text(formatTime(duration.toDouble()))),
            if ((bitrate != null && bitrate > 0) || hq)
              row(
                'Chất lượng',
                Row(children: [
                  if (bitrate != null && bitrate > 0) text('$bitrate kbps'),
                  if (hq)
                    Container(
                      margin: EdgeInsets.only(left: bitrate != null && bitrate > 0 ? 8 : 0),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(6)),
                      child: Text('HQ', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
                    ),
                ]),
              ),
            if (created != null)
              row('Ngày đăng', text('${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year} · ${timeago(song['created_at'].toString())}')),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: PillButton(label: 'Đóng', primary: false, onTap: () => Navigator.pop(ctx)),
            ),
          ]),
        ),
      );
    },
  );
}
