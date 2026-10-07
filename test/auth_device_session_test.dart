import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_wiz_command_center/main.dart' as app;

class LockedSecureStorage extends TestFlutterSecureStoragePlatform {
  LockedSecureStorage() : super({});
  @override
  Future<String?> read({required String key, required Map<String, String> options}) async {
    throw PlatformException(code: 'locked');
  }
  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    throw PlatformException(code: 'locked');
  }
}

const deviceId = 'korlix_existing_device';
const deviceLabel = 'Existing browser';

void expectDeviceIdentity(http.Request request) {
  expect(request.headers['X-Korlix-Device-Id'], deviceId);
  expect(request.headers['X-Korlix-Device-Label'], deviceLabel);
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['device_id'], deviceId);
  expect(body['device_label'], deviceLabel);
  expect(body['platform'], request.headers['X-Korlix-Platform']);
}

http.Response sessionResponse() => http.Response(
  jsonEncode({
    'session': {'access_token': 'new-access', 'refresh_token': 'new-refresh'},
    'user': {'email': 'member@example.test'},
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      app.KorlixDeviceStore.deviceIdKey: deviceId,
      app.KorlixDeviceStore.deviceLabelKey: deviceLabel,
    });
    app.kKorlixDeviceId = null;
    app.kKorlixDeviceLabel = null;
  });

  test('locked storage cannot keep an explicitly signed-out session in memory', () async {
    FlutterSecureStoragePlatform.instance = LockedSecureStorage();
    addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
    app.korlixSetInMemorySession(const app.KorlixAuthSession(
      accessToken: 'fixture-access', refreshToken: 'fixture-refresh',
      email: 'member@example.test',
    ));
    await app.korlixClearLocalAuthSession();
    expect(app.kKorlixAccessToken, isNull);
    expect(app.kKorlixRefreshToken, isNull);
    expect(app.kKorlixUserEmail, isNull);
    expect(await app.KorlixSessionStore.load(), isNull,
        reason: 'Logout tombstone must prevent restoring undeletable keychain data');
  });

  testWidgets('locked session restore ends loading and preserves migration credentials', (tester) async {
    SharedPreferences.setMockInitialValues({
      app.KorlixDeviceStore.deviceIdKey: deviceId,
      app.KorlixDeviceStore.deviceLabelKey: deviceLabel,
      app.KorlixSessionStore.accessTokenKey: 'fixture-legacy-access',
      app.KorlixSessionStore.refreshTokenKey: 'fixture-legacy-refresh',
    });
    FlutterSecureStoragePlatform.instance = LockedSecureStorage();
    addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: app.AuthGate()));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.byType(app.AuthScreen), findsOneWidget);
    expect(app.kKorlixAccessToken, isNull);
    expect(find.text('We could not restore your session. Unlock your device and sign in again.'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(app.KorlixSessionStore.accessTokenKey), 'fixture-legacy-access');
    expect(prefs.getString(app.KorlixSessionStore.refreshTokenKey), 'fixture-legacy-refresh');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'refresh uses the persisted device identity used by protected requests',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return sessionResponse();
      });
      final result = await app.KorlixSessionStore.refresh(
        app.KorlixAuthSession(
          accessToken: 'old-access',
          refreshToken: 'old-refresh',
        ),
        client: client,
      );
      expect(result?.accessToken, 'new-access');
      expect(requests.single.url.path, '/api/auth/refresh');
      expectDeviceIdentity(requests.single);
      expect(jsonDecode(requests.single.body)['refresh_token'], 'old-refresh');
      expect(app.KorlixDeviceStore.headers()['X-Korlix-Device-Id'], deviceId);
      await app.KorlixDeviceStore.ensureLoaded();
      expect(app.kKorlixDeviceId, deviceId);
    },
  );

  test('a refresh rejected by the server clears local authentication', () async {
    await app.KorlixSessionStore.save(const app.KorlixAuthSession(
      accessToken: 'fixture-access', refreshToken: 'fixture-refresh',
    ));
    app.korlixSetInMemorySession(const app.KorlixAuthSession(
      accessToken: 'fixture-access', refreshToken: 'fixture-refresh',
    ));
    final headers = await app.korlixAuthenticatedBackendHeaders(
      client: MockClient((_) async => http.Response('{"error":"revoked"}', 403)),
    );
    expect(headers.containsKey('Authorization'), isFalse);
    expect(app.kKorlixAccessToken, isNull);
    expect(await app.KorlixSessionStore.load(), isNull);
  });

  test('late refresh cannot restore the account after sign out', () async {
    app.korlixSetInMemorySession(const app.KorlixAuthSession(
      accessToken: 'fixture-access', refreshToken: 'fixture-refresh',
    ));
    await expectLater(app.korlixAuthenticatedBackendHeaders(
      client: MockClient((_) async {
        await app.korlixClearLocalAuthSession();
        return sessionResponse();
      }),
    ), throwsStateError);
    expect(app.kKorlixAccessToken, isNull);
    expect(await app.KorlixSessionStore.load(), isNull);
  });

  test('consent uses stable issuer and subject, never the bearer token or email', () {
    String token(String issuer, String subject, int expiry) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'iss': issuer, 'sub': subject, 'exp': expiry})))}.signature';
    final original = app.korlixConsentAccountScope(app.KorlixAuthSession(accessToken: token('issuer-a', 'subject-a', 1)));
    expect(original, isNotNull);
    expect(app.korlixConsentAccountScope(app.KorlixAuthSession(accessToken: token('issuer-a', 'subject-a', 2))), original);
    expect(app.korlixConsentAccountScope(app.KorlixAuthSession(accessToken: token('issuer-a', 'subject-b', 1))), isNot(original));
    expect(app.korlixConsentAccountScope(app.KorlixAuthSession(accessToken: token('issuer-b', 'subject-a', 1))), isNot(original));
    expect(app.korlixConsentAccountScope(const app.KorlixAuthSession(accessToken: 'invalid')), isNull);
    expect(app.korlixConsentAccountScope(null), isNull);
  });

  test('a rejected refresh remains rejected', () async {
    final result = await app.KorlixSessionStore.refresh(
      app.KorlixAuthSession(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
      ),
      client: MockClient((request) async {
        expectDeviceIdentity(request);
        return http.Response('{"error":"Device session is revoked"}', 403);
      }),
    );
    expect(result, isNull);
  });

  testWidgets('sign in registers the same device used for later API calls', (
    tester,
  ) async {
    final requests = <http.Request>[];
    app.KorlixAuthSession? signedIn;
    await tester.pumpWidget(
      MaterialApp(
        home: app.AuthScreen(
          seasonalDate: DateTime(2026, 11, 1),
          client: MockClient((request) async {
            requests.add(request);
            return sessionResponse();
          }),
          onSignedIn: (session) async => signedIn = session,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'member@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password')),
      'test-password',
    );
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(requests.single.url.path, '/api/auth/signin');
    expectDeviceIdentity(requests.single);
    expect(app.KorlixDeviceStore.headers()['X-Korlix-Device-Id'], deviceId);
    expect(signedIn?.accessToken, 'new-access');
  });
}
