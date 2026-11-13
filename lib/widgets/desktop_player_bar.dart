import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import '../services/player.dart';
import 'mini_player.dart' show openFullPlayer;
import 'song_row.dart';

/// Which side-panel tab is showing ('lyric' | 'comment' | 'queue'). The
/// player bar's labelled buttons and the panel share it.
final ValueNotifier<String> desktopPanelTab = ValueNotifier<String>('comment');

/// Desktop player bar (canvas "Desktop — làm mới"): 96px, full width, the
/// outermost layer so changing page never stops the music. Left: the song;
/// middle: controls + progress; right: labelled buttons for the side panel,
/// volume, full screen.
class DesktopPlayerBar extends StatelessWidget {
  /// Opens the side panel on a tab (or closes it when that tab is showing).
  final void Function(String tab) onPanel;
  final bool panelOpen;
  const DesktopPlayerBar({super.key, required this.onPanel, required this.panelOpen});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();
    final w = MediaQuery.sizeOf(context).width;
    final narrow = w < 1280;
    // The volume slider only where there is room for it next to the buttons.
    final roomy = w >= 1600;
    final side = narrow ? 250.0 : (roomy ? 420.0 : 330.0);
    final byline = songByline(song, withComposer: true);
    return Container(
      height: 96,
      decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border))),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        SizedBox(
          width: side,
          child: Row(children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => openFullPlayer(player),
              child: SongCover(song: song, size: 64, radius: 10),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: InkWell(
                onTap: () => context.push('/song/${song['id']}', extra: song),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${song['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
                  if (byline.isNotEmpty)
                    Text(byline, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                  _NowExtras(song: song, part: _NowPart.meta),
                ]),
              ),
            ),
            _NowExtras(song: song, part: _NowPart.love),
          ]),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _Icon(
                tooltip: player.shuffle ? 'Tắt trộn bài (S)' : 'Trộn bài (S)',
                icon: Icons.shuffle_rounded,
                size: 22,
                active: player.shuffle,
                onTap: player.toggleShuffle,
              ),
              const SizedBox(width: 10),
              _Icon(tooltip: 'Bài trước', icon: Icons.skip_previous_rounded, size: 32, onTap: player.playPrev, strong: true),
              const SizedBox(width: 10),
              Tooltip(
                message: player.isPlaying ? 'Tạm dừng (Space)' : 'Phát (Space)',
                child: Material(
                  color: AppColors.wine,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: player.togglePlay,
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: player.isLoading
                          ? const Padding(padding: EdgeInsets.all(15), child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
                          : Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _Icon(tooltip: 'Bài sau', icon: Icons.skip_next_rounded, size: 32, onTap: player.hasNext ? player.playNext : null, strong: true),
              const SizedBox(width: 10),
              _Icon(
                tooltip: switch (player.repeat) {
                  PlayerRepeatMode.off => 'Lặp lại danh sách (R)',
                  PlayerRepeatMode.all => 'Lặp lại một bài (R)',
                  PlayerRepeatMode.one => 'Tắt lặp lại (R)',
                },
                icon: player.repeat == PlayerRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                size: 22,
                active: player.repeat != PlayerRepeatMode.off,
                onTap: player.toggleRepeat,
              ),
            ]),
            const SizedBox(height: 4),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: _Progress(player: player)),
          ]),
        ),
        const SizedBox(width: 24),
        // Takes what it needs; the controls in the middle give way.
        ValueListenableBuilder<String>(
            valueListenable: desktopPanelTab,
            builder: (_, tab, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              _Labelled(icon: Icons.lyrics_outlined, label: 'Lời', active: panelOpen && tab == 'lyric', onTap: () => onPanel('lyric')),
              _Labelled(icon: Icons.chat_bubble_outline_rounded, label: 'Bình luận', active: panelOpen && tab == 'comment', onTap: () => onPanel('comment')),
              _Labelled(icon: Icons.queue_music_rounded, label: 'Hàng đợi', active: panelOpen && tab == 'queue', onTap: () => onPanel('queue')),
              if (!narrow) ...[
                const SizedBox(width: 2),
                _Icon(
                  tooltip: player.muted ? 'Bật tiếng (M)' : 'Tắt tiếng (M)',
                  icon: player.muted || player.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  size: 22,
                  onTap: player.toggleMute,
                ),
                if (roomy) SizedBox(
                  width: 92,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: AppColors.textSecondary,
                      inactiveTrackColor: AppColors.surfaceLight,
                      thumbColor: AppColors.textSecondary,
                    ),
                    child: Slider(value: player.muted ? 0 : player.volume.clamp(0.0, 1.0), onChanged: player.setVolume),
                  ),
                ),
              ],
              _Labelled(icon: Icons.open_in_full_rounded, label: 'Toàn màn', onTap: () => openFullPlayer(player)),
            ]),
        ),
      ]),
    );
  }
}

