import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/theme.dart';
import '../constants/google_oauth.dart';
import '../services/auth.dart';
import '../services/google_signin_desktop.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:google_sign_in/google_sign_in.dart' as gsi;

// Desktop = where the loopback Google OAuth flow runs. The button is hidden
// elsewhere (mobile uses google_sign_in instead — not wired yet).
bool get _googleDesktop =>
    GoogleOAuth.isConfigured &&
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

// iPhone/iPad: native Google sheet via google_sign_in, once the iOS OAuth
// client is configured (GoogleOAuth.iosClientId + Info.plist URL scheme).
bool get _googleIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && GoogleOAuth.iosClientId.isNotEmpty;

bool get _googleAvailable => _googleDesktop || _googleIos;

bool _gsiReady = false;

/// iOS flow: Google's own sign-in sheet → ID token → loginByGoogle.
/// Returns null on success, '' if cancelled, or a message.
Future<String?> _runGoogleSignInIos(BuildContext context) async {
  try {
    final g = gsi.GoogleSignIn.instance;
    if (!_gsiReady) {
      await g.initialize(clientId: GoogleOAuth.iosClientId, serverClientId: GoogleOAuth.webClientId);
      _gsiReady = true;
    }
    final account = await g.authenticate(scopeHint: const ['email']);
    final idToken = account.authentication.idToken;
    if (idToken == null) return 'Google không trả về thông tin đăng nhập';
    if (!context.mounted) return '';
    return await context.read<AuthProvider>().loginByGoogle(idToken);
  } on gsi.GoogleSignInException catch (e) {
    return e.code == gsi.GoogleSignInExceptionCode.canceled ? '' : 'Đăng nhập Google thất bại';
  } catch (_) {
    return 'Đăng nhập Google thất bại';
  }
}

// Sign in with Apple: iPhone/iPad and Mac (required by App Store review
// whenever another third-party login is offered).
bool get _appleAvailable =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

