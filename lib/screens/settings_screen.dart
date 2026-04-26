import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  String? _saving;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  @override
  void dispose() {
    _fullnameCtl.dispose(); _phoneCtl.dispose(); _addressCtl.dispose();
    _dobCtl.dispose(); _mobCtl.dispose(); _yobCtl.dispose();
    _passwordCtl.dispose(); _passwordConfirmCtl.dispose();
    _newUsernameCtl.dispose(); _usernameReasonCtl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) { setState(() => _loading = false); return; }
    try {
      final data = await auth.authedQuery(r'''query {
        me {
          id fullname phone address dob mob yob gender
          notification_sound show_comment_sidebar
          avatar { url } background { url }
          changeUsernameRequests(first: 5, orderBy: [{column: "id", order: DESC}]) {
            data { id old_username new_username reason reject_reason status created_at }
          }
        }
      }''');
      final me = data['me'] ?? {};
      if (!mounted) return;
      setState(() {
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
      if (mounted) {
        setState(() => _loading = false);
        _toast('Lỗi tải cài đặt: $e', error: true);
      }
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? AppColors.error : AppColors.accent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _saveInfo() async {
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
    } catch (e) { _toast('Lỗi: $e', error: true); }
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
    } else { _toast('Lỗi: $err', error: true); }
    setState(() => _saving = null);
  }

  Future<void> _uploadImage(String field) async {
    if (_uploading != null) return;
    final pick = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = pick?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
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
        if (field == 'avatar') _avatarUrl = newUrl; else _bgUrl = newUrl;
      });
      _toast(field == 'avatar' ? 'Đã đổi ảnh đại diện' : 'Đã đổi ảnh nền');
    } catch (e) { _toast('Lỗi: $e', error: true); }
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
      _fetch();
    } catch (e) { _toast('Lỗi: $e', error: true); }
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
      setState(() => _notificationSound = !next);
      _toast('Lỗi: $e', error: true);
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
      setState(() => _showCommentSidebar = !next);
      _toast('Lỗi: $e', error: true);
    }
  }

  Future<void> _cancelUsername(String id) async {
    try {
      final auth = context.read<AuthProvider>();
      await auth.authedMutate(r'mutation($id: ID!) { cancelChangeUsername(id: $id) { id } }', {'id': id});
      _toast('Đã huỷ yêu cầu');
      _fetch();
    } catch (e) { _toast('Lỗi: $e', error: true); }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final auth = context.watch<AuthProvider>();
    if (!auth.isAuthenticated) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop())),
        body: Center(child: Text('Vui lòng đăng nhập', style: AppText.bodyText)),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text('CÀI ĐẶT', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          if (_loading)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList(delegate: SliverChildListDelegate([
                _section('Hình ảnh', [_imagePickers()]),
                const SizedBox(height: 14),
                _section('Tuỳ chọn', [
                  _toggleRow(
                    icon: Icons.notifications_outlined,
                    title: 'Âm thanh thông báo',
                    subtitle: 'Phát âm thanh khi có thông báo mới',
                    value: _notificationSound,
                    onChanged: (_) => _toggleNotificationSound(),
                  ),
                  _toggleRow(
                    icon: Icons.chat_bubble_outline,
                    title: 'Sidebar bình luận',
                    subtitle: 'Hiện sidebar bình luận trên desktop',
                    value: _showCommentSidebar,
                    onChanged: (_) => _toggleCommentSidebar(),
                  ),
                ]),
                const SizedBox(height: 14),
                _section('Thông tin cá nhân', [
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
                    Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Giới tính', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                    Row(children: [
                      _genderChip('male', 'Nam'),
                      const SizedBox(width: 8),
                      _genderChip('female', 'Nữ'),
                      const SizedBox(width: 8),
                      _genderChip('other', 'Khác'),
                    ]),
                  ])),
                  const SizedBox(height: 8),
                  _saveBtn('Lưu thông tin', _saving == 'info', _saveInfo),
                ]),
                const SizedBox(height: 14),
                _section('Đổi mật khẩu', [
                  _field('Mật khẩu mới', _passwordCtl, obscure: true),
                  _field('Nhập lại mật khẩu', _passwordConfirmCtl, obscure: true),
                  const SizedBox(height: 8),
                  _saveBtn('Đổi mật khẩu', _saving == 'pw', _savePassword),
                ]),
                const SizedBox(height: 14),
                _section('Đổi tên đăng nhập', [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('Yêu cầu sẽ được BQT xét duyệt thủ công.', style: body(const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                  ),
                  _field('Tên đăng nhập mới', _newUsernameCtl),
                  _field('Lý do', _usernameReasonCtl),
                  const SizedBox(height: 8),
                  _saveBtn('Gửi yêu cầu', _saving == 'username', _requestUsername),
                  if (_usernameReqs.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('LỊCH SỬ', style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5))),
                    const SizedBox(height: 6),
                    ..._usernameReqs.map(_usernameReqRow),
                  ],
                ]),
                SizedBox(height: player.currentSong != null ? 90 : 20),
              ])),
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
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AppColors.surfaceLight,
            image: _bgUrl != null
                ? DecorationImage(image: CachedNetworkImageProvider(_bgUrl!), fit: BoxFit.cover)
                : null,
          ),
          child: _bgUrl == null
              ? const Center(child: Icon(Icons.image_outlined, color: AppColors.textMuted, size: 32))
              : null,
        ),
        Positioned(
          right: 8, bottom: 8,
          child: InkWell(
            onTap: _uploading != null ? null : () => _uploadImage('background'),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_uploading == 'background')
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                else
                  const Icon(Icons.camera_alt_outlined, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text('Đổi ảnh nền', style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white))),
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
                  ? DecorationImage(image: CachedNetworkImageProvider(_avatarUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: _avatarUrl == null
                ? const Center(child: Icon(Icons.person, color: AppColors.textMuted, size: 32))
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
          Text('Ảnh đại diện', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text))),
          const SizedBox(height: 4),
          Text('JPG / PNG / WEBP', style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted))),
        ])),
        OutlinedButton.icon(
          onPressed: _uploading != null ? null : () => _uploadImage('avatar'),
          icon: const Icon(Icons.camera_alt_outlined, size: 14),
          label: Text('Đổi', style: body(const TextStyle(fontSize: 12))),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accentLight,
            side: const BorderSide(color: AppColors.accent),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
      case 'pending': color = const Color(0xFFFFA726); label = 'Chờ duyệt'; break;
      case 'approved': color = const Color(0xFF66BB6A); label = 'Đã duyệt'; break;
      case 'rejected': color = AppColors.error; label = 'Từ chối'; break;
      case 'canceled': color = AppColors.textMuted; label = 'Đã huỷ'; break;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${r['old_username']} → ${r['new_username']}', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: body(TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color))),
          ),
          if (status == 'pending') ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _cancelUsername(r['id'].toString()),
              child: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
            ),
          ],
        ]),
        if ((r['reject_reason'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(r['reject_reason'], style: body(const TextStyle(fontSize: 11, color: AppColors.error))),
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
            Text(title, style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text))),
            if (subtitle != null)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted)))),
          ])),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.accent,
          ),
        ]),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(title, style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)))),
        ...children,
      ]),
    );
  }

  Widget _field(String label, TextEditingController ctl, {TextInputType? keyboardType, bool obscure = false, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
        TextField(
          controller: ctl,
          keyboardType: keyboardType,
          obscureText: obscure,
          style: body(const TextStyle(fontSize: 14, color: AppColors.text)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: body(const TextStyle(color: AppColors.textMuted)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent)),
          ),
        ),
      ]),
    );
  }

  Widget _genderChip(String value, String label) {
    final active = _gender == value;
    return InkWell(
      onTap: () => setState(() => _gender = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.accentSoft : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppColors.accent : AppColors.border),
        ),
        child: Text(label, style: body(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? AppColors.accentLight : AppColors.textSecondary))),
      ),
    );
  }

  Widget _saveBtn(String label, bool busy, VoidCallback onTap) {
    return SizedBox(
      height: 40,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: body(const TextStyle(fontWeight: FontWeight.w700))),
      ),
    );
  }
}
