import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/offline_store.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';

/// "Đã tải về": songs stored in the app, playable without network.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  String _size(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1).replaceAll('.', ',')} GB';
    return '${(bytes / (1 << 20)).round()} MB';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<OfflineStore>();
    final items = store.items;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: SubPageBar(
        title: 'Đã tải về',
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Xoá tất cả',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
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
              },
            ),
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
                      Expanded(child: PillButton(label: 'Phát tất cả', icon: Icons.play_arrow_rounded, onTap: () => playOrOpen(context, items.first, items, 'Đã tải về'))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PillButton(
                          label: 'Ngẫu nhiên',
                          icon: Icons.shuffle_rounded,
                          primary: false,
                          onTap: () {
                            final q = List<Map<String, dynamic>>.from(items)..shuffle();
                            playOrOpen(context, q.first, q, 'Đã tải về');
                          },
                        ),
                      ),
                    ]),
                  ),
                  for (final s in items)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 6),
                      child: SongRow(song: s, queue: items, sourceLabel: 'Đã tải về', metricKey: 'none'),
                    ),
                ],
              ),
        const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
