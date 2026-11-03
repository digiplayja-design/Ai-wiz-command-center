import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korlix_copy_box/copybox_auth.dart';
import 'package:korlix_auth_core/auth/korlix_session_refresh.dart';
import 'package:korlix_auth_core/auth/korlix_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

String token({
  String user = 'fixture-user',
  String login = 'fixture-login',
  String email = 'person@example.test',
  Duration remaining = const Duration(hours: 1),
  String issuer = 'https://auth.example.test',
}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({
    'iss': issuer,
    'sub': user,
    'session_id': login,
    'email': email,
    'exp': DateTime.now().add(remaining).millisecondsSinceEpoch ~/ 1000,
  })}.fixture';
}

Map<String, dynamic> signedIn({String? access, String refresh = 'fixture-refresh'}) => {
  'success': true,
  'user': {'id': 'fixture-user'},
  'session': {'access_token': access ?? token(), 'refresh_token': refresh},
};

http.Response response(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status, headers: {'content-type': 'application/json'});

class MemorySecureBackend implements KorlixSecureTokenBackend {
  String? value;
  Completer<String?>? delayedRead;
  Completer<void>? readStarted;
  @override
  Future<String?> read() async {
    if (delayedRead != null) {
      readStarted?.complete();
      final result = await delayedRead!.future;
      delayedRead = null;
      return result;
    }
    return value;
  }
  @override
  Future<void> write(String next) async {
    value = next;
  }
  @override
  Future<void> delete() async {
    value = null;
  }
}

class FailingClearTokenStore extends KorlixTokenStore {
  FailingClearTokenStore()
      : super(namespace: 'korlix_copybox', useSecureStorage: false);

  bool failClear = true;

  @override
  Future<void> clear() async {
    if (failClear) throw const KorlixTokenStorageException();
    await super.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  CopyBoxAuthController controller(
    Future<http.Response> Function(http.Request) handler, {
    KorlixTokenStore? tokenStore,
  }) {
    final client = MockClient(handler);
    final auth = CopyBoxAuthController(
      client: client,
      backendUrl: 'https://backend.example.test',
      tokenStore: tokenStore ?? KorlixTokenStore(
        namespace: 'korlix_copybox',
        useSecureStorage: false,
      ),
    );
    addTearDown(() {
      auth.dispose();
      client.close();
    });
    return auth;
  }

  Future<void> connect(CopyBoxAuthController auth) async {
    expect(await auth.authenticate(email: ' Person@Example.Test ', password: 'secure-password'), isTrue);
  }

  test('shared sign-in uses independent stable device and token namespace', () async {
    final requests = <http.Request>[];
    final auth = controller((request) async {
      requests.add(request);
      return response(signedIn());
    });
    await connect(auth);
    final request = requests.single;
    final body = jsonDecode(request.body) as Map;
    expect(request.url.path, '/api/auth/signin');
    expect(body['email'], 'person@example.test');
    expect(body['password'], 'secure-password');
    expect(body['client_app'], 'korlix_copybox');
    expect(body['device_id'], startsWith('korlix_copybox_'));
    expect(request.headers['X-Korlix-App'], 'korlix_copybox');
    expect(auth.deviceHeaders['X-Korlix-Device-Id'], body['device_id']);
    expect(auth.headers()['Authorization'], 'Bearer ${auth.session!.accessToken}');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('korlix_copybox_access_token'), auth.session!.accessToken);
    expect(prefs.getString(KorlixTokenStore.accessTokenKey), isNull);
    expect(prefs.getString('korlix_copybox_device_id'), body['device_id']);
  });

  test('same shared account scope survives login and email rotation', () async {
    var count = 0;
    final auth = controller((_) async => response(signedIn(access: token(
      login: 'login-${count++}', email: 'email-$count@example.test',
    ))));
    await connect(auth);
    final original = auth.accountScope;
    await connect(auth);
    expect(auth.accountScope, original);
    expect(jsonDecode(original!), ['https://auth.example.test', 'fixture-user']);
    expect(original, isNot(contains(auth.session!.accessToken)));
  });

