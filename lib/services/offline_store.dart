import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'player.dart' show songKind;
import 'api.dart';
import 'auth.dart';

/// "Đã tải về": songs saved inside the app for listening without network.
///
/// The file URL comes from the same `download` mutation the web uses, so
/// the server's per-user rate limit and download counter still apply; the
/// mp3 is then streamed into the app's private storage (not the Photos /
/// Files app). The player checks [localPath] before streaming.
class OfflineStore extends ChangeNotifier {
  OfflineStore._();
  static final OfflineStore instance = OfflineStore._();

  Directory? _dir;
  // key ("song-123") → song map with 'local_path', 'size', 'saved_at'.
  final Map<String, Map<String, dynamic>> _items = {};
  // key → 0..1 while downloading.
  final Map<String, double> _progress = {};
  bool _loaded = false;

  static String keyOf(Map song) => '${songKind(song)}-${song['id']}';

  List<Map<String, dynamic>> get items {
    final list = _items.values.toList()..sort((a, b) => (b['saved_at'] ?? '').toString().compareTo((a['saved_at'] ?? '').toString()));
    return list;
  }

  int get totalBytes => _items.values.fold(0, (s, m) => s + ((m['size'] as num?)?.toInt() ?? 0));
  bool isSaved(Map song) => _items.containsKey(keyOf(song));
  double? progressOf(Map song) => _progress[keyOf(song)];

  /// Local file for a saved song, or null.
  String? localPath(Map song) {
    final m = _items[keyOf(song)];
    final p = m?['local_path']?.toString();
    if (p == null) return null;
    return File(p).existsSync() ? p : null;
  }

  Future<File> get _index async => File('${(await _folder).path}/index.json');

  Future<Directory> get _folder async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/offline');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _index;
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString());
        if (data is Map) {
          data.forEach((k, v) {
            if (v is Map && File(v['local_path']?.toString() ?? '').existsSync()) _items[k.toString()] = Map<String, dynamic>.from(v);
          });
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await (await _index).writeAsString(jsonEncode(_items));
    } catch (_) {}
  }

  /// Downloads [song] for offline listening. Returns null on success or a
  /// Vietnamese message explaining why it couldn't.
  Future<String?> download(Map<String, dynamic> song, AuthProvider auth) async {
    await load();
    final key = keyOf(song);
    if (_items.containsKey(key)) return null;
    if (_progress.containsKey(key)) return 'Bài này đang được tải';
    final type = songKind(song);
    _progress[key] = 0;
    notifyListeners();
    File? tmp;
    try {
      const m = r'mutation($objectType: String!, $objectId: ID!) { download(object_type: $objectType, object_id: $objectId) { url } }';
      final vars = {'objectType': type, 'objectId': song['id'].toString()};
      final data = auth.isAuthenticated ? await auth.authedMutate(m, vars) : await ApiClient.mutate(m, vars);
      final url = data['download']?['url']?.toString();
      if (url == null || url.isEmpty) return 'Bạn đã tải quá nhiều, thử lại sau';

      final dir = await _folder;
      final file = File('${dir.path}/$key.mp3');
      tmp = File('${file.path}.part');
      final res = await http.Client().send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) return 'Không tải được file (mã ${res.statusCode})';
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = tmp.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          _progress[key] = got / total;
          notifyListeners();
        }
      }
      await sink.close();
      await tmp.rename(file.path);

      // Keep only what lists and the player need (detail maps carry lyrics,
      // loves, comments…).
      const fields = ['id', 'title', 'slug', 'subtitle', 'file_type', 'play_type', 'thumbnail', 'artists', 'composers', 'sheet', 'file'];
      final keep = <String, dynamic>{for (final f in fields) if (song[f] != null) f: song[f]};
      if (keep['sheet'] is Map) keep['sheet'] = {'year': keep['sheet']['year'], 'composers': keep['sheet']['composers']};
      keep
        ..['file_type'] = songKind(song)
        ..['local_path'] = file.path
        ..['size'] = got
        ..['saved_at'] = DateTime.now().toIso8601String();
      _items[key] = keep;
      await _save();
      return null;
    } catch (_) {
      return 'Không tải được, kiểm tra mạng rồi thử lại';
    } finally {
      _progress.remove(key);
      if (tmp != null && await tmp.exists()) {
        try { await tmp.delete(); } catch (_) {}
      }
      notifyListeners();
    }
  }

  Future<void> remove(Map song) async {
    final m = _items.remove(keyOf(song));
    final p = m?['local_path']?.toString();
    if (p != null) {
      try { await File(p).delete(); } catch (_) {}
    }
    await _save();
    notifyListeners();
  }

  Future<void> clear() async {
    for (final m in _items.values.toList()) {
      try { await File(m['local_path'].toString()).delete(); } catch (_) {}
    }
    _items.clear();
    await _save();
    notifyListeners();
  }
}
