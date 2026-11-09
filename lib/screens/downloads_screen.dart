import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/offline_store.dart';
import '../widgets/list_search.dart';
import '../widgets/desktop_page.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';

/// "Đã tải về": songs stored in the app, playable without network.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  /// Words in the search box: these songs are on the phone, so the list is
  /// filtered right here (works offline).
  String _q = '';

  String _size(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1).replaceAll('.', ',')} GB';
    return '${(bytes / (1 << 20)).round()} MB';
  }

  Future<void> _clearAll(OfflineStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá tất cả bài đã tải?'),
        content: Text('Giải phóng ${_size(store.totalBytes)} trên máy. Bạn vẫn nghe được các bài này khi có mạng.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xoá', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) store.clear();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<OfflineStore>();
    final items = store.items;
    final shown = _q.isEmpty ? items : items.where((s) => titleMatches('${s['title'] ?? ''}', _q)).toList();
    final desk = isDesk(context);
    void playAll() => playOrOpen(context, shown.first, shown, 'Đã tải về');
    void shuffleAll() {
      final q = List<Map<String, dynamic>>.from(shown)..shuffle();
      playOrOpen(context, q.first, q, 'Đã tải về');
    }
    final deleteBtn = IconButton(
      tooltip: 'Xoá tất cả',
      icon: const Icon(Icons.delete_outline_rounded),
      onPressed: () => _clearAll(store),
    );
    if (desk) return _desk(context, store, items, shown, playAll, shuffleAll, deleteBtn);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: SubPageBar(
        title: 'Đã tải về',
        actions: [
          if (items.isNotEmpty) deleteBtn,
        ],
      ),
      body: Stack(children: [
        items.isEmpty
            ? ListView(children: const [
                EmptyBlock(
                  icon: Icons.download_for_offline_outlined,
                  title: 'Chưa có bài nào được tải',
                  message: 'Bấm ⋮ ở một bài hát rồi chọn "Tải về để nghe offline" — nghe được cả khi không có mạng, không tốn dung lượng 4G.',
                ),
              ])
            : ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text('${items.length} bài · ${_size(store.totalBytes)} trên máy', style: AppText.meta),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(children: [
                      Expanded(child: PillButton(label: 'Phát tất cả', icon: Icons.play_arrow_rounded, onTap: shown.isEmpty ? null : playAll)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PillButton(
                          label: 'Ngẫu nhiên',
                          icon: Icons.shuffle_rounded,
                          primary: false,
                          onTap: shown.isEmpty ? null : shuffleAll,
                        ),
                      ),
                    ]),
                  ),
                  ListSearchField(
                    hint: 'Tìm trong ${items.length} bài đã tải về',
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    onChanged: (q) => setState(() => _q = q),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ListSearchSummary(query: _q, total: shown.length),
                  ),
                  const SizedBox(height: 8),
                  if (shown.isEmpty) ListSearchEmpty(query: _q),
                  for (final s in shown)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, right: 6),
                      child: SongRow(song: s, queue: shown, sourceLabel: 'Đã tải về', metricKey: 'none', highlight: _q),
                    ),
                ],
              ),
        const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  /// Desktop: no phone bar (the shell has Back); title, size and the
  /// actions on one row, songs as a table.
  Widget _desk(BuildContext context, OfflineStore store, List<Map<String, dynamic>> items, List<Map<String, dynamic>> shown, VoidCallback playAll, VoidCallback shuffleAll, Widget deleteBtn) => Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(children: [
          DeskFrame(
            child: ListView(
              padding: deskPad.copyWith(bottom: 120),
              children: [
                DeskHead(
                  title: 'Đã tải về',
                  subtitle: items.isEmpty ? '' : '${items.length} bài · ${_size(store.totalBytes)} trên máy',
                  actions: [
                    if (shown.isNotEmpty) ...deskPlayButtons(play: playAll, shuffle: shuffleAll),
                    if (items.isNotEmpty) deleteBtn,
                  ],
                ),
                if (items.isEmpty)
                  const EmptyBlock(
                    icon: Icons.download_for_offline_outlined,
                    title: 'Chưa có bài nào được tải',
                    message: 'Bấm ⋮ ở một bài hát rồi chọn "Tải về để nghe offline" — nghe được cả khi không có mạng.',
                  )
                else ...[
                  ListSearchField(hint: 'Tìm trong ${items.length} bài đã tải về', padding: EdgeInsets.zero, onChanged: (q) => setState(() => _q = q)),
                  ListSearchSummary(query: _q, total: shown.length),
                  const SizedBox(height: 14),
                  if (shown.isEmpty) ListSearchEmpty(query: _q) else const SongTableHead(), // 'none' rows still show listens in the table
                  for (final s in shown) SongRow(song: s, queue: shown, sourceLabel: 'Đã tải về', metricKey: 'none', highlight: _q),
                ],
              ],
            ),
          ),
          const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
        ]),
      );
}
