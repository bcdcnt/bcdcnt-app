import 'dart:convert';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'auth.dart';

typedef UploadedImage = ({String id, String? url});

/// Ask for one image (or several with [multiple]) from the photo library / files.
Future<List<PlatformFile>> pickImages({bool multiple = false}) async {
  final pick = await FilePicker.platform.pickFiles(type: FileType.image, withData: true, allowMultiple: multiple);
  return (pick?.files ?? const []).where((f) => f.bytes != null).toList();
}

/// presignUpload → PUT to storage → poll uploadStatus, same steps as the web
/// (and Cài đặt → ảnh đại diện). Returns the new image row.
Future<UploadedImage> uploadImage(AuthProvider auth, PlatformFile file, {String? context}) async {
  final presign = await auth.authedMutate(r'''mutation($filename: String!, $type: UploadType!, $context: String) {
    presignUpload(filename: $filename, type: $type, context: $context) { upload_url key }
  }''', {'filename': file.name, 'type': 'img', 'context': context});
  final uploadUrl = presign['presignUpload']['upload_url'];
  final key = presign['presignUpload']['key'];

  final ext = (file.extension ?? '').toLowerCase();
  final mime = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : (ext == 'gif' ? 'image/gif' : 'image/jpeg'));
  final put = await http.put(Uri.parse(uploadUrl), body: file.bytes, headers: {'Content-Type': mime});
  if (put.statusCode >= 400) throw Exception('Tải ảnh lên thất bại (${put.statusCode})');

  for (int i = 0; i < 60; i++) {
    await Future.delayed(const Duration(milliseconds: 500));
    final d = await auth.authedQuery(r'query($key: String!) { uploadStatus(key: $key) { status data message } }', {'key': key});
    final r = d['uploadStatus'];
    final s = (r?['status'] ?? '').toString().toLowerCase();
    if (s == 'completed') {
      final raw = r['data'];
      final data = raw is String ? jsonDecode(raw) : raw;
      return (id: '${data['id']}', url: data['url']?.toString());
    }
    if (s == 'failed' || s == 'error') throw Exception(r?['message'] ?? 'Xử lý ảnh lỗi');
  }
  throw Exception('Quá thời gian xử lý ảnh');
}

const _audioExts = ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'wma'];
const _videoExts = ['mp4', 'mov', 'avi', 'flv', 'mpg', 'mpeg', 'wmv', '3gp'];

/// One recording (audio, or a video the server turns into audio + video).
Future<PlatformFile?> pickMedia() async {
  final pick = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: [..._audioExts, ..._videoExts], withData: true);
  final f = pick?.files.firstOrNull;
  return f?.bytes == null ? null : f;
}

/// Same three steps as the web's DropZone with type "mp3": presign → PUT
/// (progress 0–1 through [onProgress]) → poll uploadStatus while the server
/// converts it. Returns the new file row: id, audio_url, video_url, duration…
Future<Map<String, dynamic>> uploadMedia(AuthProvider auth, PlatformFile file, {void Function(double sent)? onProgress, VoidCallback? onProcessing}) async {
  final presign = await auth.authedMutate(r'''mutation($filename: String!, $type: UploadType!) {
    presignUpload(filename: $filename, type: $type) { upload_url key }
  }''', {'filename': file.name, 'type': 'mp3'});
  final uploadUrl = presign['presignUpload']['upload_url'];
  final key = presign['presignUpload']['key'];

  final ext = (file.extension ?? '').toLowerCase();
  final mime = _videoExts.contains(ext) ? 'video/${ext == 'mov' ? 'quicktime' : ext}' : (ext == 'mp3' ? 'audio/mpeg' : 'audio/$ext');
  final bytes = file.bytes!;
  final req = http.StreamedRequest('PUT', Uri.parse(uploadUrl))
    ..headers['Content-Type'] = mime
    ..contentLength = bytes.length;
  final send = req.send();
  const chunk = 256 * 1024;
  for (var i = 0; i < bytes.length; i += chunk) {
    req.sink.add(bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk));
    onProgress?.call((i + chunk).clamp(0, bytes.length) / bytes.length);
    await Future<void>.delayed(Duration.zero);
  }
  await req.sink.close();
  final res = await send;
  if (res.statusCode >= 400) throw Exception('Tải file lên thất bại (${res.statusCode})');

  onProcessing?.call();
  // Converting a long recording takes a while: up to ~4 minutes.
  for (int i = 0; i < 120; i++) {
    await Future.delayed(const Duration(seconds: 2));
    final d = await auth.authedQuery(r'query($key: String!) { uploadStatus(key: $key) { status data message } }', {'key': key});
    final r = d['uploadStatus'];
    final s = (r?['status'] ?? '').toString().toLowerCase();
    if (s == 'completed') {
      final raw = r['data'];
      return Map<String, dynamic>.from((raw is String ? jsonDecode(raw) : raw) as Map);
    }
    if (s == 'failed' || s == 'error') throw Exception(r?['message'] ?? 'Xử lý file lỗi');
  }
  throw Exception('Quá thời gian xử lý file');
}
