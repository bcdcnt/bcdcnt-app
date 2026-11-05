/// Google OAuth config for desktop "Sign in with Google".
///
/// Credentials are injected at BUILD time via --dart-define (kept out of source
/// control). The convenient way is a gitignored JSON file:
///
///   flutter run   -d macos --dart-define-from-file=google_oauth.json
///   flutter build macos     --dart-define-from-file=google_oauth.json
///
/// where google_oauth.json (see google_oauth.example.json) holds:
///   { "GOOGLE_DESKTOP_CLIENT_ID": "...", "GOOGLE_DESKTOP_CLIENT_SECRET": "..." }
///
/// Or pass them inline: --dart-define=GOOGLE_DESKTOP_CLIENT_ID=...
/// A build without these leaves the values empty → the Google button hides.
///
/// Setup (Google Cloud Console → APIs & Services → Credentials):
///   1. Create an OAuth client ID of type **Desktop app**.
///   2. Put its Client ID + Client secret into google_oauth.json.
///   3. No redirect URI to register — desktop clients accept any
///      `http://127.0.0.1:<port>` loopback automatically.
///   4. OAuth consent screen: scopes `openid email profile`; add test users
///      while the app is in "Testing".
///
/// The backend (`loginByGoogle`) verifies the ID token via Google's tokeninfo
/// endpoint and keys off the email only — it does NOT check the audience — so
/// this dedicated desktop client works without any backend change.
class GoogleOAuth {
  /// e.g. "454137046742-xxxxxxxx.apps.googleusercontent.com"
  static const String clientId =
      String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');

  /// e.g. "GOCSPX-xxxxxxxxxxxxxxxx"
  static const String clientSecret =
      String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');

  static const List<String> scopes = ['openid', 'email', 'profile'];

  /// iPhone/iPad "Sign in with Google" (google_sign_in). OAuth client of
  /// type **iOS** for bundle net.bcdcnt.music in the same Google Cloud
  /// project (454137046742) — client IDs aren't secret. Info.plist must
  /// also list its reversed form as a URL scheme. Empty = button hidden.
  static const String iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID', defaultValue: '454137046742-4001925oiid99dhkfr08cdmd5dq6s8or.apps.googleusercontent.com');

  /// The website's client. Passed as serverClientId so the ID token the
  /// phone gets is addressed to the same client as the web's tokens; the
  /// backend accepts any client of project 454137046742 either way.
  static const String webClientId = '454137046742-racuvmqlqadldcummhfcg1eerknrumq6.apps.googleusercontent.com';

  static bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;
}
