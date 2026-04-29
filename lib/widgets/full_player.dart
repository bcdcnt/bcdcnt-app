import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/player.dart';
import '../services/auth.dart';
import '../services/api.dart';

class FullPlayer extends StatefulWidget {
  const FullPlayer({super.key});

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

enum _PanelMode { vinyl, lyrics, queue }

class _FullPlayerState extends State<FullPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _rotation;
  _PanelMode _panel = _PanelMode.vinyl;

  bool _liked = false;
  List<dynamic> _lovers = [];
  bool _downloading = false;
  bool _loversFetchedForId = false;
  String? _songLyrics;
  String? _lyricsFetchedForId;

  static const List<double> _speedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _openSongDetail(Map<String, dynamic> song) {
    final id = song['id']?.toString();
    if (id == null || id.isEmpty) return;
    Navigator.of(context).pop();
    context.push('/song/$id', extra: song);
  }

  void _openArtistDetail(Map artist) {
    final slug = artist['slug']?.toString();
    if (slug != null && slug.isNotEmpty && artist['title'] != null) {
      Navigator.of(context).pop();
      context.push('/nghe-si/$slug');
      return;
    }
    // Karaoke "artists" entries are actually users — fall back to user route.
    final id = artist['id']?.toString();
    if (id != null && id.isNotEmpty && artist['username'] != null) {
      Navigator.of(context).pop();
      context.push('/user/$id');
    }
  }

