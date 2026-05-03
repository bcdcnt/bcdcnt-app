import 'package:flutter/material.dart';
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
  static const _statusColors = {'pending': Color(0xFFFFA726), 'approved': Color(0xFF66BB6A), 'rejected': Color(0xFFEF5350), 'not_sure': Color(0xFFFFA726)};
  static const _statusIcons = {'pending': Icons.access_time, 'approved': Icons.check_circle_outline, 'rejected': Icons.cancel_outlined, 'not_sure': Icons.help_outline};

  Map<String, dynamic>? _upload;
  bool _loading = true;
  String? _error;
  VideoPlayerController? _videoCtl;
  ChewieController? _chewieCtl;

  @override
  void initState() { super.initState(); _fetch(); }
  @override
  void dispose() { _chewieCtl?.dispose(); _videoCtl?.dispose(); super.dispose(); }

  Future<void> _fetch() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) { setState(() { _loading = false; _error = 'Vui lòng đăng nhập'; }); return; }
    try {
      final data = await auth.authedQuery(r'''query($first: Int!, $where: WhereConditions) {
        me {
          uploads(first: $first, where: $where) {
            data {
              id title type status reason result link note
              content year record_year karaoke_type
              created_at modified_at
              file { audio_url video_url type duration }
              thumbnail { url }
              composers artists poets recomposers
              processor { id username }
              user { id username }
            }
          }
        }
      }''', {'first': 1, 'where': {'AND': [{'column': 'id', 'value': widget.id}]}});
      final list = (data['me']?['uploads']?['data'] ?? []) as List;
      if (!mounted) return;
      if (list.isEmpty) { setState(() { _loading = false; _error = 'Không tìm thấy bài gửi'; }); return; }
      final up = Map<String, dynamic>.from(list.first as Map);
      final videoUrl = up['file']?['video_url'];
      if (videoUrl != null) {
        _videoCtl = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
        await _videoCtl!.initialize();
        if (!mounted) return;
        _chewieCtl = ChewieController(
          videoPlayerController: _videoCtl!,
          autoPlay: false,
          looping: false,
          aspectRatio: _videoCtl!.value.aspectRatio,
        );
      }
      setState(() { _upload = up; _loading = false; });
    } catch (e) { if (mounted) setState(() { _loading = false; _error = 'Không thể tải bài gửi'; }); }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (_loading) return Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    if (_error != null || _upload == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
        body: Center(child: Text(_error ?? 'Không tìm thấy bài gửi', style: AppText.bodyText)),
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
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text('BÀI GỬI', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
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
                    color: const Color(0xFFEF5350).withValues(alpha: 0.08),
                    border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.message_outlined, size: 14, color: Color(0xFFEF5350)),
                      const SizedBox(width: 6),
                      Text('PHẢN HỒI BQT', style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEF5350), letterSpacing: 0.5))),
                    ]),
                    const SizedBox(height: 6),
                    Text(up['reason'], style: body(TextStyle(fontSize: 14, color: AppColors.text, height: 1.6))),
                  ]),
                ),

              // Result link
              if (status == 'approved' && (up['result'] ?? '').toString().isNotEmpty)
                InkWell(
                  onTap: () => launchUrl(Uri.parse(up['result']), mode: LaunchMode.externalApplication),
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
                      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: CachedNetworkImage(imageUrl: up['thumbnail']['url'], fit: BoxFit.cover)),
                    ),
                  if (up['file']?['video_url'] != null && _chewieCtl != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(aspectRatio: _videoCtl!.value.aspectRatio, child: Chewie(controller: _chewieCtl!)),
                      ),
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
                    Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('LINK GỐC', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)))),
                    InkWell(
                      onTap: () => launchUrl(Uri.parse(up['link']), mode: LaunchMode.externalApplication),
                      child: Text(up['link'], style: body(TextStyle(fontSize: 13, color: AppColors.accentLight, decoration: TextDecoration.underline))),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if ((up['note'] ?? '').toString().isNotEmpty) ...[
                    Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('GHI CHÚ', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)))),
                    Text(up['note'], style: body(TextStyle(fontSize: 13, color: AppColors.text, height: 1.5))),
                    const SizedBox(height: 14),
                  ],
                  if ((up['content'] ?? '').toString().isNotEmpty) ...[
                    Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('NỘI DUNG', style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)))),
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
        Text(label.toUpperCase(), style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5))),
        const SizedBox(height: 4),
        Text(value.toString(), style: body(TextStyle(fontSize: 14, color: AppColors.text, height: 1.5))),
      ]),
    );
  }
}
