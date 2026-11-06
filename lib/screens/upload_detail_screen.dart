import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, EmptyBlock, OfflineBlock;
import '../services/friendly_error.dart';
import 'package:provider/provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import '../widgets/waveform_player.dart';

class UploadDetailScreen extends StatefulWidget {
  final String id;
  const UploadDetailScreen({super.key, required this.id});

  @override
  State<UploadDetailScreen> createState() => _UploadDetailScreenState();
}

class _UploadDetailScreenState extends State<UploadDetailScreen> {
  static const _typeLabels = {
    'song': 'Tân nhạc',
    'folk': 'Dân ca',
    'instrumental': 'Khí nhạc',
    'karaoke': 'Karaoke',
    'poem': 'Tiếng thơ',
    'replace': 'Bổ sung bản ghi',
    'document_audio': 'Tư liệu âm thanh',
    'document_image': 'Tư liệu hình ảnh',
    'document_video': 'Tư liệu video',
    'document_news': 'Bài viết',
    'sheet': 'Bản nhạc',
  };
  static const _statusLabels = {'pending': 'Chờ duyệt', 'approved': 'Đã duyệt', 'rejected': 'Không duyệt', 'not_sure': 'Chưa rõ'};
  // Text-safe tones (≥4.5:1) — the old Material 400 shades were 1.6–2:1 on light.
  static Map<String, Color> get _statusColors => {'pending': AppColors.warningText, 'approved': AppColors.successText, 'rejected': AppColors.errorText, 'not_sure': AppColors.warningText};
  static const _statusIcons = {'pending': Icons.access_time, 'approved': Icons.check_circle_outline, 'rejected': Icons.cancel_outlined, 'not_sure': Icons.help_outline};

  Map<String, dynamic>? _upload;
  bool _loading = true;
  String? _error;
  bool _needLogin = false, _failed = false;
  /// Video couldn't be opened in-app → offer "Mở video" (external) instead.
  bool _videoFailed = false;
  VideoPlayerController? _videoCtl;
  ChewieController? _chewieCtl;

  @override
  void initState() { super.initState(); _fetch(); }
  @override
  void dispose() { _chewieCtl?.dispose(); _videoCtl?.dispose(); super.dispose(); }

  static const _fields = '''
    id title type status reason result link note
    content year record_year karaoke_type
    created_at modified_at
    file { audio_url video_url type duration }
    thumbnail { url }
    composers artists poets recomposers
    processor { id username }
    user { id username }
  ''';