  test('different issuers or subjects cannot share a local partition', () async {
    var count = 0;
    final auth = controller((_) async => response(signedIn(access: switch (count++) {
      0 => token(),
      1 => token(user: 'second-user'),
      _ => token(user: 'second-user', issuer: 'https://other-auth.example.test'),
    })));
    await connect(auth);
    final first = auth.accountScope;
    await connect(auth);
    final second = auth.accountScope;
    await connect(auth);
    expect(first, isNot(second));
    expect(second, isNot(auth.accountScope));
  });

  test('new account sends current eligibility through generic signup', () async {
    late Map body;
    final auth = controller((request) async {
      expect(request.url.path, '/api/auth/signup');
      body = jsonDecode(request.body) as Map;
      return response({'success': true, 'session': null});
    });
    final active = await auth.authenticate(
      email: 'new@example.test', password: 'secure-password', signup: true,
      ageBand: '16_17', acceptedPolicies: true, parentPermission: true,
    );
    expect(active, isFalse);
    expect(auth.session, isNull);
    expect(body['signup_eligibility'], {
      'age_band': '16_17', 'terms_accepted': true,
      'privacy_acknowledged': true, 'parent_permission': true,
      'policy_version': '2026-10-06',
    });
    expect(body.containsKey('confirmation_target'), isFalse);
  });

  test('eligibility failure stays local before signup request', () async {
    var calls = 0;
    final auth = controller((_) async { calls++; return response(signedIn()); });
    await expectLater(auth.authenticate(
      email: 'new@example.test', password: 'secure-password', signup: true,
      ageBand: '16_17', acceptedPolicies: true,
    ), throwsA(isA<CopyBoxAuthException>().having((e) => e.code, 'code', 'SIGNUP_ELIGIBILITY_REQUIRED')));
    expect(calls, 0);
  });

  test('only explicit existing-account responses produce existing-account guidance', () async {
    final auth = controller((_) async => response({
      'error': 'User already registered', 'code': 'user_already_exists',
    }, 422));
    await expectLater(auth.authenticate(
      email: 'known@example.test', password: 'secure-password', signup: true,
      ageBand: '18_plus', acceptedPolicies: true,
    ), throwsA(isA<CopyBoxAuthException>().having((e) => e.existingAccount, 'existing account', isTrue)));
    expect(auth.session, isNull);
    expect(existingKorlixAccountMessage, contains('same email address and password'));
    expect(const CopyBoxAuthException('Service unavailable', status: 503).existingAccount, isFalse);
    expect(const CopyBoxAuthException('Email not confirmed', code: 'email_not_confirmed').emailUnconfirmed, isTrue);
  });

  test('malformed sessions cannot become an authenticated guest partition', () async {
    final auth = controller((_) async => response(signedIn(access: 'not-a-jwt')));
    await expectLater(connect(auth), throwsA(isA<CopyBoxAuthException>()));
    expect(auth.session, isNull);
    expect(auth.accountScope, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('korlix_copybox_access_token'), isNull);
  });

  test('password reset uses normalized email and generic route', () async {
    final auth = controller((request) async {
      expect(request.url.path, '/api/auth/password-reset');
      expect(jsonDecode(request.body), {'email': 'person@example.test'});
      return response({'success': true});
    });
    await auth.requestPasswordReset(' Person@Example.Test ');
  });

  test('expired saved credentials open their local workspace without a network wait', () async {
    final access = token(remaining: const Duration(minutes: -5));
    SharedPreferences.setMockInitialValues({
      'korlix_copybox_access_token': access,
      'korlix_copybox_refresh_token': 'saved-refresh',
    });
    var calls = 0;
    final auth = controller((_) async { calls++; throw http.ClientException('offline'); });
    await auth.initialize();
    expect(auth.ready, isTrue);
    expect(auth.session!.accessToken, access);
    expect(auth.accountScope, isNotNull);
    expect(calls, 0);
    await auth.resume();
    expect(auth.session!.accessToken, access);
    expect(calls, 1);
  });

