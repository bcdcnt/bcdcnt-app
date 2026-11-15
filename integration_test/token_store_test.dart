import 'package:bcdcnt/services/token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Runs on a device/simulator: TokenStore against the real platform secure store.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(TokenStore.clear);

  testWidgets('tokens saved by older versions move from prefs to the secure store', (_) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', 'old-access');
    await prefs.setString('refresh_token', 'old-refresh');

    final t = await TokenStore.read();
    expect(t.access, 'old-access');
    expect(t.refresh, 'old-refresh');
    expect(prefs.getString('access_token'), isNull);
    expect(prefs.getString('refresh_token'), isNull);
    expect(await const FlutterSecureStorage(iOptions: IOSOptions(accountName: 'net.bcdcnt.auth')).read(key: 'refresh_token'), 'old-refresh');
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'), isNull, reason: 'not under the generic service name');
  });

  testWidgets('write, rotate, clear', (_) async {
    await TokenStore.write('a1', 'r1');
    await TokenStore.write('a2', 'r2');
    var t = await TokenStore.read();
    expect((t.access, t.refresh), ('a2', 'r2'));

    await TokenStore.write('a3', null);
    t = await TokenStore.read();
    expect((t.access, t.refresh), ('a3', null));

    await TokenStore.clear();
    t = await TokenStore.read();
    expect((t.access, t.refresh), (null, null));
  });
}
