import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme.dart';
import 'api.dart';
import 'auth.dart';
import 'notification_route.dart';

/// Phone push (FCM → APNs / Android).
///
/// * The token is sent to the API on launch, on refresh and whenever the
///   member signs in or out (signed out = guest device: topic pushes only).
/// * Permission is never asked at first launch: [maybeAsk] shows our own
///   short explanation first, at a moment where it makes sense (after login,
///   following someone, commenting, opening a ticket), and only asks iOS /
///   Android once the listener says yes.
/// * Tapping a push opens the same page as tapping it in Thông báo.
///
/// Without the Firebase config files (GoogleService-Info.plist /
/// google-services.json) everything here quietly does nothing.
class PushService {
  PushService._();
  static final instance = PushService._();

  static const dailySongTopic = 'daily_song';
  static const _kAskedAt = 'push_asked_at';
  static const _kDailySong = 'push_daily_song';

  bool _ready = false;
  String? _token;
  AuthProvider? _auth;
  GoRouter? _router;
  bool? _wasSignedIn;

  /// iOS + Android only (macOS/desktop/web: no push in the app).
  static bool get supported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  bool get ready => _ready;

  Future<void> init({required AuthProvider auth, required GoRouter router}) async {
    _auth = auth;
    _router = router;
    if (!supported || _ready) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Push off (no Firebase config): $e');
      return;
    }
    _ready = true;
    final fm = FirebaseMessaging.instance;