  Widget _buildArtistRow(List artists) {
    final entries = <Map>[];
    for (final a in artists) {
      if (a is Map) {
        final label = (a['title'] ?? a['username'] ?? '').toString();
        if (label.isNotEmpty) entries.add(a);
      }
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    final style = body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.accentLight));
    final sepStyle = body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textMuted));
    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final a = entries[i];
      final label = (a['title'] ?? a['username']).toString();
      children.add(InkWell(
        onTap: () => _openArtistDetail(a),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text(label, style: style),
        ),
      ));
      if (i < entries.length - 1) {
        children.add(Text(',', style: sepStyle));
      }
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  String _songType(Map<String, dynamic> song) {
    final ft = song['file_type'] ?? 'song';
    return ft == 'audio' ? 'song' : ft;
  }

  Future<void> _fetchLovesAndLyrics(Map<String, dynamic> song) async {
    final id = song['id'].toString();
    if (_loversFetchedForId == false || (song['id'].toString() != (_lyricsFetchedForId ?? ''))) {
      _lyricsFetchedForId = id;
      final type = _songType(song);
      try {
        final data = await ApiClient.query(
          'query(\$id: ID!) { $type(id: \$id) { content loves(first: 50) { data { user_id user { id username avatar { url } } } } } }',
          {'id': id},
        );
        final obj = data[type];
        final lovesData = (obj?['loves']?['data'] ?? []) as List;
        if (!mounted) return;
        setState(() {
          _lovers = lovesData;
          _songLyrics = obj?['content'];
          final userId = context.read<AuthProvider>().user?['id'];
          if (userId != null) {
            _liked = lovesData.any((l) => l['user_id'].toString() == userId.toString());
          }
          _loversFetchedForId = true;
        });
      } catch (_) {}
    }
  }

  Future<void> _handleLove(Map<String, dynamic> song) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    final type = _songType(song);
    final newLiked = !_liked;
    setState(() {
      _liked = newLiked;
      final user = auth.user;
      if (user != null) {
        if (newLiked) {
          _lovers = [{'user_id': user['id'], 'user': user}, ..._lovers];
        } else {
          _lovers = _lovers.where((l) => l['user_id'].toString() != user['id'].toString()).toList();
        }
      }
    });
    try {
      final mutation = newLiked
          ? 'mutation(\$id: ID!) { love(lovable_id: \$id, lovable_type: "$type") { id } }'
          : 'mutation(\$id: ID!) { unlove(lovable_id: \$id, lovable_type: "$type") { id } }';
      await auth.authedMutate(mutation, {'id': song['id'].toString()});
    } catch (_) {
      setState(() => _liked = !newLiked);
    }
  }

  Future<void> _handleDownload(Map<String, dynamic> song) async {
    if (_downloading) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng đăng nhập để tải'), backgroundColor: AppColors.error));
      return;
    }
    setState(() => _downloading = true);
    try {
      final data = await auth.authedMutate(
        r'''mutation($t: String!, $i: ID!) { download(object_type: $t, object_id: $i) { url } }''',
        {'t': _songType(song), 'i': song['id'].toString()},
      );
      final url = data['download']?['url'];
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bạn đã tải quá nhiều'), backgroundColor: AppColors.error));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải: $e'), backgroundColor: AppColors.error));
    }
    if (mounted) setState(() => _downloading = false);
  }

  Future<void> _handleShare(Map<String, dynamic> song) async {
    final slug = song['slug'] ?? '';
    final id = song['id'];
    final url = slug.isNotEmpty ? '$siteUrl/bai-hat/$slug-$id' : '$siteUrl/bai-hat/$id';
    final artistNames = ((song['artists']?['data'] ?? song['artists'] ?? []) as List).map((a) => a['title'] ?? '').join(', ');
    final subject = artistNames.isNotEmpty ? '${song['title']} - $artistNames' : song['title'];
    try {
      await launchUrl(Uri.parse('mailto:?subject=${Uri.encodeComponent(subject ?? '')}&body=${Uri.encodeComponent(url)}'));
    } catch (_) {}
  }

  void _showMoreSheet(BuildContext ctx, Map<String, dynamic> song, PlayerProvider player) {
    final speedLabel = '${player.playbackRate.toStringAsFixed(player.playbackRate == player.playbackRate.roundToDouble() ? 0 : 2)}x';
    final loveCount = _lovers.length > 99 ? '99+' : (_lovers.isEmpty ? null : '${_lovers.length}');
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(_liked ? Icons.favorite : Icons.favorite_border, color: _liked ? AppColors.accent : AppColors.textSecondary),
            title: Text(_liked ? 'Đã thích' : 'Yêu thích', style: body(const TextStyle(color: AppColors.text))),
            trailing: loveCount != null ? Text(loveCount, style: body(const TextStyle(color: AppColors.textMuted, fontSize: 13))) : null,
            onTap: () { Navigator.pop(sheetCtx); _handleLove(song); },
          ),
          ListTile(
            leading: const Icon(Icons.ios_share, color: AppColors.textSecondary),
            title: Text('Chia sẻ', style: body(const TextStyle(color: AppColors.text))),
            onTap: () { Navigator.pop(sheetCtx); _handleShare(song); },
          ),
          ListTile(
            leading: Icon(Icons.speed, color: player.playbackRate != 1.0 ? AppColors.accentLight : AppColors.textSecondary),
            title: Text('Tốc độ phát', style: body(const TextStyle(color: AppColors.text))),
            trailing: Text(speedLabel, style: body(TextStyle(
              color: player.playbackRate != 1.0 ? AppColors.accentLight : AppColors.textMuted,
              fontSize: 13, fontWeight: FontWeight.w700,
            ))),
            onTap: () { Navigator.pop(sheetCtx); _showSpeedSheet(); },
          ),
          ListTile(
            leading: Icon(_downloading ? Icons.hourglass_empty : Icons.download_outlined, color: AppColors.textSecondary),
            title: Text(_downloading ? 'Đang tải...' : 'Tải xuống', style: body(const TextStyle(color: AppColors.text))),
            onTap: () { Navigator.pop(sheetCtx); _handleDownload(song); },
          ),
          ListTile(
            leading: Icon(player.muted ? Icons.volume_off : Icons.volume_up, color: AppColors.textSecondary),
            title: Text(player.muted ? 'Bật âm thanh' : 'Tắt âm thanh', style: body(const TextStyle(color: AppColors.text))),
            onTap: () { Navigator.pop(sheetCtx); player.toggleMute(); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showSpeedSheet() {
    final player = context.read<PlayerProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text('Tốc độ phát', style: display(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
              ),
              ..._speedPresets.map((s) {
                final active = (player.playbackRate - s).abs() < 0.01;
                return ListTile(
                  title: Text('${s}x', style: body(TextStyle(color: active ? AppColors.accentLight : AppColors.text, fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
                  trailing: active ? const Icon(Icons.check, color: AppColors.accentLight) : null,
                  onTap: () { player.setPlaybackRate(s); Navigator.pop(ctx); },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();

    // Fetch lovers & lyrics lazily
    if (_lyricsFetchedForId != song['id'].toString()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchLovesAndLyrics(song));
    }

    if (player.isPlaying && !_rotation.isAnimating) {
      _rotation.repeat();
    } else if (!player.isPlaying && _rotation.isAnimating) {
      _rotation.stop();
    }

    final artists = (song['artists'] is List
        ? song['artists']
        : ((song['artists'] as Map?)?['data'] ?? [])) as List;
    final thumb = song['thumbnail']?['url'];
    final isInstrumental = song['file_type'] == 'instrumental';
    final screen = MediaQuery.of(context).size;
    // Use the shortest viewport dimension so the vinyl stays a circle on
    // wide-screen desktop (where width × 0.72 would overflow the height,
    // clipping the disc into an ellipse-looking slice).
    final vinylSize = math.min(math.min(screen.width, screen.height) * 0.6, 480.0);
    final queue = player.queue;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned(
            top: -100, left: 0, right: 0,
            child: Container(
              height: 400,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, 0),
                  radius: 0.8,
                  colors: [AppColors.accent.withValues(alpha: 0.3), Colors.transparent],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header — back · context · panel toggles · more
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.keyboard_arrow_down, size: 28, color: AppColors.text), onPressed: () => Navigator.pop(context)),
                      Expanded(
                        child: Text(
                          'ĐANG PHÁT',
                          textAlign: TextAlign.center,
                          style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary)),
                        ),
                      ),
                      if (!isInstrumental)
                        IconButton(
                          tooltip: 'Lời bài hát',
                          icon: Icon(
                            Icons.lyrics_outlined,
                            color: _panel == _PanelMode.lyrics ? AppColors.accentLight : AppColors.textSecondary,
                          ),
                          onPressed: () => setState(() => _panel = _panel == _PanelMode.lyrics ? _PanelMode.vinyl : _PanelMode.lyrics),
                        ),
                      if (queue.isNotEmpty)
                        IconButton(
                          tooltip: 'Danh sách phát',
                          icon: Icon(
                            Icons.queue_music,
                            color: _panel == _PanelMode.queue ? AppColors.accentLight : AppColors.textSecondary,
                          ),
                          onPressed: () => setState(() => _panel = _panel == _PanelMode.queue ? _PanelMode.vinyl : _PanelMode.queue),
                        ),
                      IconButton(icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary), onPressed: () => _showMoreSheet(context, song, player)),
                    ],
                  ),
                ),

                // Panel area (vinyl / lyrics / queue)
                Expanded(
                  child: Center(
                    child: _buildPanel(context, player, song, thumb, vinylSize, isInstrumental, queue),
                  ),
                ),

                // Song info — tap title to open song detail
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () => _openSongDetail(song),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Column(
                            children: [
                              Text(
                                song['title'] ?? '',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
                              ),
                              if (song['subtitle'] != null && (song['subtitle'] as String).isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(song['subtitle'], style: body(const TextStyle(fontSize: 14, color: AppColors.textMuted))),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildArtistRow(artists),
                    ],
                  ),
                ),

                // Progress bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: AppColors.accent,
                          inactiveTrackColor: AppColors.border,
                          thumbColor: AppColors.accent,
                          overlayColor: AppColors.accent.withValues(alpha: 0.2),
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        ),
                        child: Slider(
                          value: player.position.inMilliseconds.toDouble().clamp(0, player.duration.inMilliseconds.toDouble()),
                          max: player.duration.inMilliseconds.toDouble() > 0 ? player.duration.inMilliseconds.toDouble() : 1,
                          onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(player.position), style: body(const TextStyle(fontSize: 12, color: AppColors.textMuted, fontFeatures: [FontFeature.tabularFigures()]))),
                            Text(_fmt(player.duration), style: body(const TextStyle(fontSize: 12, color: AppColors.textMuted, fontFeatures: [FontFeature.tabularFigures()]))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Main transport controls
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ShuffleButton(active: player.shuffle, onTap: player.toggleShuffle),
                      IconButton(icon: const Icon(Icons.skip_previous, size: 36, color: AppColors.text), onPressed: player.playPrev),
                      Container(
                        width: 68, height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                          boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 8))],
                        ),
                        child: IconButton(
                          icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow, size: 34, color: Colors.white),
                          onPressed: player.togglePlay,
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.skip_next, size: 36, color: AppColors.text), onPressed: player.playNext),
                      _RepeatButton(mode: player.repeat, onTap: player.toggleRepeat),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(BuildContext context, PlayerProvider player, Map<String, dynamic> song, String? thumb, double vinylSize, bool isInstrumental, List<Map<String, dynamic>> queue) {
    if (_panel == _PanelMode.lyrics && !isInstrumental) {
      return _buildLyricsPanel();
    }
    if (_panel == _PanelMode.queue && queue.isNotEmpty) {
      return _buildQueuePanel(player, queue);
    }
    return _buildVinyl(thumb, vinylSize);
  }

  Widget _buildVinyl(String? thumb, double vinylSize) {
    return RotationTransition(
      turns: _rotation,
      child: Container(
        width: vinylSize,
        height: vinylSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.accent, AppColors.accentLight],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 24)),
            BoxShadow(color: AppColors.accent.withValues(alpha: 0.4), blurRadius: 60, spreadRadius: -10),
          ],
          border: Border.all(color: AppColors.border, width: 4),
        ),
        child: ClipOval(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (thumb != null)
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: thumb,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceLight, child: const Icon(Icons.music_note, size: 80, color: Colors.white38)),
                  ),
                ),
              for (int i = 0; i < 8; i++)
                Container(
                  width: vinylSize - (i * 30),
                  height: vinylSize - (i * 30),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 0.5),
                  ),
                ),
              // Center logo label
              Container(
                width: 62, height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bg,
                  border: Border.all(color: AppColors.border, width: 2),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(10),
                child: SvgPicture.asset('assets/logo-on-dark.svg', width: 36, height: 36),
              ),
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: (_songLyrics == null || _songLyrics!.isEmpty)
          ? Center(child: Text('Chưa có lời bài hát', style: body(const TextStyle(color: AppColors.textMuted, fontSize: 14))))
          : SingleChildScrollView(
              child: Html(
                data: _songLyrics!,
                style: {
                  'body': Style(
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                    fontSize: FontSize(14),
                    lineHeight: const LineHeight(2.0),
                    color: AppColors.textSecondary,
                    textAlign: TextAlign.center,
                    fontFamily: body().fontFamily,
                  ),
                  'p': Style(margin: Margins.only(bottom: 8)),
                },
              ),
            ),
    );
  }

  Widget _buildQueuePanel(PlayerProvider player, List<Map<String, dynamic>> queue) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: queue.length,
          itemBuilder: (ctx, idx) {
            final s = queue[idx];
            final isActive = idx == player.currentIndex;
            final artists = s['artists'] is List ? s['artists'] : (s['artists']?['data'] ?? []);
            final artistText = (artists as List).map((a) => a['title'] ?? '').join(', ');
            final thumb = s['thumbnail']?['url'];
            return InkWell(
              onTap: () => player.playAtIndex(idx),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.accentSoft : Colors.transparent,
                  border: Border(left: BorderSide(color: isActive ? AppColors.accent : Colors.transparent, width: 3)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Center(
                        child: isActive
                            ? const Icon(Icons.graphic_eq, size: 14, color: AppColors.accentLight)
                            : Text('${idx + 1}', style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: thumb != null
                          ? CachedNetworkImage(imageUrl: thumb, width: 36, height: 36, fit: BoxFit.cover)
                          : Container(width: 36, height: 36, color: AppColors.surface, child: const Icon(Icons.music_note, size: 16, color: AppColors.textMuted)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            s['title'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isActive ? AppColors.accentLight : AppColors.text)),
                          ),
                          if (artistText.isNotEmpty)
                            Text(
                              artistText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: body(TextStyle(fontSize: 11, color: isActive ? AppColors.accentLight.withValues(alpha: 0.8) : AppColors.textSecondary)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}


class _ShuffleButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _ShuffleButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active ? 'Đảo: bật' : 'Đảo: tắt',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(Icons.shuffle, size: 22, color: active ? AppColors.accentLight : AppColors.textSecondary),
              if (active)
                Positioned(
                  bottom: -5,
                  child: Container(
                    width: 4, height: 4,
                    decoration: const BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepeatButton extends StatelessWidget {
  final PlayerRepeatMode mode;
  final VoidCallback onTap;
  const _RepeatButton({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = mode != PlayerRepeatMode.off;
    final tooltip = mode == PlayerRepeatMode.off ? 'Lặp: tắt' : mode == PlayerRepeatMode.all ? 'Lặp: tất cả' : 'Lặp: 1 bài';
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(Icons.repeat, size: 22, color: active ? AppColors.accentLight : AppColors.textSecondary),
              if (mode == PlayerRepeatMode.all)
                Positioned(
                  bottom: -5,
                  child: Container(
                    width: 4, height: 4,
                    decoration: const BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
                  ),
                ),
              if (mode == PlayerRepeatMode.one)
                Positioned(
                  top: -4, right: -5,
                  child: Text('1', style: body(const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
