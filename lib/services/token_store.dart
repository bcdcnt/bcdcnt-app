import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the access/refresh tokens live: the platform's secure store
/// (Keychain on iOS/macOS, Keystore-backed on Android, DPAPI on Windows,
/// libsecret on Linux) instead of SharedPreferences (a plain plist/XML file).
///
/// Falls back to SharedPreferences where the secure store is unavailable:
/// web (no real secure storage there), or a Linux snap whose
/// password-manager-service plug is not connected. Tokens saved by older
/// versions in SharedPreferences move to the secure store on first read.
class TokenStore {
  static const _access = 'access_token';
  static const _refresh = 'refresh_token';

  static const _secure = FlutterSecureStorage(
    // The legacy file keychain works in the sandbox without the
    // keychain-access-groups entitlement (which needs team signing).
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static Future<({String? access, String? refresh})> read() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyAccess = prefs.getString(_access);
    final legacyRefresh = prefs.getString(_refresh);
    if (kIsWeb) return (access: legacyAccess, refresh: legacyRefresh);
    try {
      final access = await _secure.read(key: _access);
      final refresh = await _secure.read(key: _refresh);
      if (access != null || refresh != null) return (access: access, refresh: refresh);
      if (legacyAccess != null || legacyRefresh != null) {
        await write(legacyAccess, legacyRefresh);
      }
    } catch (_) {
      // Secure store unavailable: keep using SharedPreferences.
    }
    return (access: legacyAccess, refresh: legacyRefresh);
  }

  /// Saves both tokens; a null [refresh] removes the stored one.
  static Future<void> write(String? access, String? refresh) async {
    final prefs = await SharedPreferences.getInstance();
    if (!kIsWeb) {
      try {
        await _put(access, refresh);
        await prefs.remove(_access);
        await prefs.remove(_refresh);
        return;
      } catch (_) {
        // Fall through to SharedPreferences.
      }
    }
    access == null ? await prefs.remove(_access) : await prefs.setString(_access, access);
    refresh == null ? await prefs.remove(_refresh) : await prefs.setString(_refresh, refresh);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_access);
    await prefs.remove(_refresh);
    if (kIsWeb) return;
    try {
      await _secure.delete(key: _access);
      await _secure.delete(key: _refresh);
    } catch (_) {}
  }

  static Future<void> _put(String? access, String? refresh) async {
    access == null ? await _secure.delete(key: _access) : await _secure.write(key: _access, value: access);
    refresh == null ? await _secure.delete(key: _refresh) : await _secure.write(key: _refresh, value: refresh);
  }
}
