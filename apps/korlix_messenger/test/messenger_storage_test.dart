import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:korlix_receipt_core/auth/korlix_token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Messenger sign-out preserves hub credentials even on a shared web origin',
    () async {
      final hub = KorlixTokenStore(useSecureStorage: false);
      final messenger = KorlixTokenStore(
        useSecureStorage: false,
        namespace: 'korlix_messenger',
      );
      await hub.write(accessToken: 'hub-token', refreshToken: 'hub-refresh');
      expect(await messenger.read(), isNull);
      await messenger.write(
        accessToken: 'messenger-token',
        refreshToken: 'messenger-refresh',
      );
      expect((await hub.read())!.accessToken, 'hub-token');
      expect((await messenger.readOnly())!.accessToken, 'messenger-token');
      await messenger.clear();
      expect(await messenger.read(), isNull);
      expect((await hub.read())!.refreshToken, 'hub-refresh');
    },
  );

  test('hub logout cannot erase the Messenger installation session', () async {
    final hub = KorlixTokenStore(useSecureStorage: false);
    final messenger = KorlixTokenStore(
      useSecureStorage: false,
      namespace: 'korlix_messenger',
    );
    await messenger.write(
      accessToken: 'messenger-token',
      refreshToken: 'messenger-refresh',
    );
    await hub.clear();
    final secondaryEngine = KorlixTokenStore(
      useSecureStorage: false,
      namespace: 'korlix_messenger',
    );
    expect((await secondaryEngine.readOnly())!.accessToken, 'messenger-token');
  });
}
