import 'dart:convert';
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
