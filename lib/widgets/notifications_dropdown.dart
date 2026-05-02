import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';

/// Compact notifications popover anchored to the header bell. Fetches the
/// latest 5 unread/read notifications, lets the user mark all as read or
/// jump to the full list. Click a row to open its target object.
class NotificationsDropdown extends StatefulWidget {
  /// Builder that gets passed an onTap callback wired to open the dropdown.
  /// Pass it to whatever button you want as the anchor.
  final Widget Function(BuildContext, VoidCallback) builder;
  const NotificationsDropdown({super.key, required this.builder});

  @override
  State<NotificationsDropdown> createState() => _NotificationsDropdownState();
}

class _NotificationsDropdownState extends State<NotificationsDropdown> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _toggle() {
    if (_overlay != null) {
      _close();
    } else {
      _open();
    }
  }

  void _close() {
    _overlay?.remove();
    _overlay = null;
  }

  void _open() {
    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(builder: (ctx) {
      return Stack(children: [
        // Tap-outside scrim to dismiss.
        Positioned.fill(child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _close,
        )),
        Positioned(
          width: 360,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            // Open below the bell, expanding into the main content area
            // (right of the sidebar). Previous offset (-328, 36) assumed
            // there's 328px of space to the LEFT of the bell — true on
            // mobile but the desktop sidebar is only 220px wide, so the
            // popup spilled off-screen behind it.
            offset: const Offset(8, 40),
            child: Material(
              color: Colors.transparent,
              child: _NotifPanel(onClose: _close),
            ),
          ),
        ),
      ]);
    });
    overlay.insert(_overlay!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: widget.builder(context, _toggle),
    );
  }
}

class _NotifPanel extends StatefulWidget {
  final VoidCallback onClose;
  const _NotifPanel({required this.onClose});

  @override
  State<_NotifPanel> createState() => _NotifPanelState();
}

class _NotifPanelState extends State<_NotifPanel> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final auth = context.read<AuthProvider>();
      if (!auth.isAuthenticated) {
        if (mounted) setState(() { _items = []; _loading = false; });
        return;
      }
      // Notifications live on `me`, not at the root — querying root
      // returns nothing (or only admin-scoped data). Mirror what the
      // notifications screen does.
      final data = await auth.authedQuery(r'''query {
        me {
          notifications(first: 5, page: 1, orderBy: [{column: "created_at", order: DESC}]) {
            data { id code content action extra object_type object_id is_read created_at sender { id username avatar { url } } }
          }
        }
      }''');
      final list = ((data['me']?['notifications']?['data'] ?? []) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() { _items = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _markAllRead() async {
    try {
      final auth = context.read<AuthProvider>();
      await auth.authedMutate(r'mutation { markAsReadAll }', null);
      if (!mounted) return;
      setState(() { _items = _items.map((n) { n['is_read'] = 1; return n; }).toList(); });
      await auth.clearUnread();
    } catch (_) {}
  }

  String? _objectRoute(String? type, String? id, String? slug) {
    if (id == null) return null;
    switch (type) {
      case 'song': return '/song/$id';
      case 'folk': return '/song/$id';
      case 'instrumental': return '/song/$id';
      case 'poem': return '/song/$id';
      case 'karaoke': return '/song/$id';
      case 'artist': return slug != null ? '/nghe-si/$slug' : null;
      case 'composer': return slug != null ? '/nhac-si/$slug' : null;
      case 'poet': return slug != null ? '/nha-tho/$slug' : null;
      case 'recomposer': return slug != null ? '/soan-gia/$slug' : null;
      case 'discussion': return '/thao-luan/$id';
      case 'upload': return '/bai-gui/$id';
      case 'comment': return null;
      default: return null;
    }
  }

  void _openItem(Map<String, dynamic> n) {
    widget.onClose();
    final route = _objectRoute(n['object_type']?.toString(), n['object_id']?.toString(), null);
    if (route != null) context.push(route);
    else context.push('/thong-bao');
  }

  String _timeago(String? ts) {
    if (ts == null) return '';
    final dt = DateTime.tryParse(ts)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes}p';
    if (diff.inHours < 24) return '${diff.inHours}g';
    if (diff.inDays < 7) return '${diff.inDays}n';
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
            child: Row(children: [
              Text('Thông báo', style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text))),
              const Spacer(),
              if (_items.any((n) => n['is_read'] != 1 && n['is_read'] != true))
                TextButton(
                  onPressed: _markAllRead,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: Text('Đọc hết', style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accentLight))),
                ),
            ]),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          // List
          if (_loading)
            const Padding(padding: EdgeInsets.all(28), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))))
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Center(child: Text('Chưa có thông báo', style: body(const TextStyle(fontSize: 12, color: AppColors.textMuted)))),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _items.length,
                itemBuilder: (_, i) => _NotifRow(item: _items[i], timeagoLabel: _timeago(_items[i]['created_at']?.toString()), onTap: () => _openItem(_items[i])),
              ),
            ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          InkWell(
            onTap: () { widget.onClose(); context.push('/thong-bao'); },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(child: Text('Xem tất cả', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accentLight)))),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final String timeagoLabel;
  final VoidCallback onTap;
  const _NotifRow({required this.item, required this.timeagoLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = !(item['is_read'] == 1 || item['is_read'] == true);
    final sender = item['sender'];
    final avatar = sender?['avatar']?['url']?.toString();
    final username = sender?['username']?.toString() ?? '';
    final content = (item['content'] ?? '').toString();
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        color: unread ? AppColors.accentSoft.withValues(alpha: 0.4) : Colors.transparent,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipOval(
            child: SizedBox(
              width: 32, height: 32,
              child: avatar != null && avatar.isNotEmpty
                  ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: AppColors.surfaceLight))
                  : Container(color: AppColors.accent, alignment: Alignment.center, child: Text(username.isNotEmpty ? username[0].toUpperCase() : '?', style: body(const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(content, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 12, color: AppColors.text, height: 1.4, fontWeight: unread ? FontWeight.w600 : FontWeight.w500))),
              const SizedBox(height: 2),
              Text(timeagoLabel, style: body(const TextStyle(fontSize: 10, color: AppColors.textMuted))),
            ]),
          ),
          if (unread) Container(width: 7, height: 7, margin: const EdgeInsets.only(left: 6, top: 6), decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent)),
        ]),
      ),
    );
  }
}
