import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../constants/theme.dart';
import '../services/share.dart';
import 'brand_logo.dart';
import 'ui.dart';

/// Share a song as a picture: cover, a lyric line or member memory, title
/// and credits on the brand card. Members forward pictures in Zalo groups far
/// more than links, and the card carries the site's name with it.
Future<void> showSongShareSheet(BuildContext context, Map song, {String? hook, String? kind}) async {
  final key = GlobalKey();
  final text = songShareText(song, hook: hook, kind: kind);
  var busy = false;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      Future<void> shareImage() async {
        setSheet(() => busy = true);
        try {
          // Let the cover and logo finish painting before taking the picture.
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await WidgetsBinding.instance.endOfFrame;
          final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 3.4);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/bcdcnt-${song['id']}.png');
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          if (!ctx.mounted) return;
          final box = ctx.findRenderObject() as RenderBox?;
          await SharePlus.instance.share(ShareParams(
            files: [XFile(file.path, mimeType: 'image/png')],
            text: text,
            sharePositionOrigin: box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null,
          ));
        } catch (_) {
          if (ctx.mounted) await shareText(ctx, text: text, subject: song['title']?.toString());
        } finally {
          if (ctx.mounted) setSheet(() => busy = false);
        }
      }

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Text('Chia sẻ bài hát', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
            const SizedBox(height: 14),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                // The card is rendered at a fixed scale so the saved
                // picture looks the same whatever the reader's text size.
                child: MediaQuery.withNoTextScaling(
                  child: Semantics(
                    image: true,
                    label: 'Ảnh chia sẻ bài ${song['title'] ?? ''}',
                    excludeSemantics: true,
                    child: RepaintBoundary(key: key, child: _Card(song: song, kind: kind, hook: hook ?? firstLyricLine(song['content']))),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            PillButton(label: busy ? 'Đang tạo ảnh…' : 'Gửi ảnh (Zalo, Facebook…)', icon: Icons.image_outlined, loading: busy, onTap: busy ? null : shareImage),
            const SizedBox(height: 10),
            PillButton(
              label: 'Chỉ gửi chữ và đường link',
              icon: Icons.link_rounded,
              primary: false,
              onTap: () async {
                Navigator.pop(ctx);
                await shareText(context, text: text, subject: song['title']?.toString());
              },
            ),
            // Room for the mini player, which floats above sheets.
          ]),
        ),
      );
    }),
  );
}

class _Card extends StatelessWidget {
  final Map song;
  final String? hook;
  final String? kind;
  const _Card({required this.song, this.hook, this.kind});

  String _names(dynamic list) {
    final raw = list is Map ? list['data'] : list;
    if (raw is! List) return '';
    return raw.whereType<Map>().map((e) => '${e['title'] ?? ''}').where((s) => s.isNotEmpty).take(2).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final cover = song['thumbnail']?['url']?.toString();
    final composers = _names(song['sheet']?['composers'] ?? song['composers']);
    final year = '${song['sheet']?['year'] ?? ''}';
    final artists = _names(song['artists']);
    const paper = Color(0xFFF6E8DE);
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (cover != null)
              NetImage(url: cover, width: 92, height: 92, radius: 14, tint: true)
            else
              Container(width: 92, height: 92, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.music_note_rounded, color: paper, size: 40)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${song['title'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 21, height: 1.15, fontWeight: FontWeight.w800, color: Colors.white))),
                if (composers.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text([composers, if (year.isNotEmpty && year != '0' && year != 'null') year].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: paper))),
                ],
              ]),
            ),
          ]),
          const Spacer(),
          if (hook != null && hook!.isNotEmpty)
            Text('“${hook!.split('\n').take(3).map(noOrphan).join('\n')}”', maxLines: 5, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: hook!.length > 90 ? 15.5 : 17.5, height: 1.45, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, color: Colors.white))),
          const Spacer(),
          if (artists.isNotEmpty) Text('Trình bày: $artists', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: paper))),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white24),
          const SizedBox(height: 12),
          Row(children: [
            const BrandLogo(height: 22, onDark: true),
            const SizedBox(width: 12),
            const Spacer(),
            // Zalo often strips the message text: the picture itself says
            // where to find the song.
            Flexible(child: Text('bcdcnt.net${songWebPath(song, kind)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: paper)))),
          ]),
        ]),
      ),
    );
  }
}
