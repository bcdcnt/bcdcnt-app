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

  static bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;
}
