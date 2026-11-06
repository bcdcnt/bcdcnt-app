import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'friendly_error.dart';

const meQuery = '''query { me {
  id username email
  avatar { url } background { url }
  unread point listen
  permissions roles { alias }
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
  login(identity: \$identity, password: \$password) { access_token refresh_token message code }
}''';

const loginByGoogleMutation = '''mutation(\$token: String!) {
  loginByGoogle(token: \$token) { access_token refresh_token message code }
}''';

const loginByAppleMutation = '''mutation(\$token: String!, \$name: String) {
  loginByApple(identity_token: \$token, full_name: \$name) { access_token refresh_token message code }
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

  /// Bumped on every logout / new login. Async work (token refresh, `me`
  /// fetch) captures the epoch when it starts and drops its result if the
  /// session changed meanwhile, so a slow response can't resurrect a
  /// session the user just signed out of.
  int _epoch = 0;

  /// Short-lived token returned by validateCode (forgot-password flow).
  /// Kept in memory only — never persisted — and used solely by the next
  /// changePassword call.
  String? _resetToken;

  Map<String, dynamic>? get user => _user;
  String? get token => _token;
  bool get loading => _loading;
  bool get isAuthenticated => _user != null && _token != null;

  /// True if the current user has [name] in their `permissions` list.
  /// Returns false when not logged in or when the list is missing.
  bool get isAdmin => _user?['is_admin'] == true;

  bool hasPermission(String name) {
    if (isAdmin) return true;
    final perms = _user?['permissions'];
    if (perms is! List) return false;
    return perms.contains(name);
  }

  /// Set once when AuthProvider exists so the UI layer can react when
  /// the AppAccessGuard middleware revokes us mid-session. Banner / dialog
  /// code (lib/main.dart's ChangeNotifier listener) toggles this flag
  /// and clears it after showing the notice.
  bool appAccessRevoked = false;

  AuthProvider() {
    // Wire ApiClient's global app-access-denied callback so a 403 from
    // the AppAccessGuard middleware force-logs us out + raises a flag
    // the UI can read to display "BQT đã thu hồi quyền dùng app".
    ApiClient.onAppAccessDenied = () {
      appAccessRevoked = true;
      logout();
    };
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
      final epoch = _epoch;
      final fresh = await _doRefresh();
      if (fresh == null && epoch == _epoch) {
        // Refresh failed — wipe and present logged-out state.
        await _clearStorage();
        _token = null; _refreshToken = null; _user = null;
      } else if (fresh != null) {
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
      final epoch = _epoch;
      try {
        if (_refreshToken == null) { completer.complete(null); return; }
        final data = await ApiClient.mutate(refreshTokenMutation, {'refresh_token': _refreshToken});
        // Logged out / switched account while waiting → discard.
        if (epoch != _epoch) { completer.complete(null); return; }
        final result = data['refreshToken'];
        final newAccess = result?['access_token'];
        final newRefresh = result?['refresh_token'];
        if (newAccess is String && newAccess.isNotEmpty) {
          _token = newAccess;
          if (newRefresh is String && newRefresh.isNotEmpty) _refreshToken = newRefresh;
          final prefs = await SharedPreferences.getInstance();
          if (epoch != _epoch) { completer.complete(null); return; }
          await prefs.setString('access_token', newAccess);
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
    final epoch = _epoch;
    try {
      final tok = await _ensureToken();
      if (tok == null || epoch != _epoch) return;
      final data = await ApiClient.authedQuery(meQuery, null, tok);
      if (epoch != _epoch) return;
      final me = data['me'];
      if (me != null) {
        _user = {
          'id': me['id'], 'username': me['username'], 'email': me['email'],
          'avatar': me['avatar']?['url'], 'background': me['background']?['url'],
          'unread': me['unread'] ?? 0,
          'point': me['point'] ?? 0,
          'listen': me['listen'] ?? 0,
          // Super admin can do everything, like the web's isAdmin.
          'is_admin': ((me['roles'] as List?) ?? const []).any((r) => r is Map && r['alias'] == 'super_admin'),
          'permissions': (me['permissions'] is List)
              ? List<String>.from((me['permissions'] as List).whereType<String>())
              : <String>[],
          'player_shuffle': me['player_shuffle'],
          'player_repeat': me['player_repeat'],
          'show_comment_sidebar': me['show_comment_sidebar'] ?? false,
        };
        final prefs = await SharedPreferences.getInstance();
        if (epoch != _epoch) return;
        await prefs.setString('user', jsonEncode(_user));
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Re-fetch `me` (unread count, points, permissions…) and notify
  /// listeners. Safe to call often — e.g. on app resume or when realtime
  /// reports a new notification. No-op for guests.
  Future<void> refreshMe() async {
    if (_token == null) return;
    await _fetchMe();
  }

  /// Store a freshly issued session (login / social login). Bumps the
  /// epoch so any refresh still in flight for an older session is ignored.
  Future<void> _startSession(String access, String? refresh) async {
    _epoch++;
    _token = access;
    _refreshToken = refresh;
    _resetToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', access);
    if (refresh != null) {
      await prefs.setString('refresh_token', refresh);
    } else {
      await prefs.remove('refresh_token');
    }
  }

  Future<String?> login(String identity, String password) async {
    try {
      final data = await ApiClient.mutate(loginMutation, {'identity': identity, 'password': password});
      final result = data['login'];
      if (result?['access_token'] != null) {
        await _startSession(result['access_token'], result['refresh_token']);
        await _fetchMe();
        return null;
      }
      // Backend returns { message, code } on every business-rule
      // rejection (wrong password, not active, banned, app access
      // denied). Surface that text instead of a generic "thất bại"
      // so the login screen can actually tell the user what to do.
      final msg = result?['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      return 'Đăng nhập thất bại';
    } catch (e) { return friendlyError(e, fallback: 'Đăng nhập thất bại, vui lòng thử lại.'); }
  }

  /// Exchange a Google ID token (from the desktop OAuth flow) for our session.
  /// Returns null on success, or an error/business-rule message to show.
  Future<String?> loginByGoogle(String idToken) async {
    try {
      final data = await ApiClient.mutate(loginByGoogleMutation, {'token': idToken});
      final result = data['loginByGoogle'];
      if (result?['access_token'] != null) {
        await _startSession(result['access_token'], result['refresh_token']);
        await _fetchMe();
        return null;
      }
      // App-access gate returns { message, code } (e.g. not enough points).
      final msg = result?['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      return 'Đăng nhập Google thất bại';
    } catch (e) { return friendlyError(e, fallback: 'Đăng nhập Google thất bại, vui lòng thử lại.'); }
  }

  /// Exchange an Apple identity token (Sign in with Apple, iOS/macOS) for our
  /// session. [fullName] is only provided by Apple on the first sign-in.
  Future<String?> loginByApple(String identityToken, String? fullName) async {
    try {
      final data = await ApiClient.mutate(loginByAppleMutation, {'token': identityToken, 'name': fullName});
      final result = data['loginByApple'];
      if (result?['access_token'] != null) {
        await _startSession(result['access_token'], result['refresh_token']);
        await _fetchMe();
        return null;
      }
      final msg = result?['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      return 'Đăng nhập Apple thất bại';
    } catch (e) { return friendlyError(e, fallback: 'Đăng nhập Apple thất bại, vui lòng thử lại.'); }
  }

  Future<String?> signup(String username, String email, String password) async {
    try {
      final data = await ApiClient.mutate(signupMutation, {
        'username': username, 'email': email, 'password': password,
      });
      if (data['signup']?['id'] != null) return null;
      return 'Đăng ký thất bại';
    } catch (e) { return friendlyError(e, fallback: 'Đăng ký thất bại, vui lòng thử lại.'); }
  }

  Future<String?> forgotPassword(String identity) async {
    try {
      await ApiClient.mutate(forgotPasswordMutation, {'identity': identity});
      return null;
    } catch (e) { return friendlyError(e, fallback: 'Không gửi được mã, vui lòng thử lại.'); }
  }

  Future<String?> validateCode(String identity, String code) async {
    try {
      final data = await ApiClient.mutate(validateCodeMutation, {'identity': identity, 'code': code});
      final token = data['validateCode'];
      if (token != null && token is String && token.isNotEmpty) {
        // Memory only: the password isn't set yet, so this must not become
        // a persisted session (an app restart would otherwise log the user
        // in without them ever choosing a new password).
        _resetToken = token;
        return null;
      }
      return 'Mã xác thực không hợp lệ';
    } catch (e) { return friendlyError(e, fallback: 'Mã xác thực không hợp lệ'); }
  }

  Future<String?> changePassword(String newPassword) async {
    try {
      final reset = _resetToken;
      if (reset != null) {
        // Forgot-password flow: use the one-off token from validateCode.
        await ApiClient.mutate(changePasswordMutation, {'password': newPassword}, reset);
        _resetToken = null;
        return null;
      }
      final tok = await _ensureToken();
      if (tok == null) return 'Phiên đăng nhập đã hết, vui lòng đăng nhập lại.';
      await ApiClient.mutate(changePasswordMutation, {'password': newPassword}, tok);
      return null;
    } catch (e) { return friendlyError(e, fallback: 'Không đổi được mật khẩu, vui lòng thử lại.'); }
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

  /// Set the unread badge to [n] locally (e.g. after marking one
  /// notification read). Never goes below 0.
  Future<void> setUnread(int n) async {
    if (_user == null) return;
    _user!['unread'] = n < 0 ? 0 : n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(_user));
    notifyListeners();
  }

  /// Decrement the unread badge by one locally.
  Future<void> decrementUnread() async {
    final cur = _user?['unread'];
    await setUnread((cur is num ? cur.toInt() : 0) - 1);
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
    _epoch++;
    _refreshInFlight = null;
    _resetToken = null;
    _user = null;
    _token = null;
    _refreshToken = null;
    await _clearStorage();
    notifyListeners();
  }

  /// Authenticated query that auto-refreshes the token on expiry or
  /// `Unauthenticated` errors (one retry).
  Future<Map<String, dynamic>> authedQuery(String q, [Map<String, dynamic>? variables]) async {
    final epoch = _epoch;
    var tok = await _ensureToken();
    if (tok == null) throw Exception('Phiên đăng nhập đã hết hạn');
    try {
      return await ApiClient.authedQuery(q, variables, tok);
    } catch (e) {
      if (_isUnauthenticated(e)) {
        final fresh = await _doRefresh();
        if (fresh == null) {
          // Only end the session this request belonged to.
          if (epoch == _epoch) await logout();
          throw Exception('Phiên đăng nhập đã hết hạn');
        }
        return await ApiClient.authedQuery(q, variables, fresh);
      }
      rethrow;
    }
  }

  /// Authenticated mutation that auto-refreshes the token on expiry or
  /// `Unauthenticated` errors (one retry).
  Future<Map<String, dynamic>> authedMutate(String q, Map<String, dynamic>? variables) async {
    final epoch = _epoch;
    var tok = await _ensureToken();
    if (tok == null) throw Exception('Phiên đăng nhập đã hết hạn');
    try {
      return await ApiClient.mutate(q, variables, tok);
    } catch (e) {
      if (_isUnauthenticated(e)) {
        final fresh = await _doRefresh();
        if (fresh == null) {
          // Only end the session this request belonged to.
          if (epoch == _epoch) await logout();
          throw Exception('Phiên đăng nhập đã hết hạn');
        }
        return await ApiClient.mutate(q, variables, fresh);
      }
      rethrow;
    }
  }

  /// Where tapping an upload ([obj] with id, user_id or user.id, status,
  /// result) should go for this viewer: its own page for the sender and BQT
  /// (`upload`/`/bai-gui` is owner or manage_upload only — UploadPolicy),
  /// the published song/page for an approved upload, otherwise null (row
  /// should not be tappable).
  ({String path, Map<String, dynamic>? extra})? uploadRoute(Map obj) {
    final owner = (obj['user_id'] ?? (obj['user'] is Map ? obj['user']['id'] : null))?.toString();
    final me = _user?['id']?.toString();
    if (me != null && (owner == me || hasPermission('manage_upload'))) {
      return (path: '/bai-gui/${obj['id']}', extra: null);
    }
    if (obj['status'] != null && obj['status'] != 'approved') return null;
    return uploadResultRoute(obj['result']?.toString());
  }

  /// Only an expired/invalid session counts — NOT an authorization
  /// ("This action is unauthorized.") error from an `@can` directive. A
  /// permission denial must never refresh-then-log the user out.
  bool _isUnauthenticated(Object e) {
    if (e is ApiException) return e.isUnauthenticated;
    return e.toString().toLowerCase().contains('unauthenticated');
  }
}
