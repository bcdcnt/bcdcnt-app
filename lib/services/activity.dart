import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'api.dart';
import 'auth.dart';

/// Mirrors `packages/core/api.js#logActivity` from the web. Fires the
/// `logActivity` mutation on detail-view actions (song, sheet, person,
/// document, playlist, discussion, user, tag, …) so the user's activity
/// feed and "view" stats are populated identically across web + Flutter.
///
/// No-ops when the user is not authenticated (the backend mutation
/// requires auth). Errors are swallowed — view tracking is best-effort
/// and must not break the screen if the network blip.
const _logActivityMutation = r'''mutation($action: String!, $object_type: String!, $object_id: ID) {
  logActivity(action: $action, object_type: $object_type, object_id: $object_id) { id }
}''';

Future<void> logActivity(AuthProvider auth, String action, String objectType, dynamic objectId) async {
  if (!auth.isAuthenticated) return;
  if (objectId == null) return;
  try {
    await auth.authedMutate(_logActivityMutation, {
      'action': action,
      'object_type': objectType,
      'object_id': objectId.toString(),
    });
  } catch (_) {}
}

const _logShareMutation = r'''mutation($t: String!, $id: ID!, $c: String, $p: String) {
  logShare(object_type: $t, object_id: $id, channel: $c, platform: $p)
}''';

/// Counts one share (song or person) and returns the new total, or null on
/// failure. Guests count too (the API goes by IP for them); the server
/// counts each person once per object a day, so a repeat tap is harmless.
Future<int?> logShare(AuthProvider auth, String objectType, dynamic objectId, String channel) async {
  if (objectId == null) return null;
  final platform = kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : Platform.isMacOS ? 'macos' : Platform.isWindows ? 'windows' : 'linux');
  final vars = {'t': objectType, 'id': objectId.toString(), 'c': channel, 'p': platform};
  try {
    final d = auth.isAuthenticated ? await auth.authedMutate(_logShareMutation, vars) : await ApiClient.mutate(_logShareMutation, vars);
    return (d['logShare'] as num?)?.toInt();
  } catch (_) {
    return null;
  }
}
