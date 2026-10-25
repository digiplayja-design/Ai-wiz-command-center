import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:korlix_receipt_core/auth/korlix_token_store.dart';
import 'package:korlix_receipt_core/auth/korlix_session_refresh.dart';
import 'package:korlix_messenger/messenger_auth.dart';

String testToken({
  String user = 'fixture-user',
  String login = 'fixture-login',
}) {
  String part(Object v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'iss': 'https://auth.example.test', 'sub': user, 'session_id': login, 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})}.fixture';
}

Map<String, Object> signedIn() => {
  'user': {'id': 'fixture-user'},
  'session': {'access_token': testToken(), 'refresh_token': 'fixture-refresh'},
};
http.Response response(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  MessengerAuthController auth(
    FutureOr<http.Response> Function(http.Request) handler,
  ) {
    final controller = MessengerAuthController(
      client: MockClient((request) async => await handler(request)),
      tokenStore: KorlixTokenStore(useSecureStorage: false),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('existing KORLIX credentials use the shared backend and stable app device ID', () async {
    final requests = <http.Request>[];
    final a = auth((r) {
      requests.add(r);
      return response(signedIn());
    });
    expect(
      await a.authenticate(
        email: ' SAME@Example.Test ',
        password: 'existing-password',
      ),
      isTrue,
    );
    final body = jsonDecode(requests.single.body) as Map;
    expect(requests.single.url.path, '/api/messenger/auth/signin');
    expect(body['email'], 'same@example.test');
    expect(body['client_app'], 'korlix_messenger');
    expect(body['device_id'], startsWith('korlix_messenger_'));
    expect(a.headers()['X-Korlix-Device-Id'], body['device_id']);
    expect(a.headers()['Authorization'], startsWith('Bearer '));
    expect(a.session!.email, 'same@example.test');
  });
  test(
    'signup selects free Basic and retains age and policy declarations',
    () async {
      late Map body;
      final a = auth((r) {
        body = jsonDecode(r.body) as Map;
        return response({'session': null});
      });
      expect(
        await a.authenticate(
          email: 'new@example.test',
          password: 'new-password',
          signup: true,
          ageBand: '18_plus',
          acceptedPolicies: true,
        ),
        isFalse,
      );
      expect(body['signup_plan'], 'basic');
      expect(body['signup_eligibility']['policy_version'], '2026-10-06');
      expect(
        body.containsKey('confirmation_target'),
        isFalse,
        reason: 'Uses the independent web confirmation flow, not the main app callback',
      );
      expect(a.session, isNull);
    },
  );
  test('duplicate email offers existing-account recovery without persisting a session', () async {
    final a = auth(
      (_) => response({
        'code': 'KORLIX_ACCOUNT_EXISTS',
        'error': existingKorlixAccountMessage,
      }, 409),
    );
    await expectLater(
      a.authenticate(
        email: 'same@example.test',
        password: 'new-password',
        signup: true,
        ageBand: '18_plus',
        acceptedPolicies: true,
      ),
      throwsA(
        isA<MessengerAuthException>().having(
          (e) => e.existingAccount,
          'existing account',
          isTrue,
        ),
      ),
    );
    expect(a.session, isNull);
    expect(
      (await SharedPreferences.getInstance()).getString(
        KorlixTokenStore.accessTokenKey,
      ),
      isNull,
    );
  });
  test(
    'old backend duplicate error still offers existing-account sign in',
    () async {
      final a = auth(
        (_) => response({'error': 'User already registered'}, 422),
      );
      await expectLater(
        a.authenticate(
          email: 'same@example.test',
          password: 'password',
          signup: true,
        ),
        throwsA(
          isA<MessengerAuthException>().having(
            (e) => e.existingAccount,
            'existing account',
            isTrue,
          ),
        ),
      );
    },
  );
  test('device limit and outages retain their real error', () async {
    for (final item in [
      (403, 'Device limit reached for your basic plan.'),
      (503, 'Temporarily unavailable'),
    ]) {
      final a = auth((_) => response({'error': item.$2}, item.$1));
      await expectLater(
        a.authenticate(email: 'same@example.test', password: 'password'),
        throwsA(
          isA<MessengerAuthException>()
              .having((e) => e.existingAccount, 'existing account', isFalse)
              .having((e) => e.message, 'message', item.$2),
        ),
      );
    }
  });
  test(
    'password reset uses the existing shared-account recovery service',
    () async {
      late http.Request request;
      final a = auth((r) {
        request = r;
        return response({'success': true});
      });
      await a.requestPasswordReset(' SAME@Example.Test ');
      expect(request.url.path, '/api/messenger/auth/password-reset');
      expect(jsonDecode(request.body), {'email': 'same@example.test'});
    },
  );
  test('signout clears local session and revokes only this device', () async {
    final requests = <http.Request>[];
    final a = auth((r) {
      requests.add(r);
      return response(
        r.url.path.endsWith('signin') ? signedIn() : {'success': true},
      );
    });
    await a.authenticate(email: 'same@example.test', password: 'password');
    await a.signOut();
    expect(a.session, isNull);
    expect(requests.last.url.path, '/api/messenger/auth/signout');
    expect(
      jsonDecode(requests.last.body)['device_id'],
      a.deviceHeaders['X-Korlix-Device-Id'],
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        KorlixTokenStore.accessTokenKey,
      ),
      isNull,
    );
  });
  test(
    'a late sign-in response cannot restore a session after signout',
    () async {
      final pending = Completer<http.Response>(), sent = Completer<void>();
      final a = auth((r) {
        sent.complete();
        return pending.future;
      });
      final login = a.authenticate(
        email: 'same@example.test',
        password: 'password',
      );
      final rejected = expectLater(login, throwsA(isA<KorlixSessionChanged>()));
      await sent.future;
      await a.signOut();
      pending.complete(response(signedIn()));
      await rejected;
      expect(a.session, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString(
          KorlixTokenStore.accessTokenKey,
        ),
        isNull,
      );
    },
  );
}