    // iOS: show the banner even when the app is open (Android shows the
    // in-app bell instead; the realtime socket already updates it).
    await fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data));
    final initial = await fm.getInitialMessage();
    if (initial != null) {
      // Let the first screen build before navigating on top of it.
      Future.delayed(const Duration(milliseconds: 600), () => _open(initial.data));
    }
    fm.onTokenRefresh.listen((t) {
      _token = t;
      _register();
    });

    auth.addListener(_onAuthChanged);
    if (!auth.loading) _wasSignedIn = auth.isAuthenticated;
    // Already allowed (earlier session)? Then register straight away.
    final s = await fm.getNotificationSettings();
    if (_allowed(s.authorizationStatus)) await _start();
  }

  static bool _allowed(AuthorizationStatus s) => s == AuthorizationStatus.authorized || s == AuthorizationStatus.provisional;

  Future<AuthorizationStatus?> status() async {
    if (!_ready) return null;
    return (await FirebaseMessaging.instance.getNotificationSettings()).authorizationStatus;
  }

  Future<void> _start() async {
    try {
      _token = await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('FCM token failed: $e');
      return;
    }
    await _register();
    if (await dailySongEnabled()) {
      try { await FirebaseMessaging.instance.subscribeToTopic(dailySongTopic); } catch (_) {}
    }
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null || auth.loading) return;
    final signedIn = auth.isAuthenticated;
    if (_wasSignedIn == signedIn) return;
    final was = _wasSignedIn;
    _wasSignedIn = signedIn;
    if (signedIn && was == false) {
      // Just logged in (not a session restored at launch): good moment to ask.
      final ctx = _router?.routerDelegate.navigatorKey.currentContext;
      if (ctx != null) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (ctx.mounted) maybeAsk(ctx, reason: 'Biết ngay khi có người trả lời, nhắc đến bạn hoặc khi BQT duyệt bài gửi của bạn.');
        });
      }
    }
    if (_token == null) return;
    if (signedIn) {
      _register();
    } else if (was == true) {
      // Signed out: this phone stops getting that member's pushes.
      ApiClient.mutate(r'mutation($t: String!) { unregisterDevice(token: $t) }', {'t': _token}).catchError((_) => <String, dynamic>{});
      clearBadge();
    }
  }

  Future<void> _register() async {
    final token = _token;
    if (token == null) return;
    const m = r'mutation($t: String!, $p: String, $v: String) { registerDevice(token: $t, platform: $p, app_version: $v) }';
    final vars = {'t': token, 'p': Platform.isIOS ? 'ios' : 'android', 'v': ApiClient.appVersion};
    try {
      final auth = _auth;
      if (auth != null && auth.isAuthenticated) {
        await auth.authedMutate(m, vars);
      } else {
        await ApiClient.mutate(m, vars);
      }
    } catch (e) {
      debugPrint('registerDevice failed: $e');
    }
  }

  void _open(Map<String, dynamic> data) {
    final router = _router;
    if (router == null) return;
    final auth = _auth;
    final code = data['code']?.toString();
    if (code != null && code.isNotEmpty && auth != null && auth.isAuthenticated) {
      auth.authedMutate(r'mutation($code: String!) { markAsRead(code: $code) }', {'code': code}).catchError((_) => <String, dynamic>{});
    }
    final t = notificationRoute(data);
    if (t != null) {
      router.push(t.path, extra: t.extra);
    } else if (data['action'] != 'daily_song') {
      router.push('/thong-bao');
    }
  }

  // ── Asking for permission ────────────────────────────────────────────

  /// Ask at a good moment. [reason] is the line under the title, e.g.
  /// "Biết ngay khi có người trả lời bình luận của bạn."
  /// Shown at most once a month, and never again once allowed/denied in iOS.
  Future<void> maybeAsk(BuildContext context, {required String reason}) async {
    if (!_ready) return;
    final fm = FirebaseMessaging.instance;
    final s = await fm.getNotificationSettings();
    if (_allowed(s.authorizationStatus)) {
      if (_token == null) await _start();
      return;
    }
    if (s.authorizationStatus == AuthorizationStatus.denied) return; // only Cài đặt can change it now
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kAskedAt) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < const Duration(days: 30).inMilliseconds) return;
    if (!context.mounted) return;
    await prefs.setInt(_kAskedAt, DateTime.now().millisecondsSinceEpoch);
    final yes = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _AskSheet(reason: reason),
    );
    if (yes == true) await requestPermission();
  }

  /// The system prompt itself (also used by the switch in Cài đặt).
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final s = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    final ok = _allowed(s.authorizationStatus);
    if (ok) await _start();
    return ok;
  }

  // ── "Bài hát của ngày" (topic, works without an account) ────────────

  Future<bool> dailySongEnabled() async => (await SharedPreferences.getInstance()).getBool(_kDailySong) ?? true;

  Future<void> setDailySong(bool on) async {
    (await SharedPreferences.getInstance()).setBool(_kDailySong, on);
    if (!_ready || _token == null) return;
    try {
      if (on) {
        await FirebaseMessaging.instance.subscribeToTopic(dailySongTopic);
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(dailySongTopic);
      }
    } catch (_) {}
  }

  /// Red number on the app icon; cleared when Thông báo is opened.
  static Future<void> clearBadge() async {
    if (kIsWeb || !Platform.isIOS) return; // Android clears it with the notifications
    try { await const MethodChannel('bcdcnt/badge').invokeMethod('clear'); } catch (_) {}
  }
}

class _AskSheet extends StatelessWidget {
  final String reason;
  const _AskSheet({required this.reason});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
              child: Icon(Icons.notifications_active_rounded, size: 32, color: AppColors.accent),
            ),
            const SizedBox(height: 16),
            Text('Bật thông báo?', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
            const SizedBox(height: 8),
            Text(reason, textAlign: TextAlign.center, style: body(TextStyle(fontSize: 15, height: 1.4, color: AppColors.textSecondary))),
            const SizedBox(height: 6),
            Text('Không làm phiền từ 22h đến 7h. Tắt từng loại trong Cài đặt.', textAlign: TextAlign.center, style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(vertical: 14), shape: const StadiumBorder()),
                child: Text('Bật thông báo', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white))),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Để sau', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
            ),
          ]),
        ),
      );
}
