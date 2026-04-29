import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

const meQuery = '''query { me {
  id username email
  avatar { url } background { url }
  unread
  player_shuffle player_repeat
  show_comment_sidebar
}}''';

const _updateMeShuffleMutation = '''mutation(\$v: Boolean) {
  updateMe(player_shuffle: \$v) { id }
}''';

const _updateMeRepeatMutation = '''mutation(\$v: String) {
  updateMe(player_repeat: \$v) { id }
}''';

const loginMutation = '''mutation(\$identity: String!, \$password: String!) {
  login(identity: \$identity, password: \$password) { access_token refresh_token }
}''';

const signupMutation = '''mutation(\$username: String!, \$email: String!, \$password: String!) {
  signup(username: \$username, email: \$email, password: \$password) { id }
}''';

const forgotPasswordMutation = '''mutation(\$identity: String!) {
  forgotPassword(identity: \$identity)
}''';

const validateCodeMutation = '''mutation(\$identity: String!, \$code: String!) {
  validateCode(identity: \$identity, code: \$code, type: "forgot_password")
}''';

const changePasswordMutation = '''mutation(\$password: String!) {
  changePassword(password: \$password)
}''';

const refreshTokenMutation = '''mutation(\$refresh_token: String!) {
  refreshToken(refresh_token: \$refresh_token) { access_token refresh_token message code }
}''';

/// Decode a JWT and check if the `exp` claim is past (with a 60s buffer).
/// Returns true on any decode failure (treat as expired).
bool isTokenExpired(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return true;
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    final decoded = utf8.decode(base64.decode(payload));
    final json = jsonDecode(decoded);
    final exp = json['exp'];
    if (exp is! num) return false; // no expiry claim
    return exp < DateTime.now().millisecondsSinceEpoch / 1000 + 60;
  } catch (_) { return true; }
}

class AuthProvider extends ChangeNotifier {
  Map<String, dynamic>? _user;
  String? _token;
  String? _refreshToken;
  bool _loading = true;

  // De-dup parallel refresh attempts so we only hit the API once when many
  // requests notice the token is expired at the same time.
  Future<String?>? _refreshInFlight;

  Map<String, dynamic>? get user => _user;
  String? get token => _token;
  bool get loading => _loading;
  bool get isAuthenticated => _user != null && _token != null;

