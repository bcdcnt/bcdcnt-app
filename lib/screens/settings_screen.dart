import '../services/push.dart';
import '../widgets/push_settings.dart';
import '../services/imgcdn.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../widgets/ui.dart' show goBack, OfflineBlock;
import '../services/friendly_error.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../services/theme_provider.dart';
import '../widgets/mini_player.dart';

class SettingsScreen extends StatefulWidget {
  /// Optional section to open first (e.g. 'theme' / 'shortcuts'), used when
  /// deep-linking from the guest profile's "Phối màu" / "Phím tắt" entries.
  final String? initialSection;
  const SettingsScreen({super.key, this.initialSection});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  /// True once the profile fetch succeeded. Saving is disabled until then so
  /// a failed load can never overwrite the real profile with blank fields.
  bool _loaded = false;
  bool _loadError = false;
  String? _saving;
  String? _signupChannel;
  bool _showPassword = false;
  String? _uploading;

  String? _avatarUrl;
  String? _bgUrl;
  bool _notificationSound = false;
  bool _showCommentSidebar = false;

  final _fullnameCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _addressCtl = TextEditingController();
  final _dobCtl = TextEditingController();
  final _mobCtl = TextEditingController();
  final _yobCtl = TextEditingController();
  String _gender = '';

  final _passwordCtl = TextEditingController();
  final _passwordConfirmCtl = TextEditingController();

  final _newUsernameCtl = TextEditingController();
  final _usernameReasonCtl = TextEditingController();
  List<Map<String, dynamic>> _usernameReqs = [];

  AuthProvider? _authRef;
  bool _didInitialFetch = false;
  /// Account the form was loaded for; a different login refetches.
  String? _uid;

