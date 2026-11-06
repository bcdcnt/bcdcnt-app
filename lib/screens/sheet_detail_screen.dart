import 'package:flutter/material.dart';
import '../services/imgcdn.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/activity.dart';
import '../services/player.dart';
import '../widgets/song_row.dart';
import '../widgets/mini_player.dart';
import '../widgets/sheet_lightbox.dart';

class SheetDetailScreen extends StatefulWidget {
  final String id;
  const SheetDetailScreen({super.key, required this.id});

  @override
  State<SheetDetailScreen> createState() => _SheetDetailScreenState();
}

class _SheetDetailScreenState extends State<SheetDetailScreen> {
  Map<String, dynamic>? _sheet;
  List<Map<String, dynamic>> _songs = [];
  List<String> _images = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    if (_failed) setState(() { _failed = false; _loading = true; });
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        sheet(id: $id) {
          id title slug year lyric_type content
          composers(first: 20) { data { id slug title } }
          poets(first: 20) { data { id slug title } }
          tags { id name slug }
          uploader { id username avatar { url } }
        }
      }''', {'id': widget.id});
      final sh = data['sheet'];
      if (sh == null) { if (mounted) setState(() => _loading = false); return; }
      // Songs using this sheet
      final songsData = await ApiClient.query(r'''query($sheetId: Mixed) {
        songs(first: 30, where: { column: "sheet_id", value: $sheetId }, orderBy: [{column: "views", order: DESC}]) {
          data { id slug title views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } }
        }
      }''', {'sheetId': widget.id});
      final songs = ((songsData['songs']?['data'] ?? []) as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['file_type'] = 'song';
        return m;
      }).toList();
      // Extract images from sheet content
      final content = (sh['content'] ?? '').toString();
      final imgs = RegExp(r'<img[^>]+src="([^"]+)"', caseSensitive: false)
          .allMatches(content).map((m) => m.group(1)!).toList();
      if (!mounted) return;
      setState(() {
        _sheet = Map<String, dynamic>.from(sh);
        _songs = songs;
        _images = imgs;
        _loading = false;
      });
      logActivity(context.read<AuthProvider>(), 'view', 'sheet', sh['id']);
    } catch (_) { if (mounted) setState(() { _loading = false; _failed = true; }); }
  }

  AppBar _plainAppBar() => AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Bản nhạc'),
        centerTitle: true,
        leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
      );

  /// "Sáng tác: A, B (1965)" with each name tappable to its person page.
  Widget _creditLine(String label, List people, String routePrefix, {String suffix = ''}) {
    final style = body(TextStyle(fontSize: 16, color: AppColors.textSecondary));
    final linkStyle = body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.accentLight));
    final children = <Widget>[Text('$label: ', style: style)];
    for (int i = 0; i < people.length; i++) {
      final p = people[i] as Map;
      final slug = p['slug']?.toString() ?? '';
      final name = p['title']?.toString() ?? '';
      children.add(Semantics(
        button: slug.isNotEmpty,
        label: name,
        excludeSemantics: true,
        child: InkWell(
          onTap: slug.isEmpty ? null : () => context.push('$routePrefix$slug'),
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Align(widthFactor: 1, child: Text(name + (i < people.length - 1 ? ',' : ''), style: slug.isEmpty ? style : linkStyle)),
            ),
          ),
        ),
      ));
    }
    if (suffix.isNotEmpty) children.add(Text(' $suffix', style: style));
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: children);
  }

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 == 0) buf.write('.'); buf.write(s[i]); }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (_loading && _sheet == null) {
      return Scaffold(backgroundColor: AppColors.bg, appBar: _plainAppBar(), body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    }
    if (_failed && _sheet == null) {
      return Scaffold(backgroundColor: AppColors.bg, appBar: _plainAppBar(), body: ListView(children: [OfflineBlock(onRetry: _fetch)]));
    }
    if (_sheet == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: _plainAppBar(),
        body: Center(child: Text('Không tìm thấy bản nhạc', style: AppText.bodyText)),
      );
    }
    final sheet = _sheet!;
    final composers = (sheet['composers']?['data'] ?? []) as List;
    final poets = (sheet['poets']?['data'] ?? []) as List;
    final tags = (sheet['tags'] ?? []) as List;
    final uploader = sheet['uploader'];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg,
            title: Text('Bản nhạc'),
            centerTitle: true,
            leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList(delegate: SliverChildListDelegate([
              Text(sheet['title'] ?? '', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.3))),
              const SizedBox(height: 8),
              if (composers.isNotEmpty) _creditLine('Sáng tác', composers, '/nhac-si/', suffix: sheet['year'] != null && sheet['year'].toString().isNotEmpty ? '(${sheet['year']})' : ''),
              if (poets.isNotEmpty) _creditLine((sheet['lyric_type']?.toString().isNotEmpty == true) ? sheet['lyric_type'].toString() : 'Thơ', poets, '/nha-tho/'),
              if (uploader?['username'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                CircleAvatar(radius: 11, backgroundColor: AppColors.surfaceLight, backgroundImage: uploader['avatar']?['url'] != null ? CachedNetworkImageProvider(cdnImg(uploader['avatar']['url'].toString(), 96)) : null),
                const SizedBox(width: 6),
                Text(uploader['username'], style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary))),
              ])),

              if (_images.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(children: [
                  Icon(Icons.image_outlined, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text('Bản nhạc (${_images.length})', style: display(TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text))),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  height: 180,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (ctx, i) => Semantics(
                      button: true,
                      label: 'Xem bản nhạc trang ${i + 1}',
                      child: InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SheetLightbox(images: _images, initialIndex: i))),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(imageUrl: cdnImg(_images[i], 320), width: 130, height: 180, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(width: 130, height: 180, color: AppColors.surfaceLight, child: Icon(Icons.broken_image, color: AppColors.textMuted))),
                      ),
                    ),
                    ),
                  ),
                ),
              ],

              if (tags.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(spacing: 8, runSpacing: 8, children: tags.map((t) => Semantics(
                  button: true,
                  label: 'Tag ${t['name']}',
                  excludeSemantics: true,
                  child: InkWell(
                  onTap: () => context.push('/tag/${t['slug']}'),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13), decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border)), child: Text('#${t['name']}', style: body(TextStyle(fontSize: 15, color: AppColors.text)))),
                ))).toList()),
              ],

              if (_songs.isNotEmpty) ...[
                const SizedBox(height: 22),
                Row(children: [
                  Icon(Icons.queue_music, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text('Bản thu (${_formatInt(_songs.length)})', style: display(TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text))),
                ]),
                const SizedBox(height: 8),
                ..._songs.asMap().entries.map((e) => SongRow(song: e.value, index: e.key, showIndex: true, queue: asSongList(_songs))),
              ],

              SizedBox(height: player.currentSong != null ? 90 : 20),
            ])),
          ),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
