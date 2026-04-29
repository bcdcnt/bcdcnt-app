import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../widgets/section_header.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<dynamic> _latest = [];
  // Folk-music sub-data — populated lazily so the grid can show melodies +
  // folk categories under the Dân ca section (parity with web's Library).
  List<dynamic> _melodies = [];
  List<dynamic> _folkCats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await ApiClient.query(r'''query {
        songs(first: 8, orderBy: [{column: "id", order: DESC}]) {
          data { id slug title subtitle views play_type thumbnail { url } file { audio_url video_url duration } artists(first: 5) { data { id slug title avatar { url } } } }
        }
        melodies(first: 200, orderBy: [{column: "title", order: ASC}]) {
          data { id title slug }
        }
        fcats(first: 200, orderBy: [{column: "title", order: ASC}]) {
          data { id title slug }
        }
      }''');
      if (!mounted) return;
      setState(() {
        _latest = data['songs']?['data'] ?? [];
        _melodies = (data['melodies']?['data'] ?? []) as List;
        _folkCats = (data['fcats']?['data'] ?? []) as List;
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _openWeb(String path) => launchUrl(Uri.parse('$siteUrl$path'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Header
          Text(
            'Thư viện',
            style: display(const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.text, letterSpacing: -0.5)),
          ),
          const SizedBox(height: 6),
          Text(
            'Khám phá kho nhạc theo thể loại, thập niên, nghệ sĩ và tư liệu',
            style: body(const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
          const SizedBox(height: 24),

          // Của bạn (logged in only)
          if (auth.isAuthenticated) ...[
            const SectionHeader(icon: Icons.bookmark_outline, title: 'Của bạn'),
            _grid([
              _Tile(label: 'Yêu thích', icon: Icons.favorite, color: const Color(0xFFE57373), onTap: () => context.push('/yeu-thich')),
              _Tile(label: 'Nghe gần đây', icon: Icons.access_time, color: const Color(0xFF7986CB), onTap: () => context.push('/nghe-gan-day')),
              _Tile(label: 'Playlist của tôi', icon: Icons.queue_music, color: const Color(0xFF81C784), onTap: () => context.push('/playlist-cua-toi')),
              _Tile(label: 'Bài tôi gửi', icon: Icons.upload_outlined, color: const Color(0xFFFFB74D), onTap: () => context.push('/bai-gui-cua-toi')),
            ]),
            const SizedBox(height: 28),
          ],

          // Thể loại
          const SectionHeader(icon: Icons.category_outlined, title: 'Thể loại'),
          _grid([
            _Tile(label: 'Tân nhạc', icon: Icons.music_note, color: const Color(0xFF711313), onTap: () => context.push('/the-loai/tan-nhac')),
            _Tile(label: 'Dân ca', icon: Icons.album_outlined, color: const Color(0xFF8B6914), onTap: () => context.push('/the-loai/dan-ca')),
            _Tile(label: 'Khí nhạc', icon: Icons.piano, color: const Color(0xFF7A3B3A), onTap: () => context.push('/the-loai/khi-nhac')),
            _Tile(label: 'Tiếng thơ', icon: Icons.auto_stories_outlined, color: const Color(0xFF6B5210), onTap: () => context.push('/the-loai/tieng-tho')),
            _Tile(label: 'Thành viên hát', icon: Icons.mic_outlined, color: const Color(0xFF2D5E3A), onTap: () => context.push('/the-loai/thanh-vien-hat')),
          ]),
          const SizedBox(height: 28),

          // Tân nhạc — sub-categories (web parity)
          const SectionHeader(icon: Icons.music_note, title: 'Tân nhạc'),
          _grid([
            _Tile(label: 'Nhạc thiếu nhi', icon: Icons.child_care, color: const Color(0xFF8B6914), onTap: () => context.push('/tag/nhac-thieu-nhi')),
            _Tile(label: 'Nhạc nước ngoài', icon: Icons.public, color: const Color(0xFF2D5E3A), onTap: () => context.push('/tag/nhac-nuoc-ngoai')),
            _Tile(label: 'Nhạc nhẹ', icon: Icons.music_note_outlined, color: const Color(0xFF6B5210), onTap: () => context.push('/tag/nhac-nhe')),
            _Tile(label: 'Nhạc tiền chiến', icon: Icons.history_toggle_off, color: const Color(0xFFA89060), onTap: () => context.push('/tag/nhac-tien-chien')),
            _Tile(label: 'Nhạc phim', icon: Icons.movie_outlined, color: const Color(0xFF7A3B3A), onTap: () => context.push('/tag/nhac-phim')),
            _Tile(label: 'Video', icon: Icons.play_circle_outline, color: const Color(0xFF4A0D0D), onTap: () => context.push('/tag/video')),
          ]),
          const SizedBox(height: 28),

          // Khí nhạc — sub-categories
          const SectionHeader(icon: Icons.piano, title: 'Khí nhạc'),
          _grid([
            _Tile(label: 'Nhạc Việt Nam', icon: Icons.flag_outlined, color: const Color(0xFF7A3B3A), onTap: () => context.push('/tag/nhac-viet-nam')),
            _Tile(label: 'Nhạc nước ngoài', icon: Icons.public, color: const Color(0xFF2D5E3A), onTap: () => context.push('/tag/nhac-nuoc-ngoai')),
            _Tile(label: 'Video', icon: Icons.play_circle_outline, color: const Color(0xFF4A0D0D), onTap: () => context.push('/tag/khi-nhac-video')),
          ]),
          const SizedBox(height: 28),

          // Mới cập nhật
          if (_latest.isNotEmpty) ...[
            SectionHeader(
              icon: Icons.fiber_new,
              title: 'Mới cập nhật',
              actionText: 'Xem tất cả',
              onAction: () => context.push('/the-loai/tan-nhac'),
            ),
            _latestCarousel(),
            const SizedBox(height: 28),
          ] else if (_loading) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator(color: AppColors.accent))),
          ],

          // Khám phá
          const SectionHeader(icon: Icons.explore_outlined, title: 'Khám phá'),
          _grid([
            _Tile(label: 'Bảng xếp hạng', icon: Icons.leaderboard_outlined, color: const Color(0xFF711313), onTap: () => context.push('/bang-xep-hang')),
            _Tile(label: 'Bản nhạc', icon: Icons.music_note_outlined, color: const Color(0xFF4A0D0D), onTap: () => context.push('/sheet')),
            _Tile(label: 'Playlist', icon: Icons.queue_music_outlined, color: const Color(0xFF2D5E3A), onTap: () => context.push('/playlist')),
            _Tile(label: 'Tag', icon: Icons.tag, color: const Color(0xFF7A3B3A), onTap: () => context.push('/tag')),
          ]),
          const SizedBox(height: 28),

          // Nghệ sĩ & Tác giả
          const SectionHeader(icon: Icons.people_outline, title: 'Nghệ sĩ & Tác giả'),
          _grid([
            _Tile(label: 'Nghệ sĩ', icon: Icons.mic, color: const Color(0xFF711313), onTap: () => context.push('/nghe-si')),
            _Tile(label: 'Nhạc sĩ', icon: Icons.music_note, color: const Color(0xFF8B6914), onTap: () => context.push('/nhac-si')),
            _Tile(label: 'Nhà thơ', icon: Icons.auto_stories_outlined, color: const Color(0xFF6B5210), onTap: () => context.push('/nha-tho')),
            _Tile(label: 'Soạn giả', icon: Icons.edit_outlined, color: const Color(0xFF7A3B3A), onTap: () => context.push('/soan-gia')),
          ]),
          const SizedBox(height: 28),

          // Thư viện tư liệu
          const SectionHeader(icon: Icons.collections_bookmark_outlined, title: 'Tư liệu'),
          _grid([
            _Tile(label: 'Hình ảnh', icon: Icons.image_outlined, color: const Color(0xFF7986CB), onTap: () => context.push('/tu-lieu/hinh-anh')),
            _Tile(label: 'Âm thanh', icon: Icons.audiotrack, color: const Color(0xFF81C784), onTap: () => context.push('/tu-lieu/am-thanh')),
            _Tile(label: 'Video', icon: Icons.video_library_outlined, color: const Color(0xFFE57373), onTap: () => context.push('/tu-lieu/video')),
            _Tile(label: 'Bài viết', icon: Icons.article_outlined, color: const Color(0xFFFFB74D), onTap: () => context.push('/tu-lieu/bai-viet')),
          ]),
          const SizedBox(height: 28),

          // Theo thập niên
          const SectionHeader(icon: Icons.history_toggle_off, title: 'Tân nhạc theo thập niên'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [1940, 1950, 1960, 1970, 1980, 1990, 2000, 2010, 2020].map((d) {
              return InkWell(
                onTap: () => context.push('/bai-hat/thap-nien/$d'),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text('${d}s', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          // Cộng đồng
          const SectionHeader(icon: Icons.forum_outlined, title: 'Cộng đồng'),
          _grid([
            _Tile(label: 'Thảo luận', icon: Icons.chat_bubble_outline, color: const Color(0xFF4A0D0D), onTap: () => context.push('/thao-luan')),
            _Tile(label: 'Hoạt động', icon: Icons.timeline, color: const Color(0xFF2D1B4E), onTap: () => context.push('/cong-dong/hoat-dong-thanh-vien')),
            _Tile(label: 'Giới thiệu', icon: Icons.info_outline, color: const Color(0xFF711313), onTap: () => context.push('/gioi-thieu')),
            _Tile(label: 'Hỏi đáp AI', icon: Icons.auto_awesome, color: const Color(0xFF1A3A5C), onTap: () => _openWeb('/hoi-dap')),
          ]),
          const SizedBox(height: 28),

          // Dân ca — Làn điệu + thể loại con (full list, dynamic from API)
          if (_melodies.isNotEmpty || _folkCats.isNotEmpty) ...[
            const SectionHeader(icon: Icons.album_outlined, title: 'Dân ca'),
            if (_melodies.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Làn điệu (${_melodies.length})', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              ),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _melodies.map((m) {
                  final mm = Map<String, dynamic>.from(m);
                  return _Chip(
                    label: (mm['title'] ?? '').toString(),
                    onTap: () => context.push('/lan-dieu/${mm['slug']}'),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
            if (_folkCats.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Thể loại (${_folkCats.length})', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              ),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _folkCats.map((f) {
                  final ff = Map<String, dynamic>.from(f);
                  return _Chip(
                    label: (ff['title'] ?? '').toString(),
                    onTap: () => context.push('/tag/${ff['slug']}'),
                  );
                }).toList(),
              ),
            ],
          ],

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _grid(List<_Tile> tiles) {
    final w = MediaQuery.of(context).size.width;
    // Native desktop pattern: more columns + taller tiles than mobile.
    final cols = w >= 1280 ? 4 : (w >= 900 ? 3 : 2);
    final tileHeight = w >= 900 ? 80.0 : 64.0;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: cols,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      mainAxisExtent: tileHeight,
      children: tiles,
    );
  }

  Widget _latestCarousel() {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _latest.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (ctx, i) {
          final song = Map<String, dynamic>.from(_latest[i]);
          final artists = (song['artists']?['data'] ?? []) as List;
          final thumb = song['thumbnail']?['url'];
          return InkWell(
            onTap: () => context.push('/song/${song['id']}', extra: song),
            child: SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: thumb != null
                        ? CachedNetworkImage(imageUrl: thumb, width: 140, height: 140, fit: BoxFit.cover)
                        : Container(width: 140, height: 140, color: AppColors.surfaceLight, child: const Icon(Icons.music_note, color: AppColors.textMuted, size: 28)),
                  ),
                  const SizedBox(height: 8),
                  Text(song['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title),
                  if (artists.isNotEmpty)
                    Text(artists.map((a) => a['title'] ?? '').join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Tile({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, Color.lerp(color, Colors.black, 0.3)!],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: -3, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white))),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
      ),
    );
  }
}
