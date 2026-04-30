import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/theme.dart';
import 'waveform_player.dart';

class FileHistoryDialog extends StatefulWidget {
  final List<dynamic> uploads;
  final String? currentFileId;
  final String? songTitle;
  /// Song-level uploader (the user who first posted the song record).
  /// Distinct from each upload's file owner — surfaced here as a small
  /// header card so contributor info isn't lost after we removed the
  /// caption from the song detail hero.
  final Map<String, dynamic>? uploader;
  /// ISO timestamp of when the song record was created.
  final String? songCreatedAt;

  const FileHistoryDialog({
    super.key,
    required this.uploads,
    this.currentFileId,
    this.songTitle,
    this.uploader,
    this.songCreatedAt,
  });

  @override
  State<FileHistoryDialog> createState() => _FileHistoryDialogState();
}

class _FileHistoryDialogState extends State<FileHistoryDialog> {
  String? _expandedId;

  String _formatDate(String? s) {
    if (s == null || s.isEmpty) return '';
    try {
      final d = DateTime.parse(s).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.history, color: AppColors.textSecondary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Lịch sử bản thu', style: display(const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)))),
                  Text('(${widget.uploads.length})', style: body(const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                  IconButton(icon: const Icon(Icons.close, color: AppColors.textMuted), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            if (widget.uploader != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.surfaceLight,
                      backgroundImage: widget.uploader?['avatar']?['url'] != null
                          ? CachedNetworkImageProvider(widget.uploader!['avatar']['url'])
                          : null,
                      child: widget.uploader?['avatar']?['url'] == null
                          ? Text(
                              ((widget.uploader?['username'] ?? '?').toString()).substring(0, 1).toUpperCase(),
                              style: display(const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800)),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Đăng bài', style: body(const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.6))),
                          const SizedBox(height: 2),
                          Text(
                            widget.uploader?['username'] ?? '',
                            style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                          ),
                          if (widget.songCreatedAt != null && widget.songCreatedAt!.isNotEmpty)
                            Text(_formatDate(widget.songCreatedAt), style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.border, height: 1, indent: 16, endIndent: 16),
            ],
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: widget.uploads.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final u = widget.uploads[i];
                  final file = u['file'];
                  if (file == null) return const SizedBox.shrink();
                  final isCurrent = file['id'].toString() == (widget.currentFileId ?? '');
                  final isExpanded = _expandedId == u['id'].toString();
                  final user = file['user'];
                  final audioUrl = file['audio_url'] as String?;
                  final seedSource = int.tryParse(file['id']?.toString() ?? '0') ?? i;

                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: isCurrent ? AppColors.accent : AppColors.border),
                      borderRadius: BorderRadius.circular(14),
                      color: isCurrent ? AppColors.accentSoft.withValues(alpha: 0.4) : AppColors.surface,
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() => _expandedId = isExpanded ? null : u['id'].toString()),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.surfaceLight,
                                  backgroundImage: user?['avatar']?['url'] != null ? CachedNetworkImageProvider(user['avatar']['url']) : null,
                                  child: user?['avatar']?['url'] == null
                                      ? Text((user?['username'] ?? '?').toString().substring(0, 1).toUpperCase(), style: display(const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)))
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(child: Text(user?['username'] ?? 'Ẩn danh', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)), overflow: TextOverflow.ellipsis)),
                                          if (isCurrent) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(4)),
                                              child: Text('ĐANG DÙNG', style: body(const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.accentLight))),
                                            ),
                                          ],
                                          if (file['is_hq'] == true || file['is_hq'] == 1) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(3)),
                                              child: Text('HQ', style: body(const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white))),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(_formatDate(file['created_at']?.toString()), style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                                    ],
                                  ),
                                ),
                                AnimatedRotation(
                                  turns: isExpanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: const Icon(Icons.keyboard_arrow_down, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isExpanded && audioUrl != null) ...[
                          const Divider(color: AppColors.border, height: 1),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                            child: WaveformPlayer(
                              audioUrl: audioUrl,
                              seed: seedSource,
                              showTimestamp: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