  @override
  void initState() {
    super.initState();
    // Auth restores its token asynchronously; fetching in initState races it
    // (token null → me query skipped → real avatar/background never load,
    // only the defaults show). Wait until auth settles, then fetch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authRef = context.read<AuthProvider>();
      _authRef!.addListener(_initialFetch);
      _initialFetch();
    });
  }

  void _initialFetch() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.loading) return;            // still restoring — wait for next notify
    final uid = auth.user?['id']?.toString();
    if (_didInitialFetch && uid == _uid) return;
    final switched = _didInitialFetch;
    _didInitialFetch = true;
    _uid = uid;
    if (switched) _resetForm();
    _fetch();
  }

  /// Clear everything loaded for the previous account (logout / switch).
  void _resetForm() {
    for (final c in [_fullnameCtl, _phoneCtl, _addressCtl, _dobCtl, _mobCtl, _yobCtl,
        _passwordCtl, _passwordConfirmCtl, _newUsernameCtl, _usernameReasonCtl]) {
      c.clear();
    }
    setState(() {
      _gender = '';
      _avatarUrl = null;
      _bgUrl = null;
      _usernameReqs = [];
      _signupChannel = null;
      _loaded = false;
      _loadError = false;
      _loading = true;
    });
  }

  @override
  void dispose() {
    _authRef?.removeListener(_initialFetch);
    _fullnameCtl.dispose(); _phoneCtl.dispose(); _addressCtl.dispose();
    _dobCtl.dispose(); _mobCtl.dispose(); _yobCtl.dispose();
    _passwordCtl.dispose(); _passwordConfirmCtl.dispose();
    _newUsernameCtl.dispose(); _usernameReasonCtl.dispose();
    super.dispose();
  }

  static const _usernameReqsField = r'''changeUsernameRequests(first: 5, orderBy: [{column: "id", order: DESC}]) {
            data { id old_username new_username reason reject_reason status created_at }
          }''';

  Future<void> _fetch() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) { setState(() => _loading = false); return; }
    if (!_loading || _loadError) setState(() { _loading = true; _loadError = false; });
    try {
      final data = await auth.authedQuery('''query {
        me {
          id fullname phone address dob mob yob gender signup_channel
          notification_sound show_comment_sidebar
          avatar { url } background { url }
          $_usernameReqsField
        }
      }''');
      final me = data['me'];
      if (me is! Map) throw Exception('me null');
      if (!mounted) return;
      setState(() {
        _signupChannel = me['signup_channel']?.toString();
        _loaded = true;
        _loadError = false;
        _fullnameCtl.text = (me['fullname'] ?? '').toString();
        _phoneCtl.text = (me['phone'] ?? '').toString();
        _addressCtl.text = (me['address'] ?? '').toString();
        _dobCtl.text = (me['dob'] ?? '').toString();
        _mobCtl.text = (me['mob'] ?? '').toString();
        _yobCtl.text = (me['yob'] ?? '').toString();
        _gender = (me['gender'] ?? '').toString();
        _avatarUrl = me['avatar']?['url'];
        _bgUrl = me['background']?['url'];
        _notificationSound = me['notification_sound'] == true || me['notification_sound'] == 1;
        _showCommentSidebar = me['show_comment_sidebar'] == true || me['show_comment_sidebar'] == 1;
        _usernameReqs = ((me['changeUsernameRequests']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _loadError = true; });
    }
  }

  /// Refresh only the username-request history — never the profile
  /// controllers, so text the user is still editing survives.
  Future<void> _fetchUsernameReqs() async {
    try {
      final data = await context.read<AuthProvider>().authedQuery('query { me { id $_usernameReqsField } }');
      final me = data['me'];
      if (!mounted || me is! Map) return;
      setState(() {
        _usernameReqs = ((me['changeUsernameRequests']?['data'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {}
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppColors.error : AppColors.accent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _saveInfo() async {
    if (!_loaded) return;
    setState(() => _saving = 'info');
    try {
      final auth = context.read<AuthProvider>();
      await auth.authedMutate(r'''mutation($fullname: String, $phone: String, $address: String, $dob: String, $mob: String, $yob: String, $gender: String) {
        updateMe(fullname: $fullname, phone: $phone, address: $address, dob: $dob, mob: $mob, yob: $yob, gender: $gender) { id }
      }''', {
        'fullname': _fullnameCtl.text, 'phone': _phoneCtl.text, 'address': _addressCtl.text,
        'dob': _dobCtl.text, 'mob': _mobCtl.text, 'yob': _yobCtl.text, 'gender': _gender,
      });
      _toast('Đã lưu thông tin');
    } catch (e) { _toast(friendlyError(e), error: true); }
    if (mounted) setState(() => _saving = null);
  }

  Future<void> _savePassword() async {
    if (_passwordCtl.text.length < 6) { _toast('Mật khẩu tối thiểu 6 ký tự', error: true); return; }
    if (_passwordCtl.text != _passwordConfirmCtl.text) { _toast('Mật khẩu nhập lại không khớp', error: true); return; }
    setState(() => _saving = 'pw');
    final err = await context.read<AuthProvider>().changePassword(_passwordCtl.text);
    if (!mounted) return;
    if (err == null) {
      _toast('Đã đổi mật khẩu');
      _passwordCtl.clear(); _passwordConfirmCtl.clear();
    } else { _toast(friendlyError(err), error: true); }
    setState(() => _saving = null);
  }

  Future<void> _uploadImage(String field) async {
    if (_uploading != null) return;
    final pick = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = pick?.files.firstOrNull;
    if (file == null || file.bytes == null || !mounted) return;
    final auth = context.read<AuthProvider>();
    setState(() => _uploading = field);
    try {
      // 1. Presign
      final presign = await auth.authedMutate(r'''mutation($filename: String!, $type: UploadType!) {
        presignUpload(filename: $filename, type: $type) { upload_url key }
      }''', {'filename': file.name, 'type': 'img'});
      final uploadUrl = presign['presignUpload']['upload_url'];
      final key = presign['presignUpload']['key'];

      // 2. PUT to S3
      final mime = file.extension == 'png' ? 'image/png' : (file.extension == 'webp' ? 'image/webp' : 'image/jpeg');
      final putRes = await http.put(Uri.parse(uploadUrl), body: file.bytes, headers: {'Content-Type': mime});
      if (putRes.statusCode >= 400) throw Exception('Upload thất bại (${putRes.statusCode})');

      // 3. Poll uploadStatus
      String? completedDataJson;
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final statusData = await auth.authedQuery(r'''query($key: String!) {
          uploadStatus(key: $key) { status data message }
        }''', {'key': key});
        final result = statusData['uploadStatus'];
        final s = (result?['status'] ?? '').toString().toLowerCase();
        if (s == 'completed') { completedDataJson = jsonEncode(result?['data']); break; }
        if (s == 'failed' || s == 'error') throw Exception(result?['message'] ?? 'Xử lý ảnh lỗi');
      }
      if (completedDataJson == null) throw Exception('Quá thời gian xử lý ảnh');
      final raw = jsonDecode(completedDataJson);
      final data = raw is String ? jsonDecode(raw) : raw;
      final imageId = '${data['id']}';
      final newUrl = data['url']?.toString();

      // 4. updateMe
      final mutation = field == 'avatar'
          ? r'mutation($image_id: ID) { updateMe(image_id: $image_id) { id } }'
          : r'mutation($background_id: ID) { updateMe(background_id: $background_id) { id } }';
      final vars = field == 'avatar' ? {'image_id': imageId} : {'background_id': imageId};
      await auth.authedMutate(mutation, vars);
      if (!mounted) return;
      setState(() {
        if (field == 'avatar') { _avatarUrl = newUrl; } else { _bgUrl = newUrl; }
      });
      _toast(field == 'avatar' ? 'Đã đổi ảnh đại diện' : 'Đã đổi ảnh nền');
    } catch (e) { _toast(friendlyError(e), error: true); }
    if (mounted) setState(() => _uploading = null);
  }

  Future<void> _requestUsername() async {
    final newName = _newUsernameCtl.text.trim();
    if (newName.length < 3) { _toast('Tên đăng nhập tối thiểu 3 ký tự', error: true); return; }
    setState(() => _saving = 'username');
    try {
      final auth = context.read<AuthProvider>();
      await auth.authedMutate(r'''mutation($new_username: String!, $reason: String) {
        changeUsername(new_username: $new_username, reason: $reason) { id }
      }''', {'new_username': newName, 'reason': _usernameReasonCtl.text});
      _toast('Đã gửi yêu cầu đổi tên');
      _newUsernameCtl.clear(); _usernameReasonCtl.clear();
      _fetchUsernameReqs();
    } catch (e) { _toast(friendlyError(e), error: true); }
    if (mounted) setState(() => _saving = null);
  }

  Future<void> _toggleNotificationSound() async {
    final next = !_notificationSound;
    setState(() => _notificationSound = next);
    try {
      final auth = context.read<AuthProvider>();
      await auth.authedMutate(r'''mutation($notification_sound: Boolean) {
        updateMe(notification_sound: $notification_sound) { id }
      }''', {'notification_sound': next});
      _toast(next ? 'Bật âm thanh thông báo' : 'Tắt âm thanh thông báo');
    } catch (e) {
      if (mounted) setState(() => _notificationSound = !next);
      _toast(friendlyError(e), error: true);
    }
  }

  Future<void> _toggleCommentSidebar() async {
    final next = !_showCommentSidebar;
    setState(() => _showCommentSidebar = next);
    try {
      final auth = context.read<AuthProvider>();
      await auth.authedMutate(r'''mutation($show_comment_sidebar: Boolean) {
        updateMe(show_comment_sidebar: $show_comment_sidebar) { id }
      }''', {'show_comment_sidebar': next});
      _toast(next ? 'Bật sidebar bình luận' : 'Tắt sidebar bình luận');
    } catch (e) {
      if (mounted) setState(() => _showCommentSidebar = !next);
      _toast(friendlyError(e), error: true);
    }
  }

  Future<void> _cancelUsername(String id) async {
    try {
      final auth = context.read<AuthProvider>();
      await auth.authedMutate(r'mutation($id: ID!) { cancelChangeUsername(request_id: $id) { id } }', {'id': id});
      _toast('Đã huỷ yêu cầu');
      _fetchUsernameReqs();
    } catch (e) { _toast(friendlyError(e), error: true); }
  }

  /// Google / Apple sign-up accounts never chose a password (a random one
  /// was mailed), so they confirm by typing "XOÁ" instead.
  bool get _socialOnly => _signupChannel == 'google' || _signupChannel == 'apple';

  Future<void> _deleteAccount() async {
    // Step 1: explain what happens.
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Xoá tài khoản?', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text))),
        content: SingleChildScrollView(
          child: Text(
            'Tài khoản của bạn sẽ bị xoá vĩnh viễn:\n\n'
            '• Tên, email, số điện thoại, địa chỉ, ngày sinh, ảnh đại diện và ảnh nền bị xoá.\n'
            '• Bạn sẽ bị đăng xuất trên mọi thiết bị và không đăng nhập lại được.\n'
            '• Bình luận, bài gửi đã đăng vẫn được giữ trên trang nhưng hiện dưới tên ẩn danh.\n\n'
            'Việc này KHÔNG THỂ hoàn tác.',
            style: body(TextStyle(fontSize: 16, height: 1.5, color: AppColors.text)),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Giữ tài khoản', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Tiếp tục', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.errorText))),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    // Step 2: confirm with password (or "XOÁ" for social accounts).
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DeleteConfirmDialog(socialOnly: _socialOnly),
    );
    if (ok != true || !mounted) return;

    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    await auth.logout();
    messenger.showSnackBar(SnackBar(
      content: const Text('Đã xoá tài khoản. Cảm ơn bạn đã đồng hành cùng BCĐCNT.', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      backgroundColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
    ));
    router.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final auth = context.watch<AuthProvider>();
    // Theme (Phối màu) + shortcuts (Phím tắt) are local-only, so guests can
    // use them too — only the account sections need a login.
    const localOnlyIds = {'push', 'theme', 'shortcuts'};
    // A failed profile load shows the retry block and only the local
    // sections — never empty account forms that could be saved blank.
    final accountReady = auth.isAuthenticated && _loaded && !_loadError;
    final sections = accountReady
        ? _sectionDefs()
        : _sectionDefs().where((s) => localOnlyIds.contains(s.id)).toList();
    final header = (auth.isAuthenticated && _loadError) ? OfflineBlock(onRetry: _fetch) : null;
    // Only the account sections need a network fetch; guests skip the spinner.
    final showLoading = auth.isAuthenticated && _loading;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg,
            surfaceTintColor: Colors.transparent,
            title: Text('Cài đặt'),
            centerTitle: true,
            leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          ),
          if (showLoading)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else
            SliverFillRemaining(
              hasScrollBody: true,
              child: _SettingsBody(
                key: ValueKey('settings-${_uid ?? 'guest'}-$accountReady'),
                sections: sections,
                header: header,
                initialSectionId: widget.initialSection,
                bottomPadding: player.currentSong != null ? 90 : 20,
              ),
            ),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  Widget _imagePickers() {
    return Column(children: [
      // Background
      Stack(children: [
        Container(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AppColors.surfaceLight,
            image: _bgUrl != null
                ? DecorationImage(image: CachedNetworkImageProvider(cdnImg((_bgUrl!).toString(), 960)), fit: BoxFit.cover)
                : null,
          ),
          child: _bgUrl == null
              ? Center(child: Icon(Icons.image_outlined, color: AppColors.textMuted, size: 32))
              : null,
        ),
        Positioned(
          right: 8, bottom: 8,
          child: InkWell(
            onTap: _uploading != null ? null : () => _uploadImage('background'),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_uploading == 'background')
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                else
                  const Icon(Icons.camera_alt_outlined, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Text('Đổi ảnh nền', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white))),
              ]),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      // Avatar
      Row(children: [
        Stack(children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: AppColors.surfaceLight,
              image: _avatarUrl != null
                  ? DecorationImage(image: CachedNetworkImageProvider(cdnImg((_avatarUrl!).toString(), 160)), fit: BoxFit.cover)
                  : null,
            ),
            child: _avatarUrl == null
                ? Center(child: Icon(Icons.person, color: AppColors.textMuted, size: 32))
                : null,
          ),
          if (_uploading == 'avatar')
            Positioned.fill(child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.5)),
              child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
            )),
        ]),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ảnh đại diện', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text))),
          const SizedBox(height: 4),
          Text('JPG / PNG / WEBP', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))),
        ])),
        OutlinedButton.icon(
          onPressed: _uploading != null ? null : () => _uploadImage('avatar'),
          icon: const Icon(Icons.camera_alt_outlined, size: 18),
          label: Text('Đổi ảnh', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accentFg,
            side: BorderSide(color: AppColors.accentFg),
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
    ]);
  }

  Widget _usernameReqRow(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString();
    Color color = AppColors.textMuted;
    String label = status;
    switch (status) {
      case 'pending': color = AppColors.warningText; label = 'Chờ duyệt'; break;
      case 'approved': color = AppColors.successText; label = 'Đã duyệt'; break;
      case 'rejected': color = AppColors.errorText; label = 'Từ chối'; break;
      case 'canceled': color = AppColors.textMuted; label = 'Đã huỷ'; break;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${r['old_username']} → ${r['new_username']}', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color))),
          ),
          if (status == 'pending')
            IconButton(
              tooltip: 'Huỷ yêu cầu',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => _cancelUsername(r['id'].toString()),
              icon: Icon(Icons.close, size: 20, color: AppColors.textSecondary),
            ),
        ]),
        if ((r['reject_reason'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(r['reject_reason'].toString(), style: body(TextStyle(fontSize: 14, color: AppColors.errorText))),
          ),
      ]),
    );
  }

  Widget _toggleRow({required IconData icon, required String title, String? subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text))),
            if (subtitle != null)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: body(TextStyle(fontSize: 13, color: AppColors.textMuted)))),
          ])),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.isLight ? AppColors.accent : AppColors.accentLight,
            inactiveThumbColor: AppColors.textMuted,
            inactiveTrackColor: AppColors.border,
          ),
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctl, {TextInputType? keyboardType, bool obscure = false, String? hint, Iterable<String>? autofillHints, Widget? suffix, bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
        TextField(
          controller: ctl,
          keyboardType: keyboardType,
          obscureText: obscure,
          enabled: enabled,
          autofillHints: autofillHints,
          autocorrect: !obscure,
          enableSuggestions: !obscure,
          style: body(TextStyle(fontSize: 17, color: AppColors.text)),
          decoration: InputDecoration(
            suffixIcon: suffix,
            hintText: hint,
            hintStyle: body(TextStyle(color: AppColors.textMuted)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            filled: true,
            fillColor: AppColors.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.45), width: 1.5)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.45), width: 1.5)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.accentFg, width: 2)),
          ),
        ),
      ]),
    );
  }

  Widget _genderChip(String value, String label) {
    final active = _gender == value;
    return Semantics(
      selected: active,
      button: true,
      child: InkWell(
      onTap: () => setState(() => _gender = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.accentSoft : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? AppColors.accentFg : AppColors.border, width: active ? 2 : 1),
        ),
        child: Text(label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: active ? AppColors.accentFg : AppColors.textSecondary))),
      ),
      ),
    );
  }

  Widget _saveBtn(String label, bool busy, VoidCallback? onTap) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: busy || onTap == null ? null : onTap,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
      ),
    );
  }

  /// Section list — single source of truth shared by both layouts. Keeping
  /// it here means the body widget can be a dumb consumer.
  List<_SettingsSectionDef> _sectionDefs() {
    final defs = _allSectionDefs();
    if (MediaQuery.sizeOf(context).width >= 900) return defs;
    // Phones: what older listeners actually look for (text size, theme,
    // notifications) comes first; keyboard shortcuts are desktop-only.
    const first = ['theme', 'push'];
    return [
      for (final id in first) ...defs.where((d) => d.id == id),
      ...defs.where((d) => !first.contains(d.id) && d.id != 'shortcuts' && (kIsWeb || d.id != 'prefs')),
    ];
  }

  List<_SettingsSectionDef> _allSectionDefs() {
    return [
      _SettingsSectionDef(
        id: 'images',
        icon: Icons.image_outlined,
        title: 'Hình ảnh',
        builder: () => _imagePickers(),
      ),
      _SettingsSectionDef(
        id: 'prefs',
        icon: Icons.tune,
        title: 'Tuỳ chọn',
        builder: () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Web-only: the in-page "ding" for new notifications.
          if (kIsWeb) _toggleRow(
            icon: Icons.notifications_outlined,
            title: 'Âm thanh thông báo',
            subtitle: 'Phát âm thanh khi có thông báo mới',
            value: _notificationSound,
            onChanged: (_) => _toggleNotificationSound(),
          ),
          if (MediaQuery.sizeOf(context).width >= 900) _toggleRow(
            icon: Icons.chat_bubble_outline,
            title: 'Sidebar bình luận',
            subtitle: 'Hiện sidebar bình luận trên desktop',
            value: _showCommentSidebar,
            onChanged: (_) => _toggleCommentSidebar(),
          ),
        ]),
      ),
      _SettingsSectionDef(
        id: 'profile',
        icon: Icons.person_outline,
        title: 'Thông tin cá nhân',
        builder: () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('Họ và tên', _fullnameCtl),
          _field('Số điện thoại', _phoneCtl, keyboardType: TextInputType.phone),
          _field('Địa chỉ', _addressCtl),
          Row(children: [
            Expanded(child: _field('Ngày', _dobCtl, keyboardType: TextInputType.number, hint: 'DD')),
            const SizedBox(width: 8),
            Expanded(child: _field('Tháng', _mobCtl, keyboardType: TextInputType.number, hint: 'MM')),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _field('Năm sinh', _yobCtl, keyboardType: TextInputType.number, hint: 'YYYY')),
          ]),
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Giới tính', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _genderChip('male', 'Nam'),
              _genderChip('female', 'Nữ'),
              _genderChip('other', 'Khác'),
            ]),
          ])),
          const SizedBox(height: 8),
          _saveBtn('Lưu thông tin', _saving == 'info', _loaded ? _saveInfo : null),
        ]),
      ),
      _SettingsSectionDef(
        id: 'password',
        icon: Icons.lock_outline,
        title: 'Đổi mật khẩu',
        builder: () => AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _field('Mật khẩu mới', _passwordCtl,
                obscure: !_showPassword,
                autofillHints: const [AutofillHints.newPassword],
                suffix: IconButton(
                  tooltip: _showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.textSecondary),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                )),
            _field('Nhập lại mật khẩu', _passwordConfirmCtl, obscure: !_showPassword, autofillHints: const [AutofillHints.newPassword]),
            const SizedBox(height: 8),
            _saveBtn('Đổi mật khẩu', _saving == 'pw', _savePassword),
          ]),
        ),
      ),
      _SettingsSectionDef(
        id: 'username',
        icon: Icons.alternate_email,
        title: 'Đổi tên đăng nhập',
        builder: () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Yêu cầu sẽ được BQT xét duyệt thủ công.', style: body(TextStyle(fontSize: 14, color: AppColors.textMuted))),
          ),
          _field('Tên đăng nhập mới', _newUsernameCtl),
          _field('Lý do', _usernameReasonCtl),
          const SizedBox(height: 8),
          _saveBtn('Gửi yêu cầu', _saving == 'username', _requestUsername),
          if (_usernameReqs.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('LỊCH SỬ', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5))),
            const SizedBox(height: 6),
            ..._usernameReqs.map(_usernameReqRow),
          ],
        ]),
      ),
      if (PushService.supported)
        _SettingsSectionDef(
          id: 'push',
          icon: Icons.notifications_active_outlined,
          title: 'Thông báo điện thoại',
          builder: () => const PushSettings(),
        ),
      _SettingsSectionDef(
        id: 'theme',
        icon: Icons.palette_outlined,
        title: 'Giao diện & cỡ chữ',
        builder: () => const _ThemePicker(),
      ),
      _SettingsSectionDef(
        id: 'shortcuts',
        icon: Icons.keyboard_outlined,
        title: 'Phím tắt',
        builder: () => const _ShortcutsList(),
      ),
      _SettingsSectionDef(
        id: 'account',
        icon: Icons.manage_accounts_outlined,
        title: 'Tài khoản',
        builder: () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Xoá vĩnh viễn tài khoản và thông tin cá nhân của bạn khỏi BCĐCNT.', style: body(TextStyle(fontSize: 15, height: 1.4, color: AppColors.textSecondary))),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _deleteAccount,
              icon: Icon(Icons.delete_forever_outlined, size: 20, color: AppColors.errorText),
              label: Text('Xoá tài khoản', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.errorText))),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.errorText, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
      ),
    ];
  }
}

