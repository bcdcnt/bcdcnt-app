import 'package:flutter/material.dart';
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

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
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
    } catch (_) { if (mounted) setState(() => _loading = false); }
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
      return const Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    }
    if (_sheet == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
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
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text('BẢN NHẠC', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList(delegate: SliverChildListDelegate([
              Text(sheet['title'] ?? '', style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.3))),
              const SizedBox(height: 8),
              if (composers.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('Sáng tác: ${composers.map((c) => c['title']).join(', ')}${sheet['year'] != null && sheet['year'].toString().isNotEmpty ? ' (${sheet['year']})' : ''}', style: body(const TextStyle(fontSize: 13, color: AppColors.textSecondary)))),
              if (poets.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${(sheet['lyric_type']?.toString().isNotEmpty == true) ? sheet['lyric_type'] : 'Thơ'}: ${poets.map((p) => p['title']).join(', ')}', style: body(const TextStyle(fontSize: 13, color: AppColors.textSecondary)))),
              if (uploader?['username'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                CircleAvatar(radius: 9, backgroundColor: AppColors.surfaceLight, backgroundImage: uploader['avatar']?['url'] != null ? CachedNetworkImageProvider(uploader['avatar']['url']) : null),
                const SizedBox(width: 6),
                Text(uploader['username'], style: body(const TextStyle(fontSize: 12, color: AppColors.textMuted))),
              ])),

              if (_images.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(children: [
                  const Icon(Icons.image_outlined, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text('Bản nhạc (${_images.length})', style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  height: 180,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (ctx, i) => InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SheetLightbox(images: _images, initialIndex: i))),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(imageUrl: _images[i], width: 130, height: 180, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(width: 130, height: 180, color: AppColors.surfaceLight, child: const Icon(Icons.broken_image, color: AppColors.textMuted))),
                      ),
                    ),
                  ),
                ),
              ],

              if (tags.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(spacing: 6, runSpacing: 6, children: tags.map((t) => InkWell(
                  onTap: () => context.push('/tag/${t['slug']}'),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)), child: Text('#${t['name']}', style: body(const TextStyle(fontSize: 11, color: AppColors.textSecondary)))),
                )).toList()),
              ],

              if (_songs.isNotEmpty) ...[
                const SizedBox(height: 22),
                Row(children: [
                  const Icon(Icons.queue_music, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text('Bản thu (${_formatInt(_songs.length)})', style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
                ]),
                const SizedBox(height: 8),
                ..._songs.asMap().entries.map((e) => SongRow(song: e.value, index: e.key, showIndex: true, onTap: () => context.push('/song/${e.value['id']}', extra: e.value))),
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
