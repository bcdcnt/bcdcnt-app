import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:window_manager/window_manager.dart';
import 'auth.dart';
import 'imgcdn.dart';
import 'notification_route.dart';
import 'realtime.dart';

/// Desktop side of a new notification. Follows the account's Cài đặt ›
/// Thông báo like phone push does (one setting for every device, 22/11):
/// kinds switched off are skipped, quiet hours make it silent, and a short
/// ding plays when `notification_sound` is on,
/// and a macOS / Windows / Linux banner while the app is open but not in
/// front (canvas Desktop_BannerThongBao, 22/11): title = who did it, their
/// avatar (Windows/Linux in place of the app logo, macOS as the picture on
/// the right — macOS keeps the app icon), one banner per event, and a click
/// opens the page itself like a phone push. Phones get real push instead
/// (PushService), so this stays off there.
class DesktopAlerts {
  DesktopAlerts._();
  static final instance = DesktopAlerts._();

  static bool get supported => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

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
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          macOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
          windows: WindowsInitializationSettings(
            appName: 'Bài ca đi cùng năm tháng',
            appUserModelId: 'net.bcdcnt.music',
            guid: '6f1c2a4e-9b8d-4c3e-a7f5-2d1b0e9c8a71',
          ),
          linux: LinuxInitializationSettings(defaultActionName: 'Mở'),
        ),
        onDidReceiveNotificationResponse: (r) => _open(r.payload),
      );
    } catch (e) {
      debugPrint('DesktopAlerts init failed: $e');
    }
    await _askPermission();
    // Screenshot/automation hook: BCDCNT_FAKE_NOTIF=1 shows one sample banner
    // a few seconds after launch (even when the window is in front). No-op
    // in normal use.
    final fake = Platform.environment['BCDCNT_FAKE_NOTIF'];
    if (fake != null && fake.isNotEmpty) {
      Future.delayed(const Duration(seconds: 4), () => _onNotification({
            'content': 'đã trả lời bình luận của bạn trong “Như có Bác trong ngày đại thắng”',
            'action': 'comment',
            'object_type': 'song',
            'object_id': '446',
            'sender': {'username': 'Anh Thư', 'avatar': {'url': fake.startsWith('http') ? fake : null}},
          }, force: true));
    }
    realtime.lastEvent.addListener(() {
      final ev = realtime.lastEvent.value;
      if (ev?['kind'] == 'notification') _onNotification(ev!['data'] as Map<String, dynamic>);
    });
  }

  /// This computer blocks the app's banners (macOS: System Settings ›
  /// Notifications). Windows/Linux can't be asked → false.
  Future<bool> blocked() async {
    if (!supported || !Platform.isMacOS) return false;
    try {
      final o = await _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()?.checkPermissions();
      return o != null && !o.isEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Opens the OS page where the app's notifications are turned on.
  static Uri get systemSettingsUri => Platform.isMacOS
      ? Uri.parse('x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=net.bcdcnt.music')
      : Uri.parse('ms-settings:notifications');

  /// Same grouping as the API's PushSender::categoryOf.
  static String categoryOf(String action) => switch (action) {
        'comment' || 'mention' || 'open_comment' || 'answer_poll' => 'reply',
        'love_comment' => 'like',
        'followed_new_song' || 'song_created' => 'follow',
        'message' => 'message',
        'admin_notification' => 'admin',
        _ => 'review',
      };

  Map get _prefs => _auth?.user?['push_prefs'] is Map ? _auth!.user!['push_prefs'] as Map : const {};

  /// Quiet hours of the account (Vietnam time), like the API.
  bool get _quietNow {
    int? h(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    final start = h(_prefs['quiet_start']), end = h(_prefs['quiet_end']);
    if (start == null || end == null || start == end) return false;
    final now = DateTime.now().toUtc().add(const Duration(hours: 7)).hour;
    return start < end ? (now >= start && now < end) : (now >= start || now < end);
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

  Future<void> _onNotification(Map<String, dynamic> n, {bool force = false}) async {
    // The account's switches apply here too (one setting for every device);
    // BQT notices can't be switched off. Quiet hours: banner, but silent.
    final category = categoryOf((n['action'] ?? '').toString());
    if (category != 'admin' && _prefs[category] == false) return;
    final quiet = _quietNow;
    if (_soundOn && !quiet) _playDing();
    bool focused = false;
    try {
      focused = await windowManager.isFocused();
    } catch (_) {}
    if (focused && !force) return; // the bell badge already shows it
    String clean(Object? v) => (v ?? '').toString().replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final sender = n['sender'] is Map ? n['sender'] as Map : null;
    final name = clean(sender?['username']);
    final text = clean(n['content']);
    final avatarUrl = sender?['avatar'] is Map ? sender!['avatar']['url']?.toString() : null;
    final avatar = avatarUrl == null || avatarUrl.isEmpty ? null : await _avatarFile(avatarUrl);
    // Windows MSIX (Microsoft Store): toasts load https images themselves but
    // only partly support file paths; the plain .exe build needs the file.
    final winAvatar = avatarUrl == null || avatarUrl.isEmpty
        ? null
        : _isMsix
            ? Uri.parse(cdnImg(avatarUrl, 192, height: 192))
            : (avatar == null ? null : Uri.file(avatar));
    final payload = jsonEncode({
      for (final k in ['code', 'action', 'object_type', 'object_id', 'extra']) if (n[k] != null) k: n[k].toString(),
    });
    final details = NotificationDetails(
      macOS: DarwinNotificationDetails(presentSound: false, attachments: avatar == null ? null : [DarwinNotificationAttachment(avatar)]),
      windows: WindowsNotificationDetails(
        audio: quiet ? WindowsNotificationAudio.silent() : null,
        images: [
          if (winAvatar != null) WindowsImage(winAvatar, altText: name, placement: WindowsImagePlacement.appLogoOverride, crop: WindowsImageCrop.circle),
        ],
      ),
      linux: LinuxNotificationDetails(suppressSound: quiet, icon: avatar == null ? null : FilePathLinuxIcon(avatar)),
    );
    try {
      await _plugin.show(
        id: _id++ & 0x7fffffff,
        title: name.isEmpty ? 'BCĐCNT' : name,
        body: text.isEmpty ? 'Bạn có thông báo mới' : text,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('DesktopAlerts show failed: $e');
    }
  }

  /// Installed from the Microsoft Store (MSIX package under WindowsApps).
  static bool get _isMsix => Platform.isWindows && Platform.resolvedExecutable.toLowerCase().contains(r'\windowsapps\');

  /// The sender's avatar as a small local file (banners can't load URLs on
  /// macOS/Linux). Kept by URL; macOS moves an attachment into its own store,
  /// so each banner gets its own copy. Null when it can't be fetched.
  Future<String?> _avatarFile(String url) async {
    try {
      // Linux Snap: /tmp is private to the snap, so the notification daemon
      // (outside it) couldn't read the picture; app-support lives under
      // ~/snap/… which it can.
      final base = Platform.isLinux ? await getApplicationSupportDirectory() : await getTemporaryDirectory();
      final dir = Directory('${base.path}/bcdcnt_avatars');
      if (!await dir.exists()) await dir.create(recursive: true);
      final key = url.hashCode.toUnsigned(32).toRadixString(16);
      final cached = File('${dir.path}/$key.jpg');
      if (!await cached.exists()) {
        final res = await http.get(Uri.parse(cdnImg(url, 192, height: 192))).timeout(const Duration(seconds: 5));
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
        await cached.writeAsBytes(res.bodyBytes);
      }
      if (!Platform.isMacOS) return cached.path;
      final copy = await cached.copy('${dir.path}/$key-$_id.jpg');
      return copy.path;
    } catch (_) {
      return null;
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

  /// Click on a banner: bring the window up and open what it is about
  /// (same rules as a phone push / the Thông báo list), else the list.
  Future<void> _open(String? payload) async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
    Map<String, dynamic> data = {};
    try {
      final d = payload == null || payload.isEmpty ? null : jsonDecode(payload);
      if (d is Map) data = Map<String, dynamic>.from(d);
    } catch (_) {}
    final code = data['code']?.toString();
    final auth = _auth;
    if (code != null && code.isNotEmpty && auth != null && auth.isAuthenticated) {
      auth.authedMutate(r'mutation($code: String!) { markAsRead(code: $code) }', {'code': code}).catchError((_) => <String, dynamic>{});
    }
    final t = data.isEmpty ? null : notificationRoute(data);
    if (t != null) {
      _router?.push(t.path, extra: t.extra);
    } else {
      _router?.push('/thong-bao');
    }
  }
}
