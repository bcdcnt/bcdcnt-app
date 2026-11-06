import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'player.dart' show songKind;
import 'api.dart';
import 'auth.dart';
import 'friendly_error.dart';

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
  // key ("song-123") → song map with 'local_file', 'size', 'saved_at'.
  // Only the file name is stored: iOS moves the app container on every
  // update, so an absolute path saved last week points nowhere today.
  final Map<String, Map<String, dynamic>> _items = {};
  // key → 0..1 while downloading.
  final Map<String, double> _progress = {};

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
    final p = _pathOf(_items[keyOf(song)]);
    if (p == null) return null;
    return File(p).existsSync() ? p : null;
  }

  /// Absolute path rebuilt from the current downloads folder. Needs [_dir],
  /// which load() sets before any item exists.
  String? _pathOf(Map? m) {
    final name = m?['local_file']?.toString();
    if (name == null || name.isEmpty || _dir == null) return null;
    return '${_dir!.path}/$name';
  }

  /// File name of an entry; entries saved by older builds only have an
  /// absolute 'local_path' whose base name is still valid.
  static String? _fileNameOf(Map m) {
    final name = m['local_file']?.toString();
    if (name != null && name.isNotEmpty) return name;
    final old = m['local_path']?.toString();
    if (old == null || old.isEmpty) return null;
    return old.split(RegExp(r'[/\\]')).last;
  }

  Future<File> get _index async => File('${(await _folder).path}/index.json');

  Future<Directory> get _folder async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/offline');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  Future<void>? _loading;

  /// Callers awaiting load() get the real read, not an early return with an
  /// empty list (which made "tải cả danh sách" re-download saved songs).
  Future<void> load() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    try {
      final dir = await _folder;
      final f = await _index;
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString());
        var migrated = false;
        if (data is Map) {
          data.forEach((k, v) {
            if (v is! Map) return;
            final name = _fileNameOf(v);
            if (name == null || !File('${dir.path}/$name').existsSync()) return;
            final m = Map<String, dynamic>.from(v);
            if (m.containsKey('local_path')) {
              m.remove('local_path');
              migrated = true;
            }
            m['local_file'] = name;
            _items[k.toString()] = m;
          });
        }
        if (migrated) await _save();
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _saveChain = Future.value();

  /// Writes are queued and go through a temp file + rename, so overlapping
  /// downloads or a crash mid-write can't corrupt the list of saved songs.
  Future<void> _save() => _saveChain = _saveChain.then((_) async {
        try {
          final f = await _index;
          final tmp = File('${f.path}.tmp');
          await tmp.writeAsString(jsonEncode(_items), flush: true);
          await tmp.rename(f.path);
        } catch (_) {}
      });

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
      final client = http.Client();
      IOSink? sink;
      var got = 0;
      try {
        final res = await client.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) return 'Không tải được file (mã ${res.statusCode})';
        final total = res.contentLength ?? 0;
        sink = tmp.openWrite();
        var lastPct = -1;
        // A stalled stream must not hang a whole "tải cả danh sách" run.
        await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) {
            // Notify per whole percent, not per chunk (hundreds per MP3).
            final pct = got * 100 ~/ total;
            if (pct != lastPct) {
              lastPct = pct;
              _progress[key] = got / total;
              notifyListeners();
            }
          }
        }
        await sink.close();
        sink = null;
        // A dropped connection can end the stream early without an error;
        // a half file would play a few seconds then stop.
        if (total > 0 && got != total) return 'Tải chưa xong, kiểm tra mạng rồi thử lại';
      } finally {
        await sink?.close();
        client.close();
      }
      await tmp.rename(file.path);

      // Keep only what lists and the player need (detail maps carry lyrics,
      // loves, comments…).
      const fields = ['id', 'title', 'slug', 'subtitle', 'file_type', 'play_type', 'thumbnail', 'artists', 'composers', 'sheet', 'file'];
      final keep = <String, dynamic>{for (final f in fields) if (song[f] != null) f: song[f]};
      if (keep['sheet'] is Map) keep['sheet'] = {'year': keep['sheet']['year'], 'composers': keep['sheet']['composers']};
      keep
        ..['file_type'] = songKind(song)
        ..['local_file'] = '$key.mp3'
        ..['size'] = got
        ..['saved_at'] = DateTime.now().toIso8601String();
      _items[key] = keep;
      await _save();
      return null;
    } catch (e) {
      // Server messages ("Vui lòng đăng nhập để tải", "Không có file") are
      // clearer than a generic network hint; friendlyError keeps those.
      if (e is SocketException || e is TimeoutException || e is http.ClientException) return 'Không tải được, kiểm tra mạng rồi thử lại';
      return friendlyError(e, fallback: 'Không tải được, vui lòng thử lại');
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
    final p = _pathOf(m);
    if (p != null) {
      try { await File(p).delete(); } catch (_) {}
    }
    await _save();
    notifyListeners();
  }

  Future<void> clear() async {
    for (final m in _items.values.toList()) {
      final p = _pathOf(m);
      if (p == null) continue;
      try { await File(p).delete(); } catch (_) {}
    }
    _items.clear();
    await _save();
    notifyListeners();
  }
}