  Future<void> _fetch() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) { setState(() { _loading = false; _needLogin = true; }); return; }
    setState(() { _loading = true; _failed = false; _error = null; _needLogin = false; });
    try {
      final data = await auth.authedQuery('''query(\$first: Int!, \$where: WhereConditions) {
        me { uploads(first: \$first, where: \$where) { data { $_fields } } }
      }''', {'first': 1, 'where': {'AND': [{'column': 'id', 'value': widget.id}]}});
      final list = (data['me']?['uploads']?['data'] ?? []) as List;
      Map<String, dynamic>? up = list.isEmpty ? null : Map<String, dynamic>.from(list.first as Map);
      // Not ours: only moderators may read someone else's upload
      // (UploadPolicy::viewUpload = owner or manage_upload).
      if (up == null && auth.hasPermission('manage_upload')) {
        final d2 = await auth.authedQuery('''query(\$id: ID!) { upload(id: \$id) { $_fields } }''', {'id': widget.id});
        if (d2['upload'] is Map) up = Map<String, dynamic>.from(d2['upload'] as Map);
      }
      if (!mounted) return;
      if (up == null) {
        setState(() { _loading = false; _error = 'Bài gửi này chỉ người gửi và BQT xem được, hoặc đã bị xoá.'; });
        return;
      }
      // Show the page now; the video loads on its own.
      setState(() { _upload = up; _loading = false; });
      final videoUrl = up['file']?['video_url'];
      if (videoUrl is String && videoUrl.isNotEmpty) _initVideo(videoUrl);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _failed = true; _error = friendlyError(e); });
    }
  }

  Future<void> _initVideo(String url) async {
    final ctl = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await ctl.initialize().timeout(const Duration(seconds: 20));
    } catch (_) {
      ctl.dispose();
      if (mounted) setState(() => _videoFailed = true);
      return;
    }
    if (!mounted) { ctl.dispose(); return; }
    setState(() {
      _videoCtl = ctl;
      _chewieCtl = ChewieController(
        videoPlayerController: ctl,
        autoPlay: false,
        looping: false,
        aspectRatio: ctl.value.aspectRatio,
      );
    });
  }

  void _openResult(String result) {
    final r = uploadResultRoute(result);
    if (r != null) {
      context.push(r.path, extra: r.extra);
    } else {
      launchUrl(Uri.parse(result), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (_loading) return Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    if (_error != null || _upload == null || _needLogin) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context))),
        body: Center(child: SingleChildScrollView(child: _needLogin
            ? EmptyBlock(icon: Icons.lock_outline, title: 'Đăng nhập để xem bài gửi', action: 'Đăng nhập', onAction: () async { await askLogin(context); if (mounted) _fetch(); })
            : _failed
                ? OfflineBlock(onRetry: _fetch)
                : EmptyBlock(icon: Icons.description_outlined, title: 'Không xem được bài gửi', message: _error ?? 'Không tìm thấy bài gửi'))),
      );
    }
    final up = _upload!;
    final status = (up['status'] ?? 'pending').toString();
    final statusColor = _statusColors[status] ?? AppColors.textMuted;
    final statusIcon = _statusIcons[status] ?? Icons.access_time;
    final statusLabel = _statusLabels[status] ?? status;
    final typeLabel = _typeLabels[up['type']] ?? (up['type'] ?? '').toString();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg,
            title: Text('Bài gửi'),
            centerTitle: true,
            leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList(delegate: SliverChildListDelegate([
              Text(up['title'] ?? '(Không tiêu đề)', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.3))),
              const SizedBox(height: 14),

              // Status card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(statusLabel, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: statusColor))),
                    const SizedBox(height: 2),
                    Text(
                      '$typeLabel · ${timeago(up['created_at'])}${up['processor']?['username'] != null ? ' · BQT: ${up['processor']['username']}' : ''}',
                      style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                  ])),
                ]),
              ),
              const SizedBox(height: 14),

              // Reason
              if ((up['reason'] ?? '').toString().isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.errorText.withValues(alpha: 0.08),
                    border: Border.all(color: AppColors.errorText.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.message_outlined, size: 14, color: AppColors.errorText),
                      const SizedBox(width: 6),
                      Text('PHẢN HỒI BQT', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFEF5350), letterSpacing: 0.5))),
                    ]),
                    const SizedBox(height: 6),
                    Text(up['reason'], style: body(TextStyle(fontSize: 14, color: AppColors.text, height: 1.6))),
                  ]),
                ),

              // Result link
              if (status == 'approved' && (up['result'] ?? '').toString().isNotEmpty)
                InkWell(
                  onTap: () => _openResult(up['result'].toString()),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF66BB6A).withValues(alpha: 0.08),
                      border: Border.all(color: const Color(0xFF66BB6A).withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.open_in_new, color: Color(0xFF66BB6A), size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Xem kết quả', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF66BB6A)))),
                        Text(up['result'], maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                      ])),
                    ]),
                  ),
                ),

              // Details card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (up['thumbnail']?['url'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: CachedNetworkImage(imageUrl: cdnImg((up['thumbnail']['url']).toString(), 640), fit: BoxFit.cover)),
                    ),
                  if (up['file']?['video_url'] != null && _chewieCtl != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(aspectRatio: _videoCtl!.value.aspectRatio, child: Chewie(controller: _chewieCtl!)),
                      ),
                    )
                  else if (up['file']?['video_url'] != null && _videoFailed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: OutlinedButton.icon(
                        onPressed: () => launchUrl(Uri.parse(up['file']['video_url']), mode: LaunchMode.externalApplication),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text('Mở video', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                      ),
                    )
                  else if (up['file']?['video_url'] != null && _chewieCtl == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: AspectRatio(aspectRatio: 16 / 9, child: Container(
                        decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10)),
                        alignment: Alignment.center,
                        child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
                      )),
                    )
                  else if (up['file']?['audio_url'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: WaveformPlayer(audioUrl: up['file']['audio_url'], seed: int.tryParse('${up['id']}') ?? 0),
                    ),
                  _info('Nhạc sĩ', up['composers']),
                  _info('Nghệ sĩ', up['artists']),
                  _info('Nhà thơ', up['poets']),
                  _info('Soạn giả', up['recomposers']),
                  _info('Năm sáng tác', up['year']),
                  _info('Năm thu', up['record_year']),
                  if ((up['link'] ?? '').toString().isNotEmpty) ...[
                    Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('LINK GỐC', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)))),
                    InkWell(
                      onTap: () => launchUrl(Uri.parse(up['link']), mode: LaunchMode.externalApplication),
                      child: Text(up['link'], style: body(TextStyle(fontSize: 13, color: AppColors.accentLight, decoration: TextDecoration.underline))),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if ((up['note'] ?? '').toString().isNotEmpty) ...[
                    Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('GHI CHÚ', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)))),
                    Text(up['note'], style: body(TextStyle(fontSize: 13, color: AppColors.text, height: 1.5))),
                    const SizedBox(height: 14),
                  ],
                  if ((up['content'] ?? '').toString().isNotEmpty) ...[
                    Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('NỘI DUNG', style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)))),
                    Html(
                      data: up['content'],
                      style: {
                        'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero, fontSize: FontSize(13), lineHeight: const LineHeight(1.6), color: AppColors.text, fontFamily: body().fontFamily),
                        'p': Style(margin: Margins.only(bottom: 6)),
                        'a': Style(color: AppColors.accentLight, textDecoration: TextDecoration.none),
                      },
                      onLinkTap: (url, _, __) {
                        if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      },
                    ),
                  ],
                ]),
              ),

              SizedBox(height: player.currentSong != null ? 90 : 20),
            ])),
          ),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  Widget _info(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5))),
        const SizedBox(height: 4),
        Text(value.toString(), style: body(TextStyle(fontSize: 14, color: AppColors.text, height: 1.5))),
      ]),
    );
  }
}