/// Runs the Apple sheet and exchanges the identity token for our session.
/// Returns null on success, '' when the user cancelled, or a message.
Future<String?> _runAppleSignIn(BuildContext context) async {
  try {
    final cred = await SignInWithApple.getAppleIDCredential(scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName]);
    final token = cred.identityToken;
    if (token == null) return 'Apple không trả về thông tin đăng nhập';
    final name = [cred.familyName, cred.givenName].where((s) => s != null && s.trim().isNotEmpty).join(' ');
    if (!context.mounted) return '';
    return await context.read<AuthProvider>().loginByApple(token, name.isEmpty ? null : name);
  } on SignInWithAppleAuthorizationException catch (e) {
    return e.code == AuthorizationErrorCode.canceled ? '' : 'Đăng nhập Apple thất bại';
  } catch (_) {
    return 'Đăng nhập Apple thất bại';
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Login
// ──────────────────────────────────────────────────────────────────────────
class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key});
  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final _identity = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() { _identity.dispose(); _password.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    final err = await context.read<AuthProvider>().login(_identity.text.trim(), _password.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
    } else {
      setState(() { _error = err; _loading = false; });
    }
  }

  Future<void> _google() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    final err = await _runGoogleSignIn(context);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
    } else {
      setState(() { _error = err.isEmpty ? null : err; _loading = false; });
    }
  }

  Future<void> _apple() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    final err = await _runAppleSignIn(context);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
    } else {
      setState(() { _error = err.isEmpty ? null : err; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthShell(
      icon: Icons.person,
      title: 'Đăng nhập',
      subtitle: 'Tài khoản BCĐCNT',
      children: [
        _AuthField(
          controller: _identity,
          label: 'Tên đăng nhập hoặc email',
          icon: Icons.alternate_email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          plain: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _AuthField(
          controller: _password,
          label: 'Mật khẩu',
          icon: Icons.lock_outline,
          obscure: _obscure,
          autofillHints: const [AutofillHints.password],
          plain: true,
          textInputAction: TextInputAction.done,
          trailing: _ObscureToggle(obscure: _obscure, onTap: () => setState(() => _obscure = !_obscure)),
          onSubmitted: (_) => _submit(),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: _LinkButton(
              label: 'Quên mật khẩu?',
              onTap: _loading ? null : () {
                Navigator.pop(context);
                showDialog(context: context, builder: (_) => const ForgotPasswordDialog());
              },
            ),
          ),
        ),
        if (_error != null) _AuthError(_error!),
        const SizedBox(height: 12),
        _AuthPrimaryButton(label: 'Đăng nhập', loading: _loading, onTap: _submit),
        if (_googleAvailable || _appleAvailable) ...[
          const SizedBox(height: 14),
          const _OrDivider(),
          const SizedBox(height: 14),
          if (_appleAvailable) _AppleButton(loading: _loading, onTap: _apple),
          if (_appleAvailable && _googleAvailable) const SizedBox(height: 10),
          if (_googleAvailable) _GoogleButton(loading: _loading, onTap: _google),
        ],
        const SizedBox(height: 10),
        _AuthSwitch(
          prompt: 'Chưa có tài khoản?',
          actionLabel: 'Đăng ký',
          onTap: () {
            Navigator.pop(context);
            showDialog(context: context, builder: (_) => const RegisterDialog());
          },
        ),
      ],
    );
  }
}

/// Shared desktop Google sign-in: runs the OAuth flow then exchanges the ID
/// token for our session. Returns null on success or a message to display.
Future<String?> _runGoogleSignIn(BuildContext context) async {
  if (_googleIos) return _runGoogleSignInIos(context);
  try {
    final idToken = await GoogleSignInDesktop.signIn();
    if (!context.mounted) return 'Đã huỷ';
    return await context.read<AuthProvider>().loginByGoogle(idToken);
  } on GoogleSignInException catch (e) {
    return e.message;
  } catch (_) {
    return 'Đăng nhập Google thất bại';
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Register
// ──────────────────────────────────────────────────────────────────────────
class RegisterDialog extends StatefulWidget {
  const RegisterDialog({super.key});
  @override
  State<RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<RegisterDialog> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _loading = false;
  bool _obscure = true;
  bool _success = false;
  bool _needsActivation = false;

  @override
  void dispose() { _username.dispose(); _email.dispose(); _password.dispose(); _confirm.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() => _error = null);

    final username = _username.text.trim();
    final email = _email.text.trim();
    final pw = _password.text;
    final pw2 = _confirm.text;

    if (username.isEmpty || email.isEmpty || pw.isEmpty) {
      setState(() => _error = 'Vui lòng điền đầy đủ thông tin');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Email không hợp lệ');
      return;
    }
    if (pw.length < 6) {
      setState(() => _error = 'Mật khẩu phải từ 6 ký tự');
      return;
    }
    if (pw != pw2) {
      setState(() => _error = 'Mật khẩu xác nhận không khớp');
      return;
    }

    setState(() => _loading = true);
    final err = await context.read<AuthProvider>().signup(username, email, pw);
    if (!mounted) return;
    if (err == null) {
      // Auto-login after signup
      final loginErr = await context.read<AuthProvider>().login(email, pw);
      if (!mounted) return;
      if (loginErr == null) {
        Navigator.pop(context);
      } else {
        // Signup creates the account inactive and mails an activation code;
        // only say "check email" when login really refused for that reason.
        final needsActivation = loginErr.toLowerCase().contains('kích hoạt');
        setState(() { _success = true; _needsActivation = needsActivation; _loading = false; });
      }
    } else {
      setState(() { _error = err; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success) {
      return _AuthShell(
        icon: Icons.check_circle_outline,
        title: 'Đăng ký thành công',
        subtitle: _needsActivation
            ? 'Kiểm tra email để kích hoạt tài khoản, rồi đăng nhập.'
            : 'Đăng ký xong, vui lòng đăng nhập.',
        children: [
          _AuthPrimaryButton(
            label: 'Quay về đăng nhập',
            onTap: () {
              Navigator.pop(context);
              showDialog(context: context, builder: (_) => const LoginDialog());
            },
          ),
        ],
      );
    }
    return _AuthShell(
      icon: Icons.person_add_alt_1,
      title: 'Đăng ký',
      subtitle: 'Tạo tài khoản mới',
      children: [
        _AuthField(
          controller: _username, label: 'Tên đăng nhập', icon: Icons.account_circle_outlined,
          autofillHints: const [AutofillHints.newUsername], plain: true, textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _AuthField(
          controller: _email, label: 'Email', icon: Icons.alternate_email,
          keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], plain: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _AuthField(
          controller: _password, label: 'Mật khẩu (từ 6 ký tự)', icon: Icons.lock_outline, obscure: _obscure,
          autofillHints: const [AutofillHints.newPassword], plain: true, textInputAction: TextInputAction.next,
          trailing: _ObscureToggle(obscure: _obscure, onTap: () => setState(() => _obscure = !_obscure)),
        ),
        const SizedBox(height: 12),
        _AuthField(
          controller: _confirm, label: 'Nhập lại mật khẩu', icon: Icons.lock_outline, obscure: _obscure,
          autofillHints: const [AutofillHints.newPassword], plain: true, textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) _AuthError(_error!),
        const SizedBox(height: 12),
        _AuthPrimaryButton(label: 'Đăng ký', loading: _loading, onTap: _submit),
        const SizedBox(height: 4),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Khi đăng ký, bạn đồng ý với', style: body(TextStyle(fontSize: 14, color: AppColors.textSecondary))),
              _LinkButton(
                label: 'Chính sách & điều khoản',
                // In-app browser sheet: shows above this dialog and keeps
                // what the user already typed.
                onTap: () => launchUrl(Uri.parse('$siteUrl/dieu-khoan'), mode: LaunchMode.inAppBrowserView),
              ),
            ],
          ),
        ),
        if (_googleAvailable || _appleAvailable) ...[
          const SizedBox(height: 14),
          const _OrDivider(),
          const SizedBox(height: 14),
          if (_appleAvailable) _AppleButton(label: 'Đăng ký bằng Apple', loading: _loading, onTap: _apple),
          if (_appleAvailable && _googleAvailable) const SizedBox(height: 10),
          if (_googleAvailable) _GoogleButton(label: 'Đăng ký bằng Google', loading: _loading, onTap: _google),
        ],
        const SizedBox(height: 10),
        _AuthSwitch(
          prompt: 'Đã có tài khoản?',
          actionLabel: 'Đăng nhập',
          onTap: () {
            Navigator.pop(context);
            showDialog(context: context, builder: (_) => const LoginDialog());
          },
        ),
      ],
    );
  }

  Future<void> _google() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    final err = await _runGoogleSignIn(context);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
    } else {
      setState(() { _error = err.isEmpty ? null : err; _loading = false; });
    }
  }

  Future<void> _apple() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    final err = await _runAppleSignIn(context);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
    } else {
      setState(() { _error = err.isEmpty ? null : err; _loading = false; });
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Forgot password (3 steps)
// ──────────────────────────────────────────────────────────────────────────
class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({super.key});
  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final _identity = TextEditingController();
  final _code = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  int _step = 1; // 1: identity, 2: code, 3: new password, 4: success
  String? _error;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _identity.dispose(); _code.dispose(); _newPassword.dispose(); _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_loading) return;
    final id = _identity.text.trim();
    if (id.isEmpty) { setState(() => _error = 'Nhập email/username'); return; }
    setState(() { _loading = true; _error = null; });
    final err = await context.read<AuthProvider>().forgotPassword(id);
    if (!mounted) return;
    setState(() { _loading = false; });
    if (err == null) {
      setState(() { _step = 2; _error = null; });
    } else {
      setState(() => _error = err);
    }
  }

  Future<void> _verifyCode() async {
    if (_loading) return;
    final code = _code.text.trim();
    if (code.isEmpty) { setState(() => _error = 'Nhập mã xác thực'); return; }
    setState(() { _loading = true; _error = null; });
    final err = await context.read<AuthProvider>().validateCode(_identity.text.trim(), code);
    if (!mounted) return;
    setState(() { _loading = false; });
    if (err == null) {
      setState(() { _step = 3; _error = null; });
    } else {
      setState(() => _error = err);
    }
  }

  Future<void> _changePassword() async {
    if (_loading) return;
    final pw = _newPassword.text;
    final pw2 = _confirmPassword.text;
    if (pw.length < 6) { setState(() => _error = 'Mật khẩu phải từ 6 ký tự'); return; }
    if (pw != pw2) { setState(() => _error = 'Mật khẩu xác nhận không khớp'); return; }
    setState(() { _loading = true; _error = null; });
    final err = await context.read<AuthProvider>().changePassword(pw);
    if (!mounted) return;
    setState(() { _loading = false; });
    if (err == null) {
      setState(() { _step = 4; _error = null; });
    } else {
      setState(() => _error = err);
    }
  }

  String _stepDesc() {
    switch (_step) {
      case 1: return 'Nhập email hoặc username để nhận mã khôi phục';
      case 2: return 'Mã xác thực đã gửi. Kiểm tra email của bạn.';
      case 3: return 'Đặt mật khẩu mới';
      default: return 'Đổi mật khẩu thành công!';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 4) {
      return _AuthShell(
        icon: Icons.check_circle_outline,
        title: 'Hoàn tất',
        subtitle: _stepDesc(),
        children: [
          _AuthPrimaryButton(
            label: 'Đăng nhập ngay',
            onTap: () {
              Navigator.pop(context);
              showDialog(context: context, builder: (_) => const LoginDialog());
            },
          ),
        ],
      );
    }
    return _AuthShell(
      icon: Icons.lock_reset,
      title: 'Quên mật khẩu',
      subtitle: _stepDesc(),
      children: [
        // Stepper indicator
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: List.generate(3, (i) {
              final active = i + 1 <= _step;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: active ? AppColors.accent : AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
        if (_step == 1) ...[
          _AuthField(
            controller: _identity, label: 'Email hoặc tên đăng nhập', icon: Icons.alternate_email,
            keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email, AutofillHints.username],
            plain: true, textInputAction: TextInputAction.done, onSubmitted: (_) => _sendCode(),
          ),
          if (_error != null) _AuthError(_error!),
          const SizedBox(height: 12),
          _AuthPrimaryButton(label: 'Gửi mã', loading: _loading, onTap: _sendCode),
        ] else if (_step == 2) ...[
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Icon(Icons.mail_outline, color: AppColors.textMuted, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_identity.text.trim(), style: body(TextStyle(fontSize: 15, color: AppColors.text)), overflow: TextOverflow.ellipsis)),
            ]),
          ),
          _AuthField(
            controller: _code, label: 'Mã xác thực', icon: Icons.pin_outlined,
            keyboardType: TextInputType.number, autofillHints: const [AutofillHints.oneTimeCode],
            plain: true, textInputAction: TextInputAction.done, onSubmitted: (_) => _verifyCode(),
          ),
          if (_error != null) _AuthError(_error!),
          const SizedBox(height: 12),
          _AuthPrimaryButton(label: 'Xác thực', loading: _loading, onTap: _verifyCode),
          const SizedBox(height: 8),
          Center(child: _LinkButton(label: 'Gửi lại mã', onTap: _loading ? null : _sendCode)),
        ] else ...[
          _AuthField(
            controller: _newPassword, label: 'Mật khẩu mới', icon: Icons.lock_outline, obscure: _obscure,
            autofillHints: const [AutofillHints.newPassword], plain: true, textInputAction: TextInputAction.next,
            trailing: _ObscureToggle(obscure: _obscure, onTap: () => setState(() => _obscure = !_obscure)),
          ),
          const SizedBox(height: 12),
          _AuthField(
            controller: _confirmPassword, label: 'Nhập lại mật khẩu', icon: Icons.lock_outline, obscure: _obscure,
            autofillHints: const [AutofillHints.newPassword], plain: true, textInputAction: TextInputAction.done,
            onSubmitted: (_) => _changePassword(),
          ),
          if (_error != null) _AuthError(_error!),
          const SizedBox(height: 12),
          _AuthPrimaryButton(label: 'Đổi mật khẩu', loading: _loading, onTap: _changePassword),
        ],
        const SizedBox(height: 10),
        _AuthSwitch(
          prompt: '',
          actionLabel: '← Quay về đăng nhập',
          onTap: () {
            Navigator.pop(context);
            showDialog(context: context, builder: (_) => const LoginDialog());
          },
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Shared chrome
// ──────────────────────────────────────────────────────────────────────────
class _AuthShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _AuthShell({required this.icon, required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    // Dialog already lifts itself above the keyboard (viewInsets); the body
    // scrolls so the submit button stays reachable with the keyboard open
    // or at the largest text size.
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(colors: [Color(0xFF4A0C0C), Color(0xFF8E1F1F)]),
                          boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.3 * AppColors.shadowMul), blurRadius: 12, spreadRadius: -2)],
                        ),
                        child: Icon(icon, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title, style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
                            const SizedBox(height: 2),
                            Text(subtitle, style: body(TextStyle(fontSize: 15, color: AppColors.textSecondary))),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đóng',
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: Icon(Icons.close, color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final Widget? trailing;
  final void Function(String)? onSubmitted;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  /// Username / email / password / code: no autocorrect, no suggestions.
  final bool plain;
  const _AuthField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.trailing,
    this.onSubmitted,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.plain = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: obscure ? TextInputType.visiblePassword : keyboardType,
      autofillHints: autofillHints,
      autocorrect: !plain,
      enableSuggestions: !plain,
      textCapitalization: TextCapitalization.none,
      textInputAction: textInputAction,
      style: body(TextStyle(color: AppColors.text, fontSize: 17)),
      onSubmitted: onSubmitted,
      onEditingComplete: textInputAction == TextInputAction.next ? () => FocusScope.of(context).nextFocus() : null,
      decoration: InputDecoration(
        // Persistent label: stays visible above the text once typing starts.
        labelText: label,
        labelStyle: body(TextStyle(color: AppColors.textSecondary, fontSize: 16)),
        floatingLabelStyle: body(TextStyle(color: AppColors.accentFg, fontSize: 16, fontWeight: FontWeight.w600)),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
        suffixIcon: trailing,
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.accentFg, width: 2)),
      ),
    );
  }
}

