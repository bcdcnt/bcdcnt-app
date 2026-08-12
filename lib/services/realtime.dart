import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'auth.dart';

/// Live comment / notification stream — Pusher protocol over a raw
/// WebSocket. Mirrors what the web does in `packages/web/lib/echo.js`,
/// but without bringing in the heavyweight `pusher_channels_flutter`
/// SDK (no native gradle/podfile changes).
///
/// Two channels:
///   * public  `new-comments` — every new comment platform-wide (no
///     auth needed). Bumps [newCommentTick] so listeners can refresh.
///   * private `<lighthouse_channel>` — server-issued channel for the
///     authed user's notifications. Requires Lighthouse to register a
///     subscription first, then a Pusher auth handshake to subscribe.
///     Bumps [notificationTick] on every event.
///
/// Listeners (NotificationsDropdown, DesktopCommentSidebar, etc.) read
/// the ValueNotifiers via `addListener` and trigger their own refetch.
class RealtimeService {
  // Pusher app config — mirrored from web's `createEchoInstance`
  // (packages/web/lib/echo.js). Keep in sync if Soketi changes.
  static const _pusherKey = 'JaRyk5OUh1mjuooBBg6ZogrCxHNPuccFbsSN5CVuKbQ';
  static const _wsHost = 'ws.bcdcnt.net';
  static const _wsPort = 443;
  static const _cluster = 'mt1';

  // Lighthouse subscription queries (khớp web packages/web/lib/echo.js).
  static const _newCommentQuery =
      'subscription { newComment { id content commentable_type commentable_id '
      'user { id username avatar { url } } '
      'object { __typename '
      '... on Song { id title slug } ... on Folk { id title slug } '
      '... on Instrumental { id title slug } ... on Poem { id title slug } '
      '... on Karaoke { id title slug } ... on Artist { id title slug } '
      '... on Composer { id title slug } ... on Poet { id title slug } '
      '... on Recomposer { id title slug } ... on Sheet { id title slug } '
      '... on Document { id title slug } ... on Discussion { id title slug } '
      '... on Playlist { id title slug } } } }';
  static const _notifQuery =
      r'subscription($userId: ID!) { notificationReceived(userId: $userId) { id content action sender { id username avatar { url } } } }';

  final String apiBase;
  final AuthProvider auth;

  /// Bumped whenever any user posts a new comment (public channel).
  final ValueNotifier<int> newCommentTick = ValueNotifier(0);

  /// Bumped whenever the authed user receives a new notification.
  final ValueNotifier<int> notificationTick = ValueNotifier(0);

  /// Most recent realtime event payload, for callers that want banner
  /// previews instead of just a tick. Pair (kind, data) where kind is
  /// `'comment'` or `'notification'`.
  final ValueNotifier<Map<String, dynamic>?> lastEvent = ValueNotifier(null);

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _socketId;
  bool _connected = false;
  Timer? _reconnectTimer;
  // Subscription names we've successfully joined so we can re-subscribe
  // on reconnect.
  final Set<String> _subscribedChannels = {};
  // Lighthouse channel name for the active user's notification sub —
  // returned from the GraphQL `notificationReceived` registration.
  String? _notifChannel;
  // Lighthouse channel for the public `newComment` subscription (khớp web —
  // KHÔNG phải channel công khai "new-comments" như trước, cái đó server
  // không broadcast tới nên comment mới không bao giờ về).
  String? _newCommentChannel;

  RealtimeService({required this.apiBase, required this.auth});

  /// Connect (or reconnect) to the Pusher socket. Idempotent.
  void connect() {
    if (_connected || _channel != null) return;
    final url = 'wss://$_wsHost:$_wsPort/app/$_pusherKey?protocol=7&client=flutter&version=1.0&flash=false';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _connected = false;
    _socketId = null;
    _sub?.cancel();
    _sub = null;
    _channel = null;
    // Reset channel đã đăng ký để re-subscribe sau khi reconnect (socket_id
    // mới → subscription cũ vô hiệu). Không reset thì tick không tăng nữa.
    _subscribedChannels.clear();
    _notifChannel = null;
    _newCommentChannel = null;
    _reconnectTimer?.cancel();
    // Exponential-ish backoff: 3s, single retry. Real apps would do
    // more, but Pusher reconnect storms have caused subscriber bloat
    // before — keep it cautious.
    _reconnectTimer = Timer(const Duration(seconds: 3), connect);
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _connected = false;
    _subscribedChannels.clear();
    _notifChannel = null;
    _newCommentChannel = null;
  }

