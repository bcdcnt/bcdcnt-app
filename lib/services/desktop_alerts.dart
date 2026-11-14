import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'auth.dart';
import 'realtime.dart';

/// Desktop side of a new notification (Cài đặt → Thông báo → "Trên máy
/// tính này"): a short ding when the account's `notification_sound` is on,
/// and a macOS / Windows banner while the app is open but not in front.
/// Phones get real push instead (PushService), so this stays off there.
class DesktopAlerts {
  DesktopAlerts._();
  static final instance = DesktopAlerts._();

  static bool get supported => !kIsWeb && (Platform.isMacOS || Platform.isWindows);
  static const _systemKey = 'desktop_system_notifications';

  /// "Hiện thông báo của hệ thống" — a per-device choice, on by default.
  final ValueNotifier<bool> systemOn = ValueNotifier(true);

  final _plugin = FlutterLocalNotificationsPlugin();
  AudioPlayer? _ding;
  AuthProvider? _auth;
  GoRouter? _router;
  bool _ready = false;
  int _id = 0;

  Future<void> init({required RealtimeService realtime, required AuthProvider auth, required GoRouter router}) async {
    if (!supported || _ready) return;
    _ready = true;
    _auth = auth;
    _router = router;
    final prefs = await SharedPreferences.getInstance();
    systemOn.value = prefs.getBool(_systemKey) ?? true;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          macOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
          windows: WindowsInitializationSettings(
            appName: 'Bài ca đi cùng năm tháng',
            appUserModelId: 'net.bcdcnt.music',
            guid: '6f1c2a4e-9b8d-4c3e-a7f5-2d1b0e9c8a71',
          ),
        ),
        onDidReceiveNotificationResponse: (_) => _openNotifications(),
      );
    } catch (e) {
      debugPrint('DesktopAlerts init failed: $e');
    }
    if (systemOn.value) await _askPermission();
    realtime.lastEvent.addListener(() {
      final ev = realtime.lastEvent.value;
      if (ev?['kind'] == 'notification') _onNotification(ev!['data'] as Map<String, dynamic>);
    });
  }

  Future<void> setSystemOn(bool v) async {
    systemOn.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_systemKey, v);
    if (v) await _askPermission();
  }

  Future<void> _askPermission() async {
    try {
      await _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, sound: false);
    } catch (_) {}
  }

  bool get _soundOn {
    final v = _auth?.user?['notification_sound'];
    return v == true || v == 1;
  }

  Future<void> _onNotification(Map<String, dynamic> n) async {
    if (_soundOn) _playDing();
    if (!systemOn.value) return;
    bool focused = false;
    try {
      focused = await windowManager.isFocused();
    } catch (_) {}
    if (focused) return; // the bell badge already shows it
    final text = (n['content'] ?? '').toString().replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    try {
      await _plugin.show(id: _id++ & 0x7fffffff, title: 'BCĐCNT', body: text.isEmpty ? 'Bạn có thông báo mới' : text);
    } catch (e) {
      debugPrint('DesktopAlerts show failed: $e');
    }
  }

  Future<void> _playDing() async {
    try {
      final p = _ding ??= AudioPlayer();
      await p.setAsset('assets/sounds/ding.wav');
      await p.seek(Duration.zero);
      await p.play();
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
    _router?.push('/thong-bao');
  }
}
