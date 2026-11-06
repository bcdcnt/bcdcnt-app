import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import '../services/push.dart';
import '../services/friendly_error.dart';

/// Cài đặt → Thông báo điện thoại: system permission, "Bài hát của ngày"
/// (guests too), and for members one switch per kind + quiet hours
/// (user.push_prefs on the API).
class PushSettings extends StatefulWidget {
  const PushSettings({super.key});

  @override
  State<PushSettings> createState() => _PushSettingsState();
}

class _PushSettingsState extends State<PushSettings> with WidgetsBindingObserver {
  AuthorizationStatus? _status;
  bool _statusLoaded = false; // false until the first status() returns
  bool _daily = true;
  Map<String, dynamic>? _prefs; // null until loaded (or API not ready yet)
  bool _prefsFailed = false;

  static const _kinds = [
    ('reply', Icons.chat_bubble_outline, 'Trả lời & nhắc tên', 'Có người trả lời, nhắc đến bạn, trả lời bình chọn'),
    ('like', Icons.favorite_border, 'Lượt thích', 'Có người thích bình luận của bạn (gộp lại, không dồn dập)'),
    ('follow', Icons.person_add_alt, 'Bài mới của người bạn theo dõi', 'Nhạc sĩ, nghệ sĩ bạn theo dõi có bài mới'),
    ('review', Icons.fact_check_outlined, 'Bài gửi & hỗ trợ', 'BQT duyệt bài gửi, yêu cầu bổ sung, trả lời hỗ trợ'),
    ('message', Icons.mail_outline, 'Tin nhắn', 'Thành viên nhắn tin cho bạn'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from iOS Settings: the permission may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadStatus();
  }

  Future<void> _loadStatus() async {
    AuthorizationStatus? s;
    try {
      s = await PushService.instance.status();
    } catch (_) {}
    if (mounted) setState(() { _status = s; _statusLoaded = true; });
  }

  /// push_prefs hours may arrive as int, double or string — never crash.
  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  Future<void> _load() async {
    await _loadStatus();
    final daily = await PushService.instance.dailySongEnabled();
    if (mounted) setState(() => _daily = daily);
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    try {
      final d = await auth.authedQuery('query { me { push_prefs { reply like follow review message admin quiet_start quiet_end } } }');
      final p = d['me']?['push_prefs'];
      if (mounted && p is Map) setState(() => _prefs = Map<String, dynamic>.from(p));
    } catch (_) {
      if (mounted) setState(() => _prefsFailed = true);
    }
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    final before = Map<String, dynamic>.from(_prefs ?? {});
    setState(() => _prefs = {...?_prefs, ...patch});
    try {
      await context.read<AuthProvider>().authedMutate(
        r'mutation($p: PushPrefsInput) { updateMe(push_prefs: $p) { id } }',
        {'p': patch},
      );
    } catch (e) {
      if (mounted) {
        setState(() => _prefs = before);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không lưu được: ${friendlyError(e)}')));
      }
    }
  }

  bool get _allowed => _status == AuthorizationStatus.authorized || _status == AuthorizationStatus.provisional;

  Future<void> _enable() async {
    if (_status == AuthorizationStatus.denied) {
      // iOS won't ask twice; only the system Settings can turn it back on.
      await launchUrl(Uri.parse('app-settings:'));
      return;
    }
    await PushService.instance.requestPermission();
    await _loadStatus();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final quietStart = _int(_prefs?['quiet_start']);
    final quietEnd = _int(_prefs?['quiet_end']);
    final quietOn = quietStart != null && quietEnd != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _permissionCard(),
      const SizedBox(height: 8),
      _row(Icons.music_note_outlined, 'Bài hát của ngày', 'Vài buổi tối mỗi tuần và các ngày lễ lớn', _daily, (v) {
        setState(() => _daily = v);
        PushService.instance.setDailySong(v);
      }),
      if (auth.isAuthenticated) ...[
        if (_prefs == null && !_prefsFailed)
          Padding(padding: const EdgeInsets.all(12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentFg))))
        else if (_prefs == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(child: Text('Chưa tải được tuỳ chọn thông báo.', style: body(TextStyle(fontSize: 15, color: AppColors.textSecondary)))),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () {
                  setState(() => _prefsFailed = false);
                  _load();
                },
                child: Text('Thử lại', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
              ),
            ]),
          )
        else ...[
          for (final k in _kinds) _row(k.$2, k.$3, k.$4, _prefs![k.$1] != false, (v) => _save({k.$1: v})),
          const Divider(height: 20),
          _row(Icons.bedtime_outlined, 'Giờ yên lặng', quietOn ? 'Không báo từ ${quietStart}h đến ${quietEnd}h' : 'Báo cả ngày lẫn đêm', quietOn,
              (v) => _save(v ? {'quiet_start': 22, 'quiet_end': 7} : {'quiet_start': null, 'quiet_end': null})),
          if (quietOn)
            Padding(
              padding: const EdgeInsets.only(left: 30, bottom: 4),
              child: Row(children: [
                _hourPicker('Từ', quietStart.clamp(0, 23), (h) => _save({'quiet_start': h})),
                const SizedBox(width: 16),
                _hourPicker('Đến', quietEnd.clamp(0, 23), (h) => _save({'quiet_end': h})),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Thông báo từ BQT luôn được gửi.', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
          ),
        ],
      ],
    ]);
  }

  Widget _permissionCard() {
    if (!_statusLoaded) {
      // Reserve the card's height instead of flashing "chưa sẵn sàng".
      return Container(height: 64, decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)));
    }
    if (_status == null) {
      return Text('Thông báo chưa sẵn sàng trên bản cài này.', style: body(TextStyle(fontSize: 15, color: AppColors.textSecondary)));
    }
    final on = _allowed;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: on ? AppColors.surface : AppColors.accentSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(on ? Icons.notifications_active_rounded : Icons.notifications_off_outlined, color: on ? AppColors.textSecondary : AppColors.accentFg),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            on ? 'Thông báo đang bật' : (_status == AuthorizationStatus.denied ? 'Thông báo đang tắt trong cài đặt máy' : 'Thông báo chưa bật'),
            style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
          ),
        ),
        if (!on)
          TextButton(
            onPressed: _enable,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(_status == AuthorizationStatus.denied ? 'Mở cài đặt' : 'Bật', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentFg))),
          ),
      ]),
    );
  }

  Widget _row(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) => InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text))),
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: body(TextStyle(fontSize: 13, color: AppColors.textMuted)))),
              ]),
            ),
            Switch(value: value, onChanged: onChanged, activeThumbColor: Colors.white, activeTrackColor: AppColors.isLight ? AppColors.accent : AppColors.accentLight),
          ]),
        ),
      );

  Widget _hourPicker(String label, int value, ValueChanged<int> onChanged) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label ', style: body(TextStyle(fontSize: 15, color: AppColors.textSecondary))),
        DropdownButton<int>(
          value: value,
          underline: const SizedBox.shrink(),
          itemHeight: 48,
          items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h}h', style: body(TextStyle(fontSize: 16, color: AppColors.text))))],
          onChanged: (h) => h == null ? null : onChanged(h),
        ),
      ]);
}