/// Step 2 of account deletion: password (or typing "XOÁ" for Google/Apple
/// accounts), then calls `deleteMe`. Pops true once the server confirmed.
class _DeleteConfirmDialog extends StatefulWidget {
  final bool socialOnly;
  const _DeleteConfirmDialog({required this.socialOnly});

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final _ctl = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final v = _ctl.text.trim();
    if (widget.socialOnly) {
      final up = v.toUpperCase();
      return up == 'XOÁ' || up == 'XÓA' || up == 'XOA';
    }
    return v.isNotEmpty;
  }

  Future<void> _submit() async {
    if (!_canSubmit || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final res = await context.read<AuthProvider>().authedMutate(
        r'mutation($password: String) { deleteMe(password: $password) }',
        {'password': widget.socialOnly ? null : _ctl.text},
      );
      if (!mounted) return;
      if (res['deleteMe'] == true) {
        Navigator.pop(context, true);
        return;
      }
      setState(() { _busy = false; _error = 'Chưa xoá được tài khoản, vui lòng thử lại.'; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = friendlyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final social = widget.socialOnly;
    return AlertDialog(
      title: Text('Xác nhận xoá tài khoản', style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text))),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            social ? 'Gõ chữ XOÁ vào ô dưới để xác nhận.' : 'Nhập mật khẩu của bạn để xác nhận.',
            style: body(TextStyle(fontSize: 16, height: 1.4, color: AppColors.text)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctl,
            autofocus: true,
            enabled: !_busy,
            obscureText: !social && !_show,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: social ? null : const [AutofillHints.password],
            textCapitalization: social ? TextCapitalization.characters : TextCapitalization.none,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            style: body(TextStyle(fontSize: 17, color: AppColors.text)),
            decoration: InputDecoration(
              labelText: social ? 'Gõ XOÁ' : 'Mật khẩu',
              labelStyle: body(TextStyle(fontSize: 16, color: AppColors.textSecondary)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: social
                  ? null
                  : IconButton(
                      tooltip: _show ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                      icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _show = !_show),
                    ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.errorText))),
          ],
        ]),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text('Huỷ', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
        ),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _canSubmit && !_busy ? _submit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA32020),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Xoá vĩnh viễn', style: body(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          ),
        ),
      ],
    );
  }
}

