import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';

class PlaylistDialog extends StatefulWidget {
  final String songId;
  final String type;
  const PlaylistDialog({super.key, required this.songId, this.type = 'song'});

  @override
  State<PlaylistDialog> createState() => _PlaylistDialogState();
}

class _PlaylistDialogState extends State<PlaylistDialog> {
  List<dynamic> _playlists = [];
  bool _loading = true;
  final Set<String> _adding = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) { setState(() => _loading = false); return; }
    try {
      final data = await ApiClient.authedQuery(
        r'''query { myPlaylists(first: 50) { data { id title thumbnail { url } songs(first: 0) { paginatorInfo { total } } } } }''',
        null,
        auth.token!,
      );
      setState(() {
        _playlists = data['myPlaylists']?['data'] ?? [];
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _addTo(String playlistId) async {
    setState(() => _adding.add(playlistId));
    try {
      await context.read<AuthProvider>().authedMutate(
        r'''mutation($playlist_id: ID!, $object_id: ID!, $object_type: String!) { addToPlaylist(playlist_id: $playlist_id, object_id: $object_id, object_type: $object_type) { id } }''',
        {'playlist_id': playlistId, 'object_id': widget.songId, 'object_type': widget.type},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã thêm vào playlist'), backgroundColor: AppColors.success, duration: const Duration(seconds: 2)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error));
    }
    if (mounted) setState(() => _adding.remove(playlistId));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
              child: Row(
                children: [
                  Expanded(child: Text('Thêm vào playlist', style: display(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text)))),
                  IconButton(icon: Icon(Icons.close, color: AppColors.textMuted), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            if (!auth.isAuthenticated)
              Padding(padding: const EdgeInsets.all(24), child: Text('Đăng nhập để sử dụng tính năng này', style: AppText.bodyText))
            else if (_loading)
              Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.accent))
            else if (_playlists.isEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Text('Bạn chưa có playlist nào', style: AppText.bodyText))
            else Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _playlists.length,
                itemBuilder: (ctx, i) {
                  final p = _playlists[i];
                  final id = p['id'].toString();
                  final thumb = p['thumbnail']?['url'];
                  final count = p['songs']?['paginatorInfo']?['total'] ?? 0;
                  final isAdding = _adding.contains(id);
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: thumb != null
                          ? CachedNetworkImage(imageUrl: thumb, width: 44, height: 44, fit: BoxFit.cover)
                          : Container(width: 44, height: 44, color: AppColors.surfaceLight, child: Icon(Icons.playlist_play, color: AppColors.textMuted)),
                    ),
                    title: Text(p['title'] ?? '', style: AppText.title),
                    subtitle: Text('$count bài', style: AppText.caption),
                    trailing: isAdding
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                        : Icon(Icons.add, color: AppColors.textMuted),
                    onTap: isAdding ? null : () => _addTo(id),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
