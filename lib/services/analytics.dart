import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight GA4 client — sends events to Google's Measurement
/// Protocol endpoint directly, no Firebase. Re-uses the same
/// `G-Y6KYPD469Y` property the web app reports against so desktop /
/// Android usage shows up in the same GA dashboards instead of needing
/// a parallel property.
///
/// Identity: a UUID generated once and persisted to SharedPreferences
/// acts as `client_id`. Not tied to the logged-in BCĐCNT user; if the
/// same device signs in as different users they all roll up under one
/// client_id which is fine for the cohort-level reporting we care
/// about. Pass the logged-in user_id through the `user_id` field of
/// individual events when we want per-user funnels.
///
/// Build-time secret: GA4_API_SECRET is injected via --dart-define in
/// CI so the value isn't checked into the repo. Without it the
/// service no-ops; local dev builds happily run analytics-free.
class Analytics {
  static const _measurementId = "G-Y6KYPD469Y";
  static const _apiSecret = String.fromEnvironment("GA4_API_SECRET");
  static const _endpoint = "https://www.google-analytics.com/mp/collect";
  static const _clientIdKey = "bcdcnt_ga_client_id";

  static String? _clientId;
  static String? _appVersion;
  static String? _appPlatform;
  static bool _initStarted = false;
  static final Completer<void> _initDone = Completer<void>();

  /// Idempotent — safe to call from main() before the first event.
  /// Loads / generates the persistent client_id and captures
  /// app/platform metadata once so each event doesn't re-read them.
  static Future<void> init() async {
    if (_initStarted) return _initDone.future;
    _initStarted = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_clientIdKey);
      if (id == null || id.isEmpty) {
        id = _newClientId();
        await prefs.setString(_clientIdKey, id);
      }
      _clientId = id;
      final pkg = await PackageInfo.fromPlatform();
      _appVersion = pkg.version;
      _appPlatform = _platformLabel();
    } catch (_) {
      // Initialisation failures shouldn't crash the app — analytics is
      // best-effort. _clientId stays null → logEvent silently skips.
    }
    if (!_initDone.isCompleted) _initDone.complete();
  }

  static bool get _enabled => _apiSecret.isNotEmpty && _clientId != null;

  /// GA4 client_id format is "<random>.<timestamp>" by web convention
  /// — easier to debug in real-time view if it looks like the gtag.js
  /// values rather than an opaque UUID.
  static String _newClientId() {
    final r = Random.secure();
    final randPart = List.generate(10, (_) => r.nextInt(10)).join();
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return "$randPart.$ts";
  }

  static String _platformLabel() {
    if (kIsWeb) return "web";
    if (Platform.isWindows) return "windows";
    if (Platform.isMacOS) return "macos";
    if (Platform.isLinux) return "linux";
    if (Platform.isAndroid) return "android";
    if (Platform.isIOS) return "ios";
    return "unknown";
  }

  /// Fire a custom event. Adds `platform` + `app_version` automatically
  /// so dashboards can split by build without every call having to
  /// remember to include them.
  static Future<void> logEvent(String name, [Map<String, Object?>? params]) async {
    await _initDone.future;
    if (!_enabled) return;
    final merged = <String, Object?>{
      "platform": _appPlatform,
      "app_version": _appVersion,
      ...?params,
    };
    // GA4 rejects null values; drop them before serialising.
    merged.removeWhere((_, v) => v == null);
    final body = jsonEncode({
      "client_id": _clientId,
      "events": [
        {"name": name, "params": merged},
      ],
    });
    try {
      await http
          .post(
            Uri.parse("$_endpoint?measurement_id=$_measurementId&api_secret=$_apiSecret"),
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Network failures are non-fatal for analytics; swallow and move on.
    }
  }

  /// Convenience for the GA4-canonical `screen_view` event so GoRouter
  /// listeners don't need to re-spell the param keys.
  static Future<void> logScreenView(String screenName) =>
      logEvent("screen_view", {"screen_name": screenName});

  /// Stamp the logged-in user against subsequent events. Pass null on
  /// logout so the next session doesn't keep attributing to them.
  static Future<void> setUserId(String? userId) async {
    await _initDone.future;
    if (!_enabled) return;
    final body = jsonEncode({
      "client_id": _clientId,
      "user_id": userId,
      "user_properties": {
        if (userId != null) "logged_in": {"value": "true"},
      },
      "events": [
        {"name": "user_identify", "params": {"platform": _appPlatform}},
      ],
    });
    try {
      await http
          .post(
            Uri.parse("$_endpoint?measurement_id=$_measurementId&api_secret=$_apiSecret"),
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}