  test('main KORLIX credentials are not adopted or erased by Copy Box', () async {
    SharedPreferences.setMockInitialValues({
      KorlixTokenStore.accessTokenKey: token(user: 'main-user'),
      KorlixTokenStore.refreshTokenKey: 'main-refresh',
    });
    final auth = controller((_) async => response({'success': true}));
    await auth.initialize();
    expect(auth.session, isNull);
    await auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(KorlixTokenStore.refreshTokenKey), 'main-refresh');
  });

  test('sign-out invalidates a pending restore before it can publish', () async {
    SharedPreferences.setMockInitialValues({
      'korlix_copybox_tokens_signed_out_v1': false,
    });
    final secure = MemorySecureBackend()
      ..delayedRead = Completer<String?>()
      ..readStarted = Completer<void>();
    final auth = controller((_) async => response({'success': true}), tokenStore: KorlixTokenStore(
      namespace: 'korlix_copybox', useSecureStorage: true, secureStorage: secure,
    ));
    final initializing = auth.initialize();
    await secure.readStarted!.future;
    final signingOut = auth.signOut();
    secure.delayedRead!.complete(jsonEncode({'access_token': token(), 'refresh_token': 'saved-refresh'}));
    await initializing;
    await signingOut;
    expect(auth.ready, isTrue);
    expect(auth.session, isNull);
    expect(auth.accountScope, isNull);
  });

  test('late sign-in cannot resurrect a signed-out session', () async {
    final reply = Completer<http.Response>();
    final started = Completer<void>();
    final auth = controller((_) { started.complete(); return reply.future; });
    final signingIn = auth.authenticate(email: 'person@example.test', password: 'secure-password');
    final assertion = expectLater(signingIn, throwsA(isA<KorlixSessionChanged>()));
    await started.future;
    await auth.signOut();
    reply.complete(response(signedIn()));
    await assertion;
    expect(auth.session, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('korlix_copybox_access_token'), isNull);
  });

  test('sign-out clears local tokens and revokes only this app device', () async {
    final requests = <http.Request>[];
    final auth = controller((request) async {
      requests.add(request);
      return response(request.url.path.endsWith('/signin') ? signedIn() : {'success': true});
    });
    await connect(auth);
    final access = auth.session!.accessToken;
    final device = auth.deviceHeaders['X-Korlix-Device-Id'];
    await auth.signOut();
    final logout = requests.last;
    expect(logout.url.path, '/api/auth/signout');
    expect(logout.headers['Authorization'], 'Bearer $access');
    expect(logout.headers['X-Korlix-Device-Id'], device);
    expect(auth.session, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('korlix_copybox_access_token'), isNull);
    expect(prefs.getString('korlix_copybox_refresh_token'), isNull);
    expect(prefs.getBool('korlix_copybox_tokens_signed_out_v1'), isTrue);
  });

  test('failed durable logout retains the account and a visible error', () async {
    final tokens = FailingClearTokenStore();
    var remoteLogouts = 0;
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signout')) {
        remoteLogouts++;
        return response({'success': true});
      }
      return response(signedIn());
    }, tokenStore: tokens);
    await connect(auth);
    final scope = auth.accountScope;
    final revision = auth.revision;
    var publishedGuest = false;
    auth.addListener(() { if (auth.session == null) publishedGuest = true; });
    await expectLater(auth.signOut(), throwsA(
      isA<CopyBoxAuthException>().having((e) => e.code, 'code', 'local_signout_failed'),
    ));
    expect(auth.accountScope, scope);
    expect(auth.revision, greaterThan(revision));
    expect(publishedGuest, isFalse);
    expect(remoteLogouts, 0);
    tokens.failClear = false;
    await auth.signOut();
    expect(publishedGuest, isTrue);
    expect(auth.session, isNull);
    expect(remoteLogouts, 1);
  });

  test('an old remote logout finishes before the same device logs in again', () async {
    final logout = Completer<http.Response>();
    final started = Completer<void>();
    var logins = 0;
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signout')) { started.complete(); return logout.future; }
      logins++;
      return response(signedIn());
    });
    await connect(auth);
    final signOut = auth.signOut();
    await started.future;
    final signIn = auth.authenticate(email: 'person@example.test', password: 'secure-password');
    await Future<void>.delayed(Duration.zero);
    expect(logins, 1);
    logout.complete(response({'success': true}));
    await signOut;
    expect(await signIn, isTrue);
    expect(logins, 2);
  });

  test('concurrent refresh uses the rotating token only once', () async {
    var calls = 0;
    final refreshed = Completer<http.Response>();
    final started = Completer<void>();
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signin')) return response(signedIn());
      calls++;
      expect(request.url.path, '/api/auth/refresh');
      expect((jsonDecode(request.body) as Map)['refresh_token'], 'fixture-refresh');
      started.complete();
      return refreshed.future;
    });
    await connect(auth);
    final a = auth.sessions.ensureFresh(force: true);
    await started.future;
    final b = auth.sessions.ensureFresh(force: true);
    refreshed.complete(response(signedIn(refresh: 'rotated-refresh')));
    await Future.wait([a, b]);
    expect(calls, 1);
    expect(auth.session!.refreshToken, 'rotated-refresh');
  });

  test('refresh cannot replace an account with another account', () async {
    final auth = controller((request) async => response(signedIn(
      access: token(user: request.url.path.endsWith('/refresh') ? 'other-user' : 'fixture-user'),
    )));
    await connect(auth);
    final scope = auth.accountScope;
    await expectLater(auth.sessions.ensureFresh(force: true), throwsA(isA<KorlixSessionRefreshUnavailable>()));
    expect(auth.accountScope, scope);
    expect(auth.session!.refreshToken, 'fixture-refresh');
  });

  test('only explicit refresh rejection signs out; outages retain the account', () async {
    var reject = false;
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signin')) return response(signedIn());
      return response(reject
        ? {'error': 'Invalid refresh token', 'code': 'invalid_grant'}
        : {'error': 'Service unavailable'}, reject ? 401 : 503);
    });
    await connect(auth);
    await expectLater(auth.sessions.ensureFresh(force: true), throwsA(isA<KorlixSessionRefreshUnavailable>()));
    expect(auth.session, isNotNull);
    // A new successful login starts a fresh coordinator revision and retry window.
    await connect(auth);
    reject = true;
    await auth.sessions.ensureFresh(force: true);
    expect(auth.session, isNull);
  });

  test('rewrite uses exact generation schema and returns content only', () async {
    late Map body;
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signin')) return response(signedIn());
      expect(request.url.path, '/api/generate');
      expect(request.headers['Authorization'], startsWith('Bearer '));
      body = jsonDecode(request.body) as Map;
      return response({'title': 'Must not return title', 'content': '  Revised text.  '});
    });
    await connect(auth);
    expect(await auth.rewrite('Polish', 'Selected private draft.'), 'Revised text.');
    expect(body['prompt'], contains('Selected private draft.'));
    expect(body['source'], 'korlix_copybox');
    expect(body['purpose'], 'copy_box_rewrite');
    expect(body['history'], isEmpty);
    expect(body['mainChatMemory'], isFalse);
    expect(body['disableAccountMemory'], isTrue);
  });

  test('blank and oversized selections never leave the device', () async {
    var calls = 0;
    final auth = controller((_) async { calls++; return response(signedIn()); });
    await expectLater(auth.rewrite('Polish', ' '), throwsA(isA<CopyBoxAuthException>()));
    await expectLater(auth.rewrite('Polish', 'x' * 28001), throwsA(isA<CopyBoxAuthException>()));
    expect(calls, 0);
  });

  test('guest AI requests require a shared account and never send a prompt', () async {
    var calls = 0;
    final auth = controller((_) async { calls++; return response({}); });
    await expectLater(auth.rewrite('Polish', 'A draft'), throwsA(
      isA<CopyBoxAuthException>().having((e) => e.code, 'code', 'auth_required'),
    ));
    expect(calls, 0);
  });

  test('oversized or missing generated content is not applied', () async {
    var count = 0;
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signin')) return response(signedIn());
      return response(count++ == 0 ? {'content': 'x' * 100001} : {'title': 'Output'});
    });
    await connect(auth);
    await expectLater(auth.rewrite('Expand', 'Draft'), throwsA(isA<CopyBoxAuthException>()));
    await expectLater(auth.rewrite('Expand', 'Draft'), throwsA(isA<CopyBoxAuthException>()));
  });

  test('quota or authorization errors never replay a generation', () async {
    var writes = 0;
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signin')) return response(signedIn());
      writes++;
      return response({'error': 'Credit limit reached'}, 429);
    });
    await connect(auth);
    await expectLater(auth.rewrite('Polish', 'Draft'), throwsA(
      isA<CopyBoxAuthException>().having((e) => e.message, 'message', 'Credit limit reached'),
    ));
    expect(writes, 1);
  });

  test('late generation is discarded after sign-out', () async {
    final result = Completer<http.Response>();
    final started = Completer<void>();
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signin')) return response(signedIn());
      if (request.url.path.endsWith('/signout')) return response({'success': true});
      started.complete();
      return result.future;
    });
    await connect(auth);
    final rewrite = auth.rewrite('Polish', 'Private source');
    final assertion = expectLater(rewrite, throwsA(isA<KorlixSessionChanged>()));
    await started.future;
    await auth.signOut();
    result.complete(response({'content': 'Private result'}));
    await assertion;
  });

  test('work started during a pending account switch cannot publish afterward', () async {
    final loginReply = Completer<http.Response>();
    final loginStarted = Completer<void>();
    final rewriteReply = Completer<http.Response>();
    final rewriteStarted = Completer<void>();
    var logins = 0;
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signin')) {
        if (logins++ == 0) return response(signedIn());
        loginStarted.complete();
        return loginReply.future;
      }
      rewriteStarted.complete();
      return rewriteReply.future;
    });
    await connect(auth);
    final switching = auth.authenticate(email: 'other@example.test', password: 'secure-password');
    await loginStarted.future;
    final rewrite = auth.rewrite('Polish', 'First account source');
    final assertion = expectLater(rewrite, throwsA(isA<KorlixSessionChanged>()));
    await rewriteStarted.future;
    loginReply.complete(response(signedIn(access: token(user: 'second-user'))));
    expect(await switching, isTrue);
    rewriteReply.complete(response({'content': 'First account result'}));
    await assertion;
    expect(jsonDecode(auth.accountScope!)[1], 'second-user');
  });

  test('account deletion uses shared account route and requires an acknowledgement', () async {
    var valid = true;
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signin')) return response(signedIn());
      expect(request.url.path, '/api/account/delete-request');
      expect(request.headers['Authorization'], startsWith('Bearer '));
      return response(valid ? {'success': true, 'request': {'id': 'receipt'}} : {});
    });
    await connect(auth);
    await auth.requestAccountDeletion();
    valid = false;
    await expectLater(auth.requestAccountDeletion(), throwsA(isA<CopyBoxAuthException>()));
  });

  const receipt = 'korlix_report_00000000-0000-4000-8000-000000000001';

  test('output reports use the durable route, bounded UTF8 metadata, and receipt', () async {
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signin')) return response(signedIn());
      expect(request.url.path, '/api/report-output');
      final body = jsonDecode(request.body) as Map;
      expect(body['appArea'], 'korlix_copybox');
      expect(body['contentType'], 'text');
      expect(body.containsKey('userEmail'), isFalse);
      expect(utf8.encode(jsonEncode(body['outputSummary'])).length, lessThanOrEqualTo(12000));
      expect(utf8.encode(request.body).length, lessThan(28 * 1024));
      return response({'ok': true, 'reportId': receipt}, 202);
    });
    await connect(auth);
    await auth.reportOutput(output: '\u0000😊' * 20000, reason: 'Inaccurate', details: 'Details' * 2000);
    expect(auth.lastReportId, receipt);
  });

  test('ambiguous report response never retries or claims success', () async {
    var writes = 0;
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signin')) return response(signedIn());
      writes++;
      return response({'ok': true});
    });
    await connect(auth);
    await expectLater(auth.reportOutput(output: 'Result', reason: 'Inaccurate'), throwsA(
      isA<CopyBoxAuthException>().having((e) => e.message, 'uncertain receipt', contains('may already be saved')),
    ));
    expect(writes, 1);
    expect(auth.lastReportId, isNull);
  });

  test('late report acknowledgement cannot cross accounts', () async {
    final result = Completer<http.Response>();
    final started = Completer<void>();
    final auth = controller((request) async {
      if (request.url.path.endsWith('/signin')) return response(signedIn());
      if (request.url.path.endsWith('/signout')) return response({'success': true});
      started.complete();
      return result.future;
    });
    await connect(auth);
    final reporting = auth.reportOutput(output: 'Private output', reason: 'Inaccurate');
    final assertion = expectLater(reporting, throwsA(isA<KorlixSessionChanged>()));
    await started.future;
    await auth.signOut();
    result.complete(response({'ok': true, 'reportId': receipt}));
    await assertion;
    expect(auth.lastReportId, isNull);
  });
}
