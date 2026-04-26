import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/theme.dart';

class ApiClient {
  static Future<Map<String, dynamic>> query(String q, [Map<String, dynamic>? variables]) async {
    final params = {
      'query': q,
      if (variables != null) 'variables': jsonEncode(variables),
    };
    final uri = Uri.parse(apiBase).replace(queryParameters: params);
    final res = await http.get(uri, headers: {'Origin': siteUrl});
    final json = jsonDecode(res.body);
    return json['data'] ?? {};
  }

  static Future<Map<String, dynamic>> mutate(String q, [Map<String, dynamic>? variables, String? token]) async {
    final res = await http.post(
      Uri.parse(apiBase),
      headers: {
        'Content-Type': 'application/json',
        'Origin': siteUrl,
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'query': q, 'variables': variables}),
    );
    final json = jsonDecode(res.body);
    if (json['errors'] != null) {
      throw Exception(json['errors'][0]['message']);
    }
    return json['data'] ?? {};
  }

  static Future<Map<String, dynamic>> authedQuery(String q, Map<String, dynamic>? variables, String token) async {
    // Use POST with body for authed queries to avoid CORS preflight issues with
    // long URLs and to keep parity with mutate() — many backends preflight-fail
    // on GET with Authorization header.
    final res = await http.post(
      Uri.parse(apiBase),
      headers: {
        'Content-Type': 'application/json',
        'Origin': siteUrl,
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'query': q, if (variables != null) 'variables': variables}),
    );
    final json = jsonDecode(res.body);
    if (json['errors'] != null) {
      throw Exception(json['errors'][0]['message']);
    }
    return json['data'] ?? {};
  }
}

String formatViews(int? n) {
  if (n == null || n == 0) return '0';
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1).replaceAll('.0', '')}K';
  return n.toString();
}

String formatTime(double? sec) {
  if (sec == null || sec.isNaN) return '0:00';
  final m = (sec ~/ 60).toString();
  final s = (sec.toInt() % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String timeago(String? dateStr) {
  if (dateStr == null) return '';
  final date = DateTime.tryParse(dateStr);
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  if (diff.inDays < 30) return '${diff.inDays} ngày trước';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30} tháng trước';
  return '${diff.inDays ~/ 365} năm trước';
}
