import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_wiz_command_center/main.dart' as app;

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
    SharedPreferences.setMockInitialValues({
      app.KorlixDeviceStore.deviceIdKey: deviceId,
      app.KorlixDeviceStore.deviceLabelKey: deviceLabel,
    });
    app.kKorlixDeviceId = null;
    app.kKorlixDeviceLabel = null;
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
