import 'dart:async';
import 'package:flutter/foundation.dart';
import 'analytics.dart';
import 'api.dart';
import 'auth.dart';
import 'player.dart';

/// "N người đang nghe cùng bạn" on the Đài, near real time: while the Đài
/// plays (anywhere in the app) we ping the API every 30s; stopping pings
/// once more so we drop out at once. A Đài card on screen that is only
/// looking reads the count with the same call. The API forgets anyone
/// silent for 75s.
class RadioPresence {
  RadioPresence._();
  static final instance = RadioPresence._();

  /// (how many are listening, a few members' faces).
  final ValueNotifier<(int, List<Map<String, dynamic>>)> listeners = ValueNotifier((0, const []));

  PlayerProvider? _player;
  AuthProvider? _auth;
  bool _on = false;
  int _watchers = 0;

  static bool isRadio(PlayerProvider p) => (p.sourceLabel ?? '').startsWith('Đài BCĐCNT');

  void bind(PlayerProvider player, AuthProvider auth) {
    _player = player;
    _auth = auth;
    player.addListener(_onPlayer);
    Timer.periodic(const Duration(seconds: 30), (_) {
      if (_on || _watchers > 0) _ping();
    });
  }

  /// A Đài card came on screen (or left): it wants a fresh count.
  void watch() {
    _watchers++;
    _ping();
  }

  void unwatch() => _watchers = (_watchers - 1).clamp(0, 1 << 20);

  void _onPlayer() {
    final p = _player;
    if (p == null) return;
    final on = p.isPlaying && isRadio(p);
    if (on != _on) {
      _on = on;
      _ping();
    }
  }

  Future<void> _ping() async {
    final id = await Analytics.clientId();
    if (id == null) return;
    const m = r'mutation($c: String!, $p: Boolean!) { radioHeartbeat(client_id: $c, playing: $p) { count users { id username avatar } } }';
    final vars = {'c': id, 'p': _on};
    try {
      final auth = _auth;
      final d = auth != null && auth.isAuthenticated ? await auth.authedMutate(m, vars) : await ApiClient.mutate(m, vars);
      final r = d['radioHeartbeat'];
      if (r is! Map) return;
      listeners.value = (
        (r['count'] as num?)?.toInt() ?? 0,
        [for (final u in (r['users'] as List? ?? const [])) if (u is Map) Map<String, dynamic>.from(u)],
      );
    } catch (_) {}
  }
}
