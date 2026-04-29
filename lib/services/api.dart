import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../constants/theme.dart';

class ApiClient {
  /// Identifies requests as coming from the native app so the BE can branch
  /// behavior (e.g. analytics, in-app webviews, response trimming). Format:
  /// `bcdcnt-flutter/<platform>` — backend can split on `/`.
  static String get _clientHeader {
    final platform = kIsWeb
        ? 'web'
        : (Platform.isMacOS
            ? 'macos'
            : Platform.isIOS
                ? 'ios'
                : Platform.isAndroid
                    ? 'android'
                    : Platform.isWindows
                        ? 'windows'
                        : Platform.isLinux
                            ? 'linux'
                            : 'unknown');
    return 'bcdcnt-flutter/$platform';
  }

  static Map<String, String> _baseHeaders({String? token, bool jsonContent = false}) {
    return {
      if (jsonContent) 'Content-Type': 'application/json',
      'Origin': siteUrl,
      'X-Client-App': _clientHeader,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> query(String q, [Map<String, dynamic>? variables]) async {
    // POST with body — long queries blow URL length limits on some
    // proxies/CDNs and the response was coming back empty silently.
    final res = await http.post(
      Uri.parse(apiBase),
      headers: _baseHeaders(jsonContent: true),
      body: jsonEncode({'query': q, if (variables != null) 'variables': variables}),
    );
    final json = jsonDecode(res.body);
    if (json['errors'] != null) {
      // Surface the first GraphQL error so failures don't silently render
      // empty pages. Catch sites can decide to swallow this if they want.
      throw Exception(json['errors'][0]['message']);
    }
    return json['data'] ?? {};
  }

  static Future<Map<String, dynamic>> mutate(String q, [Map<String, dynamic>? variables, String? token]) async {
    final res = await http.post(
      Uri.parse(apiBase),
      headers: _baseHeaders(token: token, jsonContent: true),
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
      headers: _baseHeaders(token: token, jsonContent: true),
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
