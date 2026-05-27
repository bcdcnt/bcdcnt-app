import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Check GitHub Releases for a newer desktop build than the one currently
/// running. We use the GitHub Releases API directly so there's no separate
/// version manifest to host — the release tag pushed by CI is the source
/// of truth.
///
/// Only runs on the three desktop platforms (Windows, macOS, Linux). Mobile
/// updates go through the App Store / Play Store and don't need this flow;
/// web is always live.
class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String? releaseNotes;
  final String releaseUrl;

  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseUrl,
    this.releaseNotes,
  });
}

class UpdateCheck {
  // Public repo, no auth needed. Anonymous calls are rate-limited to 60/h
  // per IP — well above what a single client triggers (once per app start).
  static const _releasesApi =
      "https://api.github.com/repos/bcdcnt/bcdcnt-app/releases/latest";

  // shared_preferences key — remember which version the user already
  // dismissed so we don't re-prompt for the same release every launch.
  static const _dismissedKey = "bcdcnt_update_dismissed_version";

  /// Desktop + sideloaded Android get distributed via GitHub Releases.
  /// iOS is store-managed (TestFlight / App Store handle updates) and
  /// web is server-rendered, so checking those would only produce false
  /// positives.
  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux ||
        Platform.isAndroid;
  }

  /// Map platform to the artifact filename that CI uploads as a release
  /// asset. CI publishes `bcdcnt-windows.zip` / `bcdcnt-macos.zip` /
  /// `bcdcnt-linux.zip` / `bcdcnt-android.apk`.
  static String? _assetNameForPlatform() {
    if (kIsWeb) return null;
    if (Platform.isWindows) return "bcdcnt-windows";
    if (Platform.isMacOS) return "bcdcnt-macos";
    if (Platform.isLinux) return "bcdcnt-linux";
    if (Platform.isAndroid) return "bcdcnt-android";
    return null;
  }

  /// Returns the new version info if one is available and the user hasn't
  /// already dismissed it. Returns null when up to date, unsupported, or on
  /// any network/parsing failure (we don't want a flaky GitHub API to
  /// surface red banners to users).
  static Future<UpdateInfo?> check() async {
    if (!isSupported) return null;
    try {
      final pkg = await PackageInfo.fromPlatform();
      final current = pkg.version; // e.g. "1.0.0" — from pubspec `version:`

      final res = await http
          .get(Uri.parse(_releasesApi), headers: {"Accept": "application/vnd.github+json"})
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data["tag_name"] as String?)?.trim() ?? "";
      // Tags conventionally start with "v"; strip so we can semver-compare
      // against pubspec's "1.0.0" form.
      final latest = tag.startsWith("v") ? tag.substring(1) : tag;
      if (latest.isEmpty) return null;
      if (!_isNewer(latest, current)) return null;

      // Skip if the user dismissed exactly this version already.
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_dismissedKey) == latest) return null;

      final assetName = _assetNameForPlatform();
      final assets = (data["assets"] as List?) ?? const [];
      // The asset filename CI uploads is "bcdcnt-windows.zip" etc., so we
      // accept any asset whose name contains the platform stem. This
      // tolerates future renames like "bcdcnt-windows-x64.zip".
      Map<String, dynamic>? matched;
      for (final a in assets) {
        if (a is Map<String, dynamic>) {
          final name = (a["name"] as String?)?.toLowerCase() ?? "";
          if (assetName != null && name.contains(assetName)) {
            matched = a;
            break;
          }
        }
      }
      if (matched == null) return null;
      final url = matched["browser_download_url"] as String?;
      if (url == null) return null;

      return UpdateInfo(
        latestVersion: latest,
        downloadUrl: url,
        releaseUrl: data["html_url"] as String? ?? "",
        releaseNotes: data["body"] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Remember that the user dismissed this specific version so the banner
  /// stays hidden until the next release ships.
  static Future<void> dismiss(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedKey, version);
  }

  /// Numeric semver-ish comparison. Both inputs are dot-separated decimal
  /// segments ("1.0.0" / "1.2"). Anything non-numeric falls back to false
  /// (treat as not-newer) so an unexpected tag like "nightly-abc" doesn't
  /// spuriously prompt for an update.
  static bool _isNewer(String latest, String current) {
    final l = latest.split(".").map(int.tryParse).toList();
    final c = current.split(".").map(int.tryParse).toList();
    if (l.any((x) => x == null) || c.any((x) => x == null)) return false;
    final n = l.length > c.length ? l.length : c.length;
    for (var i = 0; i < n; i++) {
      final lv = i < l.length ? l[i]! : 0;
      final cv = i < c.length ? c[i]! : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }
}
