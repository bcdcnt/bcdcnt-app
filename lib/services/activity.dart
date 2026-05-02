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
