import 'dart:convert';

/// Where a notification leads: a go_router path plus the `extra` the page
/// expects. Shared by the notifications list and phone-push taps (push data
/// carries the same fields: action, object_type, object_id, extra, and for
/// comments commentable_type/commentable_id).
typedef NotificationTarget = ({String path, Map<String, dynamic>? extra});

const _songTypes = {'song', 'folk', 'instrumental', 'karaoke', 'poem'};
// Web links the app can also open (others, e.g. /tin-nhan/, fall back to the list).
const _appPrefixes = ['/nghe-si/', '/nhac-si/', '/soan-gia/', '/nha-tho/', '/playlist/', '/thao-luan/', '/p/', '/ho-tro/', '/user/'];
const _peoplePrefix = {'artist': 'nghe-si', 'composer': 'nhac-si', 'recomposer': 'soan-gia', 'poet': 'nha-tho'};

NotificationTarget? notificationRoute(Map notif) {
  Map? extra;
  final raw = notif['extra'];
  if (raw != null && raw != '') {
    try {
      final parsed = raw is String ? jsonDecode(raw) : raw;
      if (parsed is Map) extra = parsed;
    } catch (_) {}
  }
  final router = extra?['router'] is Map ? extra!['router'] as Map : extra;

  // Admin notices and messages carry a web link ("/tin-nhan/…", "/bai-hat/…").
  final link = extra?['link']?.toString();

  final objectType = notif['object_type']?.toString();
  if (objectType == 'upload' && router?['slug'] == null) {
    return (path: '/bai-gui/${notif['object_id']}', extra: null);
  }

  // Comment: open what the comment is on (push data adds commentable_*).
  if (objectType == 'comment') {
    final ct = (notif['commentable_type'] ?? router?['commentable_type'])?.toString().toLowerCase();
    final cid = notif['commentable_id'] ?? router?['commentable_id'];
    if (ct != null && cid != null && '$cid'.isNotEmpty) {
      final t = _byType(ct, cid, null);
      if (t != null) return t;
    }
  }

  final type = (router?['type'] ?? objectType)?.toString();
  final id = router?['id'] ?? notif['object_id'];
  final slug = router?['slug']?.toString();
  if (type != null) {
    final t = _byType(type, id, slug);
    if (t != null) return t;
  }
  if (link != null && _appPrefixes.any((p) => link.startsWith(p))) return (path: link, extra: null);
  return null;
}

NotificationTarget? _byType(String type, dynamic id, String? slug) {
  final hasId = id != null && '$id'.isNotEmpty;
  // Pass the kind along: ids repeat across song/folk/poem/… tables.
  if (_songTypes.contains(type) && hasId) return (path: '/song/$id', extra: {'id': id, 'file_type': type});
  if (_peoplePrefix.containsKey(type) && slug != null) return (path: '/${_peoplePrefix[type]}/$slug', extra: null);
  if (!hasId) return type == 'page' && slug != null ? (path: '/p/$slug', extra: null) : null;
  return switch (type) {
    'sheet' => (path: '/sheet/$id', extra: null),
    'discussion' => (path: '/thao-luan/$id', extra: null),
    'playlist' => (path: '/playlist/$id', extra: null),
    'document' => (path: '/tu-lieu/chi-tiet/$id', extra: null),
    'upload' => (path: '/bai-gui/$id', extra: null),
    'user' => (path: '/user/$id', extra: null),
    'ticket' => (path: '/ho-tro/$id', extra: null),
    _ => null,
  };
}
