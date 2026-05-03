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

      // Application events.
      if (channel == 'new-comments' && (event == 'new-comment' || event == '.new-comment')) {
        newCommentTick.value++;
        if (payload != null) lastEvent.value = {'kind': 'comment', 'data': payload};
        return;
      }
      // Notification events arrive on the private Lighthouse channel
      // wrapped in `lighthouse-subscription` envelope.
      if (channel != null && _notifChannel != null && channel == _notifChannel
          && (event == '.lighthouse-subscription' || event == 'lighthouse-subscription')) {
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
    // Public — no auth.
    _send({'event': 'pusher:subscribe', 'data': {'channel': 'new-comments'}});

    // Private notifications — only when authenticated.
    if (auth.isAuthenticated && _socketId != null) {
      await _registerNotificationSubscription();
    }
  }

  /// Register a Lighthouse subscription on the GraphQL endpoint to get
  /// a Pusher channel name back, then auth + subscribe.
  Future<void> _registerNotificationSubscription() async {
    final userId = auth.user?['id']?.toString();
    if (userId == null) return;
    try {
      final body = jsonEncode({
        'query': r'subscription($userId: ID!) { notificationReceived(userId: $userId) { id content action sender { id username avatar { url } } } }',
        'variables': {'userId': userId},
      });
      final res = await http.post(
        Uri.parse(apiBase),
        headers: {
          'Content-Type': 'application/json',
          if (auth.token != null) 'Authorization': 'Bearer ${auth.token}',
        },
        body: body,
      );
      if (res.statusCode != 200) return;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final channel = json['extensions']?['lighthouse_subscriptions']?['channel']?.toString();
      if (channel == null) return;
      _notifChannel = channel;

      // Pusher auth handshake — POST socket_id + channel_name to the
      // app's auth endpoint. Server returns the auth signature we send
      // along with the subscribe event.
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
      if (authResp.statusCode != 200) return;
      final authJson = jsonDecode(authResp.body) as Map<String, dynamic>;
      final authSig = authJson['auth']?.toString();
      if (authSig == null) return;

      _send({
        'event': 'pusher:subscribe',
        'data': {
          'channel': privateChannel,
          'auth': authSig,
        },
      });
    } catch (_) {
      // Silent — realtime is best-effort.
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