class _SettingsSectionDef {
  final String id;
  final IconData icon;
  final String title;
  final Widget Function() builder;
  const _SettingsSectionDef({required this.id, required this.icon, required this.title, required this.builder});
}

/// Renders the settings sections — 2-pane macOS layout on desktop (≥900px),
/// stacked single-column on mobile.
class _SettingsBody extends StatefulWidget {
  final List<_SettingsSectionDef> sections;
  final double bottomPadding;
  final String? initialSectionId;
  /// Shown above the sections (e.g. the "chưa tải được" retry block).
  final Widget? header;
  const _SettingsBody({super.key, required this.sections, required this.bottomPadding, this.initialSectionId, this.header});

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  String? _activeId;

  @override
  void initState() {
    super.initState();
    final ids = widget.sections.map((s) => s.id).toSet();
    _activeId = (widget.initialSectionId != null && ids.contains(widget.initialSectionId))
        ? widget.initialSectionId
        : (widget.sections.isNotEmpty ? widget.sections.first.id : null);
  }

  Widget _sectionCard(_SettingsSectionDef s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Icon(s.icon, size: 20, color: s.id == 'account' ? AppColors.errorText : AppColors.accentFg),
              const SizedBox(width: 8),
              Expanded(child: Text(s.title, style: display(TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)))),
            ]),
          ),
          s.builder(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (!isDesktop) {
      return ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, widget.bottomPadding),
        children: [
          if (widget.header != null) widget.header!,
          ...widget.sections.map(_sectionCard),
        ],
      );
    }
    if (widget.sections.isEmpty) {
      return ListView(children: [if (widget.header != null) widget.header!]);
    }
    final active = widget.sections.firstWhere(
      (s) => s.id == _activeId,
      orElse: () => widget.sections.first,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, widget.bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left pane: section nav (macOS System Settings vibe).
          SizedBox(
            width: 220,
            child: ListView(
              padding: const EdgeInsets.only(top: 6),
              children: widget.sections.map((s) {
                final selected = s.id == active.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: InkWell(
                    onTap: () => setState(() => _activeId = s.id),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.accentSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        Icon(s.icon, size: 16, color: selected ? AppColors.accentLight : AppColors.textSecondary),
                        const SizedBox(width: 10),
                        Expanded(child: Text(s.title, style: body(TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? AppColors.text : AppColors.textSecondary,
                        )))),
                      ]),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: ListView(
              key: ValueKey('settings-content-${active.id}'),
              padding: const EdgeInsets.only(top: 6),
              children: [
                if (widget.header != null) widget.header!,
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(active.title, style: AppText.displayLarge),
                ),
                active.builder(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    final themeProv = context.watch<ThemeProvider>();
    const modes = [('sang', 'Sáng'), ('toi', 'Tối'), ('system', 'Theo máy')];
    final scales = kTextScaleLabels.entries.toList();
    Widget label(String s, [String? sub]) => Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s, style: AppText.title),
            if (sub != null) Text(sub, style: AppText.meta),
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label('Giao diện'),
        _Seg(labels: [for (final m in modes) m.$2], selected: modes.indexWhere((m) => m.$1 == themeProv.mode), onSelect: (i) => themeProv.setTheme(modes[i].$1)),
        const SizedBox(height: 20),
        label('Cỡ chữ', 'Áp dụng cho toàn ứng dụng'),
        _Seg(labels: [for (final s in scales) s.value], selected: scales.indexWhere((s) => s.key == themeProv.textScaleKey), onSelect: (i) => themeProv.setTextScale(scales[i].key)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border, width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('XEM TRƯỚC', style: body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.textMuted))),
            const SizedBox(height: 6),
            Text('Nơi anh đến là biển xa, nơi anh tới ngoài đảo xa', style: body(TextStyle(fontSize: 17, height: 1.5, fontWeight: FontWeight.w600, color: AppColors.text))),
          ]),
        ),
      ],
    );
  }
}