  AuthProvider() {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
    final u = prefs.getString('user');
    if (u != null) _user = jsonDecode(u);
    // If token expired, refresh before fetching me; otherwise refresh in background.
    if (_token != null && isTokenExpired(_token!)) {
      final fresh = await _doRefresh();
      if (fresh == null) {
        // Refresh failed — wipe and present logged-out state.
        await _clearStorage();
        _token = null; _refreshToken = null; _user = null;
      } else {
        await _fetchMe();
      }
    } else if (_token != null) {
      _fetchMe();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _clearStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user');
  }

  /// Returns a fresh access token, or null if refresh failed (also clears auth).
  /// Multiple concurrent callers share the same in-flight refresh future.
  Future<String?> _doRefresh() {
    if (_refreshInFlight != null) return _refreshInFlight!;
    final completer = Completer<String?>();
    _refreshInFlight = completer.future;
    () async {
      try {
        if (_refreshToken == null) { completer.complete(null); return; }
        final data = await ApiClient.mutate(refreshTokenMutation, {'refresh_token': _refreshToken});
        final result = data['refreshToken'];
        final newAccess = result?['access_token'];
        final newRefresh = result?['refresh_token'];
        if (newAccess is String && newAccess.isNotEmpty) {
          _token = newAccess;
          if (newRefresh is String && newRefresh.isNotEmpty) _refreshToken = newRefresh;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('access_token', _token!);
          if (_refreshToken != null) await prefs.setString('refresh_token', _refreshToken!);
          notifyListeners();
          completer.complete(newAccess);
        } else {
          completer.complete(null);
        }
      } catch (_) { completer.complete(null); }
      finally { _refreshInFlight = null; }
    }();
    return completer.future;
  }

  /// Returns a token guaranteed to be not-yet-expired (within the 60s buffer),
  /// refreshing first if necessary. Returns null on failure.
  Future<String?> _ensureToken() async {
    if (_token == null) return null;
    if (!isTokenExpired(_token!)) return _token;
    return await _doRefresh();
  }

  Future<void> _fetchMe() async {
    try {
      final tok = await _ensureToken();
      if (tok == null) return;
      final data = await ApiClient.authedQuery(meQuery, null, tok);
      final me = data['me'];
      if (me != null) {
        _user = {
          'id': me['id'], 'username': me['username'], 'email': me['email'],
          'avatar': me['avatar']?['url'], 'background': me['background']?['url'],
          'unread': me['unread'] ?? 0,
          'player_shuffle': me['player_shuffle'],
          'player_repeat': me['player_repeat'],
          'show_comment_sidebar': me['show_comment_sidebar'] ?? false,
        };
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user', jsonEncode(_user));
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<String?> login(String identity, String password) async {
    try {
      final data = await ApiClient.mutate(loginMutation, {'identity': identity, 'password': password});
      final result = data['login'];
      if (result?['access_token'] != null) {
        _token = result['access_token'];
        _refreshToken = result['refresh_token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', _token!);
        if (_refreshToken != null) await prefs.setString('refresh_token', _refreshToken!);
        await _fetchMe();
        return null;
      }
      return 'Đăng nhập thất bại';
    } catch (e) { return e.toString(); }
  }

  Future<String?> signup(String username, String email, String password) async {
    try {
      final data = await ApiClient.mutate(signupMutation, {
        'username': username, 'email': email, 'password': password,
      });
      if (data['signup']?['id'] != null) return null;
      return 'Đăng ký thất bại';
    } catch (e) { return e.toString().replaceFirst('Exception: ', ''); }
  }

  Future<String?> forgotPassword(String identity) async {
    try {
      await ApiClient.mutate(forgotPasswordMutation, {'identity': identity});
      return null;
    } catch (e) { return e.toString().replaceFirst('Exception: ', ''); }
  }

  Future<String?> validateCode(String identity, String code) async {
    try {
      final data = await ApiClient.mutate(validateCodeMutation, {'identity': identity, 'code': code});
      final token = data['validateCode'];
      if (token != null && token is String && token.isNotEmpty) {
        _token = token;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', token);
        return null;
      }
      return 'Mã xác thực không hợp lệ';
    } catch (e) { return e.toString().replaceFirst('Exception: ', ''); }
  }

  Future<String?> changePassword(String newPassword) async {
    try {
      final tok = await _ensureToken();
      if (tok == null) return 'Phiên không hợp lệ';
      await ApiClient.mutate(changePasswordMutation, {'password': newPassword}, tok);
      return null;
    } catch (e) { return e.toString().replaceFirst('Exception: ', ''); }
  }

  /// Locally resets the unread badge on the cached user object.
  /// Call when user opens notifications screen for instant UI feedback.
  Future<void> clearUnread() async {
    if (_user == null) return;
    _user!['unread'] = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(_user));
    notifyListeners();
  }

  /// Persist a player setting (shuffle/repeat) to the server, fire-and-forget.
  /// Updates the cached user immediately so the UI doesn't flicker.
  Future<void> updatePlayerSetting(String key, Object value) async {
    if (_user == null || _token == null) return;
    _user![key] = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(_user));
    try {
      if (key == 'player_shuffle' && value is bool) {
        await authedMutate(_updateMeShuffleMutation, {'v': value});
      } else if (key == 'player_repeat' && value is String) {
        await authedMutate(_updateMeRepeatMutation, {'v': value});
      }
    } catch (_) {
      // Swallow — local state already updated; sync will retry next change.
    }
  }

  Future<void> logout() async {
    _user = null;
    _token = null;
    _refreshToken = null;
    await _clearStorage();
    notifyListeners();
  }

  /// Authenticated query that auto-refreshes the token on expiry or
  /// `Unauthenticated` errors (one retry).
  Future<Map<String, dynamic>> authedQuery(String q, [Map<String, dynamic>? variables]) async {
    var tok = await _ensureToken();
    if (tok == null) throw Exception('Phiên đăng nhập đã hết hạn');
    try {
      return await ApiClient.authedQuery(q, variables, tok);
    } catch (e) {
      if (_isUnauthenticated(e)) {
        final fresh = await _doRefresh();
        if (fresh == null) { await logout(); throw Exception('Phiên đăng nhập đã hết hạn'); }
        return await ApiClient.authedQuery(q, variables, fresh);
      }
      rethrow;
    }
  }

  /// Authenticated mutation that auto-refreshes the token on expiry or
  /// `Unauthenticated` errors (one retry).
  Future<Map<String, dynamic>> authedMutate(String q, Map<String, dynamic>? variables) async {
    var tok = await _ensureToken();
    if (tok == null) throw Exception('Phiên đăng nhập đã hết hạn');
    try {
      return await ApiClient.mutate(q, variables, tok);
    } catch (e) {
      if (_isUnauthenticated(e)) {
        final fresh = await _doRefresh();
        if (fresh == null) { await logout(); throw Exception('Phiên đăng nhập đã hết hạn'); }
        return await ApiClient.mutate(q, variables, fresh);
      }
      rethrow;
    }
  }

  bool _isUnauthenticated(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('unauthenticated') || msg.contains('unauthorized');
  }
}