  void _onMessage(dynamic raw) {
    try {
      final outer = jsonDecode(raw as String) as Map<String, dynamic>;
      final event = outer['event']?.toString();
      final data = outer['data'];
      final channel = outer['channel']?.toString();
      // Pusher wraps event payloads as JSON-encoded strings inside
      // `data`. Decode if it looks like JSON.
      Map<String, dynamic>? payload;
      if (data is String) {
        try { payload = jsonDecode(data) as Map<String, dynamic>; }
        catch (_) { payload = {'raw': data}; }
      } else if (data is Map) {
        payload = Map<String, dynamic>.from(data);
      }

      if (event == 'pusher:connection_established') {
        _socketId = payload?['socket_id']?.toString();
        _connected = true;
        _bootstrapSubscriptions();
        return;
      }
      if (event == 'pusher:error') {
        _scheduleReconnect();
        return;
      }
      if (event == 'pusher_internal:subscription_succeeded') {
        if (channel != null) _subscribedChannels.add(channel);
        return;
      }

      // Application events — Lighthouse gói kết quả subscription trong event
      // `.lighthouse-subscription` trên channel động do server cấp.
      final isLighthouse = event == '.lighthouse-subscription' || event == 'lighthouse-subscription';
      // New comment (public Lighthouse subscription `newComment`).
      if (isLighthouse && channel != null && _newCommentChannel != null && channel == _newCommentChannel) {
        newCommentTick.value++;
        final c = payload?['result']?['data']?['newComment'];
        if (c is Map) lastEvent.value = {'kind': 'comment', 'data': Map<String, dynamic>.from(c)};
        return;
      }
      // Notification (private Lighthouse subscription `notificationReceived`).
      if (isLighthouse && channel != null && _notifChannel != null && channel == _notifChannel) {
        notificationTick.value++;
        final notif = payload?['result']?['data']?['notificationReceived'];
        if (notif is Map) lastEvent.value = {'kind': 'notification', 'data': Map<String, dynamic>.from(notif)};
        return;
      }
    } catch (_) {
      // Swallow — bad frame, skip.
    }
  }

  Future<void> _bootstrapSubscriptions() async {
    if (_socketId == null) return;
    // New comments — Lighthouse subscription công khai (khớp web). Đăng ký lấy
    // channel động rồi auth + subscribe; nhận qua event .lighthouse-subscription.
    if (_newCommentChannel == null) {
      _newCommentChannel = await _registerLighthouseSub(_newCommentQuery, const {});
    }
    // Notifications — private, chỉ khi đăng nhập.
    if (auth.isAuthenticated && _notifChannel == null) {
      final userId = auth.user?['id']?.toString();
      if (userId != null) {
        _notifChannel = await _registerLighthouseSub(_notifQuery, {'userId': userId});
      }
    }
  }

  /// Đăng ký 1 Lighthouse subscription: POST query lấy channel động, làm Pusher
  /// auth handshake, rồi subscribe. Trả về tên channel (private-…) đã subscribe
  /// để [_onMessage] so khớp với `channel` của event nhận về.
  Future<String?> _registerLighthouseSub(String query, Map<String, dynamic> variables) async {
    try {
      final res = await http.post(
        Uri.parse(apiBase),
        headers: {
          'Content-Type': 'application/json',
          if (auth.token != null) 'Authorization': 'Bearer ${auth.token}',
        },
        body: jsonEncode({'query': query, 'variables': variables}),
      );
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final channel = json['extensions']?['lighthouse_subscriptions']?['channel']?.toString();
      if (channel == null) return null;

      // Pusher auth handshake — POST socket_id + channel_name tới auth endpoint,
      // server trả chữ ký auth để gửi kèm sự kiện subscribe.
      final stripped = channel.replaceFirst(RegExp(r'^private-'), '');
      final privateChannel = 'private-$stripped';
      final authResp = await http.post(
        Uri.parse('${apiBase.replaceAll('/graphql', '')}/graphql/subscriptions/auth'),
        headers: {
          'Content-Type': 'application/json',
          if (auth.token != null) 'Authorization': 'Bearer ${auth.token}',
        },
        body: jsonEncode({'socket_id': _socketId, 'channel_name': privateChannel}),
      );
      if (authResp.statusCode != 200) return null;
      final authSig = (jsonDecode(authResp.body) as Map<String, dynamic>)['auth']?.toString();
      if (authSig == null) return null;

      _send({'event': 'pusher:subscribe', 'data': {'channel': privateChannel, 'auth': authSig}});
      return privateChannel;
    } catch (_) {
      // Silent — realtime is best-effort.
      return null;
    }
  }

  void _send(Map<String, dynamic> frame) {
    final ch = _channel;
    if (ch == null) return;
    try { ch.sink.add(jsonEncode(frame)); } catch (_) {}
  }

  /// Re-bootstrap subscriptions when auth state changes (login /
  /// logout). Caller should invoke after AuthProvider notifies.
  void onAuthChanged() {
    _notifChannel = null;
    if (_connected && _socketId != null) {
      _bootstrapSubscriptions();
    }
  }
}

/// Singleton accessor — exposed top-level so widgets that aren't under
/// the Provider tree (notifications dropdown overlay, etc.) can wire
/// listeners without context plumbing.
RealtimeService? realtimeService;
