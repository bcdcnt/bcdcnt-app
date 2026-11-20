import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../constants/theme.dart';
import '../services/activity.dart';
import '../services/api.dart' show formatViews;
import '../services/auth.dart';
import '../services/player.dart' show songKind;
import '../services/share.dart';
import 'brand_logo.dart';
import 'ui.dart';

/// Share a song as a picture: cover, a lyric line or member memory, title
/// and credits on the brand card. Members forward pictures in Zalo groups far
/// more than links, and the card carries the site's name with it.
/// [onCount]: the new share total once the server has counted the share.
Future<void> showSongShareSheet(BuildContext context, Map song, {String? hook, String? kind, ValueChanged<int>? onCount}) {
  final k = kind ?? songKind(song);
  final auth = context.read<AuthProvider>();
  return _showShareSheet(
    context,
    title: 'Chia sẻ bài hát',
    imageLabel: 'Ảnh chia sẻ bài ${song['title'] ?? ''}',
    fileName: 'bcdcnt-$k-${song['id']}',
    text: songShareText(song, hook: hook, kind: kind),
    subject: song['title']?.toString(),
    card: _Card(song: song, kind: kind, hook: hook ?? firstLyricLine(song['content'])),
    onShared: (channel) => _count(auth, k, song['id'], channel, onCount),
  );
}

/// A person (artist, composer, poet, recomposer) as a picture: photo, years
/// and birthplace, their best-known songs and the page link.
Future<void> showPersonShareSheet(
  BuildContext context, {
  required Map person,
  required String type,
  required String label,
  required String path,
  List<String> topSongs = const [],
  int songCount = 0,
  int listens = 0,
  ValueChanged<int>? onCount,
}) {
  final name = (person['title'] ?? '').toString();
  final url = '$siteUrl$path';
  final text = [
    '🎵 $label $name',
    if (topSongs.isNotEmpty) 'Nổi tiếng với: ${topSongs.take(3).join(', ')}',
    'Nghe trên Bài ca đi cùng năm tháng: $url',
  ].join('\n');
  final auth = context.read<AuthProvider>();
  return _showShareSheet(
    context,
    title: 'Chia sẻ ${label.toLowerCase()}',
    imageLabel: 'Ảnh chia sẻ ${label.toLowerCase()} $name',
    fileName: 'bcdcnt-$type-${person['id']}',
    text: text,
    subject: name,
    card: _PersonCard(person: person, label: label, path: path, topSongs: topSongs, songCount: songCount, listens: listens),
    onShared: (channel) => _count(auth, type, person['id'], channel, onCount),
  );
}

// Auth is read up front: the page that opened the sheet may be gone by the
// time the share sheet closes.
void _count(AuthProvider auth, String type, dynamic id, String channel, ValueChanged<int>? onCount) {
  logShare(auth, type, id, channel).then((n) {
    if (n != null) onCount?.call(n);
  });
}

Future<void> _showShareSheet(
  BuildContext context, {
  required String title,
  required String imageLabel,
  required String fileName,
  required String text,
  String? subject,
  required Widget card,
  required ValueChanged<String> onShared,
}) async {
  final key = GlobalKey();
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
          final file = File('${dir.path}/$fileName.png');
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          if (!ctx.mounted) return;
          final box = ctx.findRenderObject() as RenderBox?;
          await SharePlus.instance.share(ShareParams(
            files: [XFile(file.path, mimeType: 'image/png')],
            text: text,
            sharePositionOrigin: box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null,
          ));
          onShared('image');
        } catch (_) {
          if (ctx.mounted) await shareText(ctx, text: text, subject: subject);
          onShared('link');
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
            Text(title, style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
            const SizedBox(height: 14),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                // The card is rendered at a fixed scale so the saved
                // picture looks the same whatever the reader's text size.
                child: MediaQuery.withNoTextScaling(
                  child: Semantics(
                    image: true,
                    label: imageLabel,
                    excludeSemantics: true,
                    child: RepaintBoundary(key: key, child: card),
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
                await shareText(context, text: text, subject: subject);
                onShared('link');
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
          gradient: LinearGradient(colors: AppColors.heroGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
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

class _PersonCard extends StatelessWidget {
  final Map person;
  final String label;
  final String path;
  final List<String> topSongs;
  final int songCount;
  final int listens;
  const _PersonCard({required this.person, required this.label, required this.path, required this.topSongs, required this.songCount, required this.listens});

  @override
  Widget build(BuildContext context) {
    const paper = Color(0xFFF6E8DE);
    final avatar = person['avatar']?['url']?.toString();
    final name = '${person['title'] ?? ''}';
    final yob = '${person['yob'] ?? ''}';
    // "Lương Ngọc - Bình Giang - Hải Dương" → "Hải Dương": the province is
    // enough on a picture.
    final place = '${person['born_address'] ?? ''}'.split(RegExp(r'\s*[-,]\s*')).where((x) => x.trim().isNotEmpty).lastOrNull ?? '';
    final meta = [if (yob.isNotEmpty && yob != '0' && yob != 'null') yob, if (place.isNotEmpty) place].join(' · ');
    final stats = [if (songCount > 0) '$songCount bài hát', if (listens > 0) '${formatViews(listens)} lượt nghe'].join(' · ');
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(colors: AppColors.heroGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 2)),
              child: avatar != null
                  ? NetImage(url: avatar, width: 88, height: 88, radius: 44, tint: true)
                  : CircleAvatar(backgroundColor: Colors.white12, child: Text(name.isEmpty ? '' : name[0].toUpperCase(), style: display(const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: paper)))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label.toUpperCase(), style: body(const TextStyle(fontSize: 11, letterSpacing: 0.9, fontWeight: FontWeight.w800, color: paper))),
                const SizedBox(height: 4),
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 22, height: 1.15, fontWeight: FontWeight.w800, color: Colors.white))),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: paper))),
                ],
              ]),
            ),
          ]),
          const Spacer(),
          if (topSongs.isNotEmpty) ...[
            Text('NỔI TIẾNG VỚI', style: body(const TextStyle(fontSize: 12, letterSpacing: 0.9, fontWeight: FontWeight.w800, color: paper))),
            const SizedBox(height: 8),
            for (final t in topSongs.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('♪ $t', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 16, height: 1.35, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: Colors.white))),
              ),
          ],
          const Spacer(),
          if (stats.isNotEmpty) Text(stats, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: paper))),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white24),
          const SizedBox(height: 12),
          Row(children: [
            const BrandLogo(height: 22, onDark: true),
            const SizedBox(width: 12),
            const Spacer(),
            Flexible(child: Text('bcdcnt.net$path', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: paper)))),
          ]),
        ]),
      ),
    );
  }
}