class _Progress extends StatefulWidget {
  final PlayerProvider player;
  const _Progress({required this.player});
  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  /// While dragging: the position under the finger, so the thumb doesn't
  /// jump back to the playing position until the seek lands.
  double? _drag;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    final total = p.duration.inMilliseconds / 1000;
    final now = _drag ?? p.position.inMilliseconds / 1000;
    final style = body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted, fontFeatures: const [FontFeature.tabularFigures()]));
    return Row(children: [
      SizedBox(width: 44, child: Text(formatTime(now), textAlign: TextAlign.right, style: style)),
      Expanded(
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              // 6px track, 10 under the mouse: easy to hit for older hands.
              trackHeight: _hover ? 10 : 6,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: _hover ? 8 : 0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: AppColors.wine,
              inactiveTrackColor: AppColors.surfaceLight,
              thumbColor: AppColors.wine,
            ),
            child: Slider(
              value: total > 0 ? now.clamp(0, total).toDouble() : 0,
              max: total > 0 ? total : 1,
              onChanged: total > 0 ? (v) => setState(() => _drag = v) : null,
              onChangeEnd: (v) {
                p.seek(Duration(milliseconds: (v * 1000).round()));
                setState(() => _drag = null);
              },
            ),
          ),
        ),
      ),
      SizedBox(width: 44, child: Text(formatTime(total), style: style)),
    ]);
  }
}

class _Icon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final double size;
  final VoidCallback? onTap;
  final bool active;
  final bool strong;
  const _Icon({required this.tooltip, required this.icon, required this.size, this.onTap, this.active = false, this.strong = false});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(icon, size: size, color: active ? AppColors.accentFg : (strong ? AppColors.text : AppColors.textSecondary)),
      );
}

/// Icon over a small label: the player's panel buttons are never icon-only.
class _Labelled extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Labelled({required this.icon, required this.label, this.active = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = active ? AppColors.accentFg : AppColors.textSecondary;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 22, color: c),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, style: body(TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c))),
        ]),
      ),
    );
  }
}

enum _NowPart { meta, love }

/// Bits of the playing song the queue entry doesn't carry: the recording
/// line ("THU 1985 · ĐÀI TNVN") and whether the member loves it. Both parts
/// share one fetch per song through [_NowInfo].
class _NowExtras extends StatefulWidget {
  final Map<String, dynamic> song;
  final _NowPart part;
  const _NowExtras({required this.song, required this.part});

  @override
  State<_NowExtras> createState() => _NowExtrasState();
}

class _NowInfo {
  final String key;
  String meta = '';
  bool loved = false;
  _NowInfo(this.key);
}

final ValueNotifier<_NowInfo?> _nowInfo = ValueNotifier<_NowInfo?>(null);
String? _nowLoading;

Future<void> _loadNowInfo(BuildContext context, Map<String, dynamic> song) async {
  final type = songKind(song);
  final key = '$type:${song['id']}';
  if (_nowLoading == key || _nowInfo.value?.key == key) return;
  _nowLoading = key;
  final auth = context.read<AuthProvider>();
  final uid = auth.user?['id']?.toString();
  final mine = uid == null ? '' : 'loves(first: 1, where: {column: "user_id", value: "$uid"}) { paginatorInfo { total } }';
  try {
    final d = await ApiClient.query('query(\$id: ID!) { $type(id: \$id) { record_year file { source } $mine } }', {'id': '${song['id']}'});
    final o = d[type];
    if (_nowLoading != key) return;
    final year = '${o?['record_year'] ?? ''}'.trim();
    final source = '${o?['file']?['source'] ?? ''}'.trim();
    final info = _NowInfo(key)
      ..meta = [if (year.isNotEmpty && year != '0') 'Thu $year', if (source.isNotEmpty) source].join(' · ').toUpperCase()
      ..loved = ((o?['loves']?['paginatorInfo']?['total'] as num?) ?? 0) > 0;
    _nowInfo.value = info;
  } catch (_) {
    if (_nowLoading == key) _nowInfo.value = _NowInfo(key);
  }
}

class _NowExtrasState extends State<_NowExtras> {
  @override
  Widget build(BuildContext context) {
    final key = '${songKind(widget.song)}:${widget.song['id']}';
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _loadNowInfo(context, widget.song); });
    return ValueListenableBuilder<_NowInfo?>(
      valueListenable: _nowInfo,
      builder: (context, info, _) {
        final mine = info?.key == key ? info : null;
        if (widget.part == _NowPart.meta) {
          if (mine == null || mine.meta.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(mine.meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: AppColors.textMuted))),
          );
        }
        final loved = mine?.loved ?? false;
        return IconButton(
          tooltip: loved ? 'Bỏ yêu thích' : 'Yêu thích',
          onPressed: mine == null ? null : () => _toggle(mine),
          icon: Icon(loved ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 24, color: loved ? AppColors.love : AppColors.textMuted),
        );
      },
    );
  }

  Future<void> _toggle(_NowInfo info) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      askLogin(context);
      return;
    }
    final type = songKind(widget.song);
    final now = !info.loved;
    _nowInfo.value = _NowInfo(info.key)..meta = info.meta..loved = now;
    try {
      await auth.authedMutate('mutation(\$id: ID!) { ${now ? 'love' : 'unlove'}(lovable_id: \$id, lovable_type: "$type") { id } }', {'id': '${widget.song['id']}'});
      lovesChanged.value++;
    } catch (e) {
      if (_nowInfo.value?.key == info.key) _nowInfo.value = _NowInfo(info.key)..meta = info.meta..loved = !now;
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(friendlyError(e, fallback: now ? 'Chưa thích được bài này, vui lòng thử lại.' : 'Chưa bỏ thích được, vui lòng thử lại.')),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }
}
