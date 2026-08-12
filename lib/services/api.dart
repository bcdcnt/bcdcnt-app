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

  /// AuthProvider registers a callback here so that when the
  /// AppAccessGuard middleware on the backend rejects a request
  /// (admin revoked access_app for this user), the app can react
  /// globally — typically by force-logging out and showing a notice.
  /// Without this, the user would just see opaque GraphQL errors on
  /// every action until they manually signed out.
  static void Function()? onAppAccessDenied;

  static const _appAccessDeniedCode = "user_app_access_denied";

  /// Scans the GraphQL errors array for the app-access-denied code and
  /// fires the global callback exactly once per response. The first
  /// error's message is then thrown so existing call sites still get
  /// a readable exception.
  static Never _throwErrors(List errors) {
    for (final e in errors) {
      final ext = e is Map ? e["extensions"] : null;
      final code = (ext is Map ? ext["code"] : null)?.toString();
      if (code == _appAccessDeniedCode) {
        onAppAccessDenied?.call();
        break;
      }
    }
    final first = errors.isNotEmpty ? errors[0] : null;
    final msg = (first is Map ? first["message"] : null)?.toString();
    throw Exception(msg ?? "GraphQL error");
  }

  static Future<Map<String, dynamic>> query(String q, [Map<String, dynamic>? variables]) async {
    // Prefer GET so Cloudflare can serve read queries from the edge cache
    // (cf-cache-status: HIT). POST is never edge-cached (always DYNAMIC) — that
    // was making the app noticeably slower than the web, which uses GET for the
    // same public reads. Fall back to POST only when GET itself fails (network
    // error or a proxy rejecting a very long query URL), preserving old behavior.
    final uri = Uri.parse(apiBase).replace(queryParameters: {
      'query': q,
      if (variables != null) 'variables': jsonEncode(variables),
    });
    http.Response? res;
    try {
      res = await http.get(uri, headers: _baseHeaders());
      if (res.statusCode != 200) res = null;
    } catch (_) {
      res = null;
    }
    res ??= await http.post(
      Uri.parse(apiBase),
      headers: _baseHeaders(jsonContent: true),
      body: jsonEncode({'query': q, if (variables != null) 'variables': variables}),
    );
    final json = jsonDecode(res.body);
    if (json['errors'] != null) {
      // Surface the first GraphQL error so failures don't silently render
      // empty pages. Catch sites can decide to swallow this if they want.
      _throwErrors(json['errors'] as List);
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
      _throwErrors(json['errors'] as List);
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
      _throwErrors(json['errors'] as List);
    }
    return json['data'] ?? {};
  }
}

String formatViews(int? n) {
  // Việt hoá khớp web: Tr = triệu, N = nghìn (nghìn làm tròn số nguyên).
  if (n == null || n == 0) return '0';
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')}Tr';
  if (n >= 1000) return '${(n / 1000).round()}N';
  return n.toString();
}

/// Định dạng số nguyên kiểu ngăn nghìn bằng dấu chấm (vi-VN): 10247 -> "10.247".
/// Khớp với `toLocaleString("vi-VN")` mà web dùng.
String formatInt(int? n) {
  if (n == null) return '0';
  final s = n.abs().toString();
  final buf = StringBuffer();
  if (n < 0) buf.write('-');
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
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
