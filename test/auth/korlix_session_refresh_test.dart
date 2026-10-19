import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/auth/korlix_session_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _start = DateTime.utc(2026, 10, 18, 12);
const _origin = 'https://api.korlix.example';

String _token(DateTime expiry, {String account = 'member-a', String login = 'login-a'}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({
    'iss': 'https://auth.korlix.example',
    'sub': account,
    'session_id': login,
    'exp': expiry.millisecondsSinceEpoch ~/ 1000,
  })}.fixture';
}

KorlixAuthSession _session(DateTime expiry, {String account = 'member-a', String login = 'login-a'}) =>
    KorlixAuthSession(
      accessToken: _token(expiry, account: account, login: login),
      refreshToken: 'refresh-$account-$login-${expiry.millisecondsSinceEpoch}',
      email: '$account@example.test',
    );

class _Harness {
  _Harness({Duration lifetime = const Duration(minutes: 1)}) {
    value = _session(clock.add(lifetime));
    stored = value;
    coordinator = KorlixSessionRefreshCoordinator(
      current: () => value,
      revision: () => epoch,
      now: () => clock,
      refresh: (session) async {
        refreshCalls++;
        return renew(session);
      },
      persist: (session, stillCurrent) async {
        persistCalls++;
        persistEntered?.complete();
        await persistBarrier?.future;
        if (stillCurrent()) {
          stored = session;
        }
      },
      publish: (session) {
        publishCalls++;
        value = session;
      },
      clear: () async {
        clearCalls++;
        replace(null);
      },
    );
    renew = (_) async => _session(clock.add(const Duration(hours: 1)));
  }

  DateTime clock = _start;
  KorlixAuthSession? value;
  KorlixAuthSession? stored;
  int epoch = 0;
  int refreshCalls = 0;
  int persistCalls = 0;
  int publishCalls = 0;
  int clearCalls = 0;
  Completer<void>? persistEntered;
  Completer<void>? persistBarrier;
  late KorlixRefresh renew;
  late final KorlixSessionRefreshCoordinator coordinator;

  void replace(KorlixAuthSession? session) {
    epoch++;
    value = session;
    stored = session;
  }

  Map<String, String> get headers => {'Authorization': 'Bearer ${value!.accessToken}'};

  KorlixSessionHttpClient client(Future<http.Response> Function(http.Request) handler) =>
      KorlixSessionHttpClient(inner: MockClient(handler), sessions: coordinator, baseUrl: _origin);
}

