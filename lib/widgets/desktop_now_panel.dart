import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import 'comment_section.dart';
import 'desktop_player_bar.dart' show desktopPanelTab;
import 'desktop_queue_panel.dart';
import 'lyrics_text.dart';
import 'song_row.dart';

/// Desktop side panel "beside the song playing": Lời · Bình luận · Hàng đợi.
/// Follows the song playing unless pinned (the pin keeps the song being read
/// while the music moves on).
class DesktopNowPanel extends StatefulWidget {
  final VoidCallback onClose;
  const DesktopNowPanel({super.key, required this.onClose});

  @override
  State<DesktopNowPanel> createState() => _DesktopNowPanelState();
}

class _DesktopNowPanelState extends State<DesktopNowPanel> {
  Map<String, dynamic>? _pinned;
  int? _commentTotal;
  String? _commentFor; // which song _commentTotal counts

  @override
  Widget build(BuildContext context) {
    final playing = context.watch<PlayerProvider>().currentSong;
    final song = _pinned ?? playing;
    return Container(
      color: AppColors.bg,
      child: ValueListenableBuilder<String>(
        valueListenable: desktopPanelTab,
        builder: (context, tab, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                if (song != null) SongCover(song: song, size: 40, radius: 8),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_pinned != null ? 'ĐÃ GHIM' : 'ĐANG PHÁT', style: body(TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
                    Text(song == null ? 'Chưa phát bài nào' : '${song['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text))),
                  ]),
                ),
                if (song != null)
                  IconButton(
                    tooltip: _pinned != null ? 'Bỏ ghim: theo bài đang phát' : 'Ghim bài này (giữ khi chuyển bài)',
                    onPressed: () => setState(() => _pinned = _pinned != null ? null : Map<String, dynamic>.from(song)),
                    icon: Icon(_pinned != null ? Icons.push_pin_rounded : Icons.push_pin_outlined, size: 20, color: _pinned != null ? AppColors.accentFg : AppColors.textMuted),
                  ),
                IconButton(tooltip: 'Đóng (Esc)', onPressed: widget.onClose, icon: Icon(Icons.close_rounded, size: 22, color: AppColors.textMuted)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                for (final (k, label) in const [('lyric', 'Lời'), ('comment', 'Bình luận'), ('queue', 'Hàng đợi')])
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Material(
                      color: tab == k ? AppColors.text : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => desktopPanelTab.value = k,
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          child: Text(k == 'comment' && (_commentTotal ?? 0) > 0 && song != null && _commentFor == '${songKind(song)}-${song['id']}' ? '$label $_commentTotal' : label, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: tab == k ? AppColors.bg : AppColors.textSecondary))),
                        ),
                      ),
                    ),
                  ),
              ]),
            ]),
          ),
          Divider(height: 1, color: AppColors.border),
          Expanded(
            child: switch (tab) {
              'queue' => const DesktopQueuePanel(embedded: true),
              _ when song == null => _empty(),
              'lyric' => _Lyrics(key: ValueKey('l-${songKind(song)}-${song['id']}'), song: song),
              _ => SingleChildScrollView(
                  key: ValueKey('c-${songKind(song)}-${song['id']}'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: CommentSection(
                    type: songKind(song), id: '${song['id']}', compact: true,
                    onTotal: (n) { if (mounted) setState(() { _commentTotal = n; _commentFor = '${songKind(song)}-${song['id']}'; }); },
                  ),
                ),
            },
          ),
        ]),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text('Phát một bài để xem lời và bình luận của bài đó ở đây.', textAlign: TextAlign.center, style: AppText.bodyText),
        ),
      );
}

class _Lyrics extends StatefulWidget {
  final Map<String, dynamic> song;
  const _Lyrics({super.key, required this.song});
  @override
  State<_Lyrics> createState() => _LyricsState();
}

class _LyricsState extends State<_Lyrics> {
  String? _html;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final type = songKind(widget.song);
    final have = widget.song['content']?.toString();
    if (have != null && have.trim().isNotEmpty) {
      setState(() { _html = have; _loading = false; });
      return;
    }
    try {
      final d = await ApiClient.query('query(\$id: ID!) { $type(id: \$id) { content } }', {'id': '${widget.song['id']}'});
      if (mounted) setState(() { _html = d[type]?['content']?.toString(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    final html = (_html ?? '').trim();
    if (html.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(28), child: Text('Bài này chưa có lời.', style: AppText.bodyText)));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      child: LyricsText(html: html, fontSize: 18, color: AppColors.text, labelColor: AppColors.accentFg),
    );
  }
}
