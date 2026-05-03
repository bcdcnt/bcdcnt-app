import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/auth.dart';

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

  @override
  Widget build(BuildContext context) {
    return _AuthShell(
      icon: Icons.person,
      title: 'Đăng nhập',
      subtitle: 'Tài khoản BCĐCNT',
      children: [
        _AuthField(
          controller: _identity,
          hint: 'Username hoặc email',
          icon: Icons.alternate_email,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 10),
        _AuthField(
          controller: _password,
          hint: 'Mật khẩu',
          icon: Icons.lock_outline,
          obscure: _obscure,
          trailing: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.textMuted, size: 18),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          onSubmitted: (_) => _submit(),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading ? null : () {
                Navigator.pop(context);
                showDialog(context: context, builder: (_) => const ForgotPasswordDialog());
              },
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text('Quên mật khẩu?', style: body(TextStyle(fontSize: 12, color: AppColors.accentLight, fontWeight: FontWeight.w600))),
            ),
          ),
        ),
        if (_error != null) _AuthError(_error!),
        const SizedBox(height: 12),
        _AuthPrimaryButton(label: 'Đăng nhập', loading: _loading, onTap: _submit),
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
        setState(() { _success = true; _loading = false; });
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
        subtitle: 'Kiểm tra email để kích hoạt tài khoản',
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
        _AuthField(controller: _username, hint: 'Username', icon: Icons.account_circle_outlined),
        const SizedBox(height: 10),
        _AuthField(controller: _email, hint: 'Email', icon: Icons.alternate_email),
        const SizedBox(height: 10),
        _AuthField(
          controller: _password, hint: 'Mật khẩu (≥ 6 ký tự)', icon: Icons.lock_outline, obscure: _obscure,
          trailing: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.textMuted, size: 18),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        const SizedBox(height: 10),
        _AuthField(
          controller: _confirm, hint: 'Xác nhận mật khẩu', icon: Icons.lock_outline, obscure: _obscure,
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) _AuthError(_error!),
        const SizedBox(height: 12),
        _AuthPrimaryButton(label: 'Đăng ký', loading: _loading, onTap: _submit),
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
          _AuthField(controller: _identity, hint: 'Email hoặc username', icon: Icons.alternate_email, onSubmitted: (_) => _sendCode()),
          if (_error != null) _AuthError(_error!),
          const SizedBox(height: 12),
          _AuthPrimaryButton(label: 'Gửi mã', loading: _loading, onTap: _sendCode),
        ] else if (_step == 2) ...[
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Icon(Icons.mail_outline, color: AppColors.textMuted, size: 14),
              const SizedBox(width: 6),
              Expanded(child: Text(_identity.text.trim(), style: body(TextStyle(fontSize: 12, color: AppColors.text)), overflow: TextOverflow.ellipsis)),
            ]),
          ),
          _AuthField(controller: _code, hint: 'Mã xác thực', icon: Icons.pin_outlined, onSubmitted: (_) => _verifyCode()),
          if (_error != null) _AuthError(_error!),
          const SizedBox(height: 12),
          _AuthPrimaryButton(label: 'Xác thực', loading: _loading, onTap: _verifyCode),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _loading ? null : _sendCode,
              child: Text('Gửi lại mã', style: body(TextStyle(fontSize: 12, color: AppColors.accentLight, fontWeight: FontWeight.w600))),
            ),
          ),
        ] else ...[
          _AuthField(
            controller: _newPassword, hint: 'Mật khẩu mới', icon: Icons.lock_outline, obscure: _obscure,
            trailing: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.textMuted, size: 18),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: 10),
          _AuthField(controller: _confirmPassword, hint: 'Xác nhận mật khẩu', icon: Icons.lock_outline, obscure: _obscure, onSubmitted: (_) => _changePassword()),
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
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
                      boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: -2)],
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: display(TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text))),
                        const SizedBox(height: 2),
                        Text(subtitle, maxLines: 2, style: body(TextStyle(fontSize: 11, color: AppColors.textMuted))),
                      ],
                    ),
                  ),
                  IconButton(icon: Icon(Icons.close, color: AppColors.textMuted), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 18),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? trailing;
  final void Function(String)? onSubmitted;
  const _AuthField({required this.controller, required this.hint, required this.icon, this.obscure = false, this.trailing, this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: body(TextStyle(color: AppColors.text, fontSize: 14)),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: body(TextStyle(color: AppColors.textMuted, fontSize: 13)),
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 18),
        suffixIcon: trailing,
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.accent)),
      ),
    );
  }
}

class _AuthError extends StatelessWidget {
  final String message;
  const _AuthError(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text(message, style: body(const TextStyle(color: AppColors.error, fontSize: 12)))),
          ],
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      child: loading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label, style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prompt.isNotEmpty) Text('$prompt ', style: body(TextStyle(fontSize: 12, color: AppColors.textMuted))),
          GestureDetector(
            onTap: onTap,
            child: Text(actionLabel, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accentLight))),
          ),
        ],
      ),
    );
  }
}