void main() {
  group('session identity and rejection evidence', () {
    test('rotation preserves identity while another login for the same account does not', () {
      final initial = _token(_start);
      final rotated = _token(_start.add(const Duration(hours: 1)));
      final differentLogin = _token(_start, login: 'login-b');
      expect(korlixSessionIdentity(initial), korlixSessionIdentity(rotated));
      expect(korlixSessionIdentity(initial), isNot(korlixSessionIdentity(differentLogin)));
      expect(korlixAccessTokenExpiry(rotated), _start.add(const Duration(hours: 1)));
      expect(korlixAccessTokenExpiry('legacy-opaque-fixture'), isNull);
    });

    test('only explicit refresh rejection is terminal', () {
      for (final code in [
        'refresh_token_not_found',
        'refresh_token_already_used',
        'session_expired',
        'session_not_found',
        'user_banned',
        'invalid_grant',
      ]) {
        expect(korlixRefreshWasRejected(400, {'code': code}), isTrue, reason: code);
      }
      expect(korlixRefreshWasRejected(401, {'error': 'Invalid refresh token'}), isTrue);
      expect(korlixRefreshWasRejected(403, {'error': 'This device is no longer authorized'}), isTrue);
      for (final status in [429, 500, 503]) {
        expect(korlixRefreshWasRejected(status, {'code': 'session_expired'}), isFalse);
      }
      expect(korlixRefreshWasRejected(400, {'error': 'Temporary gateway failure'}), isFalse);
      expect(korlixRefreshWasRejected(401, {'code': 'brain_vault_current_password_incorrect'}), isFalse);
    });
  });

  group('refresh coordination', () {
    test('concurrent renewals share one rotation and one durable write', () async {
      final h = _Harness();
      final pending = Completer<KorlixAuthSession?>();
      h.renew = (_) => pending.future;
      final first = h.coordinator.ensureFresh();
      final second = h.coordinator.ensureFresh(force: true);
      expect(h.refreshCalls, 1);
      final rotated = _session(h.clock.add(const Duration(hours: 1)));
      pending.complete(rotated);
      expect(await first, same(rotated));
      expect(await second, same(rotated));
      expect(h.persistCalls, 1);
      expect(h.publishCalls, 1);
      expect(h.stored, same(rotated));
      expect(h.value, same(rotated));
      expect(h.epoch, 0, reason: 'Rotation must not look like a different login.');
    });

    test('temporary failure retains credentials and backs off before recovering', () async {
      final h = _Harness();
      final original = h.value;
      h.renew = (_) => Future.error(const KorlixSessionRefreshUnavailable());
      await expectLater(h.coordinator.ensureFresh(), throwsA(isA<KorlixSessionRefreshUnavailable>()));
      expect(h.value, same(original));
      expect(h.stored, same(original));
      expect(h.clearCalls, 0);
      expect(h.coordinator.nextRefreshDelay(), const Duration(seconds: 30));
      await expectLater(h.coordinator.ensureFresh(force: true), throwsA(isA<KorlixSessionRefreshUnavailable>()));
      expect(h.refreshCalls, 1);
      h.clock = h.clock.add(const Duration(seconds: 30));
      h.renew = (_) async => _session(h.clock.add(const Duration(hours: 1)));
      await h.coordinator.ensureFresh();
      expect(h.refreshCalls, 2);
      expect(h.persistCalls, 1);
      expect(h.clearCalls, 0);
      expect(h.coordinator.nextRefreshDelay(), const Duration(minutes: 58));
    });

    testWidgets('caller timeouts keep one rotation alive and persist its late success', (tester) async {
      final h = _Harness();
      final original = h.value;
      final pending = Completer<KorlixAuthSession?>();
      h.renew = (_) => pending.future;
      final assertion = expectLater(
        h.coordinator.ensureFresh(),
        throwsA(isA<KorlixSessionRefreshUnavailable>()),
      );
      await tester.pump(const Duration(seconds: 9));
      await assertion;
      expect(h.value, same(original));
      expect(h.stored, same(original));
      expect(h.clearCalls, 0);
      final secondAssertion = expectLater(
        h.coordinator.ensureFresh(force: true),
        throwsA(isA<KorlixSessionRefreshUnavailable>()),
      );
      await tester.pump(const Duration(seconds: 9));
      await secondAssertion;
      expect(h.refreshCalls, 1, reason: 'A caller timeout must not start another token rotation.');
      expect(h.persistCalls, 0);
      expect(h.publishCalls, 0);
      final rotated = _session(h.clock.add(const Duration(hours: 1)));
      pending.complete(rotated);
      await tester.pump();
      expect(h.value, same(rotated));
      expect(h.stored, same(rotated));
      expect(h.persistCalls, 1);
      expect(h.publishCalls, 1);
      expect(await h.coordinator.ensureFresh(), same(rotated));
      expect(h.refreshCalls, 1);
    });

    for (final change in ['logout', 'account switch']) {
      testWidgets('late refresh after caller timeout cannot undo $change', (tester) async {
        final h = _Harness();
        final pending = Completer<KorlixAuthSession?>();
        h.renew = (_) => pending.future;
        final assertion = expectLater(
          h.coordinator.ensureFresh(),
          throwsA(isA<KorlixSessionRefreshUnavailable>()),
        );
        await tester.pump(const Duration(seconds: 9));
        await assertion;
        final replacement = change == 'logout'
            ? null
            : _session(h.clock.add(const Duration(hours: 1)), account: 'member-b', login: 'login-b');
        h.replace(replacement);
        pending.complete(_session(h.clock.add(const Duration(hours: 1))));
        await tester.pump();
        expect(h.value, same(replacement));
        expect(h.stored, same(replacement));
        expect(h.refreshCalls, 1);
        expect(h.persistCalls, 0);
        expect(h.publishCalls, 0);
        expect(h.clearCalls, 0);
      });
    }

    test('confirmed revocation clears the session exactly once', () async {
      final h = _Harness();
      h.renew = (_) async => null;
      final results = await Future.wait([
        h.coordinator.ensureFresh(),
        h.coordinator.ensureFresh(force: true),
      ]);
      expect(results, [null, null]);
      expect(h.clearCalls, 1);
      expect(h.value, isNull);
      expect(h.stored, isNull);
      expect(h.persistCalls, 0);
    });

    test('logout while refresh is pending cannot restore credentials', () async {
      final h = _Harness();
      final pending = Completer<KorlixAuthSession?>();
      h.renew = (_) => pending.future;
      final result = h.coordinator.ensureFresh();
      final assertion = expectLater(result, throwsA(isA<KorlixSessionChanged>()));
      h.replace(null);
      pending.complete(_session(h.clock.add(const Duration(hours: 1))));
      await assertion;
      expect(h.value, isNull);
      expect(h.stored, isNull);
      expect(h.persistCalls, 0);
      expect(h.publishCalls, 0);
    });

    test('account switch during persistence prevents both stale storage and publication', () async {
      final h = _Harness();
      h.persistEntered = Completer<void>();
      h.persistBarrier = Completer<void>();
      final result = h.coordinator.ensureFresh();
      final assertion = expectLater(result, throwsA(isA<KorlixSessionChanged>()));
      await h.persistEntered!.future;
      final accountB = _session(h.clock.add(const Duration(hours: 1)), account: 'member-b', login: 'login-b');
      h.replace(accountB);
      h.persistBarrier!.complete();
      await assertion;
      expect(h.value, same(accountB));
      expect(h.stored, same(accountB));
      expect(h.publishCalls, 0);
      expect(h.clearCalls, 0);
    });

    test('an old rejected refresh cannot sign out the replacement account', () async {
      final h = _Harness();
      final pending = Completer<KorlixAuthSession?>();
      h.renew = (_) => pending.future;
      final assertion = expectLater(h.coordinator.ensureFresh(), throwsA(isA<KorlixSessionChanged>()));
      final accountB = _session(h.clock.add(const Duration(hours: 1)), account: 'member-b', login: 'login-b');
      h.replace(accountB);
      pending.complete(null);
      await assertion;
      expect(h.value, same(accountB));
      expect(h.clearCalls, 0);
    });

    test('a refresh cannot silently change the login session of the same account', () async {
      final h = _Harness();
      final original = h.value;
      h.renew = (_) async => _session(h.clock.add(const Duration(hours: 1)), login: 'login-b');
      await expectLater(h.coordinator.ensureFresh(), throwsA(isA<KorlixSessionRefreshUnavailable>()));
      expect(h.value, same(original));
      expect(h.stored, same(original));
      expect(h.persistCalls, 0);
      expect(h.clearCalls, 0);
    });

    test('an already expired refresh result is not persisted', () async {
      final h = _Harness();
      h.renew = (_) async => _session(h.clock.subtract(const Duration(seconds: 1)));
      await expectLater(h.coordinator.ensureFresh(), throwsA(isA<KorlixSessionRefreshUnavailable>()));
      expect(h.persistCalls, 0);
      expect(h.publishCalls, 0);
      expect(h.clearCalls, 0);
    });
  });

  group('authenticated HTTP requests', () {
    test('an expired bearer is refreshed and saved before protected dispatch', () async {
      final h = _Harness(lifetime: const Duration(seconds: -1));
      final oldToken = h.value!.accessToken;
      final client = h.client((request) async {
        expect(h.persistCalls, 1);
        expect(h.stored, same(h.value));
        expect(request.headers['Authorization'], 'Bearer ${h.value!.accessToken}');
        expect(request.headers['Authorization'], isNot('Bearer $oldToken'));
        expect(request.body, 'preserved body');
        return http.Response('ok', 200);
      });
      addTearDown(client.close);
      final result = await client.post(Uri.parse('$_origin/api/social/messages'), headers: h.headers, body: 'preserved body');
      expect(result.statusCode, 200);
      expect(h.refreshCalls, 1);
      expect(h.epoch, 0);
    });

    test('early refresh outage uses valid bearer, observes backoff, then recovers', () async {
      final h = _Harness();
      final tokens = <String?>[];
      final oldToken = h.value!.accessToken;
      h.renew = (_) => Future.error(const KorlixSessionRefreshUnavailable());
      final client = h.client((request) async {
        tokens.add(request.headers['Authorization']);
        return http.Response('ok', 200);
      });
      addTearDown(client.close);
      final url = Uri.parse('$_origin/api/social/conversations');
      expect((await client.get(url, headers: h.headers)).statusCode, 200);
      expect((await client.get(url, headers: h.headers)).statusCode, 200);
      expect(tokens, ['Bearer $oldToken', 'Bearer $oldToken']);
      expect(h.refreshCalls, 1);
      expect(h.clearCalls, 0);
      h.clock = h.clock.add(const Duration(seconds: 31));
      h.renew = (_) async => _session(h.clock.add(const Duration(hours: 1)));
      expect((await client.get(url, headers: h.headers)).statusCode, 200);
      expect(tokens.last, 'Bearer ${h.value!.accessToken}');
      expect(tokens.last, isNot(tokens.first));
      expect(h.refreshCalls, 2);
    });

    test('refresh outage blocks expired bearer dispatch without clearing login', () async {
      final h = _Harness(lifetime: const Duration(seconds: -1));
      final original = h.value;
      var requests = 0;
      h.renew = (_) => Future.error(const KorlixSessionRefreshUnavailable());
      final client = h.client((request) async {
        requests++;
        return http.Response('unexpected', 200);
      });
      addTearDown(client.close);
      final result = await client.get(Uri.parse('$_origin/api/social/conversations'), headers: h.headers);
      expect(result.statusCode, 503);
      expect(jsonDecode(result.body)['code'], 'session_refresh_retry');
      expect(requests, 0);
      expect(h.value, same(original));
      expect(h.stored, same(original));
      expect(h.clearCalls, 0);
    });

    test('GET retries once with the rotated bearer and preserves request metadata', () async {
      final h = _Harness(lifetime: const Duration(minutes: 10));
      final tokens = <String?>[];
      final client = h.client((request) async {
        tokens.add(request.headers['Authorization']);
        expect(request.url.query, 'page=2');
        expect(request.headers['x-test-marker'], 'keep');
        return tokens.length == 1
            ? http.Response('{"code":"jwt_expired"}', 401)
            : http.Response('recovered', 200);
      });
      addTearDown(client.close);
      final result = await client.get(
        Uri.parse('$_origin/api/social/conversations?page=2'),
        headers: {...h.headers, 'x-test-marker': 'keep'},
      );
      expect(result.body, 'recovered');
      expect(tokens, hasLength(2));
      expect(tokens.first, isNot(tokens.last));
      expect(h.refreshCalls, 1);
      expect(h.clearCalls, 0);
    });

    test('a second rejected GET is returned without an automatic retry loop', () async {
      final h = _Harness(lifetime: const Duration(minutes: 10));
      var requests = 0;
      final client = h.client((request) async {
        requests++;
        return http.Response('{"code":"jwt_expired"}', 401);
      });
      addTearDown(client.close);
      final result = await client.get(Uri.parse('$_origin/api/social/conversations'), headers: h.headers);
      expect(result.statusCode, 401);
      expect(requests, 2);
      expect(h.refreshCalls, 1);
    });

    for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
      test('$method is never replayed automatically after an authentication failure', () async {
        final h = _Harness(lifetime: const Duration(minutes: 10));
        var requests = 0;
        final client = h.client((request) async {
          requests++;
          return http.Response('{"code":"jwt_expired"}', 401);
        });
        addTearDown(client.close);
        final request = http.Request(method, Uri.parse('$_origin/api/social/messages'))
          ..headers.addAll(h.headers)
          ..body = 'send only once';
        final result = await http.Response.fromStream(await client.send(request));
        expect(result.statusCode, 503);
        expect(result.body, contains('Please retry this action'));
        expect(requests, 1);
        expect(h.refreshCalls, 1);
        expect(h.clearCalls, 0);
      });
    }

    test('multipart uploads are not replayed after an authentication failure', () async {
      final h = _Harness(lifetime: const Duration(minutes: 10));
      var requests = 0;
      final client = h.client((request) async {
        requests++;
        expect(request.body, contains('fixture image'));
        return http.Response('{"code":"jwt_expired"}', 401);
      });
      addTearDown(client.close);
      final request = http.MultipartRequest('POST', Uri.parse('$_origin/api/social/media'))
        ..headers.addAll(h.headers)
        ..files.add(http.MultipartFile.fromString('file', 'fixture image', filename: 'fixture.txt'));
      final result = await http.Response.fromStream(await client.send(request));
      expect(result.statusCode, 503);
      expect(requests, 1);
      expect(h.refreshCalls, 1);
    });

    test('late 401 from a previous bearer uses the already refreshed login', () async {
      final h = _Harness(lifetime: const Duration(minutes: 10));
      final firstResponse = Completer<http.Response>();
      final dispatched = Completer<void>();
      final tokens = <String?>[];
      final client = h.client((request) async {
        tokens.add(request.headers['Authorization']);
        if (tokens.length == 1) {
          dispatched.complete();
          return firstResponse.future;
        }
        return http.Response('recovered', 200);
      });
      addTearDown(client.close);
      final result = client.get(Uri.parse('$_origin/api/social/conversations'), headers: h.headers);
      await dispatched.future;
      await h.coordinator.ensureFresh(force: true);
      firstResponse.complete(http.Response('{"code":"jwt_expired"}', 401));
      expect((await result).statusCode, 200);
      expect(tokens, hasLength(2));
      expect(tokens.last, 'Bearer ${h.value!.accessToken}');
      expect(h.refreshCalls, 1);
      expect(h.persistCalls, 1);
      expect(h.clearCalls, 0);
    });

    test('wrong Brain Vault password remains a domain error without refreshing login', () async {
      final h = _Harness(lifetime: const Duration(minutes: 10));
      const body = '{"code":"brain_vault_current_password_incorrect","error":"Current password is incorrect"}';
      final client = h.client((request) async => http.Response(body, 401, headers: {'x-fixture': 'preserved'}));
      addTearDown(client.close);
      final result = await client.post(Uri.parse('$_origin/api/brain-vault/unlock'), headers: h.headers);
      expect(result.statusCode, 401);
      expect(result.body, body);
      expect(result.headers['x-fixture'], 'preserved');
      expect(h.refreshCalls, 0);
      expect(h.clearCalls, 0);
    });

    test('foreign origins, authentication routes and anonymous requests bypass refresh', () async {
      final h = _Harness(lifetime: const Duration(seconds: -1));
      var requests = 0;
      final client = h.client((request) async {
        requests++;
        return http.Response('unchanged', 401);
      });
      addTearDown(client.close);
      expect((await client.get(Uri.parse('https://other.example/api/social'), headers: h.headers)).statusCode, 401);
      expect((await client.post(Uri.parse('$_origin/api/auth/refresh'), headers: h.headers)).statusCode, 401);
      expect((await client.get(Uri.parse('$_origin/api/public'))).statusCode, 401);
      expect(requests, 3);
      expect(h.refreshCalls, 0);
      expect(h.clearCalls, 0);
    });

    test('old login bearer is blocked after signing in again to the same account', () async {
      final h = _Harness(lifetime: const Duration(minutes: 10));
      final oldHeaders = h.headers;
      final replacement = _session(h.clock.add(const Duration(hours: 1)), login: 'login-b');
      h.replace(replacement);
      var requests = 0;
      final client = h.client((request) async {
        requests++;
        return http.Response('unexpected', 200);
      });
      addTearDown(client.close);
      final result = await client.get(Uri.parse('$_origin/api/social/conversations'), headers: oldHeaders);
      expect(result.statusCode, 503);
      expect(result.body, contains('account changed'));
      expect(requests, 0);
      expect(h.refreshCalls, 0);
      expect(h.value, same(replacement));
    });

    test('late authentication failure cannot refresh or clear a replacement account', () async {
      final h = _Harness(lifetime: const Duration(minutes: 10));
      final pending = Completer<http.Response>();
      final dispatched = Completer<void>();
      final client = h.client((request) async {
        dispatched.complete();
        return pending.future;
      });
      addTearDown(client.close);
      final result = client.get(Uri.parse('$_origin/api/social/conversations'), headers: h.headers);
      await dispatched.future;
      final replacement = _session(h.clock.add(const Duration(hours: 1)), account: 'member-b', login: 'login-b');
      h.replace(replacement);
      pending.complete(http.Response('{"code":"jwt_expired"}', 401));
      expect((await result).statusCode, 503);
      expect(h.refreshCalls, 0);
      expect(h.clearCalls, 0);
      expect(h.value, same(replacement));
    });
  });
}
