import '../services/imgcdn.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart';
import 'ui.dart';

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
  bool _failed = false;
  final Set<String> _adding = {};
  final _titleCtrl = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) { setState(() => _loading = false); return; }
    setState(() { _loading = true; _failed = false; });
    try {
      final data = await ApiClient.authedQuery(
        r'''query { myPlaylists(first: 50) { data { id title thumbnail { url } songs(first: 0) { paginatorInfo { total } } } } }''',
        null,
        auth.token!,
      );
      if (!mounted) return;
      setState(() {
        _playlists = data['myPlaylists']?['data'] ?? [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  /// No playlist yet: make one right here and put the song in it, instead of
  /// sending the listener away to another screen.
  Future<void> _createAndAdd() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _creating) return;
    setState(() => _creating = true);
    try {
      final data = await context.read<AuthProvider>().authedMutate(
        r'''mutation($title: String!) { createPlaylist(input: {title: $title}) { id } }''',
        {'title': title},
      );
      final id = data['createPlaylist']?['id']?.toString();
      if (!mounted) return;
      setState(() => _creating = false);
      if (id != null) await _addTo(id);
      // Adding failed but the playlist exists now: show it so they can retry.
      if (mounted) _fetch();
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error));
    }
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error));
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
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Đăng nhập để lưu bài vào playlist của bạn.', style: body(TextStyle(fontSize: 16, color: AppColors.text))),
                  const SizedBox(height: 14),
                  PillButton(
                    label: 'Đăng nhập',
                    icon: Icons.login_rounded,
                    onTap: () async {
                      await askLogin(context);
                      if (context.mounted && context.read<AuthProvider>().isAuthenticated) _fetch();
                    },
                  ),
                ]),
              )
            else if (_loading)
              Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.accent))
            else if (_failed)
              OfflineBlock(onRetry: _fetch)
            else if (_playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Bạn chưa có playlist nào. Đặt tên để tạo playlist và lưu bài này vào:', style: body(TextStyle(fontSize: 16, color: AppColors.text))),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleCtrl,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _createAndAdd(),
                    style: body(TextStyle(fontSize: 16, color: AppColors.text)),
                    decoration: InputDecoration(
                      hintText: 'Tên playlist, ví dụ: Nhạc yêu thích',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PillButton(label: 'Tạo playlist', icon: Icons.add_rounded, loading: _creating, onTap: _creating ? null : _createAndAdd),
                ]),
              )
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
                          ? CachedNetworkImage(imageUrl: cdnImg((thumb).toString(), 110), width: 44, height: 44, fit: BoxFit.cover)
                          : Container(width: 44, height: 44, color: AppColors.surfaceLight, child: Icon(Icons.playlist_play, color: AppColors.textMuted)),
                    ),
                    minVerticalPadding: 10,
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
