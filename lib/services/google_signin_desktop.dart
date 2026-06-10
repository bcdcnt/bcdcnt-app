import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../constants/google_oauth.dart';

class GoogleSignInException implements Exception {
  final String message;
  GoogleSignInException(this.message);
  @override
  String toString() => message;
}

/// "Sign in with Google" for desktop (macOS/Windows/Linux) via the OAuth 2.0
/// loopback + PKCE flow — the pattern Google recommends for installed apps,
/// since `google_sign_in` has no real desktop support.
///
/// Flow: spin up a localhost HTTP server on an ephemeral port → open the
/// Google consent screen in the user's browser → catch the redirect with the
/// auth code → exchange it (with the PKCE verifier) for tokens → return the
/// Google **ID token** (JWT) for the `loginByGoogle` mutation.
class GoogleSignInDesktop {
  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';

  static Future<String> signIn() async {
    if (!GoogleOAuth.isConfigured) {
      throw GoogleSignInException('Chưa cấu hình Google OAuth (client id/secret).');
    }

    // PKCE: verifier + S256 challenge (base64url, no padding).
    final verifier = _randomUrlSafe(64);
    final challenge =
        base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = _randomUrlSafe(24);

    // Loopback server — Google auto-allows any http://127.0.0.1:<port> for
    // Desktop-app clients, so the ephemeral port needs no registration.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}';

    final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: {
      'client_id': GoogleOAuth.clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': GoogleOAuth.scopes.join(' '),
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'prompt': 'select_account',
    });

    try {
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw GoogleSignInException('Không mở được trình duyệt.');
      }

      // Wait for the browser redirect (ignore stray requests like favicon).
      final request = await _awaitRedirect(server)
          .timeout(const Duration(minutes: 3), onTimeout: () {
        throw GoogleSignInException('Hết thời gian chờ đăng nhập.');
      });
      final params = request.uri.queryParameters;
      await _respond(request, params.containsKey('code'));

      if (params['state'] != state) {
        throw GoogleSignInException('State không khớp — huỷ để đảm bảo an toàn.');
      }
      if (params['error'] != null) {
        throw GoogleSignInException('Đăng nhập bị huỷ.');
      }
      final code = params['code'];
      if (code == null) throw GoogleSignInException('Không nhận được mã uỷ quyền.');

      final res = await http.post(Uri.parse(_tokenEndpoint), body: {
        'code': code,
        'client_id': GoogleOAuth.clientId,
        'client_secret': GoogleOAuth.clientSecret,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      });
      if (res.statusCode != 200) {
        throw GoogleSignInException('Đổi token thất bại (${res.statusCode}).');
      }
      final idToken = (jsonDecode(res.body) as Map)['id_token']?.toString();
      if (idToken == null || idToken.isEmpty) {
        throw GoogleSignInException('Google không trả về ID token.');
      }
      return idToken;
    } finally {
      await server.close(force: true);
    }
  }

  /// First request carrying `code`/`error`; reply 404 to anything else
  /// (e.g. the browser's favicon probe) so we don't resolve early.
  static Future<HttpRequest> _awaitRedirect(HttpServer server) async {
    await for (final req in server) {
      final p = req.uri.queryParameters;
      if (p.containsKey('code') || p.containsKey('error')) return req;
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    }
    throw GoogleSignInException('Đăng nhập bị huỷ.');
  }

  static Future<void> _respond(HttpRequest request, bool ok) async {
    const css =
        'font-family:-apple-system,sans-serif;text-align:center;padding-top:80px;background:#0f1117;color:#e8e8ea';
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(ok
          ? '<html><body style="$css"><h2>Đăng nhập thành công ✓</h2>'
              '<p>Bạn có thể đóng tab này và quay lại ứng dụng.</p></body></html>'
          : '<html><body style="$css"><h2>Đăng nhập bị huỷ</h2>'
              '<p>Hãy quay lại ứng dụng và thử lại.</p></body></html>');
    await request.response.close();
  }

  static String _randomUrlSafe(int len) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}