class _Seg extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const _Seg({required this.labels, required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(i),
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? AppColors.bg : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: i == selected ? [BoxShadow(color: Colors.black.withValues(alpha: AppColors.isLight ? 0.08 : 0.3), blurRadius: 4, offset: const Offset(0, 1))] : null,
                  ),
                  child: Text(labels[i], style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: i == selected ? AppColors.text : AppColors.textSecondary))),
                ),
              ),
            ),
        ]),
      );
}

class _ShortcutsList extends StatelessWidget {
  const _ShortcutsList();

  @override
  Widget build(BuildContext context) {
    final shortcuts = [
      ('Phát / Tạm dừng', ['Space']),
      ('Tua lùi 5 giây', ['←']),
      ('Tua tới 5 giây', ['→']),
      ('Bài trước', ['⇧', '←']),
      ('Bài kế tiếp', ['⇧', '→']),
      ('Tìm kiếm nhanh', ['⌘', 'K']),
      ('Mở trang Tìm kiếm', ['⌘', 'F']),
      ('Mở Cài đặt', ['⌘', ',']),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: shortcuts.map((s) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
          child: Row(children: [
            Expanded(child: Text(s.$1, style: body(TextStyle(fontSize: 13, color: AppColors.text)))),
            ...s.$2.map((k) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(k, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text))),
              ),
            )),
          ]),
        );
      }).toList(),
    );
  }
}