class _ObscureToggle extends StatelessWidget {
  final bool obscure;
  final VoidCallback onTap;
  const _ObscureToggle({required this.obscure, required this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.textSecondary, size: 22),
        onPressed: onTap,
      );
}

/// Text link with a full 48pt tap target.
class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _LinkButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: AppColors.accentFg,
        ),
        child: Text(label, style: body(TextStyle(fontSize: 15, color: AppColors.accentFg, fontWeight: FontWeight.w700))),
      );
}

class _AuthError extends StatelessWidget {
  final String message;
  const _AuthError(this.message);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.errorText;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.error_outline, color: c, size: 18)),
              const SizedBox(width: 8),
              Expanded(child: Text(message, style: body(TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w600, height: 1.35)))),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthPrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;
  const _AuthPrimaryButton({required this.label, this.loading = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: loading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      child: loading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label, style: body(const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Divider(color: AppColors.border, height: 1)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text('hoặc', style: body(TextStyle(fontSize: 14, color: AppColors.textMuted))),
      ),
      Expanded(child: Divider(color: AppColors.border, height: 1)),
    ]);
  }
}

class _GoogleButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;
  const _GoogleButton({this.label = 'Tiếp tục với Google', this.loading = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: loading ? null : onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFDADCE0)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Blue "G" — recognizable without bundling an asset.
            const Text('G', style: TextStyle(fontSize: 20, height: 1, fontWeight: FontWeight.w800, color: Color(0xFF4285F4))),
            const SizedBox(width: 10),
            Text(label, style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1F1F1F)))),
          ],
        ),
      ),
    );
  }
}

/// Black "Sign in with Apple" button per Apple's guidelines.
class _AppleButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;
  const _AppleButton({this.label = 'Tiếp tục với Apple', this.loading = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: loading ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.black54,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.apple, size: 22, color: Colors.white),
            const SizedBox(width: 8),
            Text(label, style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white))),
          ],
        ),
      ),
    );
  }
}

class _AuthSwitch extends StatelessWidget {
  final String prompt;
  final String actionLabel;
  final VoidCallback onTap;
  const _AuthSwitch({required this.prompt, required this.actionLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (prompt.isNotEmpty) Text(prompt, style: body(TextStyle(fontSize: 15, color: AppColors.textSecondary))),
          _LinkButton(label: actionLabel, onTap: onTap),
        ],
      ),
    );
  }
}
