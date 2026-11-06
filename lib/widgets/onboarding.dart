import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import '../services/theme_provider.dart';
import 'auth_dialogs.dart';
import 'ui.dart';

const _seenKey = 'onboarding_v1_seen';
bool _showing = false;

/// Shown once on a phone's first launch: pick a comfortable text size, learn
/// the two gestures that matter (tap a song, tap the red bar), and why an
/// account helps. Three short steps, skippable at any point.
Future<void> maybeShowOnboarding(BuildContext context) async {
  if (_showing) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_seenKey) == true || !context.mounted) return;
  // Members updating the app already know their way around (wait for the
  // saved login to be restored before deciding).
  final auth = context.read<AuthProvider>();
  for (var i = 0; i < 25 && auth.loading; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  if (!context.mounted) return;
  if (auth.isAuthenticated) {
    await prefs.setBool(_seenKey, true);
    return;
  }
  _showing = true;
  final nav = Navigator.of(context, rootNavigator: true);
  final wantsLogin = await nav.push<bool>(
    MaterialPageRoute<bool>(fullscreenDialog: true, builder: (_) => const _Onboarding()),
  );
  // Marked seen only once finished or skipped, so a crash mid-way shows it again.
  await prefs.setBool(_seenKey, true);
  _showing = false;
  if (wantsLogin == true && nav.mounted) {
    showDialog(context: nav.context, builder: (_) => const LoginDialog());
  }
}

class _Onboarding extends StatefulWidget {
  const _Onboarding();

  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  final _pages = PageController();
  int _i = 0;

  void _next() {
    if (_i < 2) {
      _pages.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authed = context.select<AuthProvider, bool>((a) => a.isAuthenticated);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
              child: Text('Bỏ qua', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _i = i),
              children: [
                _step(
                  icon: Icons.text_fields_rounded,
                  title: 'Chọn cỡ chữ dễ đọc',
                  text: 'Chọn cỡ chữ bạn thấy thoải mái. Có thể đổi lại bất cứ lúc nào trong Cài đặt.',
                  extra: const _ScalePicker(),
                ),
                _step(
                  icon: Icons.touch_app_rounded,
                  title: 'Chạm vào bài là nghe',
                  text: 'Chạm vào tên bài hát để nghe ngay. Thanh màu đỏ ở dưới màn hình là bài đang phát: chạm vào để xem lời, chỉnh bài, hẹn giờ tắt.\n\nNút ⋮ cạnh mỗi bài để thêm vào playlist, tải về, chia sẻ. Bài đã tải về nằm ở Thư viện → Đã tải về, nghe được cả khi không có mạng.',
                ),
                _step(
                  icon: Icons.favorite_rounded,
                  title: authed ? 'Bạn đã sẵn sàng' : 'Có tài khoản để lưu lại',
                  text: authed
                      ? 'Bấm ♥ để lưu bài yêu thích, “Tải về” để nghe khi không có mạng. Chúc bạn nghe nhạc vui!'
                      : 'Đăng nhập để lưu bài yêu thích, theo dõi nhạc sĩ, bình luận cùng mọi người. Không đăng nhập vẫn nghe được tất cả các bài.',
                  extra: authed
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: PillButton(
                            label: 'Đăng nhập',
                            icon: Icons.login_rounded,
                            onTap: () => Navigator.of(context).pop(true),
                          ),
                        ),
                ),
              ],
            ),
          ),
          Semantics(
            label: 'Bước ${_i + 1} trên 3',
            excludeSemantics: true,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < 3; k++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: k == _i ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(color: k == _i ? AppColors.accent : AppColors.border, borderRadius: BorderRadius.circular(4)),
              ),
          ])),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: SizedBox(
              width: double.infinity,
              child: PillButton(label: _i < 2 ? 'Tiếp tục' : 'Bắt đầu nghe', primary: _i < 2 || authed, onTap: _next),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _step({required IconData icon, required String title, required String text, Widget? extra}) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 36, color: AppColors.accentLight),
          ),
          const SizedBox(height: 24),
          Text(title, style: display(TextStyle(fontSize: 26, height: 1.2, fontWeight: FontWeight.w800, color: AppColors.text))),
          const SizedBox(height: 12),
          Text(text, style: body(TextStyle(fontSize: 17, height: 1.55, fontWeight: FontWeight.w500, color: AppColors.textSecondary))),
          if (extra != null) extra,
        ]),
      );
}

class _ScalePicker extends StatelessWidget {
  const _ScalePicker();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final e in kTextScaleLabels.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: theme.textScaleKey == e.key ? AppColors.accentSoft : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => theme.setTextScale(e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.textScaleKey == e.key ? AppColors.accent : Colors.transparent, width: 2),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text('${e.value}: Bài ca đi cùng năm tháng',
                          textScaler: TextScaler.linear((WidgetsBinding.instance.platformDispatcher.textScaleFactor * (kTextScales[e.key] ?? 1)).clamp(0.9, 2.0)),
                          style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
                    ),
                    if (theme.textScaleKey == e.key) Icon(Icons.check_circle_rounded, color: AppColors.accent),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
